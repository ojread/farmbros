class_name TileDatabase
extends RefCounted

const EMPTY_ID := &"empty"

const DEFINITIONS := [
	preload("res://data/tiles/dirt.tres"),
	preload("res://data/tiles/empty.tres"),
	preload("res://data/tiles/grass.tres"),
	preload("res://data/tiles/tree.tres"),
	preload("res://data/tiles/stone_wall.tres"),
	preload("res://data/tiles/door_closed.tres"),
	preload("res://data/tiles/door_open.tres"),
]

static var _by_id: Dictionary = {}

static func get_definition(id: StringName) -> TileDefinition:
	if _by_id.is_empty():
		for definition: TileDefinition in DEFINITIONS:
			_by_id[definition.id] = definition

	# Tiles with no tile_id custom data come back as "". Treat them as empty
	# on purpose, rather than relying on a definition with a blank id.
	if id == &"":
		id = EMPTY_ID

	var definition: TileDefinition = _by_id.get(id)
	if definition == null:
		push_warning("No tile definition for '%s'" % id)
	return definition
