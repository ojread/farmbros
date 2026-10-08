extends CanvasLayer
class_name Hud
## Bottom toolbar (Move + one button per block) and the current area's name.
## Built in code so it needs no scene editing. Keys 1-9 pick a tool too.

const MOVE := &"move"
const BUILD := &"build"

## Virtual pixels. The game is 640 wide, so on a 390px-wide phone this is ~40px
## on screen, which is a comfortable touch target.
const BUTTON_SIZE := 64

## What a left-click / tap does: MOVE or BUILD.
var mode: StringName = MOVE
## The block to place while in BUILD mode.
var block_id: StringName = &""

var _group := ButtonGroup.new()
var _bar: HBoxContainer
var _area_label: Label
var _buttons: Array[Button] = []


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
	# Extra room at the bottom for phone browser toolbars and home indicators.
	#margin.add_theme_constant_override("margin_bottom", 32)
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

	# Start on Move.
	_buttons[0].set_pressed_no_signal(true)
	mode = MOVE
	block_id = &""


func set_area_name(text: String) -> void:
	_area_label.text = text


func _add_button(label: String, icon: Texture2D, tool_mode: StringName,
		id: StringName, tooltip: String) -> void:
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
			block_id = id)
	_bar.add_child(button)
	_buttons.append(button)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if index >= 0 and index < _buttons.size():
		_buttons[index].button_pressed = true
