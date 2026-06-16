package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
)

const maxPacketSize = 16 * 1024 * 1024

type smokeClient struct {
	name string
	conn net.Conn
}

type fastResult struct {
	index     int
	chunk     *api.ChunkData
	elapsedMS float64
	err       error
}

func main() {
	addr := flag.String("addr", "127.0.0.1:25565", "server TCP address")
	timeout := flag.Duration("timeout", 5*time.Second, "fast client read/write timeout")
	slowLead := flag.Duration("slow-lead", 250*time.Millisecond, "time to let the slow client pressure server writes before the fast client connects")
	postFastWait := flag.Duration("post-fast-wait", 750*time.Millisecond, "time to keep the slow client connected after the fast client succeeds")
	fastClients := flag.Int("fast-clients", 1, "number of fast clients that must receive bootstrap chunks while the slow client is connected")
	flag.Parse()

	if err := run(*addr, *timeout, *slowLead, *postFastWait, *fastClients); err != nil {
		fmt.Fprintf(os.Stderr, "server_slow_reader_smoke status=fail error=%q\n", err)
		os.Exit(1)
	}
}

func run(addr string, timeout, slowLead, postFastWait time.Duration, fastClients int) error {
	if fastClients < 1 {
		return fmt.Errorf("fast clients must be at least 1, got %d", fastClients)
	}

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

	fasts := make([]*smokeClient, 0, fastClients)
	for i := 0; i < fastClients; i++ {
		fast, err := dialClient(fmt.Sprintf("fast-%d", i+1), addr, timeout)
		if err != nil {
			closeClients(fasts)
			return err
		}
		fasts = append(fasts, fast)
	}
	defer closeClients(fasts)

	for i, fast := range fasts {
		if err := fast.sendPosition(float32(i*32+1), 68, 1, timeout); err != nil {
			return err
		}
	}

	done := make(chan struct{})
	resultCh := make(chan fastResult, fastClients)
	drainErrCh := make(chan error, fastClients)
	var wg sync.WaitGroup
	for i, fast := range fasts {
		wg.Add(1)
		go func(index int, client *smokeClient) {
			defer wg.Done()
			started := time.Now()
			chunk, err := client.readChunk(timeout)
			resultCh <- fastResult{
				index:     index,
				chunk:     chunk,
				elapsedMS: float64(time.Since(started).Microseconds()) / 1000.0,
				err:       err,
			}
			if err == nil {
				drainPackets(client, done, 100*time.Millisecond, drainErrCh)
			}
		}(i, fast)
	}

	fastBootstrapMS := 0.0
	for i := 0; i < fastClients; i++ {
		result := <-resultCh
		if result.err != nil {
			close(done)
			wg.Wait()
			return result.err
		}
		if result.elapsedMS > fastBootstrapMS {
			fastBootstrapMS = result.elapsedMS
		}
		if result.chunk.GetX() != int32(result.index) || result.chunk.GetZ() != 0 {
			close(done)
			wg.Wait()
			return fmt.Errorf("fast-%d bootstrap chunk = %d,%d, want %d,0", result.index+1, result.chunk.GetX(), result.chunk.GetZ(), result.index)
		}
	}

	time.Sleep(postFastWait)
	close(done)
	wg.Wait()
	select {
	case err := <-drainErrCh:
		return err
	default:
	}

	fmt.Printf(
		"server_slow_reader_smoke status=pass slow_client=1 fast_client=%d fast_clients=%d fast_bootstrap_chunk=%d fast_bootstrap_chunks=%d fast_bootstrap_ms=%.3f protocol_change=0\n",
		fastClients, fastClients, fastClients, fastClients, fastBootstrapMS,
	)
	return nil
}

func closeClients(clients []*smokeClient) {
	for _, client := range clients {
		_ = client.conn.Close()
	}
}

func drainPackets(client *smokeClient, done <-chan struct{}, timeout time.Duration, errCh chan<- error) {
	for {
		select {
		case <-done:
			return
		default:
		}

		if _, err := client.readPacket(timeout); err != nil {
			select {
			case <-done:
				return
			default:
			}
			if isTimeout(err) {
				continue
			}
			errCh <- fmt.Errorf("%s drain packet: %w", client.name, err)
			return
		}
	}
}

func isTimeout(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
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
