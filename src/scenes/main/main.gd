extends Node2D

const PLAYER_SCENE := preload("res://objects/player/player.tscn")
const COLLECTABLE_SCENE := preload("res://objects/collectable/collectable.tscn")

## How often the server tops up the items lying around (one per area per tick).
const COLLECTABLE_REFILL_SEC := 8.0

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
@onready var collectable_spawner: MultiplayerSpawner = world.collectable_spawner
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
	collectable_spawner.spawn_function = _spawn_collectable

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

	_refill_collectables(true)
	var refill_timer := Timer.new()
	refill_timer.wait_time = COLLECTABLE_REFILL_SEC
	refill_timer.autostart = true
	refill_timer.timeout.connect(_refill_collectables)
	add_child(refill_timer)


func _setup_client_controls() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_hud.set_palette(world.get_palette())

	world.inventory.changed.connect(_on_inventory_changed)
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

# Left-click / tap: do whatever the toolbar says (walk, place a block, or feed).
func _on_primary_action(world_pos: Vector2) -> void:
	if _hud.mode == Hud.BUILD and _hud.block_id != &"":
		_request_block(world_pos, _hud.block_id)
	elif _hud.mode == Hud.FEED and _try_feed(world_pos):
		return
	else:
		_request_move(world_pos)


func _request_move(world_pos: Vector2) -> void:
	var player := world.get_local_player() as Player
	if player:
		player.request_move(world_pos)


## Feed the tapped animal if it's close enough. Returns false if there's no
## animal there, or it's too far, so the tap walks toward it instead.
func _try_feed(world_pos: Vector2) -> bool:
	var player := world.get_local_player()
	var animal := world.nearest_animal(world_pos, World.FEED_CLICK_RADIUS)
	if player == null or animal == null:
		return false
	if not world.is_in_feed_reach(player.global_position, animal.global_position):
		return false
	world.request_feed.rpc_id(1, world_pos, String(_hud.item_id))
	return true


func _on_inventory_changed() -> void:
	_hud.set_items(world.inventory.local_items)


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
	world.inventory.clear_local()
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
	for container: Node in [players, animals, world.collectables]:
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


# --- Collectables (server-owned) ----------------------------------------------

var _next_collectable_id := 0


## Top up each area to its collectable_count. Normally adds one per area per
## call, so items trickle back; `fill_all` adds them all at once (at startup).
func _refill_collectables(fill_all := false) -> void:
	var counts := {}
	for child in world.collectables.get_children():
		var item := child as Collectable
		if item == null or item.is_queued_for_deletion():
			continue
		var area := world.area_at(item.global_position)
		counts[area] = int(counts.get(area, 0)) + 1

	var spawned := false
	for area: Area in world.get_areas():
		var missing := area.collectable_count - int(counts.get(area, 0))
		var to_spawn := missing if fill_all else mini(missing, 1)
		for i in to_spawn:
			spawned = _spawn_one_collectable(area) or spawned

	# Make the newcomers visible to the players who should see them.
	if spawned:
		world.refresh_visibility()


func _spawn_one_collectable(area: Area) -> bool:
	var item_id := ItemDatabase.pick_collectable()
	var global_pos := area.random_open_position_anywhere()
	if item_id == &"" or not global_pos.is_finite():
		return false

	collectable_spawner.spawn({
		"id": _next_collectable_id,
		"item": String(item_id),
		"position": world.collectables.to_local(global_pos),
	})
	_next_collectable_id += 1
	return true


func _spawn_collectable(data: Dictionary) -> Node:
	var item := COLLECTABLE_SCENE.instantiate() as Collectable
	item.name = "Collectable%d" % data["id"]
	item.item_id = StringName(data["item"])
	item.position = data["position"]
	return item
