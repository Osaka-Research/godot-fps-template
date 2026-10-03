extends CharacterBody3D

@export var speed := 6.0
@export var sprint_speed := 9.5
@export var jump_velocity := 4.5
@export var gravity := 9.8
@export var mouse_sensitivity := 0.0025
@export var place_distance := 4.0
@export var place_range := 50.0
@export var max_health := 100.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var crosshair: CanvasLayer = $Crosshair
@onready var mobile_controls: CanvasLayer = $MobileControls
@onready var block_editor: Control = $BlockEditor
@onready var viewmodel_anchor: Node3D = $Head/Camera3D/Viewmodel

var owner_id := 1
var jump_requested := false
var look_delta := Vector2.ZERO
var touch_move_dir := Vector2.ZERO
var equipped_type_id := "default"
var health := max_health
var can_shoot := true
var vehicle: Node = null

func _ready() -> void:
	if _is_local():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
		var gun := preload("res://assets/models/gun.glb").instantiate()
		gun.scale = Vector3.ONE * 0.4
		viewmodel_anchor.add_child(gun)
	else:
		camera.current = false
		crosshair.queue_free()
		mobile_controls.queue_free()
		block_editor.queue_free()
		viewmodel_anchor.queue_free()

func _is_local() -> bool:
	return multiplayer.get_unique_id() == owner_id

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_delta += event.relative

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.physical_keycode == KEY_SPACE:
			jump_requested = true
		if event.physical_keycode == KEY_Q:
			cycle_equipped_type()
		if event.physical_keycode == KEY_B:
			block_editor.toggle()
		if event.physical_keycode == KEY_E:
			_try_toggle_vehicle()

	if event is InputEventMouseButton and event.pressed:
		if block_editor.visible:
			pass
		elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			shoot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			place_block()

const ENTER_RANGE := 4.0

func _try_toggle_vehicle() -> void:
	if vehicle:
		vehicle.request_exit.rpc_id(1, owner_id)
		return
	for car in get_tree().get_nodes_in_group("vehicle"):
		if car.driver_id == -1 and car.global_transform.origin.distance_to(global_transform.origin) < ENTER_RANGE:
			car.request_enter.rpc_id(1, owner_id)
			break

func enter_vehicle(v: Node) -> void:
	vehicle = v
	mesh.visible = false
	collision.disabled = true

func exit_vehicle() -> void:
	if vehicle:
		global_transform.origin = vehicle.global_transform.origin + vehicle.global_transform.basis.x * 2.5
	vehicle = null
	mesh.visible = true
	collision.disabled = false

func cycle_equipped_type() -> void:
	var ids := Net.block_types.keys()
	if ids.is_empty():
		return
	var idx := ids.find(equipped_type_id)
	equipped_type_id = ids[(idx + 1) % ids.size()]

func _physics_process(_delta: float) -> void:
	if not _is_local():
		return

	if vehicle:
		global_transform = vehicle.global_transform
		var steer := 0.0
		if Input.is_physical_key_pressed(KEY_A):
			steer += 1.0
		if Input.is_physical_key_pressed(KEY_D):
			steer -= 1.0
		var throttle := 0.0
		if Input.is_physical_key_pressed(KEY_W):
			throttle += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			throttle -= 1.0
		var do_brake := Input.is_physical_key_pressed(KEY_SPACE)
		vehicle.submit_drive_input.rpc_id(1, steer, throttle, do_brake)
		return

	var yaw := look_delta.x * mouse_sensitivity
	var pitch := look_delta.y * mouse_sensitivity
	look_delta = Vector2.ZERO

	var input_dir := Vector2.ZERO
	if not block_editor.visible:
		if Input.is_physical_key_pressed(KEY_W):
			input_dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input_dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input_dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input_dir.x += 1.0
	input_dir = input_dir.normalized()
	if input_dir == Vector2.ZERO:
		input_dir = touch_move_dir
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)

	_submit_input.rpc_id(1, input_dir, sprint, jump_requested, yaw, pitch)
	jump_requested = false

# Runs on the server only (owning peer targets rpc_id(1, ...) here). Server
# simulates every player so movement can't be spoofed by a modified client.
@rpc("any_peer", "call_local", "unreliable_ordered")
func _submit_input(input_dir: Vector2, sprint: bool, jump: bool, yaw: float, pitch: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != owner_id:
		return

	rotate_y(-yaw)
	head.rotate_x(-pitch)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	if not is_on_floor():
		velocity.y -= gravity * get_physics_process_delta_time()
	elif jump:
		velocity.y = jump_velocity

	var move_speed := sprint_speed if sprint else speed
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()
	_sync_transform.rpc(position, rotation.y, head.rotation.x, health)

# Broadcast from the server to every peer. A remote client's own player only
# ever moves via this broadcast (its local copy never runs _submit_input's
# body — call_local doesn't fire for an rpc_id() targeting someone else), so
# this must apply unconditionally, including to the owner.
@rpc("authority", "unreliable_ordered")
func _sync_transform(pos: Vector3, yaw_rot: float, pitch_rot: float, hp: float) -> void:
	position = pos
	rotation.y = yaw_rot
	head.rotation.x = pitch_rot
	health = hp

func apply_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	if health <= 0.0:
		health = max_health
		position = Net.SPAWN_POINTS[randi() % Net.SPAWN_POINTS.size()]
		velocity = Vector3.ZERO

func apply_heal(amount: float) -> void:
	health = min(max_health, health + amount)

func apply_force(v: Vector3) -> void:
	velocity += v

func shoot() -> void:
	if not can_shoot:
		return
	can_shoot = false

	var space_state := get_world_3d().direct_space_state
	var from := camera.global_transform.origin
	var to := from + -camera.global_transform.basis.z * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if result and result.collider.has_method("network_hit"):
		result.collider.network_hit.rpc()

	await get_tree().create_timer(0.15).timeout
	can_shoot = true

func place_block() -> void:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_transform.origin
	var forward := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * place_range)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	var point: Vector3
	if result:
		point = result.position + result.normal * (Net.GRID_SIZE * 0.5)
	else:
		point = from + forward * place_distance

	var cell := Vector3i(
		floori(point.x / Net.GRID_SIZE),
		floori(point.y / Net.GRID_SIZE),
		floori(point.z / Net.GRID_SIZE)
	)
	Net.request_place_block.rpc_id(1, cell, equipped_type_id)
