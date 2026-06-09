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

	data, err := proto.Marshal(packet)
	if err != nil {
		log.Printf("Failed to marshal packet: %v", err)
		return
	}

	// Отправляем длину пакета (4 байта), затем сам пакет
	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))

	if _, err := conn.Write(lenBuf); err != nil {
		log.Printf("Failed to write packet length: %v", err)
		return
	}
	if _, err := conn.Write(data); err != nil {
		log.Printf("Failed to write packet data: %v", err)
		return
	}

	log.Printf("Sent chunk data to %s", conn.RemoteAddr())
}
