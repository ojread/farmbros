extends CanvasLayer
class_name Hud
## Bottom toolbar (Move + one button per block) and the current area's name.
## Built in code so it needs no scene editing. Keys 1-9 pick a tool too.

const MOVE := &"move"
const BUILD := &"build"

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

	_area_label = Label.new()
	_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_label.add_theme_font_size_override("font_size", 20)
	_area_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_area_label.add_theme_constant_override("outline_size", 6)
	add_child(_area_label)
	_area_label.set_anchors_and_offsets_preset(
			Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)

	# PanelContainer swallows clicks, so tapping the bar never moves the player.
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = -8
	panel.offset_bottom = -8

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
	button.custom_minimum_size = Vector2(48, 48)
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
