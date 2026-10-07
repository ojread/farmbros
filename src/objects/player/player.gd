extends Node2D
class_name Player
## The player is just: validation of move requests, and a camera. Pointer
## input comes from the InputHandler; all movement lives in PathWalker.

const MIN_MOVE_INTERVAL_MS := 100
const CAMERA_SMOOTHING_SPEED := 8.0

@onready var walker: PathWalker = $PathWalker
@onready var camera: Camera2D = $Camera2D

var _last_move_ms := 0


func _ready() -> void:
	# Remote players (and the server) get no camera and no input.
	if not _is_local_player():
		return

	_setup_camera()

	var input_handler := get_tree().get_first_node_in_group(&"input_handler") as InputHandler
	if input_handler:
		input_handler.primary_action.connect(_request_move)
	else:
		push_warning("No InputHandler found; this player can't be controlled.")


func _setup_camera() -> void:
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = CAMERA_SMOOTHING_SPEED

	# Keep the view inside the map so the clear colour never shows.
	var world := get_tree().get_first_node_in_group(&"world") as World
	if world:
		var bounds: Rect2i = world.get_world_bounds()
		camera.limit_left = floori(bounds.position.x)
		camera.limit_top = floori(bounds.position.y)
		camera.limit_right = ceili(bounds.end.x)
		camera.limit_bottom = ceili(bounds.end.y)

	camera.reset_smoothing()


# --- Client: ask the server to move us ---------------------------------------

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
