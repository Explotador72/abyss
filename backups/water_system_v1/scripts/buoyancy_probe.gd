extends MeshInstance3D

@export var buoyancy_strength: float = 8000.0
@export var air_downforce_mult: float = 5.0
@export var water_drag: float = 8000.0
@export var lateral_resistance: float = 40000.0
@export var angular_drag: float = 20000.0
@export var max_depth: float = 4.0
@export var look_ahead: float = 1.5

# 16 Gerstner waves — IDÉNTICO al vertex shader de water.gdshader
const DIRECTIONS: Array[Vector2] = [
	Vector2(0.95, 0.31), Vector2(-0.26, 0.97), Vector2(0.42, -0.91), Vector2(-0.77, -0.64),
	Vector2(0.71, 0.70), Vector2(-0.59, 0.81), Vector2(0.17, -0.99), Vector2(-0.37, -0.93),
	Vector2(0.87, -0.50), Vector2(-0.94, 0.35), Vector2(0.99, 0.12), Vector2(-0.09, -0.50),
	Vector2(0.30, 0.95), Vector2(-0.85, 0.52), Vector2(0.60, -0.80), Vector2(-0.50, -0.86)
]
const WAVELENGTHS: Array[float] = [24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5, 0.35, 0.22, 0.14, 0.08]
const AMPLITUDES: Array[float] = [0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03, 0.018, 0.01, 0.006, 0.003]

var _ocean_manager: Node = null
static var submerged_count: int = 0
static var prev_submerged: int = 0
static var _last_physics_frame: int = 0


func _ready():
	var main_node := get_node_or_null("/root/Main")
	if main_node != null:
		_ocean_manager = main_node.get_node_or_null("OceanManager")


func _get_prop(name: String, fallback: float) -> float:
	if _ocean_manager == null:
		return fallback
	return _ocean_manager.get(name)


func get_water_height(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var hs := _get_prop("height_scale", 2.5)
	var ts := _get_prop("time_scale", 0.7)
	var ws := _get_prop("wavelength_scale", 2.0)
	var wi := _get_prop("wave_intensity", 0.5)
	var ds := _get_prop("wave_density_scale", 0.6)
	var vs := _get_prop("wave_visual_scale", 1.2)
	var t := Time.get_ticks_msec() / 1000.0 * ts * 0.39

	# Wave group envelope (idéntico al shader)
	var env1 := sin(pos.dot(Vector2(0.025, 0.035)) + t * 0.04) * 0.5 + 0.5
	var env2 := sin(pos.dot(Vector2(-0.018, 0.04)) + t * 0.03) * 0.5 + 0.5
	var envelope: float = lerp(env1, env2, 0.5) * 0.4 + 0.6

	var height: float = 0.0
	for i in 16:
		var wl: float = WAVELENGTHS[i] * maxf(ws, 0.1) / maxf(ds, 0.01)
		var amp: float = AMPLITUDES[i] * hs * wi * envelope * vs
		var k := TAU / wl
		var c := sqrt(9.8 / k)

		var js := 0.06 + (1.0 - AMPLITUDES[i] / 0.9) * 0.5
		var jx := sin(x * 0.025 + z * 0.018 + float(i) * 2.399) * js
		var jy := cos(x * 0.018 + z * 0.025 + float(i) * 2.399 * 1.3) * js
		var dir := Vector2(DIRECTIONS[i].x + jx, DIRECTIONS[i].y + jy).normalized()

		var po := sin(x * 0.01 + z * 0.014 + float(i) * 2.399) * 2.0
		po += sin(x * 0.02 - z * 0.012 + float(i) * 2.399 * 1.7) * 1.2

		var f := k * dir.dot(pos) + c * t + po
		height += amp * sin(f)

	return height


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
