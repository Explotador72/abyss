extends Camera3D

@export var move_speed := 10.0
@export var fast_multiplier := 3.0
@export var slow_multiplier := 0.3
@export var mouse_sensitivity := 0.002

var _captured := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_captured = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _captured:
		var e := event as InputEventMouseMotion
		rotation.y -= e.relative.x * mouse_sensitivity
		rotation.x -= e.relative.y * mouse_sensitivity
		rotation.x = clampf(rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _process(delta: float) -> void:
	if not _captured:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	if Input.is_key_pressed(KEY_CTRL):
		speed *= slow_multiplier

	var dir := Vector3()
	if Input.is_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_key_pressed(KEY_Q): dir.y -= 1
	if Input.is_key_pressed(KEY_E): dir.y += 1

	if dir.length_squared() > 0:
		dir = dir.normalized()
	global_position += dir * speed * delta
