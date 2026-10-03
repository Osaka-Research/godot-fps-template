extends Control

func _ready() -> void:
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected)
	$Panel/VBox/HostBtn.pressed.connect(_on_host)
	$Panel/VBox/JoinBtn.pressed.connect(_on_join)

func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		$Panel/VBox/Status.text = "Could not host (error %d)" % err
		return
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _on_join() -> void:
	var ip: String = $Panel/VBox/IPInput.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var err := Net.join(ip)
	if err != OK:
		$Panel/VBox/Status.text = "Could not connect (error %d)" % err
		return
	$Panel/VBox/Status.text = "Connecting to %s…" % ip

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _on_connection_failed() -> void:
	$Panel/VBox/Status.text = "Connection failed"
	multiplayer.multiplayer_peer = null
