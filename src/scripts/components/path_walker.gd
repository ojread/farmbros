extends Node
class_name PathWalker
## Reusable movement component: walks its parent Node2D along a navigation
## path at constant speed. The server computes the path and tells every
## client once; each peer then walks the route itself.
##
## Add as a child of any entity (player, animal, enemy...). The entity's
## MultiplayerSynchronizer should replicate, with Spawn ticked and mode Never:
##   .:position   PathWalker:path   PathWalker:path_index
## The World node must be in a group called "world".

signal arrived

@export var speed := 250.0   # global pixels per second

# Replicated on spawn so late joiners see entities that are mid-walk.
@export var path := PackedVector2Array()
@export var path_index := 0

var body: Node2D:
	get:
		return get_parent() as Node2D

@onready var world: World = get_tree().get_first_node_in_group("world")

var _target := Vector2.ZERO


func is_walking() -> bool:
	return path_index < path.size()


## Server only. Returns false if there is no route.
func walk_to(target: Vector2) -> bool:
	if not multiplayer.is_server() or world == null:
		return false

	var new_path := world.find_path(body.global_position, target)
	if new_path.size() < 2:
		return false

	_target = target
	_set_path(new_path)
	_receive_path.rpc(new_path)
	return true


## Server only. Call after the map changes (e.g. a tile was built on).
func repath() -> void:
	if is_walking():
		walk_to(_target)


@rpc("authority", "call_remote", "reliable")
func _receive_path(new_path: PackedVector2Array) -> void:
	_set_path(new_path)


func _set_path(new_path: PackedVector2Array) -> void:
	path = new_path
	path_index = 1  # Point 0 is where the entity already is.


func _follow(delta: float) -> void:
	if not is_walking():
		return

	var waypoint := path[path_index]
	body.global_position = body.global_position.move_toward(waypoint, speed * delta)

	if body.global_position.is_equal_approx(waypoint):
		path_index += 1
		if not is_walking():
			arrived.emit()


# The server steps on the fixed physics tick; clients every rendered frame.
func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_follow(delta)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		_follow(delta)
