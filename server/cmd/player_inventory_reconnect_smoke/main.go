package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
)

const maxPacketSize = 16 * 1024 * 1024

type smokeAction string

const (
	actionSelect        smokeAction = "select"
	actionExpect        smokeAction = "expect"
	actionPlaceExpect   smokeAction = "place-expect"
	actionDestroyExpect smokeAction = "destroy-expect"
)

type smokeClient struct {
	conn net.Conn
}

type inventoryObservation struct {
	selectedSlot uint32
	slotCount    uint32
	snapshots    int
	chunks       int
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 3*time.Second, "per-read/write timeout")
	action := flag.String("action", string(actionExpect), "smoke action: select, expect, place-expect, or destroy-expect")
	playerID := flag.String("player-id", "local_player", "player id to send in ClientPosition")
	slot := flag.Uint("slot", 1, "selected inventory slot to persist or expect")
	blockID := flag.Uint("block-id", 1, "block id to place for place-expect")
	expectCount := flag.Int("expect-count", -1, "expected selected slot count; negative disables count check")
	flag.Parse()

	if err := run(*addr, *timeout, smokeAction(*action), *playerID, uint32(*slot), uint32(*blockID), *expectCount); err != nil {
		fmt.Fprintf(os.Stderr, "player_inventory_reconnect_smoke status=fail action=%s player_id=%q slot=%d error=%q\n", *action, *playerID, *slot, err)
		os.Exit(1)
	}
}

func run(addr string, timeout time.Duration, action smokeAction, playerID string, slot uint32, blockID uint32, expectCount int) error {
	client, err := dialClient(addr, timeout)
	if err != nil {
		return err
	}
	defer client.conn.Close()

	if err := client.sendPosition(playerID, timeout); err != nil {
		return err
	}

	switch action {
	case actionSelect:
		if err := client.sendInventorySelect(slot, timeout); err != nil {
			return err
		}
	case actionExpect:
	case actionPlaceExpect:
		if err := client.sendBlockPlace(blockID, timeout); err != nil {
			return err
		}
	case actionDestroyExpect:
		if err := client.sendBlockDestroy(timeout); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unsupported action %q", action)
	}

	observation, err := client.readInventorySnapshot(slot, expectCount, timeout)
	if err != nil {
		return err
	}
	fmt.Printf(
		"player_inventory_reconnect_smoke status=pass action=%s player_id=%s selected_slot=%d slot_count=%d snapshots=%d chunks=%d protocol_change=0\n",
		action,
		playerID,
		observation.selectedSlot,
		observation.slotCount,
		observation.snapshots,
		observation.chunks,
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

func (c *smokeClient) sendPosition(playerID string, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{
				X:        1.5,
				Y:        68,
				Z:        1.5,
				PlayerId: playerID,
			},
		},
	}, timeout)
}

func (c *smokeClient) sendInventorySelect(slot uint32, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_InventoryAction{
			InventoryAction: &api.InventoryAction{
				Action: api.InventoryAction_SELECT_SLOT,
				Slot:   slot,
			},
		},
	}, timeout)
}

func (c *smokeClient) sendBlockPlace(blockID uint32, timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: blockID,
			},
		},
	}, timeout)
}

func (c *smokeClient) sendBlockDestroy(timeout time.Duration) error {
	return c.writePacket(&api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      60,
				Z:      1,
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

func (c *smokeClient) readInventorySnapshot(wantSlot uint32, wantCount int, timeout time.Duration) (inventoryObservation, error) {
	deadline := time.Now().Add(timeout)
	observation := inventoryObservation{}
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return observation, fmt.Errorf("timed out waiting for inventory snapshot selected_slot=%d after snapshots=%d chunks=%d", wantSlot, observation.snapshots, observation.chunks)
		}
		packet, err := c.readPacket(remaining)
		if err != nil {
			return observation, err
		}
		if packet.GetChunk() != nil {
			observation.chunks++
			continue
		}
		snapshot := packet.GetInventorySnapshot()
		if snapshot == nil {
			continue
		}
		observation.snapshots++
		observation.selectedSlot = snapshot.GetSelectedSlot()
		if snapshot.GetSelectedSlot() != wantSlot {
			continue
		}
		if uint64(wantSlot) >= uint64(len(snapshot.GetSlots())) {
			return observation, fmt.Errorf("selected slot %d outside snapshot slot count %d", wantSlot, len(snapshot.GetSlots()))
		}
		slot := snapshot.GetSlots()[wantSlot]
		if slot.GetBlockId() == 0 || slot.GetCount() == 0 {
			return observation, fmt.Errorf("selected slot %d is not placeable in snapshot: block_id=%d count=%d", wantSlot, slot.GetBlockId(), slot.GetCount())
		}
		observation.slotCount = slot.GetCount()
		if wantCount >= 0 && slot.GetCount() != uint32(wantCount) {
			continue
		}
		return observation, nil
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
