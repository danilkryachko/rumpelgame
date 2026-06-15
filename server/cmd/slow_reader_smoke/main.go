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
)

const maxPacketSize = 16 * 1024 * 1024

type smokeClient struct {
	name string
	conn net.Conn
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 5*time.Second, "fast client read/write timeout")
	slowLead := flag.Duration("slow-lead", 250*time.Millisecond, "time to let the slow client pressure server writes before the fast client connects")
	postFastWait := flag.Duration("post-fast-wait", 750*time.Millisecond, "time to keep the slow client connected after the fast client succeeds")
	flag.Parse()

	if err := run(*addr, *timeout, *slowLead, *postFastWait); err != nil {
		fmt.Fprintf(os.Stderr, "server_slow_reader_smoke status=fail error=%q\n", err)
		os.Exit(1)
	}
}

func run(addr string, timeout, slowLead, postFastWait time.Duration) error {
	slow, err := dialClient("slow", addr, timeout)
	if err != nil {
		return err
	}
	defer slow.conn.Close()
	if tcpConn, ok := slow.conn.(*net.TCPConn); ok {
		_ = tcpConn.SetReadBuffer(1)
	}

	if err := slow.sendPosition(0, 68, 0, timeout); err != nil {
		return err
	}
	time.Sleep(slowLead)

	fast, err := dialClient("fast", addr, timeout)
	if err != nil {
		return err
	}
	defer fast.conn.Close()

	fastStarted := time.Now()
	if err := fast.sendPosition(1, 68, 1, timeout); err != nil {
		return err
	}
	fastChunk, err := fast.readChunk(timeout)
	if err != nil {
		return err
	}
	fastBootstrapMS := float64(time.Since(fastStarted).Microseconds()) / 1000.0
	if fastChunk.GetX() != 0 || fastChunk.GetZ() != 0 {
		return fmt.Errorf("fast bootstrap chunk = %d,%d, want 0,0", fastChunk.GetX(), fastChunk.GetZ())
	}

	time.Sleep(postFastWait)

	fmt.Printf(
		"server_slow_reader_smoke status=pass slow_client=1 fast_client=1 fast_bootstrap_chunk=1 fast_bootstrap_ms=%.3f protocol_change=0\n",
		fastBootstrapMS,
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
		if chunk := packet.GetChunk(); chunk != nil {
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
	if length == 0 {
		return nil, errors.New("empty packet while waiting for chunk")
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
