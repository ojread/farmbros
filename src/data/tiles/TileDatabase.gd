class_name TileDatabase
extends Node

const GRASS := preload("res://data/tiles/grass.tres")
const DIRT := preload("res://data/tiles/dirt.tres")
#const WATER := preload("res://data/tiles/water.tres")
#const STONE := preload("res://data/tiles/stone.tres")
const TREE := preload("res://data/tiles/tree.tres")
const STONE_WALL := preload("res://data/tiles/stone_wall.tres")


static var definitions: Dictionary = {
	&"grass": GRASS,
	&"dirt": DIRT,
	#&"water": WATER,
	#&"stone": STONE,
	&"tree": TREE,
	&"stone": STONE_WALL,
}


static func get_definition(id: StringName) -> TileDefinition:
	return definitions.get(id)
