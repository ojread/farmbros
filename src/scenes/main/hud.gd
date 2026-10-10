extends CanvasLayer
class_name Hud
## Modal toolbar, built in code so it needs no scene editing.
##
## The bottom row picks a MODE (what you're doing). Moving and interacting is
## the default and shows nothing else. Other modes open a second row just above
## it with only that mode's tools:
##
##   Move   click a tile to walk there; click a door to open/close it
##   Build  pick a block to place, or the red X to remove blocks
##   Items  pick something you're carrying, then tap an animal to feed it
##
## To add an activity (fishing, tools...): add an entry to MODES, a constant,
## and a case for it in _rebuild_tools(). Main reads `mode` and the selected
## tool (`block_id` / `item_id`) to decide what a click does.
##
## Keys: Esc = Move, B = Build, F = Items (pressing a mode's key again goes back
## to Move), 1-9 = pick a tool in the current mode.

const MOVE := &"move"
const BUILD := &"build"
const FEED := &"feed"

## Modes in toolbar order.
const MODES := [
	{"id": MOVE, "label": "Move", "key": KEY_ESCAPE, "tip": "Move and interact (Esc)"},
	{"id": BUILD, "label": "Build", "key": KEY_B, "tip": "Build (B)"},
	{"id": FEED, "label": "Items", "key": KEY_F, "tip": "Items (F)"},
]

## Virtual pixels. The game is 640 wide, so on a 390px-wide phone this is ~40px
## on screen, which is a comfortable touch target.
const BUTTON_SIZE := 64

## What a click / tap does: MOVE, BUILD or FEED.
var mode: StringName = MOVE
## In BUILD mode: the block to place. &"" means "remove blocks".
var block_id: StringName = &""
## In FEED mode: the item to feed.
var item_id: StringName = &""

var _palette: Array[Dictionary] = []
var _items := {}
var _last_block: StringName = &""   # remembered between visits to Build mode

var _mode_buttons := {}             # mode id -> Button
var _tool_buttons: Array[Button] = []
var _tool_group: ButtonGroup

var _area_label: Label
var _tool_panel: PanelContainer
var _tool_row: HBoxContainer


func _ready() -> void:
	layer = 50

	# Laid out with containers (not anchor presets) so it re-flows whenever the
	# window changes size, e.g. rotating a phone. Everything except the panels
	# ignores the mouse, so clicks elsewhere still reach the world.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	# No extra room at the bottom; if some phones hide the bar behind their
	# browser toolbar, raise this.
	margin.add_theme_constant_override("margin_bottom", 0)
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	_area_label = Label.new()
	_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_label.add_theme_font_size_override("font_size", 20)
	_area_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_area_label.add_theme_constant_override("outline_size", 6)
	column.add_child(_area_label)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	# PanelContainers swallow clicks, so tapping a bar never moves the player.
	# Tools for the current mode (hidden when there are none, e.g. in Move).
	_tool_panel = PanelContainer.new()
	_tool_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tool_panel.visible = false
	column.add_child(_tool_panel)
	_tool_row = HBoxContainer.new()
	_tool_row.add_theme_constant_override("separation", 6)
	_tool_panel.add_child(_tool_row)

	# The mode switcher.
	var mode_panel := PanelContainer.new()
	mode_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(mode_panel)
	var mode_bar := HBoxContainer.new()
	mode_bar.add_theme_constant_override("separation", 6)
	mode_panel.add_child(mode_bar)

	var mode_group := ButtonGroup.new()
	for def: Dictionary in MODES:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = mode_group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.text = def.label
		button.tooltip_text = def.tip
		button.toggled.connect(_on_mode_toggled.bind(def.id))
		mode_bar.add_child(button)
		_mode_buttons[def.id] = button

	_mode_buttons[MOVE].set_pressed_no_signal(true)
	# Nothing to feed with until something is picked up.
	_mode_buttons[FEED].disabled = true


## entries: [{id: StringName, icon: Texture2D}] from World.get_palette().
func set_palette(entries: Array[Dictionary]) -> void:
	_palette = entries
	_last_block = entries[0].id if not entries.is_empty() else &""
	if mode == BUILD:
		_rebuild_tools()


## items: item id (String) -> count, from Inventory.local_items.
func set_items(items: Dictionary) -> void:
	_items = items
	if items.is_empty() and mode == FEED:
		# Ran out of everything; go back to Move (this rebuilds the tool row).
		_mode_buttons[MOVE].button_pressed = true
	elif mode == FEED:
		_rebuild_tools()
	_mode_buttons[FEED].disabled = items.is_empty()


func set_area_name(text: String) -> void:
	_area_label.text = text


# --- Modes -------------------------------------------------------------------

func _on_mode_toggled(pressed: bool, id: StringName) -> void:
	if not pressed:
		return
	mode = id
	_rebuild_tools()


## Fill the tool row for the current mode.
func _rebuild_tools() -> void:
	for child in _tool_row.get_children():
		_tool_row.remove_child(child)
		child.queue_free()
	_tool_buttons.clear()
	_tool_group = ButtonGroup.new()

	match mode:
		BUILD:
			for entry in _palette:
				var id: StringName = entry.id
				_add_tool("", entry.icon, id,
						"Place %s (%d)" % [String(id).capitalize(), _tool_buttons.size() + 1],
						id == _last_block)
			_tool_row.add_child(VSeparator.new())
			_add_tool("", _make_erase_icon(), &"",
					"Remove blocks (%d). Right-click or long-press also removes." % (_tool_buttons.size() + 1),
					_last_block == &"")
		FEED:
			var ids := _items.keys()
			ids.sort()
			for key in ids:
				var id := StringName(key)
				var definition := ItemDatabase.get_definition(id)
				if definition == null:
					continue
				var button := _add_tool("x%d" % int(_items[key]), definition.get_icon(), id,
						"Feed %s (%d)" % [definition.display_name, _tool_buttons.size() + 1],
						id == item_id)
				button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP

	_tool_panel.visible = not _tool_buttons.is_empty()

	# Always have something selected.
	if not _tool_buttons.is_empty() \
			and not _tool_buttons.any(func(b: Button) -> bool: return b.button_pressed):
		_tool_buttons[0].button_pressed = true


func _add_tool(label: String, icon: Texture2D, id: StringName, tooltip: String,
		selected: bool) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _tool_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.text = label
	button.icon = icon
	button.expand_icon = icon != null
	button.tooltip_text = tooltip
	button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_apply_tool(id))
	_tool_row.add_child(button)
	_tool_buttons.append(button)
	if selected:
		button.set_pressed_no_signal(true)
		_apply_tool(id)
	return button


func _apply_tool(id: StringName) -> void:
	match mode:
		BUILD:
			block_id = id
			_last_block = id
		FEED:
			item_id = id


## A red X, drawn in code so no image asset is needed.
func _make_erase_icon() -> Texture2D:
	const SIZE := 16
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var red := Color(0.9, 0.2, 0.2)
	for i in range(2, SIZE - 2):
		for t in 2:
			image.set_pixel(i, clampi(i + t, 0, SIZE - 1), red)
			image.set_pixel(SIZE - 1 - i, clampi(i + t, 0, SIZE - 1), red)
	return ImageTexture.create_from_image(image)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	for def: Dictionary in MODES:
		if key.keycode != def.key:
			continue
		var button: Button = _mode_buttons[def.id]
		if button.disabled:
			return
		# The same key twice returns to Move.
		var target: Button = _mode_buttons[MOVE] if mode == def.id else button
		target.button_pressed = true
		return

	var index := key.keycode - KEY_1
	if index >= 0 and index < _tool_buttons.size():
		_tool_buttons[index].button_pressed = true
