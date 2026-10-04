extends Node

const SERVER_PORT := 6767
const DEFAULT_SERVER_URL := "ws://127.0.0.1:6767"
const PUBLIC_SERVER_HOST := "farmbros-server.reads.org,uk"

func start_server() -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(SERVER_PORT)
	if error != OK:
		push_error("Failed to start WebSocket server: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	print("WebSocket server listening on port %d" % SERVER_PORT)
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


#func _default_url() -> String:
	#if not OS.has_feature("web"):
		#return DEFAULT_SERVER_URL  # Editor / desktop testing.
#
	#var host: String = JavaScriptBridge.eval("window.location.hostname")
	#var page_protocol: String = JavaScriptBridge.eval("window.location.protocol")
#
	## Optional override: http://192.168.1.50:8080/?server=192.168.1.50
	#var override = JavaScriptBridge.eval(
		#"new URLSearchParams(window.location.search).get('server')")
	#if override is String and not override.is_empty():
		#host = override
#
	#var scheme := "wss" if page_protocol == "https:" else "ws"
	#return "%s://%s:%d" % [scheme, host, SERVER_PORT]


#func _default_url() -> String:
	#if not OS.has_feature("web"):
		#return DEFAULT_SERVER_URL
#
	#var page_host: String = JavaScriptBridge.eval("window.location.host")
	#var protocol: String = JavaScriptBridge.eval("window.location.protocol")
#
	#if protocol == "https:":
		#return "wss://%s/ws" % page_host   # host includes :8443
	#return "ws://%s:%d" % [page_host.get_slice(":", 0), SERVER_PORT]



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

	# On your home network, via Caddy on the Pi
	if hostname.ends_with(".local") or hostname.begins_with("192.168."):
		return "wss://%s/ws" % host

	# Hosted on the internet, via the named tunnel
	return "wss://%s" % PUBLIC_SERVER_HOST
