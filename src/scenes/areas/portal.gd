extends Marker2D
class_name Portal
## A doorway to another area. A player who walks onto its tile (tap the tile)
## is moved to the target area.
##
## Add it under the Area's "Portals" node and put it on a walkable tile. The
## Area works out which tile it sits on from its position.

@export var target_area: StringName
## Name of a Marker2D directly under the target Area.
@export var target_spawn: StringName = &"SpawnPoint"

const RADIUS := 6.0
const COLOR := Color(0.62, 0.38, 0.95, 0.9)


func _ready() -> void:
	# Nothing to animate on a headless server.
	set_process(DisplayServer.get_name() != "headless")


func _process(delta: float) -> void:
	rotation += delta * 1.5


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS, 0.0, PI * 0.8, 12, COLOR, 1.5)
	draw_arc(Vector2.ZERO, RADIUS, PI, PI * 1.8, 12, COLOR, 1.5)
	draw_arc(Vector2.ZERO, RADIUS * 0.5, 0.0, TAU, 16, COLOR, 1.0)
