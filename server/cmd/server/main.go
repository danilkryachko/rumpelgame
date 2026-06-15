package main

import (
	"log"
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

	server := network.NewServer(":25565", gameWorld)
	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func defaultRocksDBPath() string {
	exe, err := os.Executable()
	if err != nil {
		return filepath.Join("data", "rocksdb")
	}
	return filepath.Join(filepath.Dir(exe), "data", "rocksdb")
}
