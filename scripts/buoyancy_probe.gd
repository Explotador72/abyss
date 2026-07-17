extends MeshInstance3D
class_name BuoyancyProbe

@export var buoyancy_strength: float = 8000.0
@export var air_downforce_mult: float = 5.0
@export var water_drag: float = 8000.0
@export var lateral_resistance: float = 40000.0
@export var angular_drag: float = 20000.0
@export var max_depth: float = 4.0
@export var look_ahead: float = 1.5

const WAVE_DIRECTIONS: Array[Vector2] = [
	Vector2(0.95, 0.31), Vector2(-0.26, 0.97), Vector2(0.42, -0.91), Vector2(-0.77, -0.64),
	Vector2(0.71, 0.70), Vector2(-0.59, 0.81), Vector2(0.17, -0.99), Vector2(-0.37, -0.93),
	Vector2(0.87, -0.50), Vector2(-0.94, 0.35), Vector2(0.99, 0.12), Vector2(-0.09, -0.50),
	Vector2(0.35, 0.20), Vector2(-0.15, 0.45), Vector2(0.50, -0.30), Vector2(-0.40, 0.10)
]
const WAVE_LENGTHS: Array[float] = [24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5, 0.3, 0.18, 0.1, 0.06]
const WAVE_AMPLITUDES: Array[float] = [0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03, 0.02, 0.015, 0.01, 0.007]

var _ocean_manager: Node = null
static var submerged_count: int = 0
static var prev_submerged: int = 0
static var _last_physics_frame: int = 0


func _ready():
	var main_node := get_node_or_null("/root/Main")
	if main_node != null:
		_ocean_manager = main_node.get_node_or_null("OceanManager")


func _get_wave_property(property_name: String, fallback: float) -> float:
	if _ocean_manager == null:
		return fallback
	return _ocean_manager.get(property_name)


func get_water_height(position_x: float, position_z: float) -> float:
	var position_2d := Vector2(position_x, position_z)
	var time_seconds := Time.get_ticks_msec() / 1000.0
	var time_scale_value := _get_wave_property("time_scale", 0.7)
	var height_scale_value := _get_wave_property("height_scale", 2.5)
	var wavelength_scale_value := _get_wave_property("wavelength_scale", 2.0)
	var intensity_value := _get_wave_property("wave_intensity", 0.5)
	var density_scale_value := _get_wave_property("wave_density_scale", 0.6)
	var visual_scale_value := _get_wave_property("wave_visual_scale", 1.2)

	var wave_time := time_seconds * time_scale_value * 0.39

	var env1: float = sin(position_2d.dot(Vector2(0.025, 0.035)) + wave_time * 0.04) * 0.5 + 0.5
	var env2: float = sin(position_2d.dot(Vector2(-0.018, 0.04)) + wave_time * 0.03) * 0.5 + 0.5
	var env3: float = sin(position_2d.dot(Vector2(0.04, -0.02)) + wave_time * 0.05) * 0.5 + 0.5
	var envelope: float = env1 * 0.35 + env2 * 0.35 + env3 * 0.30
	envelope = envelope * 0.5 + 0.5

	var total_height: float = 0.0
	for wave_index in 16:
		var seed: float = float(wave_index) * 2.399
		var wave_length: float = WAVE_LENGTHS[wave_index] * maxf(wavelength_scale_value, 0.1) / maxf(density_scale_value, 0.01)
		var amplitude: float = WAVE_AMPLITUDES[wave_index] * height_scale_value * intensity_value * envelope * visual_scale_value
		var wave_number := TAU / wave_length
		var phase_speed := sqrt(9.8 / wave_number)

		var jitter_strength: float = 0.04 + (1.0 - WAVE_AMPLITUDES[wave_index] / 0.9) * 0.3
		var jitter_x := sin(position_x * 0.025 + position_z * 0.018 + seed)
		var jitter_z := cos(position_x * 0.018 + position_z * 0.025 + seed * 1.3)
		var jitter := Vector2(jitter_x, jitter_z) * jitter_strength
		var direction := (WAVE_DIRECTIONS[wave_index] + jitter).normalized()

		var phase_off := sin(position_x * 0.01 + position_z * 0.014 + seed) * 2.0
		phase_off += sin(position_x * 0.02 - position_z * 0.012 + seed * 1.7) * 1.2

		var phase := wave_number * direction.dot(position_2d) + phase_speed * wave_time + phase_off
		total_height += amplitude * sin(phase)

	return total_height


func _find_rigid_body() -> RigidBody3D:
	var current_node := get_parent() as Node
	while current_node != null:
		if current_node is RigidBody3D:
			return current_node
		current_node = current_node.get_parent()
	return null


func _physics_process(delta_time: float):
	if Engine.get_physics_frames() != _last_physics_frame:
		_last_physics_frame = Engine.get_physics_frames()
		prev_submerged = submerged_count
		submerged_count = 0

	var rigid_body := _find_rigid_body()
	if rigid_body == null:
		return

	var prediction: Vector3 = rigid_body.linear_velocity * delta_time * look_ahead
	var world_position: Vector3 = global_position + prediction
	var water_height: float = get_water_height(world_position.x, world_position.z)
	var depth: float = water_height - world_position.y

	var body_scale := rigid_body.global_transform.basis.get_scale().x
	var center_of_mass_world: Vector3 = rigid_body.global_transform * rigid_body.center_of_mass
	var lever := world_position - center_of_mass_world
	var local_velocity: Vector3 = rigid_body.linear_velocity + rigid_body.angular_velocity.cross(lever)

	if depth > 0.0:
		submerged_count += 1

	depth = clampf(depth, -max_depth, max_depth)
	var force_multiplier := buoyancy_strength * (air_downforce_mult if depth < 0 else 1.0)
	var buoyancy_force: Vector3 = Vector3.UP * depth * force_multiplier * body_scale * body_scale
	buoyancy_force -= Vector3(0, local_velocity.y, 0) * water_drag * body_scale * body_scale
	rigid_body.apply_force(buoyancy_force, lever)

	var wet_factor := lerpf(0.65, 1.0, float(prev_submerged) / 12.0)
	var basis_ortho := rigid_body.global_transform.basis.orthonormalized()
	var velocity_local := basis_ortho.transposed() * Vector3(local_velocity.x, 0, local_velocity.z)
	var drag_local := Vector3(velocity_local.x * lateral_resistance, 0, velocity_local.z * water_drag)
	rigid_body.apply_central_force(-(basis_ortho * drag_local) * body_scale * body_scale * wet_factor)

	var angular_velocity := rigid_body.angular_velocity
	rigid_body.apply_torque(-angular_velocity * angular_drag * body_scale * body_scale)
	rigid_body.apply_torque(-Vector3(0, angular_velocity.y, 0) * angular_drag * 3.0 * body_scale * body_scale)
