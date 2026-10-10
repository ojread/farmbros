extends Node2D
class_name World
## Everything that spans areas.
##
## Every peer loads every area (they're small), laid out side by side so they
## never overlap. What differs per player is which *entities* they can see:
## the server only replicates a player or animal to peers standing in the same
## area as it. Blocks are different: they're sent to everyone, so every client
## always has an up-to-date copy of every area.
##
## The server owns all state. Clients send requests (move, place, remove) and
## the server checks them.

const SAVE_PATH := "user://world.json"
const SAVE_VERSION := 1
const AUTOSAVE_DELAY_SEC := 2.0

## World-space distance between area origins. Anything bigger than an area works.
const AREA_SPACING := 1024.0

## How far (in tiles) from a player they can place or remove blocks.
const BUILD_REACH_TILES := 5.0
## How far (in tiles) from a player they can open or close a door.
const INTERACT_REACH_TILES := 2.0
const MIN_EDIT_INTERVAL_MS := 50

## Walking this close (global pixels; a tile is 64) to an item picks it up.
const PICKUP_RADIUS := 56.0
## How far (in tiles) from a player they can feed an animal.
const FEED_REACH_TILES := 4.0
## A feed click must land within this many global pixels of the animal.
const FEED_CLICK_RADIUS := 96.0

## Scenes to load as areas, left to right. Add new areas here.
@export var area_scenes: Array[PackedScene] = []
## Where new players appear.
@export var start_area_id: StringName = &"farm"

@onready var entities: Node2D = $Entities
@onready var players: Node2D = $Entities/Players
@onready var animals: Node2D = $Entities/Animals

## Items lying around. Created in code (see _ready), next to Players/Animals.
var collectables: Node2D
var collectable_spawner: MultiplayerSpawner
var inventory: Inventory

var _areas := {}  # StringName -> Area, in load order

# Server only.
var _last_edit_ms := {}  # peer id -> ticks
var _persistence_enabled := false
var _save_dirty := false
var _save_timer: Timer


func _ready() -> void:
	_load_areas()
	_create_collectables_and_inventory()
	multiplayer.peer_disconnected.connect(forget_peer)


func _load_areas() -> void:
	for index in area_scenes.size():
		var area := area_scenes[index].instantiate() as Area
		if area == null:
			push_error("area_scenes[%d] is not an Area scene." % index)
			continue
		if _areas.has(area.area_id):
			push_error("Duplicate area id '%s'." % area.area_id)
			area.free()
			continue

		area.position = Vector2(AREA_SPACING * index, 0.0)
		add_child(area)
		# Draw areas underneath the Entities node.
		move_child(area, index)
		_areas[area.area_id] = area


# Built in code so main.tscn doesn't need to change. Every peer runs this, so
# the node paths match for replication and RPCs.
func _create_collectables_and_inventory() -> void:
	collectables = Node2D.new()
	collectables.name = "Collectables"
	entities.add_child(collectables)

	collectable_spawner = MultiplayerSpawner.new()
	collectable_spawner.name = "MultiplayerSpawner"
	collectable_spawner.spawn_path = NodePath("..")
	collectables.add_child(collectable_spawner)

	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _persistence_enabled and _save_dirty:
		save_world()


# --- Areas -------------------------------------------------------------------

func get_areas() -> Array:
	return _areas.values()


func get_area(area_id: StringName) -> Area:
	return _areas.get(area_id)


func get_start_area() -> Area:
	var area := get_area(start_area_id)
	if area == null and not _areas.is_empty():
		area = _areas.values()[0]
	return area


## Which area contains this global position, or null.
func area_at(global_pos: Vector2) -> Area:
	for area: Area in _areas.values():
		if area.get_bounds_global().has_point(global_pos):
			return area
	return null


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var area := area_at(from_world)
	if area == null:
		return PackedVector2Array()
	return area.find_path(from_world, to_world)


# --- Who is where ------------------------------------------------------------

func get_local_player() -> Node2D:
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Node2D


func get_local_area() -> Area:
	var player := get_local_player()
	return area_at(player.global_position) if player else null


## The area a connected peer's player is standing in, or null.
func get_peer_area(peer_id: int) -> Area:
	var player := players.get_node_or_null(str(peer_id)) as Node2D
	return area_at(player.global_position) if player else null


## Server only. Peers who currently have this entity spawned.
func get_peers_seeing(entity: Node2D) -> Array[int]:
	var result: Array[int] = []
	var area := area_at(entity.global_position)
	if area == null:
		return result
	for peer_id in multiplayer.get_peers():
		if get_peer_area(peer_id) == area:
			result.append(peer_id)
	return result


func forget_peer(peer_id: int) -> void:
	_last_edit_ms.erase(peer_id)
	inventory.forget(peer_id)


# --- Replication visibility (server) ------------------------------------------

## Call whenever something changes area, or a player joins. Players and animals
## are replicated only to peers standing in the same area.
func refresh_visibility() -> void:
	if not multiplayer.is_server():
		return

	var peers := multiplayer.get_peers()
	var peer_areas := {}
	for peer_id in peers:
		peer_areas[peer_id] = get_peer_area(peer_id)

	for container: Node in [players, animals, collectables]:
		for child in container.get_children():
			var entity := child as Node2D
			var sync := _synchronizer_of(child)
			if entity == null or sync == null:
				continue
			var area := area_at(entity.global_position)
			for peer_id in peers:
				sync.set_visibility_for(peer_id, area != null and peer_areas[peer_id] == area)


func _synchronizer_of(node: Node) -> MultiplayerSynchronizer:
	for child in node.get_children():
		if child is MultiplayerSynchronizer:
			return child
	return null


# --- Travel (server) ------------------------------------------------------------

## Called when a player finishes walking. If they're standing on a portal, send
## them through it.
func use_portal_at(entity: Node2D) -> void:
	var area := area_at(entity.global_position)
	if area == null:
		return
	var portal := area.get_portal_at(area.global_to_cell(entity.global_position))
	if portal:
		travel(entity, portal.target_area, portal.target_spawn)


func travel(entity: Node2D, target_area_id: StringName, spawn_name: StringName = &"") -> bool:
	if not multiplayer.is_server():
		return false

	var target := get_area(target_area_id)
	if target == null:
		push_warning("Portal leads to unknown area '%s'." % target_area_id)
		return false

	# Cancel the walk while peers can still see the entity.
	var walker := entity.get_node_or_null("PathWalker") as PathWalker
	if walker:
		walker.stop()

	entity.global_position = target.get_spawn_global(spawn_name)
	refresh_visibility()

	# Players are visible to themselves before and after, so their client never
	# respawns the node; tell it where it is now.
	var player := entity as Player
	if player:
		player.notify_teleported()
	return true


# --- Blocks ------------------------------------------------------------------

## Client -> server: place a block, or remove one if block_id is "".
@rpc("any_peer", "call_remote", "reliable")
func request_set_block(cell: Vector2i, block_id: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer_id)) as Node2D
	if player == null:
		return

	if not _edit_allowed(peer_id):
		return

	var area := area_at(player.global_position)
	if area == null:
		return

	# Only near the player.
	var player_cell := area.global_to_cell(player.global_position)
	if Vector2(cell - player_cell).length() > BUILD_REACH_TILES:
		return

	var id := StringName(block_id)
	if id == &"":
		if area.get_block(cell) == &"":
			return
	else:
		if not area.can_place_block(cell, id) or _is_cell_occupied(area, cell):
			return

	_set_block(area, cell, id)


## Client -> server: open or close the door at this cell. Only players can do
## this; animals have no way to ask.
@rpc("any_peer", "call_remote", "reliable")
func request_toggle_door(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer_id)) as Node2D
	if player == null or not _edit_allowed(peer_id):
		return

	var area := area_at(player.global_position)
	if area == null or not is_in_interact_reach(area, player.global_position, cell):
		return

	var next := BlockCatalog.toggled_door(area.get_block(cell))
	if next == &"":
		return  # Not a door.

	# Closing a door on someone would trap them inside a solid tile.
	if next == BlockCatalog.DOOR_CLOSED and _is_cell_occupied(area, cell):
		return

	_set_block(area, cell, next)


## Whether a position is close enough to a cell of `area` to interact with it.
## (Used by the server to decide, and by the client to choose between
## "interact" and "walk there".)
func is_in_interact_reach(area: Area, from_global_: Vector2, cell: Vector2i) -> bool:
	var tiles := area.global_to_cell(from_global_) - cell
	return Vector2(tiles).length() <= INTERACT_REACH_TILES


## Rate limit shared by everything a player can ask the server to change.
func _edit_allowed(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_edit_ms.get(peer_id, 0)) < MIN_EDIT_INTERVAL_MS:
		return false
	_last_edit_ms[peer_id] = now
	return true


func _set_block(area: Area, cell: Vector2i, id: StringName) -> void:
	area.set_block(cell, id)
	_apply_block.rpc(String(area.area_id), cell, String(id))
	# Anyone mid-walk might now be heading through a wall.
	_repath_walkers(area)
	_mark_dirty()


## Server -> clients: one block changed.
@rpc("authority", "call_remote", "reliable")
func _apply_block(area_id: String, cell: Vector2i, block_id: String) -> void:
	var area := get_area(StringName(area_id))
	if area:
		area.set_block(cell, StringName(block_id))


## Server -> one client: every block in every area. Sent when they join.
func send_snapshot_to(peer_id: int) -> void:
	_receive_snapshot.rpc_id(peer_id, get_block_snapshot())


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	for area: Area in _areas.values():
		area.load_blocks(snapshot.get(String(area.area_id), []))


func get_block_snapshot() -> Dictionary:
	var snapshot := {}
	for area: Area in _areas.values():
		snapshot[String(area.area_id)] = area.get_block_entries()
	return snapshot


func _is_cell_occupied(area: Area, cell: Vector2i) -> bool:
	for container: Node in [players, animals, collectables]:
		for child in container.get_children():
			var entity := child as Node2D
			if entity == null:
				continue
			if area_at(entity.global_position) == area \
					and area.global_to_cell(entity.global_position) == cell:
				return true
	return false


func _repath_walkers(area: Area) -> void:
	for container: Node in [players, animals]:
		for child in container.get_children():
			var entity := child as Node2D
			var walker := child.get_node_or_null("PathWalker") as PathWalker
			if entity and walker and walker.is_walking() \
					and area_at(entity.global_position) == area:
				walker.repath()


# --- Collecting and feeding (server) ------------------------------------------

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for child in players.get_children():
		var player := child as Node2D
		if player:
			_collect_near(player, int(player.name))


func _collect_near(player: Node2D, peer_id: int) -> void:
	for child in collectables.get_children():
		var item := child as Collectable
		if item == null or item.is_queued_for_deletion():
			continue
		if player.global_position.distance_to(item.global_position) > PICKUP_RADIUS:
			continue
		# Leaves it on the ground if the stack is full.
		if inventory.add(peer_id, item.item_id, 1) > 0:
			item.queue_free()


## Client -> server: feed the animal nearest to this click.
@rpc("any_peer", "call_remote", "reliable")
func request_feed(world_pos: Vector2, item_id: String) -> void:
	if not multiplayer.is_server() or not world_pos.is_finite():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var player := players.get_node_or_null(str(peer_id)) as Node2D
	if player == null or not _edit_allowed(peer_id):
		return

	var id := StringName(item_id)
	var definition := ItemDatabase.get_definition(id)
	if definition == null or definition.follow_seconds <= 0.0:
		return
	if inventory.count(peer_id, id) < 1:
		return

	var animal := nearest_animal(world_pos, FEED_CLICK_RADIUS)
	if animal == null or not is_in_feed_reach(player.global_position, animal.global_position):
		return

	# Only spend the item once we know the feeding will happen.
	if inventory.remove(peer_id, id, 1):
		animal.feed(player, definition.follow_seconds)


## The animal closest to `global_pos`, within `max_dist`, or null. (Used by the
## server to decide, and by the client to decide whether a tap means "feed".)
func nearest_animal(global_pos: Vector2, max_dist: float) -> Animal:
	var best: Animal = null
	var best_dist := max_dist
	for child in animals.get_children():
		var animal := child as Animal
		if animal == null or animal.is_queued_for_deletion():
			continue
		var dist := animal.global_position.distance_to(global_pos)
		if dist <= best_dist:
			best_dist = dist
			best = animal
	return best


func is_in_feed_reach(from_global_: Vector2, to_global_: Vector2) -> bool:
	var area := area_at(from_global_)
	if area == null or area_at(to_global_) != area:
		return false
	var tiles := area.global_to_cell(from_global_) - area.global_to_cell(to_global_)
	return Vector2(tiles).length() <= FEED_REACH_TILES


## Client helper for the HUD: [{id, icon}] for each placeable block.
func get_palette() -> Array[Dictionary]:
	var palette: Array[Dictionary] = []
	if _areas.is_empty():
		return palette

	var tile_set := (_areas.values()[0] as Area).ground.tile_set
	for id in BlockCatalog.PLACEABLE:
		var entry := BlockCatalog.get_entry(tile_set, id)
		if entry.is_empty():
			continue
		var icon := AtlasTexture.new()
		icon.atlas = entry.texture
		icon.region = Rect2(entry.region)
		palette.append({"id": id, "icon": icon})
	return palette


# --- Persistence (server) ------------------------------------------------------

## Load the saved world and start saving changes. Call once on the server.
func enable_persistence() -> void:
	_persistence_enabled = true

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = AUTOSAVE_DELAY_SEC
	_save_timer.timeout.connect(save_world)
	add_child(_save_timer)

	load_world()


func _mark_dirty() -> void:
	_save_dirty = true
	if _persistence_enabled and _save_timer.is_stopped():
		_save_timer.start()


func save_world() -> void:
	if not _persistence_enabled:
		return

	var data := {
		"version": SAVE_VERSION,
		"areas": get_block_snapshot(),
	}

	# Write beside the real file, then swap, so a crash mid-write can't leave a
	# half-written save.
	var temp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [temp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data))
	file.close()

	var error := DirAccess.rename_absolute(temp_path, SAVE_PATH)
	if error != OK:
		push_error("Could not replace %s: %s" % [SAVE_PATH, error_string(error)])
		return

	_save_dirty = false
	print("World saved to ", ProjectSettings.globalize_path(SAVE_PATH))


func load_world() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No saved world; starting fresh.")
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary or not parsed.get("areas") is Dictionary:
		# Keep the bad file for inspection rather than overwriting it.
		var bad_path := SAVE_PATH + ".bad"
		push_error("Saved world is unreadable; moved to %s." % bad_path)
		DirAccess.rename_absolute(SAVE_PATH, bad_path)
		return

	var saved_areas: Dictionary = parsed["areas"]
	for area: Area in _areas.values():
		area.load_blocks(saved_areas.get(String(area.area_id), []))
	print("World loaded from ", ProjectSettings.globalize_path(SAVE_PATH))
