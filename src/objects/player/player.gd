extends CharacterBody2D

const SPEED := 250.0
const TARGET_REACHED_DISTANCE := 5.0

# Render slightly behind the newest server snapshot.
const INTERPOLATION_DELAY := 0.12

# Authoritative position replicated by MultiplayerSynchronizer.
@export var network_position: Vector2

# Client-side interpolation state.
var previous_position: Vector2
var current_position: Vector2

var previous_snapshot_time: float = 0.0
var current_snapshot_time: float = 0.0

var path := PackedVector2Array()
var path_index := 0


func _ready() -> void:
	global_position = network_position
	previous_position = network_position
	current_position = network_position

	$MultiplayerSynchronizer.synchronized.connect(
		_on_synchronized
	)

	if _is_local_player():
		$Camera2D.enabled = true
		$Camera2D.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_send_move_command()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_send_move_command()


func _send_move_command() -> void:
	var target := get_global_mouse_position()

	move_to.rpc_id(1, target)


@rpc("any_peer", "reliable")
func move_to(target: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if sender_id != int(name):
		return

	var world := get_parent().get_parent()

	var navigation: WorldNavigation = world.get_node("Navigation")

	var new_path := navigation.find_path(
		global_position,
		target
	)

	if new_path.is_empty():
		path.clear()
		path_index = 0
		velocity = Vector2.ZERO
		return

	path = new_path
	path_index = 0


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_movement(delta)
	else:
		_client_interpolation()


func _server_movement(delta: float) -> void:
	global_position = network_position

	if path.is_empty():
		velocity = Vector2.ZERO
		return

	if path_index >= path.size():
		velocity = Vector2.ZERO
		path.clear()
		return

	var waypoint := path[path_index]

	var distance := global_position.distance_to(waypoint)

	if distance <= TARGET_REACHED_DISTANCE:
		path_index += 1
		return

	var direction := global_position.direction_to(waypoint)

	velocity = direction * SPEED

	move_and_slide()

	network_position = global_position


func _client_interpolation() -> void:
	if current_snapshot_time <= 0.0:
		return

	var now := Time.get_ticks_msec() / 1000.0

	var render_time := now - INTERPOLATION_DELAY

	var snapshot_duration := (
		current_snapshot_time - previous_snapshot_time
	)

	if snapshot_duration <= 0.0:
		global_position = current_position
		return

	var t := (
		render_time - previous_snapshot_time
	) / snapshot_duration

	t = clamp(t, 0.0, 1.0)

	global_position = previous_position.lerp(
		current_position,
		t
	)


func _on_synchronized() -> void:
	if multiplayer.is_server():
		return

	var now := Time.get_ticks_msec() / 1000.0

	previous_position = current_position
	previous_snapshot_time = current_snapshot_time

	current_position = network_position
	current_snapshot_time = now


func _is_local_player() -> bool:
	return not multiplayer.is_server() \
		and int(name) == multiplayer.get_unique_id()
