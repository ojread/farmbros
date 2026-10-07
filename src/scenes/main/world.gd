extends Node2D
class_name World

@onready var _ground: TileMapLayer = $Ground


func find_path(
	from_world: Vector2,
	to_world: Vector2
) -> PackedVector2Array:
	if not is_inside_tree():
		return PackedVector2Array()

	var navigation_map := get_world_2d().get_navigation_map()

	return NavigationServer2D.map_get_path(
		navigation_map,
		from_world,
		to_world,
		true
	)


## The area covered by the ground tiles, in global pixels (so it accounts for
## the World's 4x scale). Used for camera limits.
func get_world_bounds() -> Rect2:
	var cells := _ground.get_used_rect()
	var tile_size := Vector2(_ground.tile_set.tile_size)
	var top_left := _ground.to_global(Vector2(cells.position) * tile_size)
	var bottom_right := _ground.to_global(Vector2(cells.end) * tile_size)
	return Rect2(top_left, bottom_right - top_left)
