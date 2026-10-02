extends Node
class_name WorldNavigation

@export var ground: TileMapLayer

var astar := AStarGrid2D.new()
var map_rect := Rect2i()


func _ready() -> void:
	if ground == null:
		push_error("WorldNavigation: Ground TileMapLayer is not assigned.")
		return

	_build_grid()


func _build_grid() -> void:
	map_rect = ground.get_used_rect()

	astar.region = map_rect
	astar.cell_size = ground.tile_set.tile_size
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE

	astar.update()

	for y in range(map_rect.position.y, map_rect.end.y):
		for x in range(map_rect.position.x, map_rect.end.x):
			var tile := Vector2i(x, y)

			if not _is_walkable(tile):
				astar.set_point_solid(tile, true)


func _is_walkable(tile: Vector2i) -> bool:
	var tile_data := ground.get_cell_tile_data(tile)

	if tile_data == null:
		return false

	var tile_id = tile_data.get_custom_data("tile_id")
	
	var tile_definition := TileDatabase.get_definition(tile_id)

	if tile_definition == null:
		return false

	return tile_definition.walkable


func find_path(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var from_cell := ground.local_to_map(
		ground.to_local(from_world)
	)

	var to_cell := ground.local_to_map(
		ground.to_local(to_world)
	)

	if not astar.is_in_boundsv(from_cell):
		return []

	if not astar.is_in_boundsv(to_cell):
		return []

	if astar.is_point_solid(from_cell):
		return []

	if astar.is_point_solid(to_cell):
		return []

	var cell_path := astar.get_id_path(from_cell, to_cell)

	var world_path: Array[Vector2] = []

	for cell in cell_path:
		var local_position := ground.map_to_local(cell)
		var world_position := ground.to_global(local_position)

		world_path.append(world_position)

	return world_path
