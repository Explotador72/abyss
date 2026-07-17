@tool
extends Node3D

@export_group("Grid")
@export var water_chunk: PackedScene
@export var use_lod: bool = true:
	set(value): use_lod = value; _regenerate_grid()
@export var lod_center: int = 700:
	set(value): lod_center = value; _regenerate_grid()
@export var lod_ring1: int = 200:
	set(value): lod_ring1 = value; _regenerate_grid()
@export var lod_outer: int = 80:
	set(value): lod_outer = value; _regenerate_grid()
@export var grid_size: int = 7:
	set(value): grid_size = value; _regenerate_grid()
@export var chunk_size: float = 500.0:
	set(value): chunk_size = value; _regenerate_grid()
@export var chunk_overlap: float = 0.0:
	set(value): chunk_overlap = value; _sync_to_chunks("chunk_overlap", value)
@export var show_chunks: bool = false:
	set(value): show_chunks = value; _sync_to_chunks("show_chunks", value)
@export var view_distance: float = 2000.0:
	set(value): view_distance = value; _sync_to_chunks("view_distance", value)
@export var fade_start_ratio: float = 0.3:
	set(value): fade_start_ratio = value; _sync_to_chunks("fade_start_ratio", value)
@export var fade_sharpness: float = 1.5:
	set(value): fade_sharpness = value; _sync_to_chunks("fade_sharpness", value)

@export_group("Water Shape")
@export var height_scale: float = 2.5:
	set(value): height_scale = value; _sync_to_chunks("height_scale", value)
@export var time_scale: float = 0.7:
	set(value): time_scale = value; _sync_to_chunks("time_scale", value)
@export var wavelength_scale: float = 2.0:
	set(value): wavelength_scale = value; _sync_to_chunks("wavelength_scale", value)
@export var wave_intensity: float = 0.5:
	set(value): wave_intensity = value; _sync_to_chunks("wave_intensity", value)

@export_group("Appearance")
@export var normal_strength: float = 0.65:
	set(value): normal_strength = value; _sync_to_chunks("normal_strength", value)
@export var foam_intensity: float = 0.9:
	set(value): foam_intensity = value; _sync_to_chunks("foam_intensity", value)
@export var deep_opacity: float = 0.15:
	set(value): deep_opacity = value; _sync_to_chunks("deep_opacity", value)
@export var shallow_opacity: float = 0.4:
	set(value): shallow_opacity = value; _sync_to_chunks("shallow_opacity", value)
@export var ambient_occlusion: float = 0.74:
	set(value): ambient_occlusion = value; _sync_to_chunks("ambient_occlusion", value)

@export_group("Wave Detail")
@export var wave_visual_scale: float = 1.2:
	set(value): wave_visual_scale = value; _sync_to_chunks("wave_visual_scale", value)
@export var crest_sharpness: float = 1.1:
	set(value): crest_sharpness = value; _sync_to_chunks("crest_sharpness", value)
@export var normal_amplitude_scale: float = 1.3:
	set(value): normal_amplitude_scale = value; _sync_to_chunks("normal_amplitude_scale", value)
@export var mesh_scale_factor: float = 1.0:
	set(value): mesh_scale_factor = value; _sync_to_chunks("mesh_scale_factor", value)
@export var wave_density_scale: float = 0.6:
	set(value): wave_density_scale = value; _sync_to_chunks("wave_density_scale", value)


func _ready() -> void:
	_regenerate_grid()
	_center_on_camera()

func _center_on_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var half_total: float = grid_size * chunk_size * 0.5
	var cx: float = cam.global_position.x
	var cz: float = cam.global_position.z
	var sx: float = floor((cx + half_total) / chunk_size) * chunk_size - half_total
	var sz: float = floor((cz + half_total) / chunk_size) * chunk_size - half_total
	global_position = Vector3(sx, 0, sz)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_center_on_camera()


func _regenerate_grid() -> void:
	for child in get_children():
		if child != null and is_instance_valid(child):
			child.queue_free()

	if water_chunk == null:
		return

	var center: int = (grid_size - 1) / 2
	var offset: float = (grid_size - 1) * chunk_size * -0.5
	for grid_x in range(grid_size):
		for grid_z in range(grid_size):
			var chunk: Water = water_chunk.instantiate()
			var dist := maxi(absi(grid_x - center), absi(grid_z - center))
			if use_lod:
				match dist:
					0: chunk.setup(lod_center, view_distance)
					1: chunk.setup(lod_ring1, view_distance)
					_: chunk.setup(lod_outer, view_distance)
			else:
				chunk.setup(lod_center, view_distance)
			if use_lod and dist == 0:
				var mesh_size: float = chunk_size + chunk_overlap * 2.0
				var step: float = mesh_size / float(lod_ring1)
				chunk.set_neighbor_steps(Vector4(step, step, step, step))
			chunk.position = Vector3(grid_x * chunk_size + offset, 0, grid_z * chunk_size + offset)
			add_child(chunk)

	_sync_all_to_chunks()


func _sync_to_chunks(property: String, value) -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if is_instance_valid(child):
			child.set(property, value)


func _sync_all_to_chunks() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child == null or not is_instance_valid(child):
			continue
		child.set("view_distance", view_distance)
		child.set("fade_start_ratio", fade_start_ratio)
		child.set("fade_sharpness", fade_sharpness)
		child.set("height_scale", height_scale)
		child.set("time_scale", time_scale)
		child.set("wavelength_scale", wavelength_scale)
		child.set("wave_intensity", wave_intensity)
		child.set("foam_intensity", foam_intensity)
		child.set("normal_strength", normal_strength)
		child.set("deep_opacity", deep_opacity)
		child.set("shallow_opacity", shallow_opacity)
		child.set("ambient_occlusion", ambient_occlusion)
		child.set("wave_visual_scale", wave_visual_scale)
		child.set("crest_sharpness", crest_sharpness)
		child.set("normal_amplitude_scale", normal_amplitude_scale)
		child.set("mesh_scale_factor", mesh_scale_factor)
		child.set("wave_density_scale", wave_density_scale)
		child.set("show_chunks", show_chunks)
		child.set("chunk_size", chunk_size)
		child.set("chunk_overlap", chunk_overlap)
