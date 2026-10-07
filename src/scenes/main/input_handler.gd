extends Node
class_name InputHandler
## The single place pointer input is read. Main connects to its signals.
## Only input the UI didn't use gets here, so clicking a toolbar button never
## also moves the player.

signal primary_action(world_pos: Vector2)    # click / tap
signal secondary_action(world_pos: Vector2)  # right-click / long press

const LONG_PRESS_MS := 400
const TAP_SLOP_PX := 12.0

var _touch_start_pos := Vector2.ZERO
var _touch_start_ms := 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# "Emulate Mouse From Touch" (needed for UI buttons to work on touch
		# screens) also turns every tap into a mouse click. Taps are handled
		# below as touches, so skip the emulated clicks.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				primary_action.emit(_to_world(event.position))
			MOUSE_BUTTON_RIGHT:
				secondary_action.emit(_to_world(event.position))

	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touch_start_pos = event.position
			_touch_start_ms = Time.get_ticks_msec()
		elif event.position.distance_to(_touch_start_pos) <= TAP_SLOP_PX:
			var held := Time.get_ticks_msec() - _touch_start_ms
			if held >= LONG_PRESS_MS:
				secondary_action.emit(_to_world(event.position))
			else:
				primary_action.emit(_to_world(event.position))


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
