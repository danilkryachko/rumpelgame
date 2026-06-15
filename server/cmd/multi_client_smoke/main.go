package main

import (
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
	name string
	conn net.Conn
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 3*time.Second, "per-read/write timeout")
	flag.Parse()

	if err := run(*addr, *timeout); err != nil {
		fmt.Fprintf(os.Stderr, "server_multi_client_smoke status=fail error=%q\n", err)
		os.Exit(1)
	}
}

func run(addr string, timeout time.Duration) error {
	origin, err := dialClient("origin", addr, timeout)
	if err != nil {
		return err
	}
	defer origin.conn.Close()

	watcher, err := dialClient("watcher", addr, timeout)
	if err != nil {
		return err
	}
	defer watcher.conn.Close()

	if err := origin.sendPosition(1, 68, 1, timeout); err != nil {
		return err
	}
	if err := watcher.sendPosition(2, 68, 2, timeout); err != nil {
		return err
	}

	originInitial, err := origin.readChunk(timeout)
	if err != nil {
		return err
	}
	watcherInitial, err := watcher.readChunk(timeout)
	if err != nil {
		return err
	}
	if err := assertChunk(originInitial, "origin initial", 0, 0); err != nil {
		return err
	}
	if err := assertChunk(watcherInitial, "watcher initial", 0, 0); err != nil {
		return err
	}

	if err := origin.sendBlockPlace(1, 64, 1, world.Wood, timeout); err != nil {
		return err
	}

	originUpdate, err := origin.readChunk(timeout)
	if err != nil {
		return err
	}
	watcherUpdate, err := watcher.readChunk(timeout)
	if err != nil {
		return err
	}
	if err := assertUpdatedChunk(originUpdate, "origin update"); err != nil {
		return err
	}
	if err := assertUpdatedChunk(watcherUpdate, "watcher update"); err != nil {
		return err
	}

	fmt.Printf(
		"server_multi_client_smoke status=pass clients=2 origin_initial=1 watcher_initial=1 origin_update=1 watcher_update=1 chunk=0,0 block_x=1 block_y=64 block_z=1 block_id=%d protocol_change=0\n",
		world.Wood,
	)
	return nil
}

func dialClient(name, addr string, timeout time.Duration) (*smokeClient, error) {
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return nil, fmt.Errorf("%s dial %s: %w", name, addr, err)
	}
	return &smokeClient{name: name, conn: conn}, nil
}

func (c *smokeClient) sendPosition(x, y, z float32, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: x, Y: y, Z: z},
		},
	}, timeout)
}

func (c *smokeClient) sendBlockPlace(x, y, z int32, block world.BlockID, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       x,
				Y:       y,
				Z:       z,
				BlockId: uint32(block),
			},
		},
	}, timeout)
}

func (c *smokeClient) writePacket(packet *api.Packet, timeout time.Duration) error {
	data, err := proto.Marshal(packet)
	if err != nil {
		return fmt.Errorf("%s marshal packet: %w", c.name, err)
	}
	if len(data) > maxPacketSize {
		return fmt.Errorf("%s packet length %d exceeds max %d", c.name, len(data), maxPacketSize)
	}

	frame := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(frame[:4], uint32(len(data)))
	copy(frame[4:], data)

	if err := c.conn.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return fmt.Errorf("%s set write deadline: %w", c.name, err)
	}
	err = writeFull(c.conn, frame)
	clearErr := c.conn.SetWriteDeadline(time.Time{})
	if err != nil {
		return fmt.Errorf("%s write packet: %w", c.name, err)
	}
	if clearErr != nil {
		return fmt.Errorf("%s clear write deadline: %w", c.name, clearErr)
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

func (c *smokeClient) readChunk(timeout time.Duration) (*api.ChunkData, error) {
	for {
		packet, err := c.readPacket(timeout)
		if err != nil {
			return nil, err
		}
		chunk := packet.GetChunk()
		if chunk != nil {
			return chunk, nil
		}
	}
}

func (c *smokeClient) readPacket(timeout time.Duration) (*api.Packet, error) {
	if err := c.conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return nil, fmt.Errorf("%s set read deadline: %w", c.name, err)
	}
	defer c.conn.SetReadDeadline(time.Time{})

	var lenBuf [4]byte
	if _, err := io.ReadFull(c.conn, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("%s read length: %w", c.name, err)
	}

	length := binary.LittleEndian.Uint32(lenBuf[:])
	if length > maxPacketSize {
		return nil, fmt.Errorf("%s packet too large: %d bytes", c.name, length)
	}
	dataBuf := make([]byte, length)
	if _, err := io.ReadFull(c.conn, dataBuf); err != nil {
		return nil, fmt.Errorf("%s read payload: %w", c.name, err)
	}

	packet := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, packet); err != nil {
		return nil, fmt.Errorf("%s unmarshal packet: %w", c.name, err)
	}
	return packet, nil
}

func assertChunk(chunk *api.ChunkData, label string, wantX, wantZ int32) error {
	if chunk.GetX() != wantX || chunk.GetZ() != wantZ {
		return fmt.Errorf("%s chunk = %d,%d, want %d,%d", label, chunk.GetX(), chunk.GetZ(), wantX, wantZ)
	}
	if _, err := decodeChunk(chunk); err != nil {
		return fmt.Errorf("%s decode chunk: %w", label, err)
	}
	return nil
}

func assertUpdatedChunk(chunk *api.ChunkData, label string) error {
	if err := assertChunk(chunk, label, 0, 0); err != nil {
		return err
	}
	decoded, err := decodeChunk(chunk)
	if err != nil {
		return fmt.Errorf("%s decode updated chunk: %w", label, err)
	}
	if got := decoded.GetBlock(1, 64, 1); got != world.Wood {
		return fmt.Errorf("%s block 1,64,1 = %d, want %d", label, got, world.Wood)
	}
	return nil
}

func decodeChunk(chunk *api.ChunkData) (*world.Chunk, error) {
	blocks := chunk.GetBlocks()
	switch chunk.GetEncoding() {
	case api.ChunkEncoding_CHUNK_ENCODING_RAW:
		if len(blocks) != world.SerializedChunkSize {
			return nil, fmt.Errorf("raw block bytes = %d, want %d", len(blocks), world.SerializedChunkSize)
		}
	case api.ChunkEncoding_CHUNK_ENCODING_RLE:
		if chunk.GetUncompressedSize() != world.SerializedChunkSize {
			return nil, fmt.Errorf("rle uncompressed size = %d, want %d", chunk.GetUncompressedSize(), world.SerializedChunkSize)
		}
		decoded, err := world.DecodeSerializedChunkRLE(blocks)
		if err != nil {
			return nil, err
		}
		blocks = decoded
	default:
		return nil, errors.New("unsupported chunk encoding")
	}
	return world.DeserializeChunk(chunk.GetX(), chunk.GetZ(), blocks)
}
