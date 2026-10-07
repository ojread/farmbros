class_name BlockCatalog
extends RefCounted
## Which tiles players can place, and how to draw them.
##
## Nothing is duplicated here: a block id is just a tile_id custom-data value
## from the tile set (the same ids TileDatabase uses). To make another tile
## placeable, give it a tile_id in the tile set, add a TileDefinition for it
## (set walkable = false if it should block movement), and add its id below.

const PLACEABLE: Array[StringName] = [
	&"stone_wall",
	&"tree",
	&"dirt",
	&"grass",
]

# TileSet -> { id: { source, coords, texture, region } }
static var _cache := {}


## Returns {} if the tile set has no tile with this id.
static func get_entry(tile_set: TileSet, id: StringName) -> Dictionary:
	return _entries(tile_set).get(id, {})


static func _entries(tile_set: TileSet) -> Dictionary:
	if _cache.has(tile_set):
		return _cache[tile_set]

	var entries := {}
	for i in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue

		for j in source.get_tiles_count():
			var coords := source.get_tile_id(j)
			var data := source.get_tile_data(coords, 0)
			var id := StringName(data.get_custom_data("tile_id"))
			if id == &"" or id == &"empty" or entries.has(id):
				continue
			entries[id] = {
				"source": source_id,
				"coords": coords,
				"texture": source.texture,
				"region": source.get_tile_texture_region(coords),
			}

	_cache[tile_set] = entries
	return entries
