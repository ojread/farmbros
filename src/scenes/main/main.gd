extends Node2D

const PLAYER_SCENE := preload("res://objects/player/player.tscn")

## How long a connection attempt may take before we give up and retry.
const CONNECT_TIMEOUT_SEC := 10.0
## Seconds to wait between retries. The last value repeats.
const RETRY_DELAYS_SEC := [1.0, 2.0, 5.0, 10.0]
## A connection that lasted this long counts as healthy, so the next
## reconnect starts again from the shortest delay.
const STABLE_CONNECTION_SEC := 30.0

## Set in the Main scene.
@export var animal_scene: PackedScene

@onready var world: World = $World
@onready var players: Node2D = $World/Entities/Players
@onready var player_spawner: MultiplayerSpawner = $World/Entities/Players/MultiplayerSpawner
@onready var animals: Node2D = $World/Entities/Animals
@onready var animal_spawner: MultiplayerSpawner = $World/Entities/Animals/MultiplayerSpawner
@onready var input_handler: InputHandler = $InputHandler

# Client only.
var _overlay: ConnectionOverlay
var _hud: Hud
var _shown_area: Area
var _connect_timer: Timer
var _retry_timer: Timer
var _retry_attempt := 0
var _connected_at_ms := 0


func _ready() -> void:
	# The server and browser use the same Main scene.
	#
	#   godot --headless --path src -- --server   -> starts a server
	#   anything else                             -> connects as a client
	#
	# Spawn functions must be set on every peer before any spawn arrives.
	player_spawner.spawn_function = _spawn_player
	animal_spawner.spawn_function = _spawn_animal

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if _is_server_mode():
		_start_server()
	else:
		_setup_client_controls()
		_setup_client_connection_ui()
		_connect_client()


## Server mode if exported as a dedicated server, or started with --server
## (either directly, or after the `--` separator).
func _is_server_mode() -> bool:
	return OS.has_feature("dedicated_server") \
		or "--server" in OS.get_cmdline_args() \
		or "--server" in OS.get_cmdline_user_args()


func _process(_delta: float) -> void:
	# Client: show which area we're in.
	if _hud == null:
		return
	var area := world.get_local_area()
	if area != _shown_area:
		_shown_area = area
		_hud.set_area_name(area.display_name if area else "")


# --- Startup -----------------------------------------------------------------

func _start_server() -> void:
	print("Starting server")

	if Network.start_server() != OK:
		# Exit so systemd restarts us and the failure is obvious in the logs,
		# rather than leaving an idle process that looks like it's working.
		push_error("Unable to start server.")
		get_tree().quit(1)
		return

	world.enable_persistence()
	_spawn_animals()


func _setup_client_controls() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_hud.set_palette(world.get_palette())

	input_handler.primary_action.connect(_on_primary_action)
	input_handler.secondary_action.connect(_on_secondary_action)


func _setup_client_connection_ui() -> void:
	_overlay = ConnectionOverlay.new()
	add_child(_overlay)

	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = CONNECT_TIMEOUT_SEC
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)

	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_connect_client)
	add_child(_retry_timer)


func _connect_client() -> void:
	print("Starting client")
	_overlay.show_message("Connecting…")

	if Network.connect_to_server() != OK:
		_schedule_retry("Could not start the connection")
		return

	_connect_timer.start()


# --- Client input ------------------------------------------------------------

# Left-click / tap: do whatever the toolbar says (walk, or place a block).
func _on_primary_action(world_pos: Vector2) -> void:
	if _hud.mode == Hud.BUILD and _hud.block_id != &"":
		_request_block(world_pos, _hud.block_id)
	else:
		var player := world.get_local_player() as Player
		if player:
			player.request_move(world_pos)


# Right-click / long press: remove the block there.
func _on_secondary_action(world_pos: Vector2) -> void:
	_request_block(world_pos, &"")


func _request_block(world_pos: Vector2, block_id: StringName) -> void:
	var area := world.get_local_area()
	if area == null:
		return
	var cell := area.global_to_cell(world_pos)
	if area.is_in_bounds(cell):
		world.request_set_block.rpc_id(1, cell, String(block_id))


# --- Connection events -------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

	if not multiplayer.is_server():
		return

	# The new peer is already counted in get_peers().
	if multiplayer.get_peers().size() > Network.MAX_PLAYERS:
		print("Server full, rejecting peer ", peer_id)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	world.send_snapshot_to(peer_id)

	# The server creates the player's node; the spawner replicates it to peers
	# in the same area (see World.refresh_visibility).
	var start := world.get_start_area()
	player_spawner.spawn({
		"id": peer_id,
		"position": players.to_local(start.get_spawn_global()),
	})
	world.refresh_visibility.call_deferred()


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)

	if not multiplayer.is_server():
		return

	var player := players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


func _on_connected_to_server() -> void:
	_connect_timer.stop()
	_connected_at_ms = Time.get_ticks_msec()
	_overlay.hide_message()


func _on_connection_failed() -> void:
	_connect_timer.stop()
	_schedule_retry("Could not connect to the server")


func _on_connect_timeout() -> void:
	Network.disconnect_from_server()
	_schedule_retry("Connection timed out")


func _on_server_disconnected() -> void:
	var connected_for_sec := (Time.get_ticks_msec() - _connected_at_ms) / 1000.0
	if connected_for_sec >= STABLE_CONNECTION_SEC:
		_retry_attempt = 0

	_clear_entities()
	_schedule_retry("Disconnected from the server")


func _schedule_retry(reason: String) -> void:
	# More than one signal can report the same failure; only schedule once.
	if not _retry_timer.is_stopped():
		return

	var delay: float = RETRY_DELAYS_SEC[mini(_retry_attempt, RETRY_DELAYS_SEC.size() - 1)]
	_retry_attempt += 1

	push_warning("%s. Retrying in %.0f s." % [reason, delay])
	_overlay.show_message("%s.\nRetrying in %.0f s…" % [reason, delay])
	_retry_timer.start(delay)


## Client only. Drop everything the old session spawned; the server will
## spawn it all again after we reconnect. (Blocks are replaced by the snapshot.)
func _clear_entities() -> void:
	for container: Node in [players, animals]:
		for child in container.get_children():
			if child is MultiplayerSpawner:
				continue
			child.queue_free()


# --- Players -----------------------------------------------------------------

func _spawn_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = str(data["id"])
	player.position = data["position"]
	return player


# --- Animals (server-owned) ---------------------------------------------------

func _spawn_animals() -> void:
	if animal_scene == null:
		push_warning("No animal_scene assigned on Main; skipping animals.")
		return

	var next_id := 0
	for area: Area in world.get_areas():
		for i in area.animal_count:
			# Pick a spot near the area's spawn and snap it onto open ground
			# so no animal starts inside a wall. Distances are global pixels.
			var global_pos := area.random_open_position(area.get_spawn_global(), 32.0, 192.0)

			# The data is sent to every peer that sees it, so all of them
			# build the same node.
			animal_spawner.spawn({
				"id": next_id,
				"position": animals.to_local(global_pos),
			})
			next_id += 1

	world.refresh_visibility()


func _spawn_animal(data: Dictionary) -> Node:
	var animal := animal_scene.instantiate() as Node2D
	animal.name = "Animal%d" % data["id"]
	animal.position = data["position"]
	return animal
