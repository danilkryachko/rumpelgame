package network

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

const maxPacketSize = 16 * 1024 * 1024
const defaultViewDistance int32 = 10
const maxViewDistance int32 = 16
const defaultChunksPerUpdate = 64
const viewDistanceEnv = "RUMPELMC_SERVER_VIEW_DISTANCE"
const chunksPerUpdateEnv = "RUMPELMC_SERVER_CHUNKS_PER_UPDATE"
const chunkStreamMetricsEnv = "RUMPELMC_SERVER_CHUNK_STREAM_METRICS"
const chunkEncodingEnv = "RUMPELMC_SERVER_CHUNK_ENCODING"
const initialClientPacketTimeout = 250 * time.Millisecond

type Server struct {
	address         string
	world           *world.World
	viewDistance    int32
	chunksPerUpdate int
	chunkEncoding   api.ChunkEncoding
}

func NewServer(address string, gameWorld *world.World) *Server {
	return &Server{
		address:         address,
		world:           gameWorld,
		viewDistance:    configuredViewDistance(),
		chunksPerUpdate: configuredChunksPerUpdate(),
		chunkEncoding:   configuredChunkEncoding(),
	}
}

func (s *Server) Start() error {
	listener, err := net.Listen("tcp", s.address)
	if err != nil {
		return err
	}
	defer listener.Close()

	log.Printf("Listening on %s", s.address)

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("Failed to accept connection: %v", err)
			continue
		}

		go s.handleConnection(conn)
	}
}

func (s *Server) handleConnection(conn net.Conn) {
	defer conn.Close()
	log.Printf("Client connected: %s", conn.RemoteAddr())

	sentChunks := make(map[world.ChunkCoord]bool)
	firstPacket, hasFirstPacket, err := s.receiveInitialClientPacket(conn)
	if err != nil {
		log.Printf("Client disconnected before initial chunk stream: %v", err)
		return
	}
	if hasFirstPacket {
		if err := s.handleClientPacket(conn, firstPacket, sentChunks); err != nil {
			log.Printf("Failed to handle initial client packet: %v", err)
			return
		}
	} else {
		if err := s.sendChunksAround(conn, 0, 0, sentChunks); err != nil {
			log.Printf("Failed to send initial chunks: %v", err)
			return
		}
	}
	log.Printf("Started progressive chunk stream radius=%d batch=%d to %s", s.viewDistance, s.chunksPerUpdate, conn.RemoteAddr())

	// Read client packets until the connection closes.
	for {
		clientPacket, err := s.receivePacket(conn)
		if err != nil {
			log.Printf("Client disconnected: %v", err)
			return
		}

		if err := s.handleClientPacket(conn, clientPacket, sentChunks); err != nil {
			log.Printf("Failed to handle client packet: %v", err)
			return
		}
	}
}

func (s *Server) handleClientPacket(conn net.Conn, clientPacket *api.Packet, sentChunks map[world.ChunkCoord]bool) error {
	switch p := clientPacket.Payload.(type) {
	case *api.Packet_Position:
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		forgetFarSentChunks(sentChunks, center.X, center.Z, s.viewDistance+1)
		if err := s.sendChunksAround(conn, center.X, center.Z, sentChunks); err != nil {
			return fmt.Errorf("send chunks around %d,%d: %w", center.X, center.Z, err)
		}

	case *api.Packet_BlockAction:
		action := p.BlockAction
		log.Printf("Received BlockAction: action=%v, x=%d, y=%d, z=%d", action.Action, action.X, action.Y, action.Z)

		block := world.Air
		if action.Action == api.BlockAction_DESTROY {
			block = world.Air
		} else if action.Action == api.BlockAction_PLACE {
			block = world.BlockID(action.BlockId)
			if !world.IsPlaceable(block) {
				log.Printf("Ignored invalid place block id=%d", action.BlockId)
				return nil
			}
		}

		snapshot, err := s.world.SetBlockGlobal(action.X, action.Y, action.Z, block)
		if err != nil {
			return fmt.Errorf("update block: %w", err)
		}

		if _, err := s.sendChunk(conn, snapshot); err != nil {
			return fmt.Errorf("send updated chunk %d,%d: %w", snapshot.X, snapshot.Z, err)
		}

	default:
		log.Printf("Unknown packet received")
	}
	return nil
}

func forgetFarSentChunks(sentChunks map[world.ChunkCoord]bool, centerX, centerZ, distance int32) {
	for coord := range sentChunks {
		if !world.ChunkWithinRadius(coord, centerX, centerZ, distance) {
			delete(sentChunks, coord)
		}
	}
}

func (s *Server) sendChunksAround(conn net.Conn, centerX, centerZ int32, sentChunks map[world.ChunkCoord]bool) error {
	started := time.Now()
	chunks, err := s.world.ChunksAround(centerX, centerZ, s.viewDistance, sentChunks, s.chunksPerUpdate)
	if err != nil {
		return err
	}
	var batch chunkStreamBatchStats
	for _, chunk := range chunks {
		stats, err := s.sendChunk(conn, chunk)
		if err != nil {
			return err
		}
		batch.add(stats)
	}
	if chunkStreamMetricsEnabled() && batch.chunks > 0 {
		elapsed := time.Since(started)
		log.Printf(
			"Chunk stream batch center=%d,%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d elapsed_ms=%.3f chunks_per_sec=%.2f",
			centerX,
			centerZ,
			batch.chunks,
			batch.rawBytes,
			batch.payloadBytes,
			batch.wireBytes,
			float64(elapsed.Microseconds())/1000.0,
			float64(batch.chunks)/elapsed.Seconds(),
		)
	}
	return nil
}

func configuredViewDistance() int32 {
	value := os.Getenv(viewDistanceEnv)
	if value == "" {
		return defaultViewDistance
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		log.Printf("Ignoring invalid %s=%q; using %d", viewDistanceEnv, value, defaultViewDistance)
		return defaultViewDistance
	}
	if parsed > int(maxViewDistance) {
		log.Printf("Clamping %s=%d to %d", viewDistanceEnv, parsed, maxViewDistance)
		return maxViewDistance
	}
	return int32(parsed)
}

func configuredChunksPerUpdate() int {
	value := os.Getenv(chunksPerUpdateEnv)
	if value == "" {
		return defaultChunksPerUpdate
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		log.Printf("Ignoring invalid %s=%q; using %d", chunksPerUpdateEnv, value, defaultChunksPerUpdate)
		return defaultChunksPerUpdate
	}
	return parsed
}

func chunkStreamMetricsEnabled() bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(chunkStreamMetricsEnv)))
	return value == "1" || value == "true" || value == "yes" || value == "on"
}

func configuredChunkEncoding() api.ChunkEncoding {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(chunkEncodingEnv)))
	switch value {
	case "", "rle":
		return api.ChunkEncoding_CHUNK_ENCODING_RLE
	case "raw":
		return api.ChunkEncoding_CHUNK_ENCODING_RAW
	default:
		log.Printf("Ignoring invalid %s=%q; using rle", chunkEncodingEnv, value)
		return api.ChunkEncoding_CHUNK_ENCODING_RLE
	}
}

type chunkSendStats struct {
	rawBytes     int
	payloadBytes int
	wireBytes    int
}

type chunkStreamBatchStats struct {
	chunks       int
	rawBytes     int
	payloadBytes int
	wireBytes    int
}

func (s *Server) sendChunk(conn net.Conn, chunk world.ChunkSnapshot) (chunkSendStats, error) {
	blocks := chunk.Blocks
	encoding := api.ChunkEncoding_CHUNK_ENCODING_RAW
	var uncompressedSize uint32
	if s.chunkEncoding == api.ChunkEncoding_CHUNK_ENCODING_RLE {
		encoded, err := world.EncodeSerializedChunkRLE(chunk.Blocks)
		if err != nil {
			return chunkSendStats{}, err
		}
		blocks = encoded
		encoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
		uncompressedSize = uint32(len(chunk.Blocks))
	}

	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:                chunk.X,
				Z:                chunk.Z,
				Blocks:           blocks,
				Encoding:         encoding,
				UncompressedSize: uncompressedSize,
			},
		},
	}
	stats := chunkSendStats{
		rawBytes:     len(chunk.Blocks),
		payloadBytes: len(blocks),
		wireBytes:    framedPacketSize(packet),
	}
	return stats, s.sendPacket(conn, packet)
}

func (s *chunkStreamBatchStats) add(stats chunkSendStats) {
	s.chunks++
	s.rawBytes += stats.rawBytes
	s.payloadBytes += stats.payloadBytes
	s.wireBytes += stats.wireBytes
}

func framedPacketSize(packet *api.Packet) int {
	return 4 + proto.Size(packet)
}

func (s *Server) receiveInitialClientPacket(conn net.Conn) (*api.Packet, bool, error) {
	if err := conn.SetReadDeadline(time.Now().Add(initialClientPacketTimeout)); err != nil {
		return nil, false, err
	}
	packet, err := s.receivePacket(conn)
	clearErr := conn.SetReadDeadline(time.Time{})
	if err != nil {
		if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
			return nil, false, clearErr
		}
		if clearErr != nil {
			return nil, false, clearErr
		}
		return nil, false, err
	}
	if clearErr != nil {
		return nil, false, clearErr
	}
	return packet, true, nil
}

func (s *Server) receivePacket(conn net.Conn) (*api.Packet, error) {
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		return nil, err
	}

	length := binary.LittleEndian.Uint32(lenBuf)
	if length > maxPacketSize {
		return nil, fmt.Errorf("packet too large: %d bytes", length)
	}

	dataBuf := make([]byte, length)
	if _, err := io.ReadFull(conn, dataBuf); err != nil {
		return nil, err
	}

	packet := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, packet); err != nil {
		return nil, err
	}

	return packet, nil
}

func (s *Server) sendPacket(conn net.Conn, packet *api.Packet) error {
	data, err := proto.Marshal(packet)
	if err != nil {
		return err
	}

	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))

	if err := writeFull(conn, lenBuf); err != nil {
		return err
	}
	if err := writeFull(conn, data); err != nil {
		return err
	}
	return nil
}

func writeFull(writer io.Writer, data []byte) error {
	for len(data) > 0 {
		n, err := writer.Write(data)
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
		data = data[n:]
	}

	return nil
}
