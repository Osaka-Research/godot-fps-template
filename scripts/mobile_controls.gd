extends Control

const JOY_RADIUS := 90.0
const BTN_RADIUS := 60.0

var player: Node = null

var joystick_index := -1
var joystick_origin := Vector2.ZERO
var joystick_current := Vector2.ZERO
var look_index := -1

func _ready() -> void:
	player = owner
	visible = DisplayServer.is_touchscreen_available()
	set_process_input(visible)

func _button_positions() -> Dictionary:
	var size := get_viewport_rect().size
	var shoot := size - Vector2(140.0, 140.0)
	return {
		"shoot": shoot,
		"jump": shoot + Vector2(0.0, -150.0),
		"place": shoot + Vector2(-150.0, -30.0),
		"new": shoot + Vector2(-150.0, -190.0),
	}

func _input(event: InputEvent) -> void:
	if not player:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			var btns := _button_positions()
			for btn_name in btns:
				if event.position.distance_to(btns[btn_name]) <= BTN_RADIUS:
					_fire_button(btn_name)
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
			var half_w := get_viewport_rect().size.x * 0.5
			if event.position.x < half_w and joystick_index == -1:
				joystick_index = event.index
				joystick_origin = event.position
				joystick_current = event.position
			elif event.position.x >= half_w and look_index == -1:
				look_index = event.index
			get_viewport().set_input_as_handled()
		else:
			if event.index == joystick_index:
				joystick_index = -1
				player.touch_move_dir = Vector2.ZERO
			if event.index == look_index:
				look_index = -1
		queue_redraw()

	elif event is InputEventScreenDrag:
		if event.index == joystick_index:
			joystick_current = event.position
			var delta := joystick_current - joystick_origin
			if delta.length() > JOY_RADIUS:
				delta = delta.normalized() * JOY_RADIUS
				joystick_current = joystick_origin + delta
			player.touch_move_dir = delta / JOY_RADIUS
			queue_redraw()
		elif event.index == look_index:
			player.look_delta += event.relative

func _fire_button(btn_name: String) -> void:
	match btn_name:
		"jump":
			player.jump_requested = true
		"shoot":
			player.shoot()
		"place":
			player.place_block()
		"new":
			player.block_editor.toggle()

func _draw() -> void:
	if not visible:
		return
	if joystick_index != -1:
		draw_circle(joystick_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_circle(joystick_current, 34.0, Color(1, 1, 1, 0.35))

	var font := ThemeDB.fallback_font
	var fsize := 14
	for btn_name in _button_positions():
		var pos: Vector2 = _button_positions()[btn_name]
		draw_circle(pos, BTN_RADIUS, Color(1, 1, 1, 0.18))
		var label: String = String(btn_name).to_upper()
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, pos - text_size * 0.5 + Vector2(0, fsize * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color(1, 1, 1, 0.9))
