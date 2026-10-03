extends Control

@onready var name_edit: LineEdit = $Panel/VBox/NameEdit
@onready var color_btn: ColorPickerButton = $Panel/VBox/ColorBtn
@onready var trigger_opt: OptionButton = $Panel/VBox/TriggerOpt
@onready var action_opt: OptionButton = $Panel/VBox/ActionOpt
@onready var param_spin: SpinBox = $Panel/VBox/ParamSpin
@onready var submit_btn: Button = $Panel/VBox/SubmitBtn
@onready var close_btn: Button = $Panel/VBox/CloseBtn
@onready var status_label: Label = $Panel/VBox/StatusLabel

const TRIGGERS := ["touch", "hit", "timer", "break"]
const ACTIONS := ["apply_force", "deal_damage", "heal", "change_color", "spawn_particle", "destroy_self", "spawn_block"]

func _ready() -> void:
	visible = false
	for t in TRIGGERS:
		trigger_opt.add_item(t.capitalize())
	for a in ACTIONS:
		action_opt.add_item(a.capitalize().replace("_", " "))
	submit_btn.pressed.connect(_on_submit)
	close_btn.pressed.connect(toggle)
	Net.block_type_rejected.connect(_on_rejected)
	Net.block_type_approved.connect(_on_approved)

func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_submit() -> void:
	var trigger: String = TRIGGERS[trigger_opt.selected]
	var action: String = ACTIONS[action_opt.selected]

	var trigger_args := {}
	if trigger == "timer":
		trigger_args["seconds"] = param_spin.value
	elif trigger == "break":
		trigger_args["hits"] = int(param_spin.value)

	var action_args := {}
	match action:
		"apply_force":
			action_args["strength"] = param_spin.value
		"deal_damage":
			action_args["amount"] = param_spin.value
		"heal":
			action_args["amount"] = param_spin.value
		"change_color":
			action_args["color"] = color_btn.color
		"spawn_block":
			action_args["type_id"] = "default"

	var def := {
		"name": name_edit.text,
		"color": color_btn.color,
		"rules": [{"trigger": trigger, "trigger_args": trigger_args, "action": action, "action_args": action_args}],
	}
	Net.submit_block_type.rpc_id(1, def)
	status_label.text = "Submitting…"

func _on_rejected(reason: String) -> void:
	status_label.text = "Rejected: " + reason

func _on_approved(type_id: String) -> void:
	status_label.text = "Approved as " + type_id + " — press Q to cycle to it"
