package main

import (
	"log"
	"rumpelmc/server/pkg/network"
)

func main() {
	log.Println("Starting Rumpelmc Server...")

	server := network.NewServer(":25565")
	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
