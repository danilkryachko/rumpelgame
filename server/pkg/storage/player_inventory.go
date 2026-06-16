package storage

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	playerinventory "rumpelmc/server/pkg/inventory"
	"rumpelmc/server/pkg/world"
)

const (
	playerInventoryRecordVersion = 1
	maxPlayerInventoryIDBytes    = 128
	maxPlayerInventorySlots      = 64
)

var (
	errEmptyPlayerInventoryID = errors.New("player inventory id cannot be empty")
	errLongPlayerInventoryID  = errors.New("player inventory id is too long")
	errInvalidPlayerID        = errors.New("player inventory id cannot contain NUL")
)

type persistedPlayerInventory struct {
	Version         uint32                         `json:"version"`
	PlacementPolicy string                         `json:"placement_policy"`
	SelectedSlot    uint32                         `json:"selected_slot"`
	Slots           []persistedPlayerInventorySlot `json:"slots"`
}

type persistedPlayerInventorySlot struct {
	BlockID uint32 `json:"block_id"`
	Count   uint32 `json:"count"`
}

func (s *RocksChunkStore) LoadPlayerInventory(playerID string) (playerinventory.State, bool, error) {
	key, err := playerInventoryKey(playerID)
	if err != nil {
		return playerinventory.State{}, false, fmt.Errorf("load RocksDB player inventory %q: %w", playerID, err)
	}

	data, ok, err := s.getData(key)
	if err != nil {
		return playerinventory.State{}, false, fmt.Errorf("load RocksDB player inventory %q: %w", playerID, err)
	}
	if !ok {
		return playerinventory.State{}, false, nil
	}

	state, err := decodePlayerInventoryState(data)
	if err != nil {
		return playerinventory.State{}, false, fmt.Errorf("decode RocksDB player inventory %q: %w", playerID, err)
	}
	return state, true, nil
}

func (s *RocksChunkStore) SavePlayerInventory(playerID string, state playerinventory.State) error {
	key, err := playerInventoryKey(playerID)
	if err != nil {
		return fmt.Errorf("save RocksDB player inventory %q: %w", playerID, err)
	}

	data, err := encodePlayerInventoryState(state)
	if err != nil {
		return fmt.Errorf("encode RocksDB player inventory %q: %w", playerID, err)
	}
	if err := s.putData(key, data); err != nil {
		return fmt.Errorf("save RocksDB player inventory %q: %w", playerID, err)
	}
	return nil
}

func encodePlayerInventoryState(state playerinventory.State) ([]byte, error) {
	if err := validatePlacementPolicy(state.PlacementPolicy); err != nil {
		return nil, err
	}
	if len(state.Slots) > maxPlayerInventorySlots {
		return nil, fmt.Errorf("slot count %d exceeds max %d", len(state.Slots), maxPlayerInventorySlots)
	}

	record := persistedPlayerInventory{
		Version:         playerInventoryRecordVersion,
		PlacementPolicy: string(state.PlacementPolicy),
		SelectedSlot:    state.SelectedSlot,
		Slots:           make([]persistedPlayerInventorySlot, len(state.Slots)),
	}
	for index, slot := range state.Slots {
		record.Slots[index] = persistedPlayerInventorySlot{
			BlockID: uint32(slot.BlockID),
			Count:   slot.Count,
		}
	}
	return json.Marshal(record)
}

func decodePlayerInventoryState(data []byte) (playerinventory.State, error) {
	var record persistedPlayerInventory
	if err := json.Unmarshal(data, &record); err != nil {
		return playerinventory.State{}, err
	}
	if record.Version != playerInventoryRecordVersion {
		return playerinventory.State{}, fmt.Errorf("unsupported version %d", record.Version)
	}

	policy := playerinventory.PlacementPolicy(record.PlacementPolicy)
	if err := validatePlacementPolicy(policy); err != nil {
		return playerinventory.State{}, err
	}
	if len(record.Slots) > maxPlayerInventorySlots {
		return playerinventory.State{}, fmt.Errorf("slot count %d exceeds max %d", len(record.Slots), maxPlayerInventorySlots)
	}

	state := playerinventory.State{
		Slots:           make([]playerinventory.Slot, len(record.Slots)),
		PlacementPolicy: policy,
		SelectedSlot:    record.SelectedSlot,
	}
	for index, slot := range record.Slots {
		state.Slots[index] = playerinventory.Slot{
			BlockID: world.BlockID(slot.BlockID),
			Count:   slot.Count,
		}
	}
	return state, nil
}

func validatePlacementPolicy(policy playerinventory.PlacementPolicy) error {
	switch policy {
	case playerinventory.PlacementPolicyRetain, playerinventory.PlacementPolicyConsume:
		return nil
	default:
		return fmt.Errorf("unsupported placement policy %q", policy)
	}
}

func playerInventoryKey(playerID string) ([]byte, error) {
	if playerID == "" {
		return nil, errEmptyPlayerInventoryID
	}
	if len(playerID) > maxPlayerInventoryIDBytes {
		return nil, errLongPlayerInventoryID
	}
	if strings.ContainsRune(playerID, 0) {
		return nil, errInvalidPlayerID
	}

	key := make([]byte, 3+len(playerID))
	copy(key, []byte{'p', 'i', 0})
	copy(key[3:], playerID)
	return key, nil
}
