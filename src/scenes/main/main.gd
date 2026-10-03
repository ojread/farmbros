extends Node2D

const PLAYER_SCENE := preload("res://objects/player/player.tscn")

@onready var world: World = $World
@onready var players: Node2D = $World/Players
@onready var player_spawner: MultiplayerSpawner = $World/Players/MultiplayerSpawner
@onready var spawn_point: Marker2D = $World/SpawnPoint


func _ready() -> void:
	# The server and browser use the same Main scene.
	#
	# When running:
	#
	#   godot --headless --server
	#
	# we start a server.
	#
	# Otherwise this is a browser/client.
	
	player_spawner.spawn_function = _spawn_player
	
	if "--server" in OS.get_cmdline_args():
		print("Starting server")
		_start_server()
	else:
		print("Starting client")
		_connect_client()

	# These signals are useful on both server and client.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _start_server() -> void:
	var error := Network.start_server()

	if error != OK:
		push_error("Unable to start server.")


func _connect_client() -> void:
	var error := Network.connect_to_server()

	if error != OK:
		push_error("Unable to connect to server.")


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

	if not multiplayer.is_server():
		return

	# The server creates the player's node.
	player_spawner.spawn(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)

	if not multiplayer.is_server():
		return

	var player := players.get_node_or_null(str(peer_id))

	if player:
		player.queue_free()


func _spawn_player(peer_id: int) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.world = world
	player.global_position = spawn_point.global_position
	return player
