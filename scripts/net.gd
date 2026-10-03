extends Node

const PORT := 8910
const MAX_PLAYERS := 8
const GRID_SIZE := 2.0
const MAX_FORCE := 20.0
const MAX_DAMAGE := 50.0
const MAX_HEAL := 50.0
const MIN_TIMER_INTERVAL := 0.5

signal block_type_rejected(reason: String)

var players_root: Node3D
var blocks_root: Node3D

var block_types: Dictionary = {}    # type_id -> {name, color, rules}
var placed_cells: Dictionary = {}   # "x,y,z" -> true (server-only bookkeeping)
var _next_block_type_seq := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	block_types["default"] = {
		"name": "Block",
		"color": Color(0.72, 0.55, 0.35, 1),
		"rules": [],
	}

func host(port: int = PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func join(ip: String, port: int = PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func register_world(players: Node3D, blocks: Node3D) -> void:
	players_root = players
	blocks_root = blocks
	if multiplayer.is_server():
		spawn_player(1)
		for id in multiplayer.get_peers():
			spawn_player(id)

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		spawn_player(id)
		_receive_full_palette.rpc_id(id, block_types)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players_root and players_root.has_node(str(id)):
		players_root.get_node(str(id)).queue_free()

const SPAWN_POINTS := [
	Vector3(0, 1.5, 5),
	Vector3(4, 1.5, 5),
	Vector3(-4, 1.5, 5),
	Vector3(0, 1.5, 8),
	Vector3(4, 1.5, 8),
	Vector3(-4, 1.5, 8),
]

func spawn_player(id: int) -> void:
	if not players_root or players_root.has_node(str(id)):
		return
	var player := preload("res://scenes/Player.tscn").instantiate()
	player.name = str(id)
	player.owner_id = id
	player.position = SPAWN_POINTS[id % SPAWN_POINTS.size()]
	players_root.add_child(player, true)

func free_cell(cell: Vector3i) -> void:
	placed_cells.erase("%d,%d,%d" % [cell.x, cell.y, cell.z])

# Any connected peer may request a block; only the server actually places one
# (it owns Blocks/, so MultiplayerSpawner replicates the new node to everyone).
@rpc("any_peer", "call_local", "reliable")
func request_place_block(cell: Vector3i, type_id: String) -> void:
	if not multiplayer.is_server() or not blocks_root:
		return
	if not block_types.has(type_id):
		return
	var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
	if placed_cells.has(key):
		return
	placed_cells[key] = true
	var block := preload("res://scenes/Block.tscn").instantiate()
	block.name = "b_%d_%d_%d_%s" % [cell.x, cell.y, cell.z, type_id]
	block.position = Vector3(cell.x, cell.y, cell.z) * GRID_SIZE + Vector3.ONE * (GRID_SIZE * 0.5)
	blocks_root.add_child(block, true)

# --- Player-invented block types: submit -> moderate -> broadcast ---

@rpc("any_peer", "call_local", "reliable")
func submit_block_type(def: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var creator := sender if sender != 0 else multiplayer.get_unique_id()

	var result: Dictionary = await Moderation.review(def)
	if not result.get("approved", false):
		_block_type_rejected.rpc_id(creator, str(result.get("reason", "Rejected")))
		return

	_next_block_type_seq += 1
	var type_id := "t%d" % _next_block_type_seq
	var clean := Moderation.sanitize(def)
	block_types[type_id] = clean
	_sync_block_type.rpc(type_id, clean)
	_block_type_approved.rpc_id(creator, type_id)

@rpc("authority", "reliable")
func _sync_block_type(type_id: String, def: Dictionary) -> void:
	block_types[type_id] = def

@rpc("authority", "reliable")
func _receive_full_palette(all_types: Dictionary) -> void:
	block_types = all_types

@rpc("authority", "call_local", "reliable")
func _block_type_rejected(reason: String) -> void:
	block_type_rejected.emit(reason)

signal block_type_approved(type_id: String)

@rpc("authority", "call_local", "reliable")
func _block_type_approved(type_id: String) -> void:
	block_type_approved.emit(type_id)
