package network

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	playerinventory "rumpelmc/server/pkg/inventory"
	"rumpelmc/server/pkg/item"
	"rumpelmc/server/pkg/itementity"
	"rumpelmc/server/pkg/world"
)

const maxPacketSize = 16 * 1024 * 1024
const defaultViewDistance int32 = 10
const maxViewDistance int32 = 16
const defaultChunksPerUpdate = 64
const defaultBootstrapRadius int32 = 0
const defaultClientWriteTimeout = 2 * time.Second
const defaultMaxClients = 0
const viewDistanceEnv = "RUMPELMC_SERVER_VIEW_DISTANCE"
const chunksPerUpdateEnv = "RUMPELMC_SERVER_CHUNKS_PER_UPDATE"
const bootstrapRadiusEnv = "RUMPELMC_SERVER_BOOTSTRAP_RADIUS"
const chunkStreamMetricsEnv = "RUMPELMC_SERVER_CHUNK_STREAM_METRICS"
const chunkEncodingEnv = "RUMPELMC_SERVER_CHUNK_ENCODING"
const chunkOrderEnv = "RUMPELMC_SERVER_CHUNK_ORDER"
const clientWriteTimeoutEnv = "RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS"
const maxClientsEnv = "RUMPELMC_SERVER_MAX_CLIENTS"
const inventoryModeEnv = "RUMPELMC_SERVER_INVENTORY_MODE"
const miningCooldownEnv = "RUMPELMC_SERVER_MINING_COOLDOWN_MS"
const itemEntityDespawnEnv = "RUMPELMC_SERVER_ITEM_ENTITY_DESPAWN_MS"
const initialClientPacketTimeout = 250 * time.Millisecond
const maxPlayerIDLength = 64
const serverBlockActionReach = 7.0
const serverBlockActionReachSquared = serverBlockActionReach * serverBlockActionReach
const serverPlayerCollisionHalfWidth = 0.4
const serverPlayerCollisionHeight = 1.8
const serverItemPickupReach = 6.0
const serverItemPickupReachSquared = serverItemPickupReach * serverItemPickupReach
const serverItemEntityMergeRadius = 1.25
const serverItemEntityMergeRadiusSquared = serverItemEntityMergeRadius * serverItemEntityMergeRadius
const defaultItemEntityDespawn = 5 * time.Minute
const defaultCountedMiningCooldown = time.Duration(world.DefaultBlockMiningMS) * time.Millisecond

type networkErrorClass string

const (
	networkErrorNone              networkErrorClass = "none"
	networkErrorEOF               networkErrorClass = "eof"
	networkErrorShortFrame        networkErrorClass = "short_frame"
	networkErrorOversizedFrame    networkErrorClass = "oversized_frame"
	networkErrorMalformedProtobuf networkErrorClass = "malformed_protobuf"
	networkErrorTimeout           networkErrorClass = "timeout"
	networkErrorShortWrite        networkErrorClass = "short_write"
	networkErrorEncode            networkErrorClass = "encode_error"
	networkErrorOther             networkErrorClass = "other"
)

var (
	errPacketTooLarge  = errors.New("packet too large")
	errMalformedPacket = errors.New("malformed protobuf")
	errPacketEncode    = errors.New("packet encode")
)

type playerInventoryStore interface {
	LoadPlayerInventory(playerID string) (playerinventory.State, bool, error)
	SavePlayerInventory(playerID string, state playerinventory.State) error
}

type itemEntityStore interface {
	LoadItemEntities() (itementity.State, bool, error)
	SaveItemEntities(state itementity.State) error
}

type chunkOrderMode string

const (
	chunkOrderNearest     chunkOrderMode = "nearest"
	chunkOrderDirectional chunkOrderMode = "directional"
)

type inventoryMode string

const (
	inventoryModeCreative inventoryMode = "creative"
	inventoryModeCounted  inventoryMode = "counted"
)

type itemEntity struct {
	entityID  uint64
	itemID    item.ID
	count     uint32
	x         float64
	y         float64
	z         float64
	spawnedAt time.Time
}

type Server struct {
	address                string
	world                  *world.World
	viewDistance           int32
	bootstrapRadius        int32
	chunksPerUpdate        int
	chunkEncoding          api.ChunkEncoding
	chunkOrderMode         chunkOrderMode
	writeTimeout           time.Duration
	maxClients             int
	inventoryMode          inventoryMode
	miningCooldown         time.Duration
	miningCooldownOverride bool
	itemEntityDespawn      time.Duration
	miningDurations        map[world.BlockID]time.Duration
	now                    func() time.Time
	inventoryStore         playerInventoryStore
	itemEntityStore        itemEntityStore
	itemEntitiesMu         sync.Mutex
	itemEntities           map[uint64]itemEntity
	nextItemEntityID       uint64
	itemEntityRevision     uint64
	clientsMu              sync.Mutex
	clients                map[*clientSession]struct{}
}

func NewServer(address string, gameWorld *world.World) *Server {
	viewDistance := configuredViewDistance()
	inventoryMode := configuredInventoryMode()
	miningCooldown, miningCooldownOverride := configuredMiningCooldownWithOverride(inventoryMode)
	return &Server{
		address:                address,
		world:                  gameWorld,
		viewDistance:           viewDistance,
		bootstrapRadius:        configuredBootstrapRadius(viewDistance),
		chunksPerUpdate:        configuredChunksPerUpdate(),
		chunkEncoding:          configuredChunkEncoding(),
		chunkOrderMode:         configuredChunkOrderMode(),
		writeTimeout:           configuredClientWriteTimeout(),
		maxClients:             configuredMaxClients(),
		inventoryMode:          inventoryMode,
		miningCooldown:         miningCooldown,
		miningCooldownOverride: miningCooldownOverride,
		itemEntityDespawn:      configuredItemEntityDespawn(),
		miningDurations:        configuredMiningDurations(inventoryMode, miningCooldown, miningCooldownOverride),
		now:                    time.Now,
		itemEntities:           make(map[uint64]itemEntity),
		nextItemEntityID:       1,
		clients:                make(map[*clientSession]struct{}),
	}
}

func NewServerWithPlayerInventoryStore(address string, gameWorld *world.World, inventoryStore playerInventoryStore) *Server {
	server := NewServer(address, gameWorld)
	server.inventoryStore = inventoryStore
	if itemStore, ok := inventoryStore.(itemEntityStore); ok {
		server.itemEntityStore = itemStore
	}
	return server
}

func (s *Server) Start() error {
	if err := s.loadItemEntitiesFromStore(); err != nil {
		return err
	}

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

	client := s.newClientSession(conn)
	activeClients, admitted := s.tryRegisterClient(client)
	if !admitted {
		log.Printf("Client rejected by admission limit admission_result=rejected active_clients=%d max_clients=%d address=%s", activeClients, s.maxClients, conn.RemoteAddr())
		return
	}
	log.Printf("Client connected: %s active_clients=%d max_clients=%d", conn.RemoteAddr(), activeClients, s.maxClients)
	defer s.unregisterClient(client)

	if err := s.sendInventorySnapshotToSession(client); err != nil {
		log.Printf("Failed to send inventory snapshot packet_error_class=%s: %v", classifyNetworkError(err), err)
		return
	}
	if err := s.sendItemEntitySnapshotToSessionIfNotEmpty(client); err != nil {
		log.Printf("Failed to send item entity snapshot packet_error_class=%s: %v", classifyNetworkError(err), err)
		return
	}

	firstPacket, hasFirstPacket, err := s.receiveInitialClientPacket(conn)
	if err != nil {
		log.Printf("Client disconnected before initial chunk stream packet_error_class=%s: %v", classifyNetworkError(err), err)
		return
	}
	if hasFirstPacket {
		if err := s.handleInitialClientPacketForSession(client, firstPacket); err != nil {
			log.Printf("Failed to handle initial client packet packet_error_class=%s: %v", classifyNetworkError(err), err)
			return
		}
	} else {
		if err := s.sendChunksAroundWithRadiusForSession(client, 0, 0, s.bootstrapRadius, world.ChunkOrder{}); err != nil {
			log.Printf("Failed to send initial chunks packet_error_class=%s: %v", classifyNetworkError(err), err)
			return
		}
	}
	log.Printf("Started progressive chunk stream radius=%d bootstrap_radius=%d batch=%d to %s", s.viewDistance, s.bootstrapRadius, s.chunksPerUpdate, conn.RemoteAddr())

	// Read client packets until the connection closes.
	for {
		clientPacket, err := s.receivePacket(conn)
		if err != nil {
			log.Printf("Client disconnected packet_error_class=%s: %v", classifyNetworkError(err), err)
			return
		}

		if err := s.handleClientPacketForSession(client, clientPacket); err != nil {
			log.Printf("Failed to handle client packet packet_error_class=%s: %v", classifyNetworkError(err), err)
			return
		}
	}
}

func (s *Server) registerClient(client *clientSession) {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()

	s.clients[client] = struct{}{}
}

func (s *Server) tryRegisterClient(client *clientSession) (int, bool) {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()

	activeClients := len(s.clients)
	if s.maxClients > 0 && activeClients >= s.maxClients {
		return activeClients, false
	}
	s.clients[client] = struct{}{}
	return activeClients + 1, true
}

func (s *Server) unregisterClient(client *clientSession) {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()

	delete(s.clients, client)
}

func (s *Server) disconnectClient(client *clientSession) {
	s.unregisterClient(client)
	if err := client.conn.Close(); err != nil {
		log.Printf("Failed to close client %s: %v", client.conn.RemoteAddr(), err)
	}
}

func (s *Server) handleInitialClientPacket(conn net.Conn, clientPacket *api.Packet, sentChunks map[world.ChunkCoord]bool) error {
	streamState := clientChunkStreamState{sentChunks: sentChunks}
	return s.handleInitialClientPacketWithState(conn, clientPacket, &streamState)
}

func (s *Server) handleInitialClientPacketWithState(conn net.Conn, clientPacket *api.Packet, streamState *clientChunkStreamState) error {
	if clientPacket == nil {
		log.Printf("Ignored nil client packet")
		return nil
	}
	switch p := clientPacket.Payload.(type) {
	case *api.Packet_Position:
		if p.Position == nil {
			log.Printf("Ignored nil client position")
			return nil
		}
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		forgetFarSentChunks(streamState.sentChunks, center.X, center.Z, s.viewDistance+1)
		if err := s.sendChunksAroundWithRadius(conn, center.X, center.Z, s.bootstrapRadius, streamState.sentChunks); err != nil {
			return fmt.Errorf("send bootstrap chunks around %d,%d: %w", center.X, center.Z, err)
		}
		streamState.recordCenter(center)
		return nil
	default:
		return s.handleClientPacketWithState(conn, clientPacket, streamState)
	}
}

func (s *Server) handleInitialClientPacketForSession(client *clientSession, clientPacket *api.Packet) error {
	if clientPacket == nil {
		log.Printf("Ignored nil client packet")
		return nil
	}
	switch p := clientPacket.Payload.(type) {
	case *api.Packet_Position:
		if p.Position == nil {
			log.Printf("Ignored nil client position")
			return nil
		}
		loadedInventory, err := s.bindPlayerInventoryFromPosition(client, p.Position)
		if err != nil {
			return err
		}
		if loadedInventory {
			if err := s.sendInventorySnapshotToSession(client); err != nil {
				return fmt.Errorf("send inventory snapshot: %w", err)
			}
		}
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		if err := s.sendChunksAroundWithRadiusForSession(client, center.X, center.Z, s.bootstrapRadius, world.ChunkOrder{}); err != nil {
			return fmt.Errorf("send bootstrap chunks around %d,%d: %w", center.X, center.Z, err)
		}
		client.recordPosition(p.Position)
		client.recordCenter(center)
		return nil
	default:
		return s.handleClientPacketForSession(client, clientPacket)
	}
}

func (s *Server) handleClientPacket(conn net.Conn, clientPacket *api.Packet, sentChunks map[world.ChunkCoord]bool) error {
	streamState := clientChunkStreamState{sentChunks: sentChunks}
	return s.handleClientPacketWithState(conn, clientPacket, &streamState)
}

func (s *Server) handleClientPacketWithState(conn net.Conn, clientPacket *api.Packet, streamState *clientChunkStreamState) error {
	if clientPacket == nil {
		log.Printf("Ignored nil client packet")
		return nil
	}
	switch p := clientPacket.Payload.(type) {
	case *api.Packet_Position:
		if p.Position == nil {
			log.Printf("Ignored nil client position")
			return nil
		}
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		order := streamState.chunkOrderForCenter(center, s.chunkOrderMode)
		forgetFarSentChunks(streamState.sentChunks, center.X, center.Z, s.viewDistance+1)
		if err := s.sendChunksAroundOrdered(conn, center.X, center.Z, streamState.sentChunks, order); err != nil {
			return fmt.Errorf("send chunks around %d,%d: %w", center.X, center.Z, err)
		}
		streamState.recordCenter(center)

	case *api.Packet_BlockAction:
		action := p.BlockAction
		if action == nil {
			log.Printf("Ignored nil block action")
			return nil
		}
		log.Printf("Received BlockAction: action=%v, x=%d, y=%d, z=%d", action.Action, action.X, action.Y, action.Z)

		block := world.Air
		applyInventoryPlacement := false
		placementInventory := playerinventory.NewCreativeHotbar()
		switch action.Action {
		case api.BlockAction_DESTROY:
			block = world.Air
		case api.BlockAction_PLACE:
			block = world.BlockID(action.BlockId)
			if !world.IsPlaceable(block) || !placementInventory.CanPlaceBlock(block) {
				log.Printf("Ignored invalid place block id=%d", action.BlockId)
				return nil
			}
			applyInventoryPlacement = true
		default:
			log.Printf("Ignored unknown block action=%v", action.Action)
			return nil
		}

		snapshot, err := s.world.SetBlockGlobal(action.X, action.Y, action.Z, block)
		if err != nil {
			return fmt.Errorf("update block: %w", err)
		}
		if applyInventoryPlacement {
			placementInventory.PlaceBlock(block)
		}

		if _, err := s.sendChunk(conn, snapshot); err != nil {
			return fmt.Errorf("send updated chunk %d,%d: %w", snapshot.X, snapshot.Z, err)
		}

	case *api.Packet_InventoryAction:
		if p.InventoryAction == nil {
			log.Printf("Ignored nil inventory action")
			return nil
		}
		log.Printf("Ignored inventory action without session")

	case *api.Packet_ItemPickup:
		if p.ItemPickup == nil {
			log.Printf("Ignored nil item pickup")
			return nil
		}
		log.Printf("Ignored item pickup without session")

	default:
		log.Printf("Unknown packet received")
	}
	return nil
}

func (s *Server) handleClientPacketForSession(client *clientSession, clientPacket *api.Packet) error {
	if clientPacket == nil {
		log.Printf("Ignored nil client packet")
		return nil
	}
	switch p := clientPacket.Payload.(type) {
	case *api.Packet_Position:
		if p.Position == nil {
			log.Printf("Ignored nil client position")
			return nil
		}
		loadedInventory, err := s.bindPlayerInventoryFromPosition(client, p.Position)
		if err != nil {
			return err
		}
		if loadedInventory {
			if err := s.sendInventorySnapshotToSession(client); err != nil {
				return fmt.Errorf("send inventory snapshot: %w", err)
			}
		}
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		order := client.chunkOrderForCenter(center, s.chunkOrderMode)
		if err := s.sendChunksAroundForSession(client, center.X, center.Z, order); err != nil {
			return fmt.Errorf("send chunks around %d,%d: %w", center.X, center.Z, err)
		}
		client.recordPosition(p.Position)
		client.recordCenter(center)

	case *api.Packet_BlockAction:
		action := p.BlockAction
		if action == nil {
			log.Printf("Ignored nil block action")
			return nil
		}
		log.Printf("Received BlockAction: action=%v, x=%d, y=%d, z=%d", action.Action, action.X, action.Y, action.Z)

		block := world.Air
		applyInventoryPlacement := false
		switch action.Action {
		case api.BlockAction_DESTROY:
			block = world.Air
		case api.BlockAction_PLACE:
			block = world.BlockID(action.BlockId)
			if !world.IsPlaceable(block) || !client.inventory.CanPlaceBlock(block) {
				log.Printf("Ignored invalid place block id=%d", action.BlockId)
				return nil
			}
			applyInventoryPlacement = true
		default:
			log.Printf("Ignored unknown block action=%v", action.Action)
			return nil
		}
		position := client.recordedPosition()
		if !blockActionWithinReach(position, action) {
			log.Printf("Ignored out-of-reach block action=%v, x=%d, y=%d, z=%d", action.Action, action.X, action.Y, action.Z)
			return nil
		}
		if action.Action == api.BlockAction_PLACE && blockActionIntersectsPlayer(position, action) {
			log.Printf("Ignored player-intersecting block placement x=%d, y=%d, z=%d", action.X, action.Y, action.Z)
			return nil
		}
		actionTime := s.currentTime()
		if action.Action == api.BlockAction_DESTROY {
			targetBlock, err := s.world.BlockAtGlobal(action.X, action.Y, action.Z)
			if err != nil {
				return fmt.Errorf("read block for destroy cooldown: %w", err)
			}
			miningDuration := s.miningDurationForBlockWithTool(targetBlock, client.selectedToolID())
			if !client.destroyCooldownReady(actionTime, miningDuration) {
				log.Printf("Ignored mining cooldown block action x=%d, y=%d, z=%d block_id=%d cooldown=%s", action.X, action.Y, action.Z, targetBlock, miningDuration)
				return nil
			}
		}

		snapshot, previousBlock, err := s.world.ReplaceBlockGlobal(action.X, action.Y, action.Z, block)
		if err != nil {
			return fmt.Errorf("update block: %w", err)
		}
		inventoryChanged := false
		itemEntitiesChanged := false
		if applyInventoryPlacement {
			if !client.placeInventoryBlock(block) {
				return fmt.Errorf("place inventory block %d: unavailable", block)
			}
			if err := s.saveClientInventory(client); err != nil {
				return err
			}
			inventoryChanged = true
		}
		if action.Action == api.BlockAction_DESTROY && world.IsPlaceable(previousBlock) {
			itemEntitiesChanged, err = s.spawnItemEntityForBlock(previousBlock, action.X, action.Y, action.Z)
			if err != nil {
				if _, _, rollbackErr := s.world.ReplaceBlockGlobal(action.X, action.Y, action.Z, previousBlock); rollbackErr != nil {
					return fmt.Errorf("spawn item entity: %w; rollback block edit: %v", err, rollbackErr)
				}
				return err
			}
			client.recordSuccessfulDestroy(actionTime)
		}

		if err := s.broadcastChunkUpdate(client, snapshot); err != nil {
			return fmt.Errorf("send updated chunk %d,%d: %w", snapshot.X, snapshot.Z, err)
		}
		if itemEntitiesChanged {
			if err := s.broadcastItemEntitySnapshot(client); err != nil {
				return fmt.Errorf("send item entity snapshot: %w", err)
			}
		}
		if inventoryChanged {
			if err := s.sendInventorySnapshotToSession(client); err != nil {
				return fmt.Errorf("send inventory snapshot: %w", err)
			}
		}

	case *api.Packet_InventoryAction:
		action := p.InventoryAction
		if action == nil {
			log.Printf("Ignored nil inventory action")
			return nil
		}
		log.Printf("Received InventoryAction: action=%v, slot=%d, tool_slot=%d", action.Action, action.Slot, action.ToolSlot)

		switch action.Action {
		case api.InventoryAction_SELECT_SLOT:
			if !client.selectInventorySlot(action.Slot) {
				log.Printf("Ignored invalid inventory slot=%d", action.Slot)
				if err := s.sendInventorySnapshotToSession(client); err != nil {
					return fmt.Errorf("send inventory snapshot: %w", err)
				}
				return nil
			}
			if err := s.saveClientInventory(client); err != nil {
				return err
			}
			if err := s.sendInventorySnapshotToSession(client); err != nil {
				return fmt.Errorf("send inventory snapshot: %w", err)
			}
		case api.InventoryAction_SELECT_TOOL_SLOT:
			if !client.selectToolSlot(action.ToolSlot) {
				log.Printf("Ignored invalid tool slot=%d", action.ToolSlot)
				if err := s.sendInventorySnapshotToSession(client); err != nil {
					return fmt.Errorf("send inventory snapshot: %w", err)
				}
				return nil
			}
			if err := s.sendInventorySnapshotToSession(client); err != nil {
				return fmt.Errorf("send inventory snapshot: %w", err)
			}
		default:
			log.Printf("Ignored unknown inventory action=%v", action.Action)
			return nil
		}

	case *api.Packet_ItemPickup:
		action := p.ItemPickup
		if action == nil {
			log.Printf("Ignored nil item pickup")
			return nil
		}
		log.Printf("Received ItemPickupAction: entity_id=%d", action.EntityId)

		collected, err := s.collectItemEntityForSession(client, action.EntityId)
		if err != nil {
			return err
		}
		if !collected {
			if err := s.sendItemEntitySnapshotToSession(client); err != nil {
				return fmt.Errorf("send item entity snapshot: %w", err)
			}
			return nil
		}
		if err := s.broadcastItemEntitySnapshot(client); err != nil {
			return fmt.Errorf("send item entity snapshot: %w", err)
		}
		if err := s.sendInventorySnapshotToSession(client); err != nil {
			return fmt.Errorf("send inventory snapshot: %w", err)
		}

	default:
		log.Printf("Unknown packet received")
	}
	return nil
}

func (s *Server) bindPlayerInventoryFromPosition(client *clientSession, position *api.ClientPosition) (bool, error) {
	if s.inventoryStore == nil || position == nil {
		return false, nil
	}

	playerID, ok := normalizedPlayerID(position.GetPlayerId())
	if !ok {
		return false, nil
	}
	if !client.bindPlayerID(playerID) {
		return false, nil
	}

	state, found, err := s.inventoryStore.LoadPlayerInventory(playerID)
	if err != nil {
		return false, fmt.Errorf("load player inventory %q: %w", playerID, err)
	}
	if found {
		client.applyInventoryState(state)
		return true, nil
	}
	if err := s.saveClientInventory(client); err != nil {
		return false, err
	}
	return false, nil
}

func (s *Server) saveClientInventory(client *clientSession) error {
	if s.inventoryStore == nil {
		return nil
	}

	playerID, state, ok := client.inventoryState()
	if !ok {
		return nil
	}
	return s.saveClientInventoryState(playerID, state)
}

func (s *Server) saveClientInventoryState(playerID string, state playerinventory.State) error {
	if s.inventoryStore == nil || playerID == "" {
		return nil
	}
	if err := s.inventoryStore.SavePlayerInventory(playerID, state); err != nil {
		return fmt.Errorf("save player inventory %q: %w", playerID, err)
	}
	return nil
}

func (s *Server) loadItemEntitiesFromStore() error {
	if s.itemEntityStore == nil {
		return nil
	}

	state, found, err := s.itemEntityStore.LoadItemEntities()
	if err != nil {
		return fmt.Errorf("load item entities: %w", err)
	}
	if !found {
		return nil
	}

	entities := make(map[uint64]itemEntity, len(state.Entities))
	var maxEntityID uint64
	now := s.currentTime()
	for _, entity := range state.Entities {
		entities[entity.EntityID] = itemEntity{
			entityID:  entity.EntityID,
			itemID:    item.ID(entity.ItemID),
			count:     entity.Count,
			x:         entity.X,
			y:         entity.Y,
			z:         entity.Z,
			spawnedAt: itemEntitySpawnedAtFromUnixMS(entity.SpawnedAtUnixMS, now),
		}
		if entity.EntityID > maxEntityID {
			maxEntityID = entity.EntityID
		}
	}

	nextEntityID := state.NextEntityID
	if nextEntityID == 0 || nextEntityID <= maxEntityID {
		nextEntityID = maxEntityID + 1
		if nextEntityID == 0 {
			nextEntityID = 1
		}
	}

	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()
	s.itemEntities = entities
	s.nextItemEntityID = nextEntityID
	s.itemEntityRevision = state.Revision
	if s.pruneExpiredItemEntitiesLocked(now) {
		if err := s.saveItemEntitiesLocked(); err != nil {
			return fmt.Errorf("save item entities after load despawn: %w", err)
		}
	}
	return nil
}

func normalizedPlayerID(playerID string) (string, bool) {
	playerID = strings.TrimSpace(playerID)
	if playerID == "" || len(playerID) > maxPlayerIDLength {
		return "", false
	}
	for _, r := range playerID {
		if r >= 'a' && r <= 'z' {
			continue
		}
		if r >= 'A' && r <= 'Z' {
			continue
		}
		if r >= '0' && r <= '9' {
			continue
		}
		switch r {
		case '.', '_', '-':
			continue
		default:
			return "", false
		}
	}
	return playerID, true
}

type clientSession struct {
	conn                  net.Conn
	stateMu               sync.Mutex
	writeMu               sync.Mutex
	streamState           clientChunkStreamState
	lastPosition          clientPositionState
	lastDestroyAt         time.Time
	inventory             playerinventory.Inventory
	selectedInventorySlot uint32
	toolbelt              []item.ID
	selectedToolSlot      uint32
	playerID              string
}

type clientPositionState struct {
	x  float64
	y  float64
	z  float64
	ok bool
}

func (s *Server) newClientSession(conn net.Conn) *clientSession {
	return newClientSessionWithInventory(conn, s.newSessionInventory())
}

func (s *Server) newSessionInventory() playerinventory.Inventory {
	switch s.inventoryMode {
	case inventoryModeCounted:
		return playerinventory.NewCountedHotbar()
	default:
		return playerinventory.NewCreativeHotbar()
	}
}

func newClientSession(conn net.Conn) *clientSession {
	return newClientSessionWithInventory(conn, playerinventory.NewCreativeHotbar())
}

func newClientSessionWithInventory(conn net.Conn, inventory playerinventory.Inventory) *clientSession {
	selectedSlot, _ := inventory.FirstPlaceableSlot()
	toolbelt := item.DefaultToolbelt()

	return &clientSession{
		conn: conn,
		streamState: clientChunkStreamState{
			sentChunks: make(map[world.ChunkCoord]bool),
		},
		inventory:             inventory,
		selectedInventorySlot: selectedSlot,
		toolbelt:              toolbelt,
		selectedToolSlot:      0,
	}
}

func (c *clientSession) chunkOrderForCenter(center world.ChunkCoord, mode chunkOrderMode) world.ChunkOrder {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.streamState.chunkOrderForCenter(center, mode)
}

func (c *clientSession) recordCenter(center world.ChunkCoord) {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	c.streamState.recordCenter(center)
}

func (c *clientSession) recordPosition(position *api.ClientPosition) {
	if position == nil {
		return
	}

	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	c.lastPosition = clientPositionState{
		x:  float64(position.GetX()),
		y:  float64(position.GetY()),
		z:  float64(position.GetZ()),
		ok: true,
	}
}

func (c *clientSession) blockActionInReach(action *api.BlockAction) bool {
	if action == nil {
		return false
	}

	return blockActionWithinReach(c.recordedPosition(), action)
}

func (c *clientSession) recordedPosition() clientPositionState {
	c.stateMu.Lock()
	position := c.lastPosition
	c.stateMu.Unlock()

	return position
}

func blockActionWithinReach(position clientPositionState, action *api.BlockAction) bool {
	if !position.ok || action == nil {
		return false
	}

	blockCenterX := float64(action.GetX()) + 0.5
	blockCenterY := float64(action.GetY()) + 0.5
	blockCenterZ := float64(action.GetZ()) + 0.5
	dx := blockCenterX - position.x
	dy := blockCenterY - position.y
	dz := blockCenterZ - position.z
	return dx*dx+dy*dy+dz*dz <= serverBlockActionReachSquared
}

func blockActionIntersectsPlayer(position clientPositionState, action *api.BlockAction) bool {
	if !position.ok || action == nil {
		return false
	}
	if action.GetY() < 0 || action.GetY() >= int32(world.ChunkHeight) {
		return false
	}

	playerMinX := position.x - serverPlayerCollisionHalfWidth
	playerMaxX := position.x + serverPlayerCollisionHalfWidth
	playerMinY := position.y
	playerMaxY := position.y + serverPlayerCollisionHeight
	playerMinZ := position.z - serverPlayerCollisionHalfWidth
	playerMaxZ := position.z + serverPlayerCollisionHalfWidth

	blockMinX := float64(action.GetX())
	blockMaxX := blockMinX + 1
	blockMinY := float64(action.GetY())
	blockMaxY := blockMinY + 1
	blockMinZ := float64(action.GetZ())
	blockMaxZ := blockMinZ + 1

	return playerMinX < blockMaxX &&
		playerMaxX > blockMinX &&
		playerMinY < blockMaxY &&
		playerMaxY > blockMinY &&
		playerMinZ < blockMaxZ &&
		playerMaxZ > blockMinZ
}

func (c *clientSession) destroyCooldownReady(now time.Time, cooldown time.Duration) bool {
	if cooldown <= 0 {
		return true
	}

	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.lastDestroyAt.IsZero() || !now.Before(c.lastDestroyAt.Add(cooldown))
}

func (c *clientSession) recordSuccessfulDestroy(now time.Time) {
	if now.IsZero() {
		return
	}

	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	c.lastDestroyAt = now
}

func (s *Server) miningDurationForBlock(block world.BlockID) time.Duration {
	if s.miningDurations != nil {
		if duration, ok := s.miningDurations[block]; ok {
			return duration
		}
		return 0
	}
	if world.IsPlaceable(block) {
		return s.miningCooldown
	}
	return 0
}

func (s *Server) miningDurationForBlockWithTool(block world.BlockID, toolID item.ID) time.Duration {
	baseDuration := s.miningDurationForBlock(block)
	if baseDuration <= 0 || s.miningCooldownOverride {
		return baseDuration
	}

	baseMS := int(baseDuration / time.Millisecond)
	adjustedMS := item.AdjustedMiningDurationMS(baseMS, block, toolID)
	return time.Duration(adjustedMS) * time.Millisecond
}

func (c *clientSession) hasSentChunk(coord world.ChunkCoord) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.streamState.sentChunks[coord]
}

func (c *clientSession) selectedSlot() uint32 {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.selectedInventorySlot
}

func (c *clientSession) selectedToolID() item.ID {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if len(c.toolbelt) == 0 || uint64(c.selectedToolSlot) >= uint64(len(c.toolbelt)) {
		return item.HandToolID
	}
	return c.toolbelt[c.selectedToolSlot]
}

func (c *clientSession) selectedToolSlotIndex() uint32 {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if len(c.toolbelt) == 0 || uint64(c.selectedToolSlot) >= uint64(len(c.toolbelt)) {
		return 0
	}
	return c.selectedToolSlot
}

func (c *clientSession) selectInventorySlot(slot uint32) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if !c.inventory.CanSelectSlot(slot) {
		return false
	}
	c.selectedInventorySlot = slot
	return true
}

func (c *clientSession) selectToolSlot(slot uint32) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if len(c.toolbelt) == 0 || uint64(slot) >= uint64(len(c.toolbelt)) {
		return false
	}
	c.selectedToolSlot = slot
	return true
}

func (c *clientSession) placeInventoryBlock(block world.BlockID) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if !c.inventory.PlaceBlock(block) {
		return false
	}
	c.normalizeSelectedInventorySlotLocked()
	return true
}

func (c *clientSession) addInventoryBlock(block world.BlockID) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if !c.inventory.AddBlock(block) {
		return false
	}
	c.normalizeSelectedInventorySlotLocked()
	return true
}

func (c *clientSession) collectInventoryBlock(block world.BlockID, count uint32) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if !c.inventory.CollectBlock(block, count) {
		return false
	}
	c.normalizeSelectedInventorySlotLocked()
	return true
}

func (c *clientSession) currentInventoryState() playerinventory.State {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.inventory.State(c.selectedInventorySlot)
}

func (c *clientSession) boundPlayerID() string {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	return c.playerID
}

func (c *clientSession) normalizeSelectedInventorySlot() {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	c.normalizeSelectedInventorySlotLocked()
}

func (c *clientSession) normalizeSelectedInventorySlotLocked() {
	if c.inventory.CanSelectSlot(c.selectedInventorySlot) {
		return
	}
	if slot, ok := c.inventory.FirstPlaceableSlot(); ok {
		c.selectedInventorySlot = slot
		return
	}
	c.selectedInventorySlot = 0
}

func (c *clientSession) bindPlayerID(playerID string) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if c.playerID != "" {
		return false
	}
	c.playerID = playerID
	return true
}

func (c *clientSession) applyInventoryState(state playerinventory.State) {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	c.inventory = playerinventory.NewFromState(state)
	c.selectedInventorySlot = state.SelectedSlot
	c.normalizeSelectedInventorySlotLocked()
}

func (c *clientSession) inventoryState() (string, playerinventory.State, bool) {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if c.playerID == "" {
		return "", playerinventory.State{}, false
	}
	return c.playerID, c.inventory.State(c.selectedInventorySlot), true
}

type clientChunkStreamState struct {
	sentChunks    map[world.ChunkCoord]bool
	lastCenter    world.ChunkCoord
	hasLastCenter bool
}

func (s *clientChunkStreamState) chunkOrderForCenter(center world.ChunkCoord, mode chunkOrderMode) world.ChunkOrder {
	if mode != chunkOrderDirectional || !s.hasLastCenter {
		return world.ChunkOrder{}
	}
	return world.ChunkOrder{
		DirectionX: directionComponent(center.X - s.lastCenter.X),
		DirectionZ: directionComponent(center.Z - s.lastCenter.Z),
	}
}

func (s *clientChunkStreamState) recordCenter(center world.ChunkCoord) {
	s.lastCenter = center
	s.hasLastCenter = true
}

func directionComponent(delta int32) int32 {
	if delta < 0 {
		return -1
	}
	if delta > 0 {
		return 1
	}
	return 0
}

func forgetFarSentChunks(sentChunks map[world.ChunkCoord]bool, centerX, centerZ, distance int32) {
	for coord := range sentChunks {
		if !world.ChunkWithinRadius(coord, centerX, centerZ, distance) {
			delete(sentChunks, coord)
		}
	}
}

func (s *Server) sendChunksAround(conn net.Conn, centerX, centerZ int32, sentChunks map[world.ChunkCoord]bool) error {
	return s.sendChunksAroundWithRadius(conn, centerX, centerZ, s.viewDistance, sentChunks)
}

func (s *Server) sendChunksAroundOrdered(conn net.Conn, centerX, centerZ int32, sentChunks map[world.ChunkCoord]bool, order world.ChunkOrder) error {
	return s.sendChunksAroundWithRadiusOrdered(conn, centerX, centerZ, s.viewDistance, sentChunks, order)
}

func (s *Server) sendChunksAroundForSession(client *clientSession, centerX, centerZ int32, order world.ChunkOrder) error {
	return s.sendChunksAroundWithRadiusForSession(client, centerX, centerZ, s.viewDistance, order)
}

func (s *Server) sendChunksAroundWithRadius(conn net.Conn, centerX, centerZ, radius int32, sentChunks map[world.ChunkCoord]bool) error {
	return s.sendChunksAroundWithRadiusOrdered(conn, centerX, centerZ, radius, sentChunks, world.ChunkOrder{})
}

func (s *Server) sendChunksAroundWithRadiusOrdered(conn net.Conn, centerX, centerZ, radius int32, sentChunks map[world.ChunkCoord]bool, order world.ChunkOrder) error {
	started := time.Now()
	chunks, err := s.world.ChunksAroundOrdered(centerX, centerZ, radius, sentChunks, s.chunksPerUpdate, order)
	if err != nil {
		return err
	}
	var batch chunkStreamBatchStats
	for _, chunk := range chunks {
		stats, err := s.sendChunk(conn, chunk)
		if err != nil {
			return err
		}
		batch.add(stats)
	}
	if chunkStreamMetricsEnabled() && batch.chunks > 0 {
		elapsed := time.Since(started)
		log.Printf(
			"Chunk stream batch center=%d,%d radius=%d order=%s direction=%d,%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d elapsed_ms=%.3f chunks_per_sec=%.2f",
			centerX,
			centerZ,
			radius,
			s.chunkOrderMode,
			order.DirectionX,
			order.DirectionZ,
			batch.chunks,
			batch.rawBytes,
			batch.payloadBytes,
			batch.wireBytes,
			float64(elapsed.Microseconds())/1000.0,
			float64(batch.chunks)/elapsed.Seconds(),
		)
	}
	return nil
}

func (s *Server) sendChunksAroundWithRadiusForSession(client *clientSession, centerX, centerZ, radius int32, order world.ChunkOrder) error {
	started := time.Now()

	client.stateMu.Lock()
	forgetFarSentChunks(client.streamState.sentChunks, centerX, centerZ, s.viewDistance+1)
	chunks, err := s.world.ChunksAroundOrdered(centerX, centerZ, radius, client.streamState.sentChunks, s.chunksPerUpdate, order)
	client.stateMu.Unlock()
	if err != nil {
		return err
	}

	var batch chunkStreamBatchStats
	for _, chunk := range chunks {
		stats, err := s.sendChunkToSession(client, chunk)
		if err != nil {
			return err
		}
		batch.add(stats)
	}
	if chunkStreamMetricsEnabled() && batch.chunks > 0 {
		elapsed := time.Since(started)
		log.Printf(
			"Chunk stream batch center=%d,%d radius=%d order=%s direction=%d,%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d elapsed_ms=%.3f chunks_per_sec=%.2f",
			centerX,
			centerZ,
			radius,
			s.chunkOrderMode,
			order.DirectionX,
			order.DirectionZ,
			batch.chunks,
			batch.rawBytes,
			batch.payloadBytes,
			batch.wireBytes,
			float64(elapsed.Microseconds())/1000.0,
			float64(batch.chunks)/elapsed.Seconds(),
		)
	}
	return nil
}

func (s *Server) broadcastChunkUpdate(origin *clientSession, chunk world.ChunkSnapshot) error {
	coord := world.ChunkCoord{X: chunk.X, Z: chunk.Z}
	targets := s.chunkUpdateTargets(origin, coord)
	for _, target := range targets {
		if _, err := s.sendChunkToSession(target, chunk); err != nil {
			if target == origin {
				return err
			}
			log.Printf("Failed to broadcast updated chunk %d,%d to %s packet_error_class=%s: %v", chunk.X, chunk.Z, target.conn.RemoteAddr(), classifyNetworkError(err), err)
			s.disconnectClient(target)
		}
	}
	return nil
}

func (s *Server) chunkUpdateTargets(origin *clientSession, coord world.ChunkCoord) []*clientSession {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()

	targets := make([]*clientSession, 0, len(s.clients))
	if origin != nil {
		targets = append(targets, origin)
	}
	for client := range s.clients {
		if client == origin || !client.hasSentChunk(coord) {
			continue
		}
		targets = append(targets, client)
	}
	return targets
}

func configuredViewDistance() int32 {
	value := os.Getenv(viewDistanceEnv)
	if value == "" {
		return defaultViewDistance
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		log.Printf("Ignoring invalid %s=%q; using %d", viewDistanceEnv, value, defaultViewDistance)
		return defaultViewDistance
	}
	if parsed > int(maxViewDistance) {
		log.Printf("Clamping %s=%d to %d", viewDistanceEnv, parsed, maxViewDistance)
		return maxViewDistance
	}
	return int32(parsed)
}

func configuredChunksPerUpdate() int {
	value := os.Getenv(chunksPerUpdateEnv)
	if value == "" {
		return defaultChunksPerUpdate
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		log.Printf("Ignoring invalid %s=%q; using %d", chunksPerUpdateEnv, value, defaultChunksPerUpdate)
		return defaultChunksPerUpdate
	}
	return parsed
}

func configuredBootstrapRadius(viewDistance int32) int32 {
	value := os.Getenv(bootstrapRadiusEnv)
	if value == "" {
		return minInt32(defaultBootstrapRadius, viewDistance)
	}
	if strings.EqualFold(strings.TrimSpace(value), "full") {
		return viewDistance
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		fallback := minInt32(defaultBootstrapRadius, viewDistance)
		log.Printf("Ignoring invalid %s=%q; using %d", bootstrapRadiusEnv, value, fallback)
		return fallback
	}
	if parsed > int(viewDistance) {
		log.Printf("Clamping %s=%d to %d", bootstrapRadiusEnv, parsed, viewDistance)
		return viewDistance
	}
	return int32(parsed)
}

func minInt32(a, b int32) int32 {
	if a < b {
		return a
	}
	return b
}

func chunkStreamMetricsEnabled() bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(chunkStreamMetricsEnv)))
	return value == "1" || value == "true" || value == "yes" || value == "on"
}

func configuredChunkEncoding() api.ChunkEncoding {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(chunkEncodingEnv)))
	switch value {
	case "", "rle":
		return api.ChunkEncoding_CHUNK_ENCODING_RLE
	case "raw":
		return api.ChunkEncoding_CHUNK_ENCODING_RAW
	default:
		log.Printf("Ignoring invalid %s=%q; using rle", chunkEncodingEnv, value)
		return api.ChunkEncoding_CHUNK_ENCODING_RLE
	}
}

func configuredChunkOrderMode() chunkOrderMode {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(chunkOrderEnv)))
	switch value {
	case "", string(chunkOrderNearest):
		return chunkOrderNearest
	case string(chunkOrderDirectional):
		return chunkOrderDirectional
	default:
		log.Printf("Ignoring invalid %s=%q; using nearest", chunkOrderEnv, value)
		return chunkOrderNearest
	}
}

func configuredClientWriteTimeout() time.Duration {
	value := strings.TrimSpace(os.Getenv(clientWriteTimeoutEnv))
	if value == "" {
		return defaultClientWriteTimeout
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		log.Printf("Ignoring invalid %s=%q; using %s", clientWriteTimeoutEnv, value, defaultClientWriteTimeout)
		return defaultClientWriteTimeout
	}
	return time.Duration(parsed) * time.Millisecond
}

func configuredMaxClients() int {
	value := strings.TrimSpace(os.Getenv(maxClientsEnv))
	if value == "" {
		return defaultMaxClients
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		log.Printf("Ignoring invalid %s=%q; using %d", maxClientsEnv, value, defaultMaxClients)
		return defaultMaxClients
	}
	return parsed
}

func configuredItemEntityDespawn() time.Duration {
	value := strings.TrimSpace(os.Getenv(itemEntityDespawnEnv))
	if value == "" {
		return defaultItemEntityDespawn
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		log.Printf("Ignoring invalid %s=%q; using %s", itemEntityDespawnEnv, value, defaultItemEntityDespawn)
		return defaultItemEntityDespawn
	}
	return time.Duration(parsed) * time.Millisecond
}

func configuredInventoryMode() inventoryMode {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(inventoryModeEnv)))
	switch value {
	case "", string(inventoryModeCreative):
		return inventoryModeCreative
	case string(inventoryModeCounted), "survival":
		return inventoryModeCounted
	default:
		log.Printf("Ignoring invalid %s=%q; using %s", inventoryModeEnv, value, inventoryModeCreative)
		return inventoryModeCreative
	}
}

func configuredMiningCooldown(mode inventoryMode) time.Duration {
	cooldown, _ := configuredMiningCooldownWithOverride(mode)
	return cooldown
}

func configuredMiningCooldownWithOverride(mode inventoryMode) (time.Duration, bool) {
	defaultCooldown := defaultMiningCooldownForMode(mode)
	value := strings.TrimSpace(os.Getenv(miningCooldownEnv))
	if value == "" {
		return defaultCooldown, false
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		log.Printf("Ignoring invalid %s=%q; using %s", miningCooldownEnv, value, defaultCooldown)
		return defaultCooldown, false
	}
	return time.Duration(parsed) * time.Millisecond, true
}

func defaultMiningCooldownForMode(mode inventoryMode) time.Duration {
	if mode == inventoryModeCounted {
		return defaultCountedMiningCooldown
	}
	return 0
}

func configuredMiningDurations(mode inventoryMode, globalCooldown time.Duration, globalOverride bool) map[world.BlockID]time.Duration {
	if globalOverride {
		return miningDurationsForPlaceableBlocks(globalCooldown)
	}
	return defaultMiningDurationsForMode(mode)
}

func defaultMiningDurationsForMode(mode inventoryMode) map[world.BlockID]time.Duration {
	if mode != inventoryModeCounted {
		return miningDurationsForPlaceableBlocks(0)
	}

	durations := make(map[world.BlockID]time.Duration)
	for _, definition := range world.BlockDefinitions() {
		if definition.Placeable {
			durations[definition.ID] = time.Duration(definition.MiningDurationMS) * time.Millisecond
		}
	}
	return durations
}

func miningDurationsForPlaceableBlocks(duration time.Duration) map[world.BlockID]time.Duration {
	durations := make(map[world.BlockID]time.Duration)
	for _, definition := range world.BlockDefinitions() {
		if definition.Placeable {
			durations[definition.ID] = duration
		}
	}
	return durations
}

func (s *Server) currentTime() time.Time {
	if s.now == nil {
		return time.Now()
	}
	return s.now()
}

type chunkSendStats struct {
	rawBytes     int
	payloadBytes int
	wireBytes    int
}

type chunkStreamBatchStats struct {
	chunks       int
	rawBytes     int
	payloadBytes int
	wireBytes    int
}

func (s *Server) sendChunk(conn net.Conn, chunk world.ChunkSnapshot) (chunkSendStats, error) {
	packet, stats, err := s.chunkPacket(chunk)
	if err != nil {
		return chunkSendStats{}, err
	}
	return stats, s.sendPacket(conn, packet)
}

func (s *Server) sendChunkToSession(client *clientSession, chunk world.ChunkSnapshot) (chunkSendStats, error) {
	packet, stats, err := s.chunkPacket(chunk)
	if err != nil {
		return chunkSendStats{}, err
	}

	if err := s.sendPacketToSession(client, packet); err != nil {
		return chunkSendStats{}, err
	}
	return stats, nil
}

func (s *Server) sendInventorySnapshotToSession(client *clientSession) error {
	return s.sendPacketToSession(client, inventorySnapshotPacket(client.inventory, client.selectedSlot(), client.selectedToolSlotIndex()))
}

func (s *Server) sendItemEntitySnapshotToSessionIfNotEmpty(client *clientSession) error {
	if err := s.pruneExpiredItemEntities(s.currentTime()); err != nil {
		return err
	}
	if !s.hasItemEntities() {
		return nil
	}
	return s.sendItemEntitySnapshotToSession(client)
}

func (s *Server) sendItemEntitySnapshotToSession(client *clientSession) error {
	if err := s.pruneExpiredItemEntities(s.currentTime()); err != nil {
		return err
	}
	return s.sendPacketToSession(client, itemEntitySnapshotPacket(s.itemEntitySnapshot()))
}

func (s *Server) broadcastItemEntitySnapshot(origin *clientSession) error {
	if err := s.pruneExpiredItemEntities(s.currentTime()); err != nil {
		return err
	}
	packet := itemEntitySnapshotPacket(s.itemEntitySnapshot())

	targets := s.itemEntitySnapshotTargets(origin)

	for _, target := range targets {
		if err := s.sendPacketToSession(target, packet); err != nil {
			if target == origin {
				return err
			}
			log.Printf("Failed to broadcast item entity snapshot to %s packet_error_class=%s: %v", target.conn.RemoteAddr(), classifyNetworkError(err), err)
			s.disconnectClient(target)
		}
	}
	return nil
}

func (s *Server) itemEntitySnapshotTargets(origin *clientSession) []*clientSession {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()

	targets := make([]*clientSession, 0, len(s.clients)+1)
	if origin != nil {
		targets = append(targets, origin)
	}
	for client := range s.clients {
		if client == origin {
			continue
		}
		targets = append(targets, client)
	}
	return targets
}

func (s *Server) sendPacketToSession(client *clientSession, packet *api.Packet) error {
	client.writeMu.Lock()
	defer client.writeMu.Unlock()

	if s.writeTimeout > 0 {
		if err := client.conn.SetWriteDeadline(time.Now().Add(s.writeTimeout)); err != nil {
			return err
		}
	}
	sendErr := s.sendPacket(client.conn, packet)
	var clearErr error
	if s.writeTimeout > 0 {
		clearErr = client.conn.SetWriteDeadline(time.Time{})
	}
	if sendErr != nil {
		return sendErr
	}
	if clearErr != nil {
		return clearErr
	}
	return nil
}

func (s *Server) chunkPacket(chunk world.ChunkSnapshot) (*api.Packet, chunkSendStats, error) {
	blocks := chunk.Blocks
	encoding := api.ChunkEncoding_CHUNK_ENCODING_RAW
	var uncompressedSize uint32
	if s.chunkEncoding == api.ChunkEncoding_CHUNK_ENCODING_RLE {
		encoded, err := world.EncodeSerializedChunkRLE(chunk.Blocks)
		if err != nil {
			return nil, chunkSendStats{}, err
		}
		blocks = encoded
		encoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
		uncompressedSize = uint32(len(chunk.Blocks))
	}

	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:                chunk.X,
				Z:                chunk.Z,
				Blocks:           blocks,
				Encoding:         encoding,
				UncompressedSize: uncompressedSize,
			},
		},
	}
	stats := chunkSendStats{
		rawBytes:     len(chunk.Blocks),
		payloadBytes: len(blocks),
		wireBytes:    framedPacketSize(packet),
	}
	return packet, stats, nil
}

func inventorySnapshotPacket(inventory playerinventory.Inventory, selectedSlot uint32, selectedToolSlot uint32) *api.Packet {
	return &api.Packet{
		Payload: &api.Packet_InventorySnapshot{
			InventorySnapshot: inventorySnapshot(inventory, selectedSlot, selectedToolSlot),
		},
	}
}

func inventorySnapshot(inventory playerinventory.Inventory, selectedSlot uint32, selectedToolSlot uint32) *api.InventorySnapshot {
	slots := inventory.Slots()
	apiSlots := make([]*api.InventorySlot, 0, len(slots))
	for _, slot := range slots {
		apiSlots = append(apiSlots, &api.InventorySlot{
			BlockId: uint32(slot.BlockID),
			Count:   slot.Count,
		})
	}
	return &api.InventorySnapshot{
		Slots:            apiSlots,
		SelectedSlot:     selectedSlot,
		SelectedToolSlot: selectedToolSlot,
	}
}

func itemEntitySnapshotPacket(snapshot *api.ItemEntitySnapshot) *api.Packet {
	return &api.Packet{
		Payload: &api.Packet_ItemEntities{
			ItemEntities: snapshot,
		},
	}
}

func (s *Server) hasItemEntities() bool {
	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()

	return len(s.itemEntities) > 0
}

func (s *Server) itemEntitySnapshot() *api.ItemEntitySnapshot {
	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()

	state := s.itemEntityStateLocked()
	entities := make([]*api.ItemEntity, 0, len(state.Entities))
	for _, entity := range state.Entities {
		entities = append(entities, &api.ItemEntity{
			EntityId: entity.EntityID,
			ItemId:   entity.ItemID,
			Count:    entity.Count,
			X:        float32(entity.X),
			Y:        float32(entity.Y),
			Z:        float32(entity.Z),
		})
	}
	return &api.ItemEntitySnapshot{
		Entities: entities,
		Revision: state.Revision,
	}
}

func (s *Server) itemEntityStateLocked() itementity.State {
	ids := make([]uint64, 0, len(s.itemEntities))
	for id := range s.itemEntities {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })

	entities := make([]itementity.Entity, 0, len(ids))
	for _, id := range ids {
		entity := s.itemEntities[id]
		entities = append(entities, itementity.Entity{
			EntityID:        entity.entityID,
			ItemID:          string(entity.itemID),
			Count:           entity.count,
			X:               entity.x,
			Y:               entity.y,
			Z:               entity.z,
			SpawnedAtUnixMS: itemEntitySpawnedAtUnixMS(entity.spawnedAt),
		})
	}
	nextEntityID := s.nextItemEntityID
	if nextEntityID == 0 {
		nextEntityID = 1
	}
	return itementity.State{
		NextEntityID: nextEntityID,
		Revision:     s.itemEntityRevision,
		Entities:     entities,
	}
}

func (s *Server) saveItemEntitiesLocked() error {
	if s.itemEntityStore == nil {
		return nil
	}
	return s.itemEntityStore.SaveItemEntities(s.itemEntityStateLocked())
}

func (s *Server) spawnItemEntityForBlock(block world.BlockID, x, y, z int32) (bool, error) {
	itemID, ok := item.BlockItemID(block)
	if !ok {
		return false, nil
	}
	spawnedAt := s.currentTime()
	spawnX := float64(x) + 0.5
	spawnY := float64(y) + 0.5
	spawnZ := float64(z) + 0.5

	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()

	if s.itemEntities == nil {
		s.itemEntities = make(map[uint64]itemEntity)
	}
	if s.nextItemEntityID == 0 {
		s.nextItemEntityID = 1
	}

	previousEntities := cloneRuntimeItemEntities(s.itemEntities)
	previousNextEntityID := s.nextItemEntityID
	previousRevision := s.itemEntityRevision

	s.pruneExpiredItemEntitiesLocked(spawnedAt)
	if s.mergeItemEntityLocked(itemID, 1, spawnX, spawnY, spawnZ, spawnedAt) {
		s.itemEntityRevision++
		if err := s.saveItemEntitiesLocked(); err != nil {
			s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
			return false, fmt.Errorf("save item entities after merge: %w", err)
		}
		return true, nil
	}
	s.removeOldestItemEntityIfAtCapacityLocked()

	entityID, ok := s.allocateItemEntityIDLocked()
	if !ok {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		return false, errors.New("item entity id space exhausted")
	}

	s.itemEntities[entityID] = itemEntity{
		entityID:  entityID,
		itemID:    itemID,
		count:     1,
		x:         spawnX,
		y:         spawnY,
		z:         spawnZ,
		spawnedAt: spawnedAt,
	}
	s.itemEntityRevision++
	if err := s.saveItemEntitiesLocked(); err != nil {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		return false, fmt.Errorf("save item entities after spawn: %w", err)
	}
	return true, nil
}

func (s *Server) removeOldestItemEntityIfAtCapacityLocked() bool {
	if len(s.itemEntities) < itementity.MaxStateEntities {
		return false
	}

	var (
		oldestID        uint64
		oldestSpawnedAt time.Time
		found           bool
	)
	for entityID, entity := range s.itemEntities {
		if !found ||
			entity.spawnedAt.Before(oldestSpawnedAt) ||
			(entity.spawnedAt.Equal(oldestSpawnedAt) && entityID < oldestID) {
			oldestID = entityID
			oldestSpawnedAt = entity.spawnedAt
			found = true
		}
	}
	if !found {
		return false
	}
	delete(s.itemEntities, oldestID)
	return true
}

func (s *Server) allocateItemEntityIDLocked() (uint64, bool) {
	start := s.nextItemEntityID
	if start == 0 {
		start = 1
		s.nextItemEntityID = 1
	}
	for {
		entityID := s.nextItemEntityID
		s.nextItemEntityID++
		if s.nextItemEntityID == 0 {
			s.nextItemEntityID = 1
		}
		if _, exists := s.itemEntities[entityID]; !exists {
			return entityID, true
		}
		if s.nextItemEntityID == start {
			return 0, false
		}
	}
}

func (s *Server) pruneExpiredItemEntities(now time.Time) error {
	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()

	previousEntities := cloneRuntimeItemEntities(s.itemEntities)
	previousNextEntityID := s.nextItemEntityID
	previousRevision := s.itemEntityRevision
	if !s.pruneExpiredItemEntitiesLocked(now) {
		return nil
	}
	if err := s.saveItemEntitiesLocked(); err != nil {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		return fmt.Errorf("save item entities after despawn: %w", err)
	}
	return nil
}

func (s *Server) pruneExpiredItemEntitiesLocked(now time.Time) bool {
	if s.itemEntityDespawn <= 0 || len(s.itemEntities) == 0 {
		return false
	}

	changed := false
	for entityID, entity := range s.itemEntities {
		if entity.spawnedAt.IsZero() {
			entity.spawnedAt = now
			s.itemEntities[entityID] = entity
			continue
		}
		if now.Before(entity.spawnedAt.Add(s.itemEntityDespawn)) {
			continue
		}
		delete(s.itemEntities, entityID)
		changed = true
	}
	if changed {
		s.itemEntityRevision++
	}
	return changed
}

func (s *Server) mergeItemEntityLocked(itemID item.ID, count uint32, x, y, z float64, spawnedAt time.Time) bool {
	if count == 0 || count > itementity.MaxEntityStackCount {
		return false
	}

	var (
		bestID       uint64
		bestDistance float64
		found        bool
	)
	for entityID, entity := range s.itemEntities {
		if entity.itemID != itemID || entity.count > itementity.MaxEntityStackCount-count {
			continue
		}
		distance := itemEntityDistanceSquared(entity, x, y, z)
		if distance > serverItemEntityMergeRadiusSquared {
			continue
		}
		if !found || distance < bestDistance || (distance == bestDistance && entityID < bestID) {
			bestID = entityID
			bestDistance = distance
			found = true
		}
	}
	if !found {
		return false
	}

	entity := s.itemEntities[bestID]
	entity.count += count
	if entity.spawnedAt.IsZero() || entity.spawnedAt.Before(spawnedAt) {
		entity.spawnedAt = spawnedAt
	}
	s.itemEntities[bestID] = entity
	return true
}

func itemEntityDistanceSquared(entity itemEntity, x, y, z float64) float64 {
	dx := entity.x - x
	dy := entity.y - y
	dz := entity.z - z
	return dx*dx + dy*dy + dz*dz
}

func itemEntitySpawnedAtFromUnixMS(unixMS int64, fallback time.Time) time.Time {
	if unixMS <= itementity.LegacySpawnedAtUnixMS {
		return fallback
	}
	return time.Unix(unixMS/1000, (unixMS%1000)*int64(time.Millisecond)).UTC()
}

func itemEntitySpawnedAtUnixMS(spawnedAt time.Time) int64 {
	if spawnedAt.IsZero() {
		return itementity.LegacySpawnedAtUnixMS
	}
	return spawnedAt.UTC().UnixNano() / int64(time.Millisecond)
}

func cloneRuntimeItemEntities(entities map[uint64]itemEntity) map[uint64]itemEntity {
	cloned := make(map[uint64]itemEntity, len(entities))
	for entityID, entity := range entities {
		cloned[entityID] = entity
	}
	return cloned
}

func (s *Server) restoreRuntimeItemEntitiesLocked(entities map[uint64]itemEntity, nextEntityID uint64, revision uint64) {
	s.itemEntities = cloneRuntimeItemEntities(entities)
	s.nextItemEntityID = nextEntityID
	s.itemEntityRevision = revision
}

func (s *Server) collectItemEntityForSession(client *clientSession, entityID uint64) (bool, error) {
	if entityID == 0 {
		return false, nil
	}

	s.itemEntitiesMu.Lock()
	defer s.itemEntitiesMu.Unlock()

	previousEntities := cloneRuntimeItemEntities(s.itemEntities)
	previousNextEntityID := s.nextItemEntityID
	previousRevision := s.itemEntityRevision
	pruned := s.pruneExpiredItemEntitiesLocked(s.currentTime())

	entity, ok := s.itemEntities[entityID]
	if !ok {
		if err := s.saveItemEntityPruneIfNeededLocked(pruned, previousEntities, previousNextEntityID, previousRevision); err != nil {
			return false, err
		}
		return false, nil
	}
	if !itemEntityWithinPickupReach(client.recordedPosition(), entity) {
		if err := s.saveItemEntityPruneIfNeededLocked(pruned, previousEntities, previousNextEntityID, previousRevision); err != nil {
			return false, err
		}
		return false, nil
	}
	block, ok := item.BlockForItem(entity.itemID)
	if !ok {
		if err := s.saveItemEntityPruneIfNeededLocked(pruned, previousEntities, previousNextEntityID, previousRevision); err != nil {
			return false, err
		}
		return false, nil
	}
	playerID := client.boundPlayerID()
	previousInventoryState := client.currentInventoryState()
	if !client.collectInventoryBlock(block, entity.count) {
		if err := s.saveItemEntityPruneIfNeededLocked(pruned, previousEntities, previousNextEntityID, previousRevision); err != nil {
			return false, err
		}
		return false, nil
	}
	collectedInventoryState := client.currentInventoryState()

	delete(s.itemEntities, entityID)
	s.itemEntityRevision++
	if err := s.saveClientInventoryState(playerID, collectedInventoryState); err != nil {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		client.applyInventoryState(previousInventoryState)
		return false, err
	}
	if err := s.saveItemEntitiesLocked(); err != nil {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		client.applyInventoryState(previousInventoryState)
		if rollbackErr := s.saveClientInventoryState(playerID, previousInventoryState); rollbackErr != nil {
			return false, fmt.Errorf("save item entities after pickup: %w; rollback player inventory: %v", err, rollbackErr)
		}
		return false, fmt.Errorf("save item entities after pickup: %w", err)
	}
	return true, nil
}

func (s *Server) saveItemEntityPruneIfNeededLocked(pruned bool, previousEntities map[uint64]itemEntity, previousNextEntityID uint64, previousRevision uint64) error {
	if !pruned {
		return nil
	}
	if err := s.saveItemEntitiesLocked(); err != nil {
		s.restoreRuntimeItemEntitiesLocked(previousEntities, previousNextEntityID, previousRevision)
		return fmt.Errorf("save item entities after despawn: %w", err)
	}
	return nil
}

func itemEntityWithinPickupReach(position clientPositionState, entity itemEntity) bool {
	if !position.ok {
		return false
	}
	dx := entity.x - position.x
	dy := entity.y - position.y
	dz := entity.z - position.z
	return dx*dx+dy*dy+dz*dz <= serverItemPickupReachSquared
}

func (s *chunkStreamBatchStats) add(stats chunkSendStats) {
	s.chunks++
	s.rawBytes += stats.rawBytes
	s.payloadBytes += stats.payloadBytes
	s.wireBytes += stats.wireBytes
}

func framedPacketSize(packet *api.Packet) int {
	return 4 + proto.Size(packet)
}

func (s *Server) receiveInitialClientPacket(conn net.Conn) (*api.Packet, bool, error) {
	if err := conn.SetReadDeadline(time.Now().Add(initialClientPacketTimeout)); err != nil {
		return nil, false, err
	}
	packet, err := s.receivePacket(conn)
	clearErr := conn.SetReadDeadline(time.Time{})
	if err != nil {
		var netErr net.Error
		if errors.As(err, &netErr) && netErr.Timeout() {
			return nil, false, clearErr
		}
		if clearErr != nil {
			return nil, false, clearErr
		}
		return nil, false, err
	}
	if clearErr != nil {
		return nil, false, clearErr
	}
	return packet, true, nil
}

func (s *Server) receivePacket(conn net.Conn) (*api.Packet, error) {
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		return nil, fmt.Errorf("read packet length: %w", err)
	}

	length := binary.LittleEndian.Uint32(lenBuf)
	if length > maxPacketSize {
		return nil, fmt.Errorf("%w: %d bytes", errPacketTooLarge, length)
	}

	dataBuf := make([]byte, length)
	if _, err := io.ReadFull(conn, dataBuf); err != nil {
		return nil, fmt.Errorf("read packet payload: %w", err)
	}

	packet := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, packet); err != nil {
		return nil, fmt.Errorf("%w: %v", errMalformedPacket, err)
	}

	return packet, nil
}

func (s *Server) sendPacket(conn net.Conn, packet *api.Packet) error {
	data, err := proto.Marshal(packet)
	if err != nil {
		return fmt.Errorf("%w: %v", errPacketEncode, err)
	}

	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))

	if err := writeFull(conn, lenBuf); err != nil {
		return err
	}
	if err := writeFull(conn, data); err != nil {
		return err
	}
	return nil
}

func classifyNetworkError(err error) networkErrorClass {
	if err == nil {
		return networkErrorNone
	}

	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return networkErrorTimeout
	}
	var opErr *net.OpError
	if errors.As(err, &opErr) && opErr.Op == "read" && errors.Is(opErr.Err, syscall.ECONNRESET) {
		return networkErrorEOF
	}
	if errors.Is(err, errPacketTooLarge) {
		return networkErrorOversizedFrame
	}
	if errors.Is(err, errMalformedPacket) {
		return networkErrorMalformedProtobuf
	}
	if errors.Is(err, errPacketEncode) {
		return networkErrorEncode
	}
	if errors.Is(err, io.ErrShortWrite) {
		return networkErrorShortWrite
	}
	if errors.Is(err, io.ErrUnexpectedEOF) {
		return networkErrorShortFrame
	}
	if errors.Is(err, io.EOF) {
		return networkErrorEOF
	}
	return networkErrorOther
}

func writeFull(writer io.Writer, data []byte) error {
	for len(data) > 0 {
		n, err := writer.Write(data)
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
		data = data[n:]
	}

	return nil
}
