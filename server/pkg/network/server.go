package network

import (
	"log"
	"net"
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
	// TODO: Handle packets
}
