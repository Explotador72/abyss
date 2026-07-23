class_name BuoyantBody
extends Node

signal probe_entered_water(probe: Node, state: Dictionary)
signal probe_exited_water(probe: Node, state: Dictionary)

@export var rigid_body_path : NodePath
@export var ocean_path : NodePath
@export_range(0.0, 10.0, 0.01, "or_greater") var buoyancy_strength := 1.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var water_density := 1025.0
@export_range(0.0, 20.0, 0.01, "or_greater") var heave_damping := 2.0
@export_range(0.0, 100.0, 0.01, "or_greater") var longitudinal_water_drag := 0.45
@export_range(0.0, 100.0, 0.01, "or_greater") var lateral_water_drag := 0.45
@export_range(0.0, 100.0, 0.1, "or_greater") var max_probe_acceleration := 35.0
@export var apply_forces := true

var rigid_body : RigidBody3D
var ocean : OceanSystem

var _cached_physical_probes : Array[Node] = []
var _cached_fx_probes : Array[Node] = []
var _cache_dirty := true
var _probe_states := {}
var _probe_wet := {}
var _probe_last_event_time := {}

const EPSILON := 0.0001


func _ready() -> void:
	_resolve_nodes()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_cache_dirty = true


func _physics_process(_delta : float) -> void:
	if not apply_forces:
		return
	if rigid_body == null or ocean == null:
		_resolve_nodes()
	if rigid_body == null or ocean == null:
		return

	var force_sample_points := _get_active_sample_points()
	var contact_sample_points := _get_contact_sample_points()
	if force_sample_points.is_empty() and contact_sample_points.is_empty():
		return

	var query_entries : Array[Dictionary] = []
	var points := PackedVector3Array()
	for sample_point in force_sample_points:
		points.push_back(sample_point["world_position"])
		query_entries.push_back({"type": "force", "sample_point": sample_point})
	for sample_point in contact_sample_points:
		points.push_back(sample_point["world_position"])
		query_entries.push_back({"type": "contact", "sample_point": sample_point})
	if points.is_empty():
		return

	var samples := ocean.sample_water_surface_batch(points, self)
	if samples.size() != query_entries.size():
		return

	var total_volume := _get_total_max_submerged_volume(force_sample_points)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var total_external_force := Vector3.ZERO
	var heave_submersion := 0.0
	for i in query_entries.size():
		var entry := query_entries[i]
		var sample_point : Dictionary = entry["sample_point"]
		var water_sample : WaterSurfaceSample = samples[i]
		if str(entry["type"]) == "force":
			var force_result := _apply_sample_forces(sample_point, water_sample, total_volume, gravity)
			total_external_force += Vector3(force_result.get("applied_force", Vector3.ZERO))
			heave_submersion += float(force_result.get("displaced_volume", 0.0)) / total_volume
			_update_probe_state(sample_point, water_sample, force_result, false)
		else:
			var contact_result := {
				"force": Vector3.ZERO,
				"applied_force": Vector3.ZERO,
				"submersion": 0.0,
			}
			_update_probe_state(sample_point, water_sample, contact_result, true)
	total_external_force += _apply_heave_damping(clampf(heave_submersion, 0.0, 1.0))


func refresh_probes() -> void:
	_cache_dirty = true


func get_probe_states(tag_filter := "") -> Array[Dictionary]:
	var states : Array[Dictionary] = []
	for state in _probe_states.values():
		if not (state is Dictionary):
			continue
		if tag_filter != "" and str(state.get("tag", "")) != tag_filter:
			continue
		states.push_back(state)
	return states


func get_wet_probe_states(tag_filter := "") -> Array[Dictionary]:
	var states : Array[Dictionary] = []
	for state in get_probe_states(tag_filter):
		if bool(state.get("is_wet", false)):
			states.push_back(state)
	return states


func _resolve_nodes() -> void:
	if not rigid_body_path.is_empty():
		rigid_body = get_node_or_null(rigid_body_path) as RigidBody3D
	if rigid_body == null:
		rigid_body = get_parent() as RigidBody3D
	if rigid_body == null:
		rigid_body = _find_parent_rigid_body()
	if not ocean_path.is_empty():
		ocean = get_node_or_null(ocean_path) as OceanSystem
	if ocean == null:
		ocean = get_tree().get_first_node_in_group(&"ocean_system") as OceanSystem


func _find_parent_rigid_body() -> RigidBody3D:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D:
			return node
		node = node.get_parent()
	return null


func _get_physical_probes() -> Array[Node]:
	if _cache_dirty:
		_rebuild_cache()
	return _cached_physical_probes


func _get_fx_probes() -> Array[Node]:
	if _cache_dirty:
		_rebuild_cache()
	return _cached_fx_probes


func _rebuild_cache() -> void:
	_cached_physical_probes.clear()
	_cached_fx_probes.clear()
	_scan_probes(self)
	_cache_dirty = false


func _scan_probes(node: Node) -> void:
	for child in node.get_children():
		if child is BuoyancyProbeNode:
			_cached_physical_probes.push_back(child)
		elif child is BuoyancyFxProbeNode:
			_cached_fx_probes.push_back(child)
		else:
			_scan_probes(child)


func _get_active_sample_points() -> Array[Dictionary]:
	var samples : Array[Dictionary] = []
	for probe in _get_physical_probes():
		if probe == null or not _is_probe_enabled(probe):
			continue
		samples.push_back({
			"world_position": probe.global_position,
			"local_position": probe.position,
			"max_submerged_volume_cubic_meters": float(probe.call(&"get_max_submerged_volume")),
			"buoyancy_height": float(probe.call(&"get_buoyancy_height")),
			"longitudinal_water_drag_multiplier": float(probe.get(&"longitudinal_water_drag_multiplier")),
			"lateral_water_drag_multiplier": float(probe.get(&"lateral_water_drag_multiplier")),
			"source_probe": probe,
			"is_fx_probe": false,
		})
	return samples


func _get_contact_sample_points() -> Array[Dictionary]:
	var samples : Array[Dictionary] = []
	for probe in _get_fx_probes():
		if probe == null or not _is_probe_enabled(probe):
			continue
		samples.push_back({
			"world_position": probe.global_position,
			"local_position": probe.position,
			"source_probe": probe,
			"is_fx_probe": true,
		})
	return samples


func _is_probe_enabled(probe: Node) -> bool:
	var value = probe.get(&"enabled")
	return true if value == null else bool(value)


func _get_total_max_submerged_volume(sample_points : Array[Dictionary]) -> float:
	var total_volume := 0.0
	for sample_point in sample_points:
		total_volume += _get_probe_max_submerged_volume(sample_point)
	return maxf(total_volume, 0.0001)


func _get_probe_max_submerged_volume(sample_point : Dictionary) -> float:
	return maxf(float(sample_point.get("max_submerged_volume_cubic_meters", 0.0)), 0.0)


func _apply_heave_damping(submersion: float) -> Vector3:
	if submersion <= 0.0 or heave_damping <= 0.0:
		return Vector3.ZERO
	var heave_force := Vector3.UP * (-rigid_body.linear_velocity.y * heave_damping * rigid_body.mass * submersion)
	rigid_body.apply_central_force(heave_force)
	return heave_force


func _apply_sample_forces(sample_point : Dictionary, sample : WaterSurfaceSample, total_volume : float, gravity : float) -> Dictionary:
	var sample_position : Vector3 = sample_point["world_position"]
	var buoyancy_height := maxf(float(sample_point.get("buoyancy_height", 1.0)), 0.001)
	var probe_bottom_y := sample_position.y - buoyancy_height
	var immersion_depth := clampf(sample.height - probe_bottom_y, 0.0, buoyancy_height)
	var submersion := immersion_depth / buoyancy_height
	var empty_result := {
		"force": Vector3.ZERO,
		"applied_force": Vector3.ZERO,
		"buoyancy_force": Vector3.ZERO,
		"displaced_volume": 0.0,
		"submersion": submersion,
	}
	var offset := sample_position - rigid_body.global_position
	var point_velocity := rigid_body.linear_velocity + rigid_body.angular_velocity.cross(offset)
	var max_submerged_volume := _get_probe_max_submerged_volume(sample_point)
	var volume_ratio := max_submerged_volume / total_volume
	var displaced_volume := max_submerged_volume * submersion
	var buoyancy_force := Vector3.UP * water_density * gravity * buoyancy_strength * displaced_volume

	var horizontal_point_velocity := Vector3(point_velocity.x, 0.0, point_velocity.z)
	var forward := -rigid_body.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := rigid_body.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var longitudinal_multiplier := float(sample_point.get("longitudinal_water_drag_multiplier", 1.0))
	var lateral_multiplier := float(sample_point.get("lateral_water_drag_multiplier", 1.0))
	var longitudinal_speed := horizontal_point_velocity.dot(forward)
	var lateral_speed := horizontal_point_velocity.dot(right)
	var longitudinal_drag_force := -forward * longitudinal_speed * longitudinal_water_drag * longitudinal_multiplier * rigid_body.mass * volume_ratio * submersion
	var lateral_drag_force := -right * lateral_speed * lateral_water_drag * lateral_multiplier * rigid_body.mass * volume_ratio * submersion

	var total_force := buoyancy_force + longitudinal_drag_force + lateral_drag_force
	if max_probe_acceleration > 0.0:
		var max_force := rigid_body.mass * volume_ratio * max_probe_acceleration
		if max_force > 0.0 and total_force.length_squared() > max_force * max_force:
			total_force = total_force.normalized() * max_force
	var applied_force := Vector3.ZERO
	if submersion > 0.0:
		rigid_body.apply_force(total_force, offset)
		applied_force = total_force
	return {
		"force": total_force,
		"applied_force": applied_force,
		"buoyancy_force": buoyancy_force,
		"displaced_volume": displaced_volume,
		"submersion": submersion,
	}


func _update_probe_state(sample_point: Dictionary, water_sample: WaterSurfaceSample, force_result: Dictionary, is_fx_probe: bool) -> void:
	var probe : Node = sample_point.get("source_probe")
	if probe == null:
		return
	var key := probe.get_instance_id()
	var sample_position : Vector3 = sample_point["world_position"]
	var depth := water_sample.height - sample_position.y
	var submersion := float(force_result.get("submersion", 0.0))
	var force: Vector3 = force_result.get("force", Vector3.ZERO)

	var enter_threshold := 0.03
	var exit_threshold := -0.03
	if is_fx_probe and probe.has_method(&"get_enter_depth_threshold"):
		enter_threshold = float(probe.call(&"get_enter_depth_threshold", enter_threshold))
	if is_fx_probe and probe.has_method(&"get_exit_depth_threshold"):
		exit_threshold = float(probe.call(&"get_exit_depth_threshold", exit_threshold))
	if enter_threshold <= exit_threshold:
		enter_threshold = exit_threshold + 0.001

	var was_wet := bool(_probe_wet.get(key, false))
	var is_wet := was_wet
	if was_wet:
		if depth <= exit_threshold:
			is_wet = false
	else:
		if depth >= enter_threshold:
			is_wet = true

	var now := float(Time.get_ticks_msec()) * 0.001
	var min_event_interval := 0.08
	if is_wet != was_wet:
		var last_event_time := float(_probe_last_event_time.get(key, -1.0e20))
		if now - last_event_time < min_event_interval:
			is_wet = was_wet
		else:
			_probe_last_event_time[key] = now

	_probe_wet[key] = is_wet
	var tag_value = probe.get(&"tag")
	var state := {
		"probe": probe,
		"tag": "" if tag_value == null else str(tag_value),
		"world_position": sample_position,
		"water_position": Vector3(sample_position.x, water_sample.height, sample_position.z),
		"depth": depth,
		"submersion": submersion,
		"is_wet": is_wet,
		"was_wet": was_wet,
		"entered": is_wet and not was_wet,
		"exited": was_wet and not is_wet,
		"force": force,
		"normal": water_sample.normal,
		"surface_velocity": water_sample.surface_velocity,
		"is_fx_probe": is_fx_probe,
		"time": now,
	}
	_probe_states[key] = state
	if bool(state["entered"]):
		probe_entered_water.emit(probe, state)
	elif bool(state["exited"]):
		probe_exited_water.emit(probe, state)
