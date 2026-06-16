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
	"strconv"
	"strings"
)

func main() {
	log.Println("Starting Rumpelmc Server...")

	dbPath := defaultRocksDBPath()
	store, err := storage.OpenRocksChunkStore(dbPath)
	if err != nil {
		log.Fatalf("Failed to open RocksDB chunk store at %s: %v", dbPath, err)
	}

	generatorConfig, err := configuredWorldGeneratorConfig()
	if err != nil {
		log.Fatalf("Invalid world generator config: %v", err)
	}
	gameWorld, err := world.NewWorldWithGeneratorConfig(store, generatorConfig)
	if err != nil {
		log.Fatalf("Failed to create world generator: %v", err)
	}
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

func configuredWorldGeneratorConfig() (world.GeneratorConfig, error) {
	config := world.DefaultGeneratorConfig()

	if seed := strings.TrimSpace(os.Getenv("RUMPELMC_WORLD_SEED")); seed != "" {
		parsedSeed, err := strconv.ParseInt(seed, 10, 64)
		if err != nil {
			return world.GeneratorConfig{}, fmt.Errorf("RUMPELMC_WORLD_SEED must be a signed 64-bit integer: %w", err)
		}
		config.Seed = parsedSeed
	}

	if dimensionID := strings.TrimSpace(os.Getenv("RUMPELMC_WORLD_DIMENSION_ID")); dimensionID != "" {
		config.DimensionID = dimensionID
	}

	if version := strings.TrimSpace(os.Getenv("RUMPELMC_WORLD_GENERATOR_VERSION")); version != "" {
		config.Version = world.GeneratorVersion(version)
	}

	if _, err := world.NewWorldGenerator(config); err != nil {
		return world.GeneratorConfig{}, err
	}
	return config, nil
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
