class_name ItemDatabase
extends RefCounted

const DEFINITIONS := [
	preload("res://data/items/apple.tres"),
	preload("res://data/items/berries.tres"),
	preload("res://data/items/pear.tres"),
]

static var _by_id := {}


static func get_definition(id: StringName) -> ItemDefinition:
	_ensure_loaded()
	return _by_id.get(id)


## A random collectable item id, weighted by spawn_weight.
static func pick_collectable() -> StringName:
	var total := 0.0
	for definition: ItemDefinition in DEFINITIONS:
		if definition.collectable:
			total += definition.spawn_weight
	if total <= 0.0:
		return &""

	var roll := randf() * total
	for definition: ItemDefinition in DEFINITIONS:
		if not definition.collectable:
			continue
		roll -= definition.spawn_weight
		if roll <= 0.0:
			return definition.id
	return &""


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	for definition: ItemDefinition in DEFINITIONS:
		_by_id[definition.id] = definition
