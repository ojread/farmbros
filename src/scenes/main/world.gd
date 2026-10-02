extends Node2D
class_name World

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
