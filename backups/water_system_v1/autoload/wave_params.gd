@tool
extends Node

# Sync parameters (set by OceanManager → Water.gd)
var height_scale: float = 2.5
var time_scale: float = 0.7
var wavelength_scale: float = 2.0
var wave_intensity: float = 0.5
var wave_visual_scale: float = 1.2
var wave_density_scale: float = 0.6
var crest_sharpness: float = 1.1
var sub_wave_scale: float = 1.0

# Shared time, updated every frame by Water.gd _process
# Equivale a u_time * 0.39 en el shader
var current_time: float = 0.0

# Gerstner wave data — IDÉNTICO a water.gdshader
const DIRECTIONS: Array[Vector2] = [
	Vector2(0.95, 0.31), Vector2(-0.26, 0.97), Vector2(0.42, -0.91), Vector2(-0.77, -0.64),
	Vector2(0.71, 0.70), Vector2(-0.59, 0.81), Vector2(0.17, -0.99), Vector2(-0.37, -0.93),
	Vector2(0.87, -0.50), Vector2(-0.94, 0.35), Vector2(0.99, 0.12), Vector2(-0.09, -0.50),
	Vector2(0.30, 0.95), Vector2(-0.85, 0.52), Vector2(0.60, -0.80), Vector2(-0.50, -0.86)
]
const WAVELENGTHS: Array[float] = [24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5, 0.35, 0.22, 0.14, 0.08]
const AMPLITUDES: Array[float] = [0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03, 0.018, 0.01, 0.006, 0.003]

# Devuelve altura y gradiente del oleaje en (x, z) — réplica exacta del vertex shader
func get_wave_height(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var t := current_time

	# Wave group envelope (idéntico al shader)
	var env_dir1 := Vector2(0.025, 0.035)
	var env_dir2 := Vector2(-0.018, 0.04)
	var env1: float = sin(pos.dot(env_dir1) + t * 0.04) * 0.5 + 0.5
	var env2: float = sin(pos.dot(env_dir2) + t * 0.03) * 0.5 + 0.5
	var envelope: float = lerp(env1, env2, 0.5) * 0.4 + 0.6

	var height: float = 0.0
	for i in 16:
		var seed := float(i) * 2.399
		var wl: float = WAVELENGTHS[i] * maxf(wavelength_scale, 0.1) / maxf(wave_density_scale, 0.01)
		var amp: float = AMPLITUDES[i] * height_scale * wave_intensity * envelope * wave_visual_scale
		if i >= 12:
			amp *= sub_wave_scale

		var k := TAU / wl
		var c := sqrt(9.8 / k)

		# Direction jitter (idéntico al shader)
		var jitter_strength: float = 0.06 + (1.0 - AMPLITUDES[i] / 0.9) * 0.5
		var jx := sin(pos.x * 0.025 + pos.y * 0.018 + seed) * jitter_strength
		var jy := cos(pos.x * 0.018 + pos.y * 0.025 + seed * 1.3) * jitter_strength
		var dir := Vector2(DIRECTIONS[i].x + jx, DIRECTIONS[i].y + jy).normalized()

		# Phase offset (idéntico al shader)
		var phase_off: float = sin(pos.x * 0.01 + pos.y * 0.014 + seed) * 2.0
		phase_off += sin(pos.x * 0.02 - pos.y * 0.012 + seed * 1.7) * 1.2

		var f := k * dir.dot(pos) + c * t + phase_off
		height += amp * sin(f)

	return height
