class_name ItemDefinition
extends Resource
## One kind of item players can carry. Add new items as .tres files and list
## them in ItemDatabase.

const SHEET := preload("res://common/images/colored-transparent_packed.png")
const DOT_SIZE := 16

@export var id: StringName
@export var display_name := ""

@export_category("Appearance")
## Used for the placeholder dot while no icon_region is set.
@export var color := Color.WHITE
## Rectangle of the tile sheet to draw (16x16 tiles, so e.g. Rect2(16 * x, 16 * y, 16, 16)).
## Leave empty to draw a coloured dot instead.
@export var icon_region := Rect2()

@export_category("Animals")
## Seconds an animal follows the player after eating this. 0 = can't be fed.
@export var follow_seconds := 0.0

@export_category("Collecting")
## Whether the server scatters this item around the map.
@export var collectable := true
## Relative chance of being picked when something spawns.
@export var spawn_weight := 1.0

var _icon: Texture2D


func get_icon() -> Texture2D:
	if _icon == null:
		_icon = _make_icon()
	return _icon


func _make_icon() -> Texture2D:
	if icon_region.has_area():
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEET
		atlas.region = icon_region
		return atlas

	var image := Image.create(DOT_SIZE, DOT_SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(DOT_SIZE, DOT_SIZE) / 2.0 - Vector2(0.5, 0.5)
	for y in DOT_SIZE:
		for x in DOT_SIZE:
			var dist := Vector2(x, y).distance_to(centre)
			if dist <= 6.5:
				image.set_pixel(x, y, color.darkened(0.45) if dist > 5.0 else color)
	return ImageTexture.create_from_image(image)
