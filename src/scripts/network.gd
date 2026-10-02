extends Node

const SERVER_PORT := 7001
const DEFAULT_SERVER_URL := "ws://127.0.0.1:7001"

func start_server() -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(SERVER_PORT)
	if error != OK:
		push_error("Failed to start WebSocket server: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("WebSocket server listening on port %d" % SERVER_PORT)
	return OK


func connect_to_server(
	url: String = DEFAULT_SERVER_URL
) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		push_error("Failed to create WebSocket client: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % url)
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
