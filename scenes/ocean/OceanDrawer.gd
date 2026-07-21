@tool
class_name OceanDrawer
extends Node3D

@export var fft_normal: Texture2D:
	set(v): fft_normal = v; sync_params()
@export var fft_height: Texture2D:
	set(v): fft_height = v; sync_params()
@export var fft_foam: Texture2D:
	set(v): fft_foam = v; sync_params()
@export var use_fft: bool = false:
	set(v): use_fft = v; sync_params()

var ocean: OceanManager:
	get:
		if ocean == null:
			ocean = _find_ocean()
		return ocean

var _player_ref: Node3D = null
var _center_chunk_index: int = -1

func _find_ocean() -> OceanManager:
	var p: Node = get_parent()
	while p != null:
		if p is OceanManager:
			return p
		p = p.get_parent()
	return null

func _ready() -> void:
	rebuild_grid()

func rebuild_grid() -> void:
	if ocean == null:
		return
	for child in get_children():
		if child != null and is_instance_valid(child):
			child.queue_free()
	var center: int = (ocean.grid_size - 1) / 2
	var offset_f: float = (ocean.grid_size - 1) * ocean.chunk_size * -0.5
	var gs: int = ocean.grid_size
	var cs: float = ocean.chunk_size
	var ol: float = ocean.chunk_overlap
	var extra: float = ol * 2.0
	for gx in range(gs):
		for gz in range(gs):
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(cs + extra, cs + extra)
			var dist := maxi(absi(gx - center), absi(gz - center))
			var lod: int = ocean.lod_center if dist <= 1 else ocean.lod_outer
			pm.subdivide_width = lod
			pm.subdivide_depth = lod
			mi.mesh = pm
			mi.material_override = ShaderMaterial.new()
			var shader_res: Shader = load("res://assets/shaders/ocean.gdshader")
			if shader_res != null:
				mi.material_override.shader = shader_res
			mi.position = Vector3(gx * cs + offset_f, 0, gz * cs + offset_f)
			mi.name = "Chunk_%d_%d" % [gx, gz]
			add_child(mi)
			mi.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else self
			_center_chunk_index = get_child_count() - 1
	sync_params()

func _center_on_player() -> void:
	if ocean == null:
		return
	if _player_ref == null:
		_player_ref = get_node_or_null("/root/Main/Player")
	var target: Node3D = _player_ref
	if target == null:
		target = get_viewport().get_camera_3d()
	if target == null:
		return
	var tx: float = target.global_position.x
	var tz: float = target.global_position.z
	var sx: float = round(tx / ocean.chunk_size) * ocean.chunk_size
	var sz: float = round(tz / ocean.chunk_size) * ocean.chunk_size
	global_position = Vector3(sx, 0, sz)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_center_on_player()
	_ensure_shader()
	sync_params()
	_update_debug()

func _ensure_shader() -> void:
	var shader_res: Shader = load("res://assets/shaders/ocean.gdshader")
	if shader_res == null:
		return
	for child in get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null:
			continue
		var mat: Material = mi.material_override
		if mat is ShaderMaterial and mat.shader == null:
			mat.shader = shader_res

func sync_params() -> void:
	if ocean == null:
		return
	var shared_time: float = Time.get_ticks_msec() / 1000.0
	for child in get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null:
			continue
		var mat: Material = mi.material_override
		if not (mat is ShaderMaterial):
			continue
		# FFT textures
		mat.set_shader_parameter("u_fft_normal", fft_normal)
		mat.set_shader_parameter("u_fft_height", fft_height)
		mat.set_shader_parameter("u_fft_foam", fft_foam)
		mat.set_shader_parameter("u_use_fft", 1.0 if use_fft else 0.0)
		# FFT params (from OceanManager extended)
		mat.set_shader_parameter("u_fft_tiling", ocean.fft_tiling)
		mat.set_shader_parameter("u_fft_fps", ocean.fft_fps)
		mat.set_shader_parameter("u_fft_margin", ocean.fft_margin)
		mat.set_shader_parameter("u_fft_tex_resolution", ocean.fft_tex_resolution)
		mat.set_shader_parameter("u_fft_detail_scale", ocean.fft_detail_scale)
		mat.set_shader_parameter("u_fft_detail_strength", ocean.fft_detail_strength)
		# Wave modifiers
		mat.set_shader_parameter("u_wave_scale", ocean.wave_scale)
		mat.set_shader_parameter("u_wave_intensity", ocean.wave_intensity)
		mat.set_shader_parameter("u_wavelength_scale", ocean.wavelength_scale)
		mat.set_shader_parameter("u_wave_speed_scale", ocean.wave_speed_scale)
		mat.set_shader_parameter("u_wave_smoothness", ocean.wave_smoothness)
		mat.set_shader_parameter("u_time", shared_time * 0.02)
		mat.set_shader_parameter("u_view_distance", ocean.view_distance)
		mat.set_shader_parameter("u_fade_start_ratio", ocean.fade_start_ratio)
		mat.set_shader_parameter("u_fade_sharpness", ocean.fade_sharpness)
		mat.set_shader_parameter("u_shallow_color", ocean.shallow_color)
		mat.set_shader_parameter("u_deep_color", ocean.deep_color)
		mat.set_shader_parameter("u_light_color", ocean.light_color)
		mat.set_shader_parameter("u_depth_gradient_power", ocean.depth_gradient_power)
		mat.set_shader_parameter("u_foam_residual_density", ocean.foam_residual_density)
		mat.set_shader_parameter("u_foam_residual_threshold", ocean.foam_residual_threshold)
		mat.set_shader_parameter("u_foam_peak_threshold", ocean.foam_peak_threshold)
		mat.set_shader_parameter("u_foam_peak_density", ocean.foam_peak_density)
		mat.set_shader_parameter("u_foam_color", ocean.foam_color)
		mat.set_shader_parameter("u_specular_strength", ocean.specular_strength)
		mat.set_shader_parameter("u_specular_shininess", ocean.specular_shininess)
		mat.set_shader_parameter("u_refraction_strength", ocean.refraction_strength)
		mat.set_shader_parameter("u_normal_detail_scale", ocean.normal_detail_scale)
		mat.set_shader_parameter("u_normal_detail_strength", ocean.normal_detail_strength)
		var cam := get_viewport().get_camera_3d()
		if cam:
			mat.set_shader_parameter("u_camera_pos", cam.global_position)
			var dist: float = mi.global_position.distance_to(cam.global_position)
			if not Engine.is_editor_hint():
				mi.visible = dist < ocean.view_distance

var _debug_mesh: MeshInstance3D = null

func _update_debug() -> void:
	if ocean == null:
		return
	if not ocean.show_chunks:
		if _debug_mesh != null:
			_debug_mesh.queue_free()
			_debug_mesh = null
		return
	if _debug_mesh != null:
		_debug_mesh.queue_free()
	var half_size: float = ocean.chunk_size * 0.5 + ocean.chunk_overlap
	var center: int = (ocean.grid_size - 1) / 2
	var offset_f: float = (ocean.grid_size - 1) * ocean.chunk_size * -0.5
	var y: float = 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for gx in range(ocean.grid_size):
		for gz in range(ocean.grid_size):
			var cx: float = gx * ocean.chunk_size + offset_f
			var cz: float = gz * ocean.chunk_size + offset_f
			var is_center := (gx == center and gz == center)
			var corners := [
				Vector3(cx - half_size, y, cz - half_size),
				Vector3(cx + half_size, y, cz - half_size),
				Vector3(cx + half_size, y, cz + half_size),
				Vector3(cx - half_size, y, cz + half_size)
			]
			if is_center:
				st.set_color(Color(1, 0.1, 0.1, 1))
			else:
				st.set_color(Color.GREEN_YELLOW)
			var edges := [[0, 1], [1, 2], [2, 3], [3, 0]]
			for e in range(4):
				st.add_vertex(corners[edges[e][0]])
				st.add_vertex(corners[edges[e][1]])
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.name = "DebugGrid"
	_debug_mesh.mesh = st.commit()
	_debug_mesh.material_override = ORMMaterial3D.new()
	_debug_mesh.material_override.albedo_color = Color.WHITE
	_debug_mesh.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mesh.material_override.no_depth_test = true
	_debug_mesh.material_override.vertex_color_use_as_albedo = true
	add_child(_debug_mesh)
