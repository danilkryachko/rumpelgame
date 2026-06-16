package network

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	playerinventory "rumpelmc/server/pkg/inventory"
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
const initialClientPacketTimeout = 250 * time.Millisecond

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

type chunkOrderMode string

const (
	chunkOrderNearest     chunkOrderMode = "nearest"
	chunkOrderDirectional chunkOrderMode = "directional"
)

type Server struct {
	address         string
	world           *world.World
	viewDistance    int32
	bootstrapRadius int32
	chunksPerUpdate int
	chunkEncoding   api.ChunkEncoding
	chunkOrderMode  chunkOrderMode
	writeTimeout    time.Duration
	maxClients      int
	clientsMu       sync.Mutex
	clients         map[*clientSession]struct{}
}

func NewServer(address string, gameWorld *world.World) *Server {
	viewDistance := configuredViewDistance()
	return &Server{
		address:         address,
		world:           gameWorld,
		viewDistance:    viewDistance,
		bootstrapRadius: configuredBootstrapRadius(viewDistance),
		chunksPerUpdate: configuredChunksPerUpdate(),
		chunkEncoding:   configuredChunkEncoding(),
		chunkOrderMode:  configuredChunkOrderMode(),
		writeTimeout:    configuredClientWriteTimeout(),
		maxClients:      configuredMaxClients(),
		clients:         make(map[*clientSession]struct{}),
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

	client := newClientSession(conn)
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
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		if err := s.sendChunksAroundWithRadiusForSession(client, center.X, center.Z, s.bootstrapRadius, world.ChunkOrder{}); err != nil {
			return fmt.Errorf("send bootstrap chunks around %d,%d: %w", center.X, center.Z, err)
		}
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
		center := world.ChunkCoordForPosition(p.Position.X, p.Position.Z)
		order := client.chunkOrderForCenter(center, s.chunkOrderMode)
		if err := s.sendChunksAroundForSession(client, center.X, center.Z, order); err != nil {
			return fmt.Errorf("send chunks around %d,%d: %w", center.X, center.Z, err)
		}
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

		snapshot, err := s.world.SetBlockGlobal(action.X, action.Y, action.Z, block)
		if err != nil {
			return fmt.Errorf("update block: %w", err)
		}
		if applyInventoryPlacement {
			client.inventory.PlaceBlock(block)
			client.normalizeSelectedInventorySlot()
		}

		if err := s.broadcastChunkUpdate(client, snapshot); err != nil {
			return fmt.Errorf("send updated chunk %d,%d: %w", snapshot.X, snapshot.Z, err)
		}
		if applyInventoryPlacement {
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
		log.Printf("Received InventoryAction: action=%v, slot=%d", action.Action, action.Slot)

		switch action.Action {
		case api.InventoryAction_SELECT_SLOT:
			if !client.selectInventorySlot(action.Slot) {
				log.Printf("Ignored invalid inventory slot=%d", action.Slot)
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

	default:
		log.Printf("Unknown packet received")
	}
	return nil
}

type clientSession struct {
	conn                  net.Conn
	stateMu               sync.Mutex
	writeMu               sync.Mutex
	streamState           clientChunkStreamState
	inventory             playerinventory.Inventory
	selectedInventorySlot uint32
}

func newClientSession(conn net.Conn) *clientSession {
	inventory := playerinventory.NewCreativeHotbar()
	selectedSlot, _ := inventory.FirstPlaceableSlot()

	return &clientSession{
		conn: conn,
		streamState: clientChunkStreamState{
			sentChunks: make(map[world.ChunkCoord]bool),
		},
		inventory:             inventory,
		selectedInventorySlot: selectedSlot,
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

func (c *clientSession) selectInventorySlot(slot uint32) bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if !c.inventory.CanSelectSlot(slot) {
		return false
	}
	c.selectedInventorySlot = slot
	return true
}

func (c *clientSession) normalizeSelectedInventorySlot() {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()

	if c.inventory.CanSelectSlot(c.selectedInventorySlot) {
		return
	}
	if slot, ok := c.inventory.FirstPlaceableSlot(); ok {
		c.selectedInventorySlot = slot
		return
	}
	c.selectedInventorySlot = 0
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
	return s.sendPacketToSession(client, inventorySnapshotPacket(client.inventory, client.selectedSlot()))
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

func inventorySnapshotPacket(inventory playerinventory.Inventory, selectedSlot uint32) *api.Packet {
	return &api.Packet{
		Payload: &api.Packet_InventorySnapshot{
			InventorySnapshot: inventorySnapshot(inventory, selectedSlot),
		},
	}
}

func inventorySnapshot(inventory playerinventory.Inventory, selectedSlot uint32) *api.InventorySnapshot {
	slots := inventory.Slots()
	apiSlots := make([]*api.InventorySlot, 0, len(slots))
	for _, slot := range slots {
		apiSlots = append(apiSlots, &api.InventorySlot{
			BlockId: uint32(slot.BlockID),
			Count:   slot.Count,
		})
	}
	return &api.InventorySnapshot{
		Slots:        apiSlots,
		SelectedSlot: selectedSlot,
	}
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
