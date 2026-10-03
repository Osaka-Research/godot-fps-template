extends StaticBody3D

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

@rpc("any_peer", "call_local", "reliable")
func network_hit() -> void:
	take_hit()

func take_hit() -> void:
	if collision.disabled:
		return
	collision.disabled = true
	mesh.visible = false
	await get_tree().create_timer(2.0).timeout
	mesh.visible = true
	collision.disabled = false
