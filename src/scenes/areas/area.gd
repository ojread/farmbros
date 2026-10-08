extends Node2D
class_name Area
## One travelable map: static ground, player-built blocks, portals, spawn
## points and the pathfinding grid.
##
## Scene layout (see farm.tscn / forest.tscn):
##   Area (this script)
##   ├─ Ground       TileMapLayer   hand-painted terrain; players can't change it
##   ├─ SpawnPoint   Marker2D       where players arrive by default
##   ├─ <others>     Marker2D       extra named arrival points (portals target these)
##   └─ Portals      Node2D
##      └─ ...       Portal         doorways to other areas
##
## A "Blocks" TileMapLayer for player-built tiles is created automatically on
## top of Ground.
##
## Pathfinding uses AStarGrid2D rather than a baked navigation mesh, because
## placing a block has to take effect immediately and baking is slow.

const NO_CELL := Vector2i(2147483647, 2147483647)

@export var area_id: StringName
@export var display_name := ""
## Animals the server spawns here at startup (needs Main.animal_scene).
@export var animal_count := 3
## How many fruit etc. the server keeps lying around here.
@export var collectable_count := 5

@onready var ground: TileMapLayer = $Ground

var blocks: TileMapLayer

var _astar := AStarGrid2D.new()
var _spawns := {}   # StringName -> Marker2D
var _portals := {}  # Vector2i -> Portal


func _ready() -> void:
	if display_name.is_empty():
		display_name = String(area_id).capitalize()

	# Movement is handled by the grid, so the tile layers need no physics or
	# navigation of their own.
	ground.collision_enabled = false
	ground.navigation_enabled = false

	blocks = TileMapLayer.new()
	blocks.name = "Blocks"
	blocks.tile_set = ground.tile_set
	blocks.collision_enabled = false
	blocks.navigation_enabled = false
	add_child(blocks)
	move_child(blocks, ground.get_index() + 1)

	_collect_spawns_and_portals()
	_build_grid()


# --- Coordinates -------------------------------------------------------------

func global_to_cell(global_pos: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(global_pos))


## Centre of the cell, in global pixels.
func cell_to_global(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))


func is_in_bounds(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell)


## The area covered by the ground tiles, in global pixels.
func get_bounds_global() -> Rect2:
	var rect := ground.get_used_rect()
	var tile_size := Vector2(ground.tile_set.tile_size)
	var top_left := ground.to_global(Vector2(rect.position) * tile_size)
	var bottom_right := ground.to_global(Vector2(rect.end) * tile_size)
	return Rect2(top_left, bottom_right - top_left)


# --- Spawns and portals ------------------------------------------------------

## Global position of the named spawn, snapped onto an open tile. Falls back to
## "SpawnPoint", then any spawn, then the middle of the area.
func get_spawn_global(spawn_name: StringName = &"") -> Vector2:
	var marker: Marker2D = _spawns.get(spawn_name)
	if marker == null:
		marker = _spawns.get(&"SpawnPoint")
	if marker == null and not _spawns.is_empty():
		marker = _spawns.values()[0]

	var wanted := get_bounds_global().get_center()
	if marker:
		wanted = marker.global_position

	var cell := _nearest_open_cell(global_to_cell(wanted))
	return cell_to_global(cell) if cell != NO_CELL else wanted


func get_portal_at(cell: Vector2i) -> Portal:
	return _portals.get(cell)


func _collect_spawns_and_portals() -> void:
	for child in get_children():
		if child is Marker2D and not child is Portal:
			_spawns[StringName(child.name)] = child

	var portals_root := get_node_or_null("Portals")
	if portals_root == null:
		return
	for child in portals_root.get_children():
		var portal := child as Portal
		if portal:
			_portals[global_to_cell(portal.global_position)] = portal


# --- Pathfinding -------------------------------------------------------------

## Path from one global position to another, as global waypoints. The first
## point is `from_global` itself. If the target is blocked, the path ends at
## the nearest open tile. Empty if there is no way to go.
func find_path(from_global_: Vector2, to_global_: Vector2) -> PackedVector2Array:
	var from_cell := _nearest_open_cell(global_to_cell(from_global_))
	var to_cell := _nearest_open_cell(global_to_cell(to_global_))
	if from_cell == NO_CELL or to_cell == NO_CELL:
		return PackedVector2Array()

	var ids := _astar.get_id_path(from_cell, to_cell, true)
	if ids.is_empty():
		return PackedVector2Array()

	var points := PackedVector2Array()
	points.append(from_global_)
	if ids.size() == 1:
		# Same tile: just step to its centre.
		points.append(cell_to_global(ids[0]))
	else:
		# Skip ids[0]; the entity is already there.
		for i in range(1, ids.size()):
			points.append(cell_to_global(ids[i]))
	return points


## A random open position near `near_global`, for spawning things.
func random_open_position(near_global: Vector2, min_dist: float, max_dist: float) -> Vector2:
	var wanted := near_global \
			+ Vector2.from_angle(randf() * TAU) * randf_range(min_dist, max_dist)
	var cell := _nearest_open_cell(global_to_cell(wanted))
	return cell_to_global(cell) if cell != NO_CELL else near_global


## A random open tile anywhere in the area, or Vector2.INF if none was found.
func random_open_position_anywhere() -> Vector2:
	var rect := _astar.region
	if rect.size == Vector2i.ZERO:
		return Vector2.INF
	for _attempt in 20:
		var cell := Vector2i(
				randi_range(rect.position.x, rect.end.x - 1),
				randi_range(rect.position.y, rect.end.y - 1))
		if not _astar.is_point_solid(cell):
			return cell_to_global(cell)
	return Vector2.INF


## The closest open cell to `cell` (itself if it is open), or NO_CELL.
func _nearest_open_cell(cell: Vector2i, max_radius := 3) -> Vector2i:
	var rect := _astar.region
	if rect.size == Vector2i.ZERO:
		return NO_CELL

	cell = cell.clamp(rect.position, rect.end - Vector2i.ONE)
	if not _astar.is_point_solid(cell):
		return cell

	var best := NO_CELL
	var best_dist := INF
	for dy in range(-max_radius, max_radius + 1):
		for dx in range(-max_radius, max_radius + 1):
			var candidate := cell + Vector2i(dx, dy)
			if not _astar.is_in_boundsv(candidate) or _astar.is_point_solid(candidate):
				continue
			var dist := float(dx * dx + dy * dy)
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best


func _build_grid() -> void:
	var rect := ground.get_used_rect()
	if rect.size == Vector2i.ZERO:
		push_error("Area '%s' has no ground tiles." % area_id)
		return

	_astar.region = rect
	_astar.cell_size = Vector2(ground.tile_set.tile_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	_rebuild_solids()


func _rebuild_solids() -> void:
	var rect := _astar.region
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			_astar.set_point_solid(cell, _is_cell_solid(cell))


func _refresh_cell(cell: Vector2i) -> void:
	if _astar.is_in_boundsv(cell):
		_astar.set_point_solid(cell, _is_cell_solid(cell))


func _is_cell_solid(cell: Vector2i) -> bool:
	return _is_tile_solid(ground.get_cell_tile_data(cell)) \
			or _is_tile_solid(blocks.get_cell_tile_data(cell))


## A tile blocks movement if its definition says so, or (for tiles that have no
## definition yet) if it carries a collision shape in the tile set.
func _is_tile_solid(data: TileData) -> bool:
	if data == null:
		return false
	if data.get_collision_polygons_count(0) > 0:
		return true
	var definition := TileDatabase.get_definition(StringName(data.get_custom_data("tile_id")))
	return definition != null and not definition.walkable


# --- Blocks ------------------------------------------------------------------

## The id of the player-built block at this cell, or &"".
func get_block(cell: Vector2i) -> StringName:
	var data := blocks.get_cell_tile_data(cell)
	if data == null:
		return &""
	return StringName(data.get_custom_data("tile_id"))


## Place a block, or remove it if block_id is &"". No validation; the server
## calls can_place_block() first.
func set_block(cell: Vector2i, block_id: StringName) -> void:
	if block_id == &"":
		blocks.erase_cell(cell)
	else:
		var entry := BlockCatalog.get_entry(blocks.tile_set, block_id)
		if entry.is_empty():
			push_warning("Unknown block '%s'" % block_id)
			return
		blocks.set_cell(cell, entry.source, entry.coords)
	_refresh_cell(cell)


## Terrain-level rules. (The server also checks reach and who is standing there.)
func can_place_block(cell: Vector2i, block_id: StringName) -> bool:
	if not block_id in BlockCatalog.PLACEABLE:
		return false
	if BlockCatalog.get_entry(blocks.tile_set, block_id).is_empty():
		return false
	if not _astar.is_in_boundsv(cell):
		return false
	if get_block(cell) != &"":
		return false
	if _is_tile_solid(ground.get_cell_tile_data(cell)):
		return false
	if _portals.has(cell):
		return false
	for spawn_name in _spawns:
		if global_to_cell(get_spawn_global(spawn_name)) == cell:
			return false
	return true


## Every player-built block as [x, y, id] triples (RPC- and JSON-friendly).
func get_block_entries() -> Array:
	var entries := []
	for cell in blocks.get_used_cells():
		entries.append([cell.x, cell.y, String(get_block(cell))])
	return entries


## Replace all player-built blocks with these entries.
func load_blocks(entries: Array) -> void:
	blocks.clear()
	_rebuild_solids()
	for entry in entries:
		if entry is Array and entry.size() == 3:
			set_block(Vector2i(int(entry[0]), int(entry[1])), StringName(str(entry[2])))
