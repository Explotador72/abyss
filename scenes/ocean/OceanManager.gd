@tool
class_name OceanManager
extends Node3D

@export_group("Grid")
@export var grid_size: int = 7:
	set(value): grid_size = value; _notify_drawer("grid_changed")
@export var chunk_size: float = 500.0:
	set(value): chunk_size = value; _notify_drawer("grid_changed")
@export var chunk_overlap: float = 0.0:
	set(value): chunk_overlap = value; _notify_drawer("grid_changed")

@export_group("LOD")
@export var lod_center: int = 200:
	set(value): lod_center = value; _notify_drawer("lod_changed")
@export var lod_ring: int = 200:
	set(value): lod_ring = value; _notify_drawer("lod_changed")
@export var lod_outer: int = 60:
	set(value): lod_outer = value; _notify_drawer("lod_changed")

@export_group("Fade")
@export var view_distance: float = 2000.0:
	set(value): view_distance = value; _notify_drawer("params_changed")
@export var fade_start_ratio: float = 0.3:
	set(value): fade_start_ratio = value; _notify_drawer("params_changed")
@export var fade_sharpness: float = 1.5:
	set(value): fade_sharpness = value; _notify_drawer("params_changed")

@export_group("Waves")
@export var wave_scale: float = 3.0:
	set(value): wave_scale = value; _notify_drawer("params_changed")
@export var wave_intensity: float = 0.8:
	set(value): wave_intensity = value; _notify_drawer("params_changed")
@export var wavelength_scale: float = 1.5:
	set(value): wavelength_scale = value; _notify_drawer("params_changed")
@export var wave_speed_scale: float = 1.0:
	set(value): wave_speed_scale = value; _notify_drawer("params_changed")
@export var wave_smoothness: float = 0.85:
	set(value): wave_smoothness = clamp(value, 0.0, 1.0); _notify_drawer("params_changed")

@export_group("FFT Flipbook")
@export var fft_tiling: float = 0.5:
	set(value): fft_tiling = value; _notify_drawer("params_changed")
@export var fft_fps: float = 15.0:
	set(value): fft_fps = value; _notify_drawer("params_changed")
@export var fft_margin: float = 4.0:
	set(value): fft_margin = value; _notify_drawer("params_changed")
@export var fft_tex_resolution: float = 512.0:
	set(value): fft_tex_resolution = value; _notify_drawer("params_changed")
@export var fft_detail_scale: float = 0.3:
	set(value): fft_detail_scale = value; _notify_drawer("params_changed")
@export var fft_detail_strength: float = 0.15:
	set(value): fft_detail_strength = value; _notify_drawer("params_changed")

@export_group("Colors")
@export var shallow_color: Color = Color(0.1, 0.5, 0.48):
	set(value): shallow_color = value; _notify_drawer("params_changed")
@export var deep_color: Color = Color(0.0, 0.05, 0.2):
	set(value): deep_color = value; _notify_drawer("params_changed")
@export var light_color: Color = Color(0.7, 0.85, 0.9):
	set(value): light_color = value; _notify_drawer("params_changed")
@export var depth_gradient_power: float = 1.5:
	set(value): depth_gradient_power = value; _notify_drawer("params_changed")

@export_group("Detail")
@export var normal_detail_scale: float = 0.5:
	set(value): normal_detail_scale = value; _notify_drawer("params_changed")
@export var normal_detail_strength: float = 0.0:
	set(value): normal_detail_strength = value; _notify_drawer("params_changed")
@export var refraction_strength: float = 0.05:
	set(value): refraction_strength = value; _notify_drawer("params_changed")

@export_group("Foam")
@export var foam_residual_density: float = 0.5:
	set(value): foam_residual_density = value; _notify_drawer("params_changed")
@export var foam_residual_threshold: float = 0.3:
	set(value): foam_residual_threshold = value; _notify_drawer("params_changed")
@export var foam_peak_threshold: float = 0.75:
	set(value): foam_peak_threshold = value; _notify_drawer("params_changed")
@export var foam_peak_density: float = 0.8:
	set(value): foam_peak_density = value; _notify_drawer("params_changed")
@export var foam_color: Color = Color(0.95, 0.95, 0.98):
	set(value): foam_color = value; _notify_drawer("params_changed")

@export_group("Specular")
@export var specular_strength: float = 0.8:
	set(value): specular_strength = value; _notify_drawer("params_changed")
@export var specular_shininess: float = 64.0:
	set(value): specular_shininess = value; _notify_drawer("params_changed")

@export_group("Debug")
@export var show_chunks: bool = false:
	set(value): show_chunks = value; _notify_drawer("debug_changed")

var _drawer_ref: Node = null
var _ready_done: bool = false

func _ready() -> void:
	_drawer_ref = _find_drawer()
	_ready_done = true

func _find_drawer() -> Node:
	for child in get_children():
		if child is OceanDrawer:
			return child
	return null

func _notify_drawer(what: String) -> void:
	if not _ready_done:
		return
	if _drawer_ref == null:
		_drawer_ref = _find_drawer()
	if _drawer_ref != null:
		match what:
			"grid_changed":
				_drawer_ref.rebuild_grid()
			"lod_changed":
				_drawer_ref.rebuild_grid()
			_:
				_drawer_ref.sync_params()

func get_wave_height(x: float, z: float, time: float) -> float:
	var h: float = 0.0
	var ws: float = wavelength_scale
	var ox: float = x
	var oz: float = z
	for i in NUM_WAVES:
		var dir_x: float = _wave_dirs[i].x
		var dir_z: float = _wave_dirs[i].y
		var wl: float = _wave_wls[i] * ws
		var amp: float = _wave_amps[i] * wave_scale * wave_intensity
		var phase: float = _wave_phases[i]
		var speed: float = sqrt(9.81 * wl / (2.0 * PI)) * 0.5 * wave_speed_scale
		var theta: float = speed * time + dir_x * ox + dir_z * oz + phase
		h += amp * sin(theta)
	return h

const NUM_WAVES := 4
const _wave_dirs := [
	Vector2(0.8, 0.6), Vector2(-0.7, 0.7), Vector2(-0.9, -0.4),
	Vector2(0.4, -0.9),
]
const _wave_wls := [
	120.0, 70.0, 40.0, 22.0,
]
const _wave_amps := [
	0.6, 0.35, 0.18, 0.08,
]
const _wave_phases := [
	0.0, 1.8, 3.2, 0.7,
]
const _wave_steeps := [
	0.1, 0.08, 0.06, 0.04,
]
