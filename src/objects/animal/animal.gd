extends Node2D
class_name Animal
## A farm animal. The AI lives in WanderBrain; this just shows a heart above
## the animal while it is following someone.

@onready var brain: WanderBrain = $WanderBrain


func _ready() -> void:
	brain.following_changed.connect(queue_redraw)


## Server only. Called when a player feeds this animal.
func feed(player: Node2D, follow_seconds: float) -> void:
	brain.follow(player, follow_seconds)


func _draw() -> void:
	if brain == null or not brain.following:
		return
	var colour := Color(0.95, 0.25, 0.35)
	var centre := Vector2(0, -11)
	draw_circle(centre + Vector2(-1.6, 0), 2.0, colour)
	draw_circle(centre + Vector2(1.6, 0), 2.0, colour)
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(-3.5, 0.5),
		centre + Vector2(3.5, 0.5),
		centre + Vector2(0, 4.8),
	]), colour)
