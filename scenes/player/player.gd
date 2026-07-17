extends RigidBody3D

@export_group("Boat Properties")
@export var mass_override: float = 2000.0

@export_group("Controls")
@export var engine_accel: float = 100.0
@export var steer_accel: float = 0.5
@export var mouse_sensitivity: float = 0.002
@export var camera_pitch_limit: float = 80.0

@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch


func _ready() -> void:
	var body_scale := global_transform.basis.get_scale().x
	mass = mass_override * body_scale * body_scale * body_scale
	center_of_mass = Vector3(0, -0.5, 0)
	sleeping = false
	gravity_scale = 1.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta_time: float = state.step
	var current_transform: Transform3D = state.transform

	if BuoyancyProbe.submerged_count >= 4:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S):
			var heading: Vector3 = -current_transform.basis.z
			heading.y = 0.0
			heading = heading.normalized()
			var direction_sign: float = 1.0 if Input.is_key_pressed(KEY_W) else -1.0
			state.linear_velocity += heading * direction_sign * engine_accel * delta_time

		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D):
			var turn_sign: float = 1.0 if Input.is_key_pressed(KEY_A) else -1.0
			var yaw_torque: Vector3 = current_transform.basis.y * turn_sign * steer_accel * mass
			state.angular_velocity += (yaw_torque / mass) * delta_time


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pitch.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pitch.rotation.x = clampf(
			camera_pitch.rotation.x,
			deg_to_rad(-camera_pitch_limit),
			deg_to_rad(camera_pitch_limit)
		)
