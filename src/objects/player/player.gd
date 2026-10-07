extends Node2D
class_name Player
## The player is just: validation of move requests, portal use, and a camera.
## Pointer input is read by InputHandler and routed by Main; all movement
## lives in the PathWalker child.

const MIN_MOVE_INTERVAL_MS := 100
const CAMERA_SMOOTHING_SPEED := 8.0

@onready var walker: PathWalker = $PathWalker
@onready var camera: Camera2D = $Camera2D
@onready var world: World = get_tree().get_first_node_in_group(&"world")

var _last_move_ms := 0


func _ready() -> void:
	if multiplayer.is_server():
		# Standing on a portal when a walk ends means "go through".
		walker.arrived.connect(_on_arrived)
	elif _is_local_player():
		# Deferred so replicated spawn properties (position) are applied first.
		_setup_camera.call_deferred()


# --- Client: ask the server to move us ---------------------------------------

func request_move(target: Vector2) -> void:
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


func _on_arrived() -> void:
	world.use_portal_at(self)


# --- Travel ----------------------------------------------------------------------

## Server only. Tell the owning client we were moved to another area.
func notify_teleported() -> void:
	_teleported.rpc_id(int(name), position)


@rpc("authority", "call_remote", "reliable")
func _teleported(new_position: Vector2) -> void:
	position = new_position
	_setup_camera()


# --- Camera ----------------------------------------------------------------------

func _setup_camera() -> void:
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = CAMERA_SMOOTHING_SPEED

	# Keep the view inside the area we're in so the clear colour never shows.
	var area := world.area_at(global_position)
	if area:
		var bounds := area.get_bounds_global()
		camera.limit_left = floori(bounds.position.x)
		camera.limit_top = floori(bounds.position.y)
		camera.limit_right = ceili(bounds.end.x)
		camera.limit_bottom = ceili(bounds.end.y)

	camera.make_current()
	camera.reset_smoothing()


func _is_local_player() -> bool:
	return not multiplayer.is_server() \
		and int(name) == multiplayer.get_unique_id()
