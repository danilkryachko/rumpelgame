package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"rumpelmc/server/pkg/network"
	"rumpelmc/server/pkg/storage"
	"rumpelmc/server/pkg/world"
)

func main() {
	log.Println("Starting Rumpelmc Server...")

	dbPath := defaultRocksDBPath()
	store, err := storage.OpenRocksChunkStore(dbPath)
	if err != nil {
		log.Fatalf("Failed to open RocksDB chunk store at %s: %v", dbPath, err)
	}

	gameWorld := world.NewWorld(store)
	defer gameWorld.Close()

	address, err := configuredServerAddress()
	if err != nil {
		log.Fatalf("Invalid server address: %v", err)
	}

	server := network.NewServer(address, gameWorld)
	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func configuredServerAddress() (string, error) {
	if address := os.Getenv("RUMPELMC_SERVER_ADDRESS"); address != "" {
		if !isLoopbackAddress(address) {
			return "", fmt.Errorf("RUMPELMC_SERVER_ADDRESS must use a loopback host until auth/encryption exists: %q", address)
		}
		return address, nil
	}
	return "127.0.0.1:25565", nil
}

func isLoopbackAddress(address string) bool {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return false
	}
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func defaultRocksDBPath() string {
	if path := os.Getenv("RUMPELMC_SERVER_ROCKSDB_PATH"); path != "" {
		return path
	}
	exe, err := os.Executable()
	if err != nil {
		return filepath.Join("data", "rocksdb")
	}
	return filepath.Join(filepath.Dir(exe), "data", "rocksdb")
}
