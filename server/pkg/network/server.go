package network

import (
	"encoding/binary"
	"log"
	"net"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

type Server struct {
	address string
}

func NewServer(address string) *Server {
	return &Server{
		address: address,
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

	// Генерируем тестовый чанк и отправляем его
	chunk := world.NewChunk(0, 0)
	chunk.GenerateFlat()

	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:      chunk.X,
				Z:      chunk.Z,
				Blocks: chunk.Serialize(),
			},
		},
	}

	if err := s.sendPacket(conn, packet); err != nil {
		log.Printf("Failed to send chunk: %v", err)
		return
	}
	log.Printf("Sent chunk data to %s", conn.RemoteAddr())

	// Чтение пакетов в цикле
	for {
		lenBuf := make([]byte, 4)
		if _, err := conn.Read(lenBuf); err != nil {
			log.Printf("Client disconnected: %v", err)
			return
		}
		length := binary.LittleEndian.Uint32(lenBuf)

		dataBuf := make([]byte, length)
		if _, err := conn.Read(dataBuf); err != nil {
			log.Printf("Error reading packet: %v", err)
			return
		}

		clientPacket := &api.Packet{}
		if err := proto.Unmarshal(dataBuf, clientPacket); err != nil {
			log.Printf("Error unmarshaling: %v", err)
			continue
		}

		switch p := clientPacket.Payload.(type) {
		case *api.Packet_BlockAction:
			action := p.BlockAction
			log.Printf("Received BlockAction: action=%v, x=%d, y=%d, z=%d", action.Action, action.X, action.Y, action.Z)

			if action.Action == api.BlockAction_DESTROY {
				chunk.SetBlock(int(action.X), int(action.Y), int(action.Z), world.BlockID(0))
			} else if action.Action == api.BlockAction_PLACE {
				chunk.SetBlock(int(action.X), int(action.Y), int(action.Z), world.BlockID(action.BlockId))
			}

			// Отправляем обновленный чанк обратно
			updatePacket := &api.Packet{
				Payload: &api.Packet_Chunk{
					Chunk: &api.ChunkData{
						X:      chunk.X,
						Z:      chunk.Z,
						Blocks: chunk.Serialize(),
					},
				},
			}
			s.sendPacket(conn, updatePacket)

		default:
			log.Printf("Unknown packet received")
		}
	}
}

func (s *Server) sendPacket(conn net.Conn, packet *api.Packet) error {
	data, err := proto.Marshal(packet)
	if err != nil {
		return err
	}

	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))

	if _, err := conn.Write(lenBuf); err != nil {
		return err
	}
	if _, err := conn.Write(data); err != nil {
		return err
	}
	return nil
}
