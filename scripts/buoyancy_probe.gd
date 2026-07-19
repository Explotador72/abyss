extends MeshInstance3D
class_name BuoyancyProbe

@export var buoyancy_strength: float = 8000.0
@export var air_downforce_mult: float = 5.0
@export var water_drag: float = 8000.0
@export var lateral_resistance: float = 40000.0
@export var angular_drag: float = 20000.0
@export var max_depth: float = 4.0
@export var look_ahead: float = 1.5

var _ocean_manager: Node = null
static var submerged_count: int = 0
static var prev_submerged: int = 0
static var _last_physics_frame: int = 0


func _ready():
	var main_node := get_node_or_null("/root/Main")
	if main_node != null:
		_ocean_manager = main_node.get_node_or_null("OceanManager")


func get_water_height(position_x: float, position_z: float) -> float:
	if _ocean_manager == null or not _ocean_manager.has_method("get_wave_height"):
		return 0.0
	var wave: float = _ocean_manager.get_wave_height(position_x, position_z)
	return wave + _ocean_manager.water_base_y


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
