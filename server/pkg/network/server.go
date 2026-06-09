package network

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

const maxPacketSize = 16 * 1024 * 1024
const viewDistance int32 = 10
const chunkForgetDistance int32 = viewDistance + 1
const chunksPerUpdate = 6

type Server struct {
	address string
	world   *world.World
}

func NewServer(address string, gameWorld *world.World) *Server {
	return &Server{
		address: address,
		world:   gameWorld,
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
	if err := s.sendChunksAround(conn, 0, 0, sentChunks); err != nil {
		log.Printf("Failed to send initial chunks: %v", err)
		return
	}
	log.Printf("Started progressive chunk stream radius=%d batch=%d to %s", viewDistance, chunksPerUpdate, conn.RemoteAddr())

	// Чтение пакетов в цикле
	for {
		clientPacket, err := s.receivePacket(conn)
		if err != nil {
			log.Printf("Client disconnected: %v", err)
			return
		}

		switch p := clientPacket.Payload.(type) {
		case *api.Packet_Position:
			center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
			forgetFarSentChunks(sentChunks, center.X, center.Z, chunkForgetDistance)
			if err := s.sendChunksAround(conn, center.X, center.Z, sentChunks); err != nil {
				log.Printf("Failed to send chunks around %d,%d: %v", center.X, center.Z, err)
				return
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
					continue
				}
			}

			snapshot, err := s.world.SetBlockGlobal(action.X, action.Y, action.Z, block)
			if err != nil {
				log.Printf("Failed to update block: %v", err)
				return
			}

			if err := s.sendChunk(conn, snapshot); err != nil {
				log.Printf("Failed to send updated chunk %d,%d: %v", snapshot.X, snapshot.Z, err)
				return
			}

		default:
			log.Printf("Unknown packet received")
		}
	}
}

func forgetFarSentChunks(sentChunks map[world.ChunkCoord]bool, centerX, centerZ, distance int32) {
	for coord := range sentChunks {
		if !world.ChunkWithinRadius(coord, centerX, centerZ, distance) {
			delete(sentChunks, coord)
		}
	}
}

func (s *Server) sendChunksAround(conn net.Conn, centerX, centerZ int32, sentChunks map[world.ChunkCoord]bool) error {
	chunks, err := s.world.ChunksAround(centerX, centerZ, viewDistance, sentChunks, chunksPerUpdate)
	if err != nil {
		return err
	}
	for _, chunk := range chunks {
		if err := s.sendChunk(conn, chunk); err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) sendChunk(conn net.Conn, chunk world.ChunkSnapshot) error {
	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:      chunk.X,
				Z:      chunk.Z,
				Blocks: chunk.Blocks,
			},
		},
	}
	return s.sendPacket(conn, packet)
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
