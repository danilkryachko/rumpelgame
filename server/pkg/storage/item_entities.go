package storage

import (
	"encoding/json"
	"fmt"

	"rumpelmc/server/pkg/itementity"
)

const (
	itemEntityRecordVersion       = 2
	legacyItemEntityRecordVersion = 1
)

type persistedItemEntities struct {
	Version      uint32                `json:"version"`
	NextEntityID uint64                `json:"next_entity_id"`
	Revision     uint64                `json:"revision"`
	Entities     []persistedItemEntity `json:"entities"`
}

type persistedItemEntity struct {
	EntityID        uint64  `json:"entity_id"`
	ItemID          string  `json:"item_id"`
	Count           uint32  `json:"count"`
	X               float64 `json:"x"`
	Y               float64 `json:"y"`
	Z               float64 `json:"z"`
	SpawnedAtUnixMS int64   `json:"spawned_at_unix_ms,omitempty"`
}

func (s *RocksChunkStore) LoadItemEntities() (itementity.State, bool, error) {
	data, ok, err := s.getData(itemEntitiesKey())
	if err != nil {
		return itementity.State{}, false, fmt.Errorf("load RocksDB item entities: %w", err)
	}
	if !ok {
		return itementity.State{}, false, nil
	}

	state, err := decodeItemEntityState(data)
	if err != nil {
		return itementity.State{}, false, fmt.Errorf("decode RocksDB item entities: %w", err)
	}
	return state, true, nil
}

func (s *RocksChunkStore) SaveItemEntities(state itementity.State) error {
	data, err := encodeItemEntityState(state)
	if err != nil {
		return fmt.Errorf("encode RocksDB item entities: %w", err)
	}
	if err := s.putData(itemEntitiesKey(), data); err != nil {
		return fmt.Errorf("save RocksDB item entities: %w", err)
	}
	return nil
}

func encodeItemEntityState(state itementity.State) ([]byte, error) {
	normalized, err := itementity.NormalizeState(state)
	if err != nil {
		return nil, err
	}

	record := persistedItemEntities{
		Version:      itemEntityRecordVersion,
		NextEntityID: normalized.NextEntityID,
		Revision:     normalized.Revision,
		Entities:     make([]persistedItemEntity, len(normalized.Entities)),
	}
	for index, entity := range normalized.Entities {
		record.Entities[index] = persistedItemEntity{
			EntityID:        entity.EntityID,
			ItemID:          string(entity.ItemID),
			Count:           entity.Count,
			X:               entity.X,
			Y:               entity.Y,
			Z:               entity.Z,
			SpawnedAtUnixMS: entity.SpawnedAtUnixMS,
		}
	}
	return json.Marshal(record)
}

func decodeItemEntityState(data []byte) (itementity.State, error) {
	var record persistedItemEntities
	if err := json.Unmarshal(data, &record); err != nil {
		return itementity.State{}, err
	}
	if record.Version != itemEntityRecordVersion && record.Version != legacyItemEntityRecordVersion {
		return itementity.State{}, fmt.Errorf("unsupported version %d", record.Version)
	}

	state := itementity.State{
		Entities:     make([]itementity.Entity, len(record.Entities)),
		NextEntityID: record.NextEntityID,
		Revision:     record.Revision,
	}
	for index, entity := range record.Entities {
		state.Entities[index] = itementity.Entity{
			EntityID:        entity.EntityID,
			ItemID:          entity.ItemID,
			Count:           entity.Count,
			X:               entity.X,
			Y:               entity.Y,
			Z:               entity.Z,
			SpawnedAtUnixMS: entity.SpawnedAtUnixMS,
		}
	}
	return itementity.NormalizeState(state)
}

func itemEntitiesKey() []byte {
	return []byte{'i', 'e', 0}
}
