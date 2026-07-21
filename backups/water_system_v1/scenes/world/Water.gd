@tool
class_name Water
extends MeshInstance3D

@export var mesh_subdivisions: int = 300
@export var chunk_size: float = 500.0:
	set(value):
		chunk_size = value
		_update_mesh()
@export var chunk_overlap: float = 5.0:
	set(value):
		chunk_overlap = value
		_update_mesh()

@export var height_scale: float = 2.5
@export var time_scale: float = 1.0
@export var wavelength_scale: float = 1.2

@export var wave_intensity: float = 1.0
@export var normal_strength: float = 0.25:
	set(value):
		normal_strength = value
		if material_override is ShaderMaterial:
			material_override.set_shader_parameter("u_normal_strength", value)
@export var foam_intensity: float = 0.8

@export var deep_opacity: float = 0.08
@export var shallow_opacity: float = 0.25
@export var ambient_occlusion: float = 0.05

@export var wave_visual_scale: float = 2.0  # NEW: Amplify overall wave visual impact
@export var crest_sharpness: float = 1.2   # NEW: Make wave crests sharper
@export var normal_amplitude_scale: float = 1.5  # NEW: Boost normal displacement

@export var mesh_scale_factor: float = 2.0     # NEW: Control mesh visual size
@export var wave_density_scale: float = 0.5     # NEW: Adjust wave density for mesh size

@export var island_behavior: bool = false
@export var island_radius: float = 10.0
@export var water_depth: float = 2.0

@export var view_distance: float = 0.0
var neighbor_step: Vector4 = Vector4.ZERO
@export var show_chunks: bool = false
@export var fade_start_ratio: float = 0.3
@export var fade_sharpness: float = 1.5

func _ready() -> void:
	update_shader_parameters()

func setup(subdivisions: int, view_dist: float) -> void:
	mesh_subdivisions = subdivisions
	view_distance = view_dist
	_update_mesh()

func set_neighbor_steps(steps: Vector4) -> void:
	neighbor_step = steps

func _update_mesh() -> void:
	var extra: float = chunk_overlap * 2.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(chunk_size + extra, chunk_size + extra)
	pm.subdivide_width = mesh_subdivisions
	pm.subdivide_depth = mesh_subdivisions
	mesh = pm

func _process(delta: float) -> void:
	var material: ShaderMaterial = material_override
	if not material is ShaderMaterial:
		return

	var cam = get_viewport().get_camera_3d()
	if cam and view_distance > 0.0:
		material.set_shader_parameter("u_camera_pos", cam.global_position)
		material.set_shader_parameter("u_view_distance", view_distance)
		material.set_shader_parameter("u_fade_start_ratio", fade_start_ratio)
		material.set_shader_parameter("u_fade_sharpness", fade_sharpness)
		var dist: float = global_position.distance_to(cam.global_position)
		if not Engine.is_editor_hint():
			visible = dist < view_distance

	update_shader_parameters()

func update_shader_parameters() -> void:
	if not is_inside_tree():
		return
		
	# Update water appearance parameters
	var material: ShaderMaterial = material_override
	if material is ShaderMaterial:
		material.set_shader_parameter("height_scale", height_scale * wave_intensity)
		material.set_shader_parameter("u_wavelength_scale", wavelength_scale)
		material.set_shader_parameter("u_foam_intensity", foam_intensity)
		material.set_shader_parameter("u_band_count", 4.0)
		var shared_time: float = Time.get_ticks_msec() / 1000.0
		material.set_shader_parameter("u_time", shared_time * time_scale)
		if Engine.has_singleton("WaveParams"):
			WaveParams.current_time = shared_time * time_scale * 0.39
			WaveParams.height_scale = height_scale
			WaveParams.time_scale = time_scale
			WaveParams.wavelength_scale = wavelength_scale
			WaveParams.wave_intensity = wave_intensity
			WaveParams.wave_visual_scale = wave_visual_scale
			WaveParams.wave_density_scale = wave_density_scale
			WaveParams.sub_wave_scale = 1.0

		# NEW: Apply visual scaling parameters
		material.set_shader_parameter("u_wave_visual_scale", wave_visual_scale)
		material.set_shader_parameter("u_crest_sharpness", crest_sharpness)
		material.set_shader_parameter("u_normal_amplitude_scale", normal_amplitude_scale)
		material.set_shader_parameter("u_mesh_scale_factor", mesh_scale_factor)
		material.set_shader_parameter("u_wave_density_scale", wave_density_scale)
		material.set_shader_parameter("u_neighbor_step", neighbor_step)
		material.set_shader_parameter("u_half_chunk", chunk_size * 0.5 + chunk_overlap)



func set_dark_mode(enabled: bool) -> void:
	# Toggle for horror lighting conditions
	if material_override is ShaderMaterial:
		if enabled:
			material_override.set_shader_parameter("u_normal_strength", 0.15)
			material_override.set_shader_parameter("u_caustic_strength", 0.1)
			material_override.set_shader_parameter("u_ambient_fill", 0.02)
		else:
			material_override.set_shader_parameter("u_normal_strength", normal_strength)
			material_override.set_shader_parameter("u_caustic_strength", 0.25)
			material_override.set_shader_parameter("u_ambient_fill", ambient_occlusion)
