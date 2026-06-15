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

type smokeAction string

const (
	actionExpect  smokeAction = "expect"
	actionPlace   smokeAction = "place"
	actionDestroy smokeAction = "destroy"
)

type smokeClient struct {
	conn net.Conn
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 3*time.Second, "per-read/write timeout")
	action := flag.String("action", string(actionExpect), "smoke action: expect, place, or destroy")
	x := flag.Int("x", 1, "global block x coordinate")
	y := flag.Int("y", 64, "global block y coordinate")
	z := flag.Int("z", 1, "global block z coordinate")
	blockID := flag.Int("block-id", int(world.Wood), "block id used for place")
	wantBlock := flag.Int("want-block", int(world.Air), "expected block id for expect action")
	wantBefore := flag.Int("want-before", -1, "optional expected block id before place/destroy")
	flag.Parse()

	if err := run(*addr, *timeout, smokeAction(*action), int32(*x), int32(*y), int32(*z), world.BlockID(*blockID), world.BlockID(*wantBlock), *wantBefore); err != nil {
		fmt.Fprintf(os.Stderr, "server_persisted_reload_smoke status=fail action=%s error=%q\n", *action, err)
		os.Exit(1)
	}
}

func run(addr string, timeout time.Duration, action smokeAction, x, y, z int32, blockID, wantBlock world.BlockID, wantBefore int) error {
	client, err := dialClient(addr, timeout)
	if err != nil {
		return err
	}
	defer client.conn.Close()

	chunkX, localX := world.GlobalToChunkLocal(x, world.ChunkWidth)
	chunkZ, localZ := world.GlobalToChunkLocal(z, world.ChunkDepth)
	if err := client.sendPosition(float32(x)+0.5, float32(y)+4.0, float32(z)+0.5, timeout); err != nil {
		return err
	}

	initial, err := client.readChunkFor(chunkX, chunkZ, timeout)
	if err != nil {
		return err
	}
	initialBlock, err := blockAt(initial, localX, int(y), localZ)
	if err != nil {
		return err
	}
	if wantBefore >= 0 && initialBlock != world.BlockID(wantBefore) {
		return fmt.Errorf("initial block %d,%d,%d = %d, want %d", x, y, z, initialBlock, wantBefore)
	}

	beforeBlock := initialBlock
	afterBlock := initialBlock
	switch action {
	case actionExpect:
		if initialBlock != wantBlock {
			return fmt.Errorf("expected block %d,%d,%d = %d, want %d", x, y, z, initialBlock, wantBlock)
		}
	case actionPlace:
		if err := client.sendBlockAction(api.BlockAction_PLACE, x, y, z, blockID, timeout); err != nil {
			return err
		}
		afterBlock, err = client.readUpdatedBlock(chunkX, chunkZ, localX, int(y), localZ, timeout)
		if err != nil {
			return err
		}
		if afterBlock != blockID {
			return fmt.Errorf("placed block %d,%d,%d = %d, want %d", x, y, z, afterBlock, blockID)
		}
	case actionDestroy:
		if err := client.sendBlockAction(api.BlockAction_DESTROY, x, y, z, 0, timeout); err != nil {
			return err
		}
		afterBlock, err = client.readUpdatedBlock(chunkX, chunkZ, localX, int(y), localZ, timeout)
		if err != nil {
			return err
		}
		if afterBlock != world.Air {
			return fmt.Errorf("destroyed block %d,%d,%d = %d, want %d", x, y, z, afterBlock, world.Air)
		}
	default:
		return fmt.Errorf("unsupported action %q", action)
	}

	fmt.Printf(
		"server_persisted_reload_smoke status=pass action=%s chunk=%d,%d block_x=%d block_y=%d block_z=%d before_block=%d after_block=%d want_block=%d block_id=%d protocol_change=0\n",
		action,
		chunkX,
		chunkZ,
		x,
		y,
		z,
		beforeBlock,
		afterBlock,
		wantBlock,
		blockID,
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

func (c *smokeClient) sendBlockAction(action api.BlockAction_ActionType, x, y, z int32, block world.BlockID, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  action,
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

func (c *smokeClient) readUpdatedBlock(chunkX int32, chunkZ int32, localX int, localY int, localZ int, timeout time.Duration) (world.BlockID, error) {
	updated, err := c.readChunkFor(chunkX, chunkZ, timeout)
	if err != nil {
		return world.Air, err
	}
	return blockAt(updated, localX, localY, localZ)
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
			if _, err := decodeChunk(chunk); err != nil {
				return nil, fmt.Errorf("decode chunk %d,%d: %w", wantX, wantZ, err)
			}
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

func blockAt(chunk *api.ChunkData, x, y, z int) (world.BlockID, error) {
	decoded, err := decodeChunk(chunk)
	if err != nil {
		return world.Air, err
	}
	return decoded.GetBlock(x, y, z), nil
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
