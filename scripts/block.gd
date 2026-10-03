extends StaticBody3D

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var touch_area: Area3D = $TouchArea
@onready var timer: Timer = $Timer
@onready var particles: GPUParticles3D = $GPUParticles3D

var cell := Vector3i.ZERO
var type_id := "default"
var hits_taken := 0

func _ready() -> void:
	_parse_name()
	_apply_color(_def().get("color", Color(0.72, 0.55, 0.35, 1)))
	touch_area.body_entered.connect(_on_touch)

	for rule in _def().get("rules", []):
		if rule.get("trigger") == "timer":
			var interval: float = max(float(rule.get("trigger_args", {}).get("seconds", 2.0)), Net.MIN_TIMER_INTERVAL)
			timer.wait_time = interval
			timer.timeout.connect(_run_action.bind(rule, null))
			timer.start()

func _def() -> Dictionary:
	return Net.block_types.get(type_id, {})

func _parse_name() -> void:
	var parts := name.split("_")
	cell = Vector3i(int(parts[1]), int(parts[2]), int(parts[3]))
	type_id = parts[4]

func _apply_color(c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mesh.set_surface_override_material(0, mat)

func _on_touch(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	for rule in _def().get("rules", []):
		if rule.get("trigger") == "touch":
			_run_action(rule, body)

@rpc("any_peer", "call_local", "reliable")
func network_hit() -> void:
	if not multiplayer.is_server():
		return
	hits_taken += 1
	for rule in _def().get("rules", []):
		if rule.get("trigger") == "hit":
			_run_action(rule, null)
		elif rule.get("trigger") == "break" and hits_taken >= int(rule.get("trigger_args", {}).get("hits", 3)):
			_run_action(rule, null)
			_destroy()

func _run_action(rule: Dictionary, body) -> void:
	var action: String = rule.get("action", "")
	var args: Dictionary = rule.get("action_args", {})
	match action:
		"change_color":
			_apply_color(args.get("color", Color.WHITE))
		"spawn_particle":
			particles.restart()
			particles.emitting = true
		"destroy_self":
			if multiplayer.is_server():
				_destroy()
		"apply_force":
			if multiplayer.is_server() and body is CharacterBody3D:
				var strength: float = clamp(float(args.get("strength", 5.0)), 0.0, Net.MAX_FORCE)
				body.apply_force(Vector3(0.0, strength, 0.0))
		"deal_damage":
			if multiplayer.is_server() and body and body.has_method("apply_damage"):
				var amount: float = clamp(float(args.get("amount", 10.0)), 0.0, Net.MAX_DAMAGE)
				body.apply_damage(amount)
		"heal":
			if multiplayer.is_server() and body and body.has_method("apply_heal"):
				var amount: float = clamp(float(args.get("amount", 10.0)), 0.0, Net.MAX_HEAL)
				body.apply_heal(amount)
		"spawn_block":
			if multiplayer.is_server():
				var target_type: String = args.get("type_id", "default")
				if Net.block_types.has(target_type):
					Net.request_place_block(cell + Vector3i(0, 1, 0), target_type)

func _destroy() -> void:
	Net.free_cell(cell)
	queue_free()
