package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

const maxPacketSize = 16 * 1024 * 1024

type smokeClient struct {
	conn net.Conn
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 3*time.Second, "per-read/write timeout")
	seed := flag.Int64("seed", world.DefaultWorldSeed, "world generator seed")
	dimension := flag.String("dimension", world.DefaultDimensionID, "world generator dimension id")
	chunkX := flag.Int("chunk-x", -3, "chunk x coordinate")
	chunkZ := flag.Int("chunk-z", 5, "chunk z coordinate")
	flag.Parse()

	if err := run(*addr, *timeout, *seed, *dimension, int32(*chunkX), int32(*chunkZ)); err != nil {
		fmt.Fprintf(os.Stderr, "server_height_generator_smoke status=fail error=%q\n", err)
		os.Exit(1)
	}
}

func run(addr string, timeout time.Duration, seed int64, dimension string, chunkX, chunkZ int32) error {
	config := world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     world.GeneratorVersionHeightV1,
	}
	generator, err := world.NewWorldGenerator(config)
	if err != nil {
		return err
	}
	expected, err := generator.GenerateChunk(chunkX, chunkZ)
	if err != nil {
		return err
	}
	expectedRaw := expected.Serialize()

	client, err := dialClient(addr, timeout)
	if err != nil {
		return err
	}
	defer client.conn.Close()

	positionX := float32(int64(chunkX)*int64(world.ChunkWidth) + int64(world.ChunkWidth/2))
	positionZ := float32(int64(chunkZ)*int64(world.ChunkDepth) + int64(world.ChunkDepth/2))
	if err := client.sendPosition(positionX+0.5, 96, positionZ+0.5, timeout); err != nil {
		return err
	}

	chunkData, err := client.readChunkFor(chunkX, chunkZ, timeout)
	if err != nil {
		return err
	}
	actual, raw, err := decodeChunk(chunkData)
	if err != nil {
		return fmt.Errorf("decode live chunk: %w", err)
	}
	if !bytes.Equal(raw, expectedRaw) {
		return fmt.Errorf("live height_v1 raw bytes do not match local generator bytes")
	}

	minSurfaceY, maxSurfaceY, err := surfaceRange(actual)
	if err != nil {
		return err
	}
	if minSurfaceY == maxSurfaceY {
		return fmt.Errorf("height_v1 live chunk surface is flat at y=%d", minSurfaceY)
	}

	sum := sha256.Sum256(raw)
	fmt.Printf(
		"server_height_generator_smoke status=pass generator_version=%s seed=%d dimension=%s chunk=%d,%d encoding=%s payload_bytes=%d raw_bytes=%d raw_sha256=%x surface_min=%d surface_max=%d varied_surface=1 protocol_change=0\n",
		world.GeneratorVersionHeightV1,
		seed,
		dimension,
		chunkX,
		chunkZ,
		chunkEncodingLabel(chunkData.GetEncoding()),
		len(chunkData.GetBlocks()),
		len(raw),
		sum,
		minSurfaceY,
		maxSurfaceY,
	)
	return nil
}

func dialClient(addr string, timeout time.Duration) (*smokeClient, error) {
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	return &smokeClient{conn: conn}, nil
}

func (c *smokeClient) sendPosition(x, y, z float32, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: x, Y: y, Z: z},
		},
	}, timeout)
}

func (c *smokeClient) writePacket(packet *api.Packet, timeout time.Duration) error {
	data, err := proto.Marshal(packet)
	if err != nil {
		return fmt.Errorf("marshal packet: %w", err)
	}
	if len(data) > maxPacketSize {
		return fmt.Errorf("packet length %d exceeds max %d", len(data), maxPacketSize)
	}

	frame := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(frame[:4], uint32(len(data)))
	copy(frame[4:], data)

	if err := c.conn.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return fmt.Errorf("set write deadline: %w", err)
	}
	err = writeFull(c.conn, frame)
	clearErr := c.conn.SetWriteDeadline(time.Time{})
	if err != nil {
		return fmt.Errorf("write packet: %w", err)
	}
	if clearErr != nil {
		return fmt.Errorf("clear write deadline: %w", clearErr)
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

func (c *smokeClient) readChunkFor(wantX, wantZ int32, timeout time.Duration) (*api.ChunkData, error) {
	deadline := time.Now().Add(timeout)
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil, fmt.Errorf("timed out waiting for chunk %d,%d", wantX, wantZ)
		}
		packet, err := c.readPacket(remaining)
		if err != nil {
			return nil, err
		}
		chunk := packet.GetChunk()
		if chunk != nil && chunk.GetX() == wantX && chunk.GetZ() == wantZ {
			return chunk, nil
		}
	}
}

func (c *smokeClient) readPacket(timeout time.Duration) (*api.Packet, error) {
	if err := c.conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return nil, fmt.Errorf("set read deadline: %w", err)
	}
	defer c.conn.SetReadDeadline(time.Time{})

	var lenBuf [4]byte
	if _, err := io.ReadFull(c.conn, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("read length: %w", err)
	}

	length := binary.LittleEndian.Uint32(lenBuf[:])
	if length > maxPacketSize {
		return nil, fmt.Errorf("packet too large: %d bytes", length)
	}
	dataBuf := make([]byte, length)
	if _, err := io.ReadFull(c.conn, dataBuf); err != nil {
		return nil, fmt.Errorf("read payload: %w", err)
	}

	packet := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, packet); err != nil {
		return nil, fmt.Errorf("unmarshal packet: %w", err)
	}
	return packet, nil
}

func decodeChunk(chunk *api.ChunkData) (*world.Chunk, []byte, error) {
	blocks := chunk.GetBlocks()
	switch chunk.GetEncoding() {
	case api.ChunkEncoding_CHUNK_ENCODING_RAW:
		if len(blocks) != world.SerializedChunkSize {
			return nil, nil, fmt.Errorf("raw block bytes = %d, want %d", len(blocks), world.SerializedChunkSize)
		}
	case api.ChunkEncoding_CHUNK_ENCODING_RLE:
		if chunk.GetUncompressedSize() != world.SerializedChunkSize {
			return nil, nil, fmt.Errorf("rle uncompressed size = %d, want %d", chunk.GetUncompressedSize(), world.SerializedChunkSize)
		}
		decoded, err := world.DecodeSerializedChunkRLE(blocks)
		if err != nil {
			return nil, nil, err
		}
		blocks = decoded
	default:
		return nil, nil, errors.New("unsupported chunk encoding")
	}
	chunkData, err := world.DeserializeChunk(chunk.GetX(), chunk.GetZ(), blocks)
	if err != nil {
		return nil, nil, err
	}
	return chunkData, blocks, nil
}

func surfaceRange(chunk *world.Chunk) (int, int, error) {
	minSurfaceY := world.ChunkHeight
	maxSurfaceY := -1
	for x := 0; x < world.ChunkWidth; x++ {
		for z := 0; z < world.ChunkDepth; z++ {
			surfaceY := -1
			for y := world.ChunkHeight - 1; y >= 0; y-- {
				if chunk.GetBlock(x, y, z) != world.Air {
					surfaceY = y
					break
				}
			}
			if surfaceY < 0 {
				return 0, 0, fmt.Errorf("empty height_v1 column at local %d,%d", x, z)
			}
			if got := chunk.GetBlock(x, surfaceY, z); got != world.Grass {
				return 0, 0, fmt.Errorf("surface block at %d,%d,%d = %d, want %d", x, surfaceY, z, got, world.Grass)
			}
			if got := chunk.GetBlock(x, surfaceY+1, z); got != world.Air {
				return 0, 0, fmt.Errorf("air block above surface at %d,%d,%d = %d, want %d", x, surfaceY+1, z, got, world.Air)
			}
			if surfaceY < minSurfaceY {
				minSurfaceY = surfaceY
			}
			if surfaceY > maxSurfaceY {
				maxSurfaceY = surfaceY
			}
		}
	}
	return minSurfaceY, maxSurfaceY, nil
}

func chunkEncodingLabel(encoding api.ChunkEncoding) string {
	switch encoding {
	case api.ChunkEncoding_CHUNK_ENCODING_RAW:
		return "raw"
	case api.ChunkEncoding_CHUNK_ENCODING_RLE:
		return "rle"
	default:
		return "unknown"
	}
}
