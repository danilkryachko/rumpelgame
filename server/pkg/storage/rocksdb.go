package storage

/*
#cgo pkg-config: rocksdb
#include <stdlib.h>
#include <rocksdb/c.h>
*/
import "C"

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"unsafe"

	"rumpelmc/server/pkg/world"
)

type RocksChunkStore struct {
	db *C.rocksdb_t
	ro *C.rocksdb_readoptions_t
	wo *C.rocksdb_writeoptions_t
}

func OpenRocksChunkStore(path string) (*RocksChunkStore, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}

	opts := C.rocksdb_options_create()
	if opts == nil {
		return nil, fmt.Errorf("failed to create RocksDB options")
	}
	defer C.rocksdb_options_destroy(opts)
	C.rocksdb_options_set_create_if_missing(opts, 1)

	cPath := C.CString(path)
	defer C.free(unsafe.Pointer(cPath))

	var cErr *C.char
	db := C.rocksdb_open(opts, cPath, &cErr)
	if cErr != nil {
		return nil, takeRocksError(cErr)
	}
	if db == nil {
		return nil, fmt.Errorf("rocksdb_open returned nil")
	}

	store := &RocksChunkStore{
		db: db,
		ro: C.rocksdb_readoptions_create(),
		wo: C.rocksdb_writeoptions_create(),
	}
	if store.ro == nil || store.wo == nil {
		store.Close()
		return nil, fmt.Errorf("failed to create RocksDB read/write options")
	}
	return store, nil
}

func (s *RocksChunkStore) LoadChunk(x, z int32) (*world.Chunk, bool, error) {
	key := chunkKey(x, z)

	var cErr *C.char
	var valueLen C.size_t
	value := C.rocksdb_get(
		s.db,
		s.ro,
		(*C.char)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
		&valueLen,
		&cErr,
	)
	if cErr != nil {
		return nil, false, takeRocksError(cErr)
	}
	if value == nil {
		return nil, false, nil
	}
	defer C.rocksdb_free(unsafe.Pointer(value))

	data := C.GoBytes(unsafe.Pointer(value), C.int(valueLen))
	chunk, err := world.DeserializeChunk(x, z, data)
	if err != nil {
		return nil, false, err
	}
	return chunk, true, nil
}

func (s *RocksChunkStore) SaveChunk(chunk *world.Chunk) error {
	key := chunkKey(chunk.X, chunk.Z)
	data := chunk.Serialize()

	var cErr *C.char
	C.rocksdb_put(
		s.db,
		s.wo,
		(*C.char)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
		(*C.char)(unsafe.Pointer(&data[0])),
		C.size_t(len(data)),
		&cErr,
	)
	if cErr != nil {
		return takeRocksError(cErr)
	}
	return nil
}

func (s *RocksChunkStore) Close() {
	if s.wo != nil {
		C.rocksdb_writeoptions_destroy(s.wo)
		s.wo = nil
	}
	if s.ro != nil {
		C.rocksdb_readoptions_destroy(s.ro)
		s.ro = nil
	}
	if s.db != nil {
		C.rocksdb_close(s.db)
		s.db = nil
	}
}

func takeRocksError(cErr *C.char) error {
	err := fmt.Errorf("%s", C.GoString(cErr))
	C.rocksdb_free(unsafe.Pointer(cErr))
	return err
}

func chunkKey(x, z int32) []byte {
	key := make([]byte, 9)
	key[0] = 'c'
	binary.BigEndian.PutUint32(key[1:5], uint32(x)^0x80000000)
	binary.BigEndian.PutUint32(key[5:9], uint32(z)^0x80000000)
	return key
}
