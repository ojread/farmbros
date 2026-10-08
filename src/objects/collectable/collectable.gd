extends Node2D
class_name Collectable
## An item lying on the ground. The server decides what it is and removes it
## when a player walks over it; clients just draw it.

## Set by Main's spawn function before the node enters the tree.
var item_id: StringName

var _sprite: Sprite2D
var _age := randf() * TAU


func _ready() -> void:
	# A headless server has nothing to draw.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	var definition := ItemDatabase.get_definition(item_id)
	if definition == null:
		push_warning("Collectable with unknown item '%s'" % item_id)
		return
	_sprite = Sprite2D.new()
	_sprite.texture = definition.get_icon()
	add_child(_sprite)


func _process(delta: float) -> void:
	if _sprite:
		_age += delta * 3.0
		_sprite.position.y = sin(_age) * 0.8
