extends Node2D
class_name Player

const SPEED := 250.0
const MIN_MOVE_INTERVAL_MS := 100

# Set by Main when the player is spawned.
var world: World

# The current route and progress along it. Both are replicated on spawn
# (see the MultiplayerSynchronizer) so late joiners see players who are
# already walking.
@export var path := PackedVector2Array()
@export var path_index := 0

var _last_move_ms := 0


func _ready() -> void:
	if _is_local_player():
		$Camera2D.enabled = true
		$Camera2D.make_current()


# --- Input (local client only) ----------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player():
		return

	# Requires Project Settings > Input Devices > Pointing >
	# "Emulate Mouse From Touch" to be OFF, otherwise a tap fires both.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_request_move(_screen_to_world(event.position))

	elif event is InputEventScreenTouch:
		if event.pressed:
			_request_move(_screen_to_world(event.position))


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _request_move(target: Vector2) -> void:
	print("_request_move", target)
	move_to.rpc_id(1, target)


# --- Server: validate the request, compute the path, tell everyone ----------

@rpc("any_peer", "reliable")
func move_to(target: Vector2) -> void:
	print("move_to", target)
	if not multiplayer.is_server():
		return

	# A client may only control its own player.
	if multiplayer.get_remote_sender_id() != int(name):
		return

	if not target.is_finite():
		return

	var now := Time.get_ticks_msec()
	if now - _last_move_ms < MIN_MOVE_INTERVAL_MS:
		return
	_last_move_ms = now

	if world == null:
		return

	var new_path := world.find_path(global_position, target)
	if new_path.size() < 2:
		return

	_set_path(new_path)
	_receive_path.rpc(new_path)


# --- Clients: the server says "walk this route" -----------------------------

@rpc("authority", "call_remote", "reliable")
func _receive_path(new_path: PackedVector2Array) -> void:
	print("_receive_path", new_path)
	_set_path(new_path)


# --- Shared movement ---------------------------------------------------------

func _set_path(new_path: PackedVector2Array) -> void:
	path = new_path
	path_index = 1  # Point 0 is where the player already is.


func _follow_path(delta: float) -> void:
	if path_index >= path.size():
		return

	var waypoint := path[path_index]
	global_position = global_position.move_toward(waypoint, SPEED * delta)

	if global_position.is_equal_approx(waypoint):
		path_index += 1


# The server steps on the fixed physics tick; clients step every rendered
# frame so motion stays smooth at any refresh rate.
func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_follow_path(delta)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		_follow_path(delta)


func _is_local_player() -> bool:
	return not multiplayer.is_server() \
		and int(name) == multiplayer.get_unique_id()
