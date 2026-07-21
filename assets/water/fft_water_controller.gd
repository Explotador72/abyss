@tool
extends MeshInstance3D

const WATER_MAT := preload('res://assets/materials/water_fft.tres')
const MESH_HIGH8K := preload('res://assets/meshes/clipmap/clipmap_high_8k.obj')
const MESH_HIGH := preload('res://assets/meshes/clipmap/clipmap_high.obj')
const MESH_LOW := preload('res://assets/meshes/clipmap/clipmap_low.obj')

enum MeshQuality { LOW, HIGH, HIGH8K }

@export_group('Wave Parameters')
@export_color_no_alpha var water_color : Color = Color(0.1, 0.15, 0.18) :
	set(value): water_color = value; RenderingServer.global_shader_parameter_set(&'water_color', water_color.srgb_to_linear())

@export_color_no_alpha var foam_color : Color = Color(0.73, 0.67, 0.62) :
	set(value): foam_color = value; RenderingServer.global_shader_parameter_set(&'foam_color', foam_color.srgb_to_linear())

@export var parameters : Array[WaveCascadeParameters] :
	set(value):
		var new_size := len(value)
		for i in range(new_size):
			if not value[i]: value[i] = WaveCascadeParameters.new()
			if not value[i].is_connected(&'scale_changed', _update_scales_uniform):
				value[i].scale_changed.connect(_update_scales_uniform)
			value[i].spectrum_seed = Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000))
			value[i].time = 120.0 + PI*i
		parameters = value
		_setup_wave_generator()
		_update_scales_uniform()

@export_group('Performance Parameters')
@export_enum('128x128:128', '256x256:256', '512x512:512', '1024x1024:1024') var map_size := 1024 :
	set(value):
		map_size = value
		_setup_wave_generator()

@export var mesh_quality := MeshQuality.HIGH8K :
	set(value):
		mesh_quality = value
		mesh = MESH_LOW if mesh_quality == MeshQuality.LOW else (MESH_HIGH if mesh_quality == MeshQuality.HIGH else MESH_HIGH8K)

@export_range(0, 60) var updates_per_second := 50.0 :
	set(value):
		next_update_time = next_update_time - (1.0/(updates_per_second + 1e-10) - 1.0/(value + 1e-10))
		updates_per_second = value

@export var displacement_updates_per_second := 10

var wave_generator : WaveGenerator :
	set(value):
		if wave_generator: wave_generator.queue_free()
		wave_generator = value
		add_child(wave_generator)
var rng = RandomNumberGenerator.new()
var time := 0.0
var next_update_time := 0.0

var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()

var _accumulator = 0.0
var _displacement_update_rate: float
var _img: Image = null
var _img_height: int
var _img_width: int
var map_scales : PackedVector4Array

func get_wave_height(global_position: Vector3) -> float:
	var uv: Vector2 = Vector2(global_position.x, global_position.z)
	var displacement: Vector3 = Vector3.ZERO
	var i = 0
	var scales: Vector4 = map_scales[i]
	var sample_uv: Vector2 = uv * Vector2(scales.x, scales.y)
	displacement += _sample_displacement(i, sample_uv) * scales.z
	return displacement.y

func _init() -> void:
	rng.set_seed(1234)

func _ready() -> void:
	map_scales.resize(len(parameters))
	RenderingServer.global_shader_parameter_set(&'water_color', water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&'foam_color', foam_color.srgb_to_linear())

	if wave_generator:
		_img = wave_generator.retrieve_displacement_map(0, _img)
		_img_height = _img.get_height()
		_img_width = _img.get_width()
	_displacement_update_rate = (1 / displacement_updates_per_second)

func _process(delta : float) -> void:
	if updates_per_second == 0 or time >= next_update_time:
		var target_update_delta := 1.0 / (updates_per_second + 1e-10)
		var update_delta := delta if updates_per_second == 0 else target_update_delta + (time - next_update_time)
		next_update_time = time + target_update_delta
		_update_water(update_delta)
	time += delta

	if wave_generator:
		_accumulator += delta
		if _accumulator >= _displacement_update_rate:
			_accumulator -= _displacement_update_rate
			_img = wave_generator.retrieve_displacement_map(0, _img)

func _setup_wave_generator() -> void:
	if parameters.size() <= 0: return
	for param in parameters:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size()))

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = wave_generator.descriptors[&'displacement_map'].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors[&'normal_map'].rid

	RenderingServer.global_shader_parameter_set(&'num_cascades', parameters.size())
	RenderingServer.global_shader_parameter_set(&'displacements', displacement_maps)
	RenderingServer.global_shader_parameter_set(&'normals', normal_maps)

func _update_scales_uniform() -> void:
	map_scales.resize(len(parameters))
	for i in len(parameters):
		var params := parameters[i]
		var uv_scale := Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale)
	WATER_MAT.set_shader_parameter(&'map_scales', map_scales)

func _update_water(delta : float) -> void:
	if wave_generator == null: _setup_wave_generator()
	wave_generator.update(delta, parameters)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()

func _sample_displacement(cascade: int, uv: Vector2) -> Vector3:
	uv.x = wrapf(uv.x, 0.0, 1.0)
	uv.y = wrapf(uv.y, 0.0, 1.0)
	var x: float = uv.x * (_img_width - 1)
	var y: float = uv.y * (_img_height - 1)
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var x1 = min(x0 + 1, _img_width - 1)
	var y1 = min(y0 + 1, _img_height - 1)
	var fx := x - x0
	var fy := y - y0
	var c00: Color = _img.get_pixel(x0, y0)
	var c10: Color = _img.get_pixel(x1, y0)
	var c01: Color = _img.get_pixel(x0, y1)
	var c11: Color = _img.get_pixel(x1, y1)
	var col_x0 := c00.lerp(c10, fx)
	var col_x1 := c01.lerp(c11, fx)
	var col := col_x0.lerp(col_x1, fy)
	return Vector3(col.r, col.g, col.b)
