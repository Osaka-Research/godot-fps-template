extends VehicleBody3D

@export var engine_force_value := 300.0
@export var max_steer := 0.5
@export var brake_force := 4.0

var driver_id := -1

const WHEEL_LOCAL := {
	"front_left": Vector3(0.3, 0.4, 0.66),
	"front_right": Vector3(-0.3, 0.4, 0.66),
	"back_left": Vector3(0.3, 0.4, -0.66),
	"back_right": Vector3(-0.3, 0.4, -0.66),
}
const FRONT := ["front_left", "front_right"]

func _ready() -> void:
	add_to_group("vehicle")

	var model := preload("res://assets/models/car.glb").instantiate()
	add_child(model)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.15, 2.55)
	shape.shape = box
	shape.position = Vector3(0.0, 0.725, -0.025)
	add_child(shape)

	for key in WHEEL_LOCAL:
		var pos: Vector3 = WHEEL_LOCAL[key]
		var wheel := VehicleWheel3D.new()
		wheel.name = key
		wheel.position = pos
		wheel.wheel_radius = 0.3
		wheel.wheel_rest_length = 0.12
		wheel.use_as_traction = true
		wheel.use_as_steering = FRONT.has(key)
		add_child(wheel)

	if not multiplayer.is_server():
		freeze = true

@rpc("any_peer", "call_local", "reliable")
func request_enter(player_id: int) -> void:
	if not multiplayer.is_server() or driver_id != -1:
		return
	driver_id = player_id
	_driver_changed.rpc(driver_id)
	var player := Net.players_root.get_node_or_null(str(player_id))
	if player:
		player.enter_vehicle(self)

@rpc("any_peer", "call_local", "reliable")
func request_exit(player_id: int) -> void:
	if not multiplayer.is_server() or driver_id != player_id:
		return
	driver_id = -1
	_driver_changed.rpc(-1)
	var player := Net.players_root.get_node_or_null(str(player_id))
	if player:
		player.exit_vehicle()

@rpc("authority", "reliable")
func _driver_changed(new_driver_id: int) -> void:
	if new_driver_id == driver_id:
		return
	if driver_id != -1:
		var prev := Net.players_root.get_node_or_null(str(driver_id))
		if prev:
			prev.exit_vehicle()
	driver_id = new_driver_id
	if driver_id != -1:
		var cur := Net.players_root.get_node_or_null(str(driver_id))
		if cur:
			cur.enter_vehicle(self)

@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_drive_input(steer: float, throttle: float, do_brake: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var pid := sender if sender != 0 else multiplayer.get_unique_id()
	if pid != driver_id:
		return
	steering = clamp(steer, -1.0, 1.0) * max_steer
	engine_force = throttle * engine_force_value
	brake = brake_force if do_brake else 0.0
	_sync_vehicle_state.rpc(global_transform, linear_velocity, angular_velocity)

@rpc("authority", "unreliable_ordered")
func _sync_vehicle_state(t: Transform3D, lin_vel: Vector3, ang_vel: Vector3) -> void:
	global_transform = t
	linear_velocity = lin_vel
	angular_velocity = ang_vel
