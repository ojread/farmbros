extends Node2D

const PLAYER_SCENE := preload("res://objects/player/player.tscn")

## Assign in the inspector once the animal scene exists.
@export var animal_scene: PackedScene
@export var animal_count := 5

@onready var world: World = $World
@onready var players: Node2D = $World/Players
@onready var player_spawner: MultiplayerSpawner = $World/Players/MultiplayerSpawner
@onready var animals: Node2D = $World/Animals
@onready var animal_spawner: MultiplayerSpawner = $World/Animals/MultiplayerSpawner
@onready var spawn_point: Marker2D = $World/SpawnPoint


func _ready() -> void:
	# The server and browser use the same Main scene.
	#
	#   godot --headless --path src --server   -> starts a server
	#   anything else                          -> connects as a client
	#
	# Spawn functions must be set on every peer before any spawn arrives.
	player_spawner.spawn_function = _spawn_player
	animal_spawner.spawn_function = _spawn_animal

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if "--server" in OS.get_cmdline_args():
		_start_server()
	else:
		_connect_client()


# --- Startup -----------------------------------------------------------------

func _start_server() -> void:
	print("Starting server")

	if Network.start_server() != OK:
		# Exit so systemd restarts us and the failure is obvious in the logs,
		# rather than leaving an idle process that looks like it's working.
		push_error("Unable to start server.")
		get_tree().quit(1)
		return

	_spawn_animals()


func _connect_client() -> void:
	print("Starting client")

	if Network.connect_to_server() != OK:
		push_error("Unable to connect to server.")


# --- Connection events -------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

	if not multiplayer.is_server():
		return

	# The server creates the player's node; the spawner replicates it.
	player_spawner.spawn(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)

	if not multiplayer.is_server():
		return

	var player := players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


func _on_connection_failed() -> void:
	push_error("Could not connect to the server.")


func _on_server_disconnected() -> void:
	push_error("Disconnected from the server.")


# --- Players -----------------------------------------------------------------

func _spawn_player(peer_id: int) -> Node:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = str(peer_id)
	player.position = players.to_local(spawn_point.global_position)
	return player


# --- Animals (server-owned) ---------------------------------------------------

func _spawn_animals() -> void:
	if animal_scene == null:
		push_warning("No animal_scene assigned on Main; skipping animals.")
		return

	var nav_map := world.get_world_2d().get_navigation_map()

	if not await _wait_for_navigation(nav_map):
		push_warning("Navigation mesh never became queryable; skipping animals. "
				+ "regions=%d iteration=%d" % [
					NavigationServer2D.map_get_regions(nav_map).size(),
					NavigationServer2D.map_get_iteration_id(nav_map)])
		return

	for i in animal_count:
		# Pick a spot near the spawn point and snap it onto the walkable mesh
		# so no animal starts inside a wall. Distances are global pixels.
		var wanted := spawn_point.global_position \
				+ Vector2.from_angle(randf() * TAU) * randf_range(32.0, 192.0)
		var walkable := NavigationServer2D.map_get_closest_point(nav_map, wanted)

		# The data is sent to every client, so all peers build the same node.
		animal_spawner.spawn({
			"id": i,
			"position": animals.to_local(walkable),
		})


# The map's iteration id becomes non-zero after the first sync, but the mesh
# can still return Vector2.ZERO for a little while after that. The spawn
# point is placed on walkable ground, so the closest mesh point to it must be
# non-zero once the mesh is really usable. Capped so a bad scene can't hang
# the server.
func _wait_for_navigation(nav_map: RID) -> bool:
	for _frame in 300:
		# Don't query before the first sync; that logs an error.
		if NavigationServer2D.map_get_iteration_id(nav_map) != 0:
			var probe := NavigationServer2D.map_get_closest_point(
					nav_map, spawn_point.global_position)
			if probe != Vector2.ZERO:
				return true
		await get_tree().physics_frame
	return false


func _spawn_animal(data: Dictionary) -> Node:
	var animal := animal_scene.instantiate() as Node2D
	animal.name = "Animal%d" % data["id"]
	animal.position = data["position"]
	return animal
