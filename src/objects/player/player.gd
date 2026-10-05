extends Node2D
class_name Player
## The player is now just: input, validation, and a camera. All movement
## lives in the PathWalker child.

const MIN_MOVE_INTERVAL_MS := 100

@onready var walker: PathWalker = $PathWalker

var _last_move_ms := 0


func _ready() -> void:
	if _is_local_player():
		$Camera2D.enabled = true
		$Camera2D.make_current()


# --- Input (local client only) ----------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player():
		return

	# Requires "Emulate Mouse From Touch" to be OFF in project settings.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_request_move(_screen_to_world(event.position))
	elif event is InputEventScreenTouch:
		if event.pressed:
			_request_move(_screen_to_world(event.position))


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _request_move(target: Vector2) -> void:
	move_to.rpc_id(1, target)


# --- Server: validate the request, then hand over to the walker -------------

@rpc("any_peer", "reliable")
func move_to(target: Vector2) -> void:
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

	walker.walk_to(target)


func _is_local_player() -> bool:
	return not multiplayer.is_server() \
		and int(name) == multiplayer.get_unique_id()
