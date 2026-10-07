extends Node

const SERVER_PORT := 6767
const DEFAULT_SERVER_URL := "ws://127.0.0.1:6767"
const PUBLIC_SERVER_HOST := "farmbros-server.reads.org.uk"

## Players beyond this are disconnected as soon as they connect.
const MAX_PLAYERS := 8

## The server only accepts connections from this machine, so it can't be
## reached directly over the LAN; everything goes through the tunnel.
## If whatever proxies to the server runs on a different machine (or targets
## the Pi's LAN IP), change this to "*".
const SERVER_BIND_ADDRESS := "127.0.0.1"


func start_server() -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(SERVER_PORT, SERVER_BIND_ADDRESS)
	if error != OK:
		push_error("Failed to start WebSocket server: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	print("WebSocket server listening on %s:%d" % [SERVER_BIND_ADDRESS, SERVER_PORT])
	return OK


func connect_to_server(url: String = "") -> Error:
	if url.is_empty():
		url = _default_url()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		push_error("Failed to create WebSocket client: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % url)
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _default_url() -> String:
	if not OS.has_feature("web"):
		return DEFAULT_SERVER_URL

	var hostname: String = JavaScriptBridge.eval("window.location.hostname")
	var host: String = JavaScriptBridge.eval("window.location.host")

	# Quick tunnels: https://you.github.io/farmbros/?server=random-words.trycloudflare.com
	var override = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('server')")
	if override is String and not override.is_empty():
		return "wss://%s" % override

	# Local development: web build served from this machine, server running
	# locally too.
	if hostname == "localhost" or hostname == "127.0.0.1":
		return DEFAULT_SERVER_URL

	# On your home network, via Caddy on the Pi
	if hostname.ends_with(".local") or hostname.begins_with("192.168."):
		return "wss://%s/ws" % host

	# Hosted on the internet, via the named tunnel
	return "wss://%s" % PUBLIC_SERVER_HOST
