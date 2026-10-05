extends Node
class_name WanderBrain
## Server-only AI: pick a nearby spot, walk there, pause, repeat.
## Clients never run this; they just receive the paths the server sends.

@export var walker: PathWalker
@export var radius := 256.0     # global pixels (the world is scaled 4x)
@export var min_pause := 2.0
@export var max_pause := 6.0

var _home := Vector2.ZERO
var _pause_left := 0.0


func _ready() -> void:
	if not multiplayer.is_server():
		set_process(false)
		return

	_home = walker.body.global_position
	_pause_left = randf_range(0.0, max_pause)  # Stagger so herds don't sync up.


func _process(delta: float) -> void:
	if walker.is_walking():
		return

	_pause_left -= delta
	if _pause_left > 0.0:
		return

	_pause_left = randf_range(min_pause, max_pause)

	var offset := Vector2.from_angle(randf() * TAU) \
			* randf_range(radius * 0.25, radius)
	walker.walk_to(_home + offset)
