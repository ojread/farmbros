extends CanvasLayer
class_name Hud
## Bottom toolbar and the current area's name. Built in code so it needs no
## scene editing. From the left: Move, one button per placeable block, Erase,
## then one button per kind of item you're carrying (pick one, then tap an
## animal to feed it). Keys 1-9 pick a tool too.

const MOVE := &"move"
const BUILD := &"build"
const REMOVE := &"remove"
const FEED := &"feed"

## Virtual pixels. The game is 640 wide, so on a 390px-wide phone this is ~40px
## on screen, which is a comfortable touch target.
const BUTTON_SIZE := 64

## What a left-click / tap does: MOVE, BUILD, REMOVE or FEED.
var mode: StringName = MOVE
## The block to place while in BUILD mode.
var block_id: StringName = &""
## The item to feed while in FEED mode.
var item_id: StringName = &""

var _group := ButtonGroup.new()
var _bar: HBoxContainer
var _area_label: Label
var _buttons: Array[Button] = []
var _static_button_count := 0   # Move + blocks + Erase; the rest are item buttons
var _item_separator: VSeparator


func _ready() -> void:
	layer = 50

	# Laid out with containers (not anchor presets) so it re-flows whenever the
	# window changes size, e.g. rotating a phone. Everything except the toolbar
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

	# PanelContainer swallows clicks, so tapping the bar never moves the player.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 6)
	panel.add_child(_bar)


## entries: [{id: StringName, icon: Texture2D}] from World.get_palette().
func set_palette(entries: Array[Dictionary]) -> void:
	for button in _buttons:
		button.queue_free()
	_buttons.clear()

	_add_button("Move", null, MOVE, &"", "Move (1)")
	for entry in entries:
		var id: StringName = entry.id
		_add_button("", entry.icon, BUILD, id,
				"Place %s (%d)" % [String(id).capitalize(), _buttons.size() + 1])
	_add_button("", _make_erase_icon(), REMOVE, &"",
			"Remove blocks (%d). Right-click or long-press also removes." % (_buttons.size() + 1))
	_static_button_count = _buttons.size()

	# Start on Move.
	_buttons[0].set_pressed_no_signal(true)
	mode = MOVE
	block_id = &""
	item_id = &""


## items: item id (String) -> count, from Inventory.local_items. Rebuilds the
## item buttons, keeping the current selection if that item is still held.
func set_items(items: Dictionary) -> void:
	if _static_button_count == 0:
		return  # set_palette() hasn't run yet

	var selected := item_id if mode == FEED else &""

	while _buttons.size() > _static_button_count:
		_remove_button(_buttons.pop_back())
	if _item_separator:
		_bar.remove_child(_item_separator)
		_item_separator.queue_free()
		_item_separator = null

	var ids := items.keys()
	ids.sort()
	var selected_button: Button = null
	for key in ids:
		var id := StringName(key)
		var definition := ItemDatabase.get_definition(id)
		if definition == null:
			continue
		if _item_separator == null:
			_item_separator = VSeparator.new()
			_bar.add_child(_item_separator)
		var button := _add_button("x%d" % int(items[key]), definition.get_icon(), FEED, id,
				"Feed %s (%d)" % [definition.display_name, _buttons.size() + 1])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		if id == selected:
			selected_button = button

	if selected_button:
		selected_button.set_pressed_no_signal(true)
	elif selected != &"":
		# Ran out of what we were holding.
		_buttons[0].button_pressed = true


func _remove_button(button: Button) -> void:
	_bar.remove_child(button)
	button.queue_free()


func set_area_name(text: String) -> void:
	_area_label.text = text


func _add_button(label: String, icon: Texture2D, tool_mode: StringName,
		id: StringName, tooltip: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.text = label
	button.icon = icon
	button.expand_icon = icon != null
	button.tooltip_text = tooltip
	button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			mode = tool_mode
			block_id = id if tool_mode == BUILD else &""
			item_id = id if tool_mode == FEED else &"")
	_bar.add_child(button)
	_buttons.append(button)
	return button


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
	var index := key.keycode - KEY_1
	if index >= 0 and index < _buttons.size():
		_buttons[index].button_pressed = true
