extends CharacterBody2D
class_name Player

const SPEED := 250.0
const TARGET_REACHED_DISTANCE := 5.0

# Render slightly behind the newest server snapshot.
const INTERPOLATION_DELAY := 0.12


# Authoritative position replicated by MultiplayerSynchronizer.
@export var network_position: Vector2


# Navigation path calculated by the server.
var path := PackedVector2Array()
var path_index := 0

# Client-side interpolation state.
var previous_position: Vector2
var current_position: Vector2

var previous_snapshot_time: float = 0.0
var current_snapshot_time: float = 0.0

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	# Wait for the navigation map to sync
	await get_tree().physics_frame
	
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
	print_debug("_send_move_command", target)
	move_to.rpc_id(1, target)


@rpc("any_peer", "reliable")
func move_to(target: Vector2) -> void:
	
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# A client may only control its own player.
	if sender_id != int(name):
		return

	#var world: World = get_parent().get_parent()
#
	#var new_path := world.find_path(
		#global_position,
		#target
	#)
#
	#if new_path.is_empty():
		#path.clear()
		#path_index = 0
		#velocity = Vector2.ZERO
		#return
#
	#path = new_path
	#path_index = 0
	
	navigation_agent.target_position = target


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_movement(delta)
	else:
		_client_interpolation()


func _server_movement(delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		return

	# Get the next point along the path
	var current_agent_position: Vector2 = global_position
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()
	
	if Engine.get_physics_frames() % 30 == 0:
		print_debug("pos=", global_position, " next=", next_path_position, " path=", navigation_agent.get_current_navigation_path())
		
	# Calculate movement direction
	var direction: Vector2 = (next_path_position - current_agent_position).normalized()
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
	#print_debug("_on_synchronized", network_position)
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
