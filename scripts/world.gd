extends Node3D

func _ready() -> void:
	Net.register_world($Players, $Blocks)
