extends CanvasLayer
class_name ConnectionOverlay
## Full-screen dimmed message shown while connecting, retrying or disconnected.
## Built in code so it doesn't need any changes to main.tscn.

var _label: Label


func _ready() -> void:
	layer = 100
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # Swallow clicks underneath.
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)
	_label.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 32)


func show_message(text: String) -> void:
	_label.text = text
	visible = true


func hide_message() -> void:
	visible = false
