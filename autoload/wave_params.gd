@tool
extends Node

# Synced from OceanManager — all wave parameters the shader uses
var height_scale: float = 2.5
var time_scale: float = 0.7
var wavelength_scale: float = 2.0
var wave_intensity: float = 0.5
var wave_visual_scale: float = 1.2
var wave_density_scale: float = 0.6
var crest_sharpness: float = 1.1

# Shared time, updated every frame by Water.gd _process
var current_time: float = 0.0

# Gerstner wave data — mirrors water.gdshader exactly
const DIRECTIONS: Array[Vector2] = [
	Vector2(0.9, 0.3), Vector2(-0.3, 0.9), Vector2(0.4, -0.8), Vector2(-0.8, -0.4),
	Vector2(0.7, 0.6), Vector2(-0.5, 0.3), Vector2(0.1, -0.3), Vector2(-0.2, -0.9)
]
const WAVELENGTHS: Array[float] = [20.0, 16.0, 10.0, 7.0, 5.0, 3.5, 2.5, 2.0]
const AMPLITUDES: Array[float] = [1.0, 0.7, 0.45, 0.3, 0.22, 0.15, 0.10, 0.07]

func get_wave_height(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var t := current_time

	# Wave group envelope (matches shader)
	var env1: float = sin(pos.dot(Vector2(0.025, 0.035)) + t * 0.04) * 0.5 + 0.5
	var env2: float = sin(pos.dot(Vector2(-0.018, 0.04)) + t * 0.03) * 0.5 + 0.5
	var envelope: float = lerp(env1, env2, 0.5) * 0.4 + 0.6

	var height: float = 0.0
	for i in 8:
		var wl: float = WAVELENGTHS[i] * maxf(wavelength_scale, 0.1) / maxf(wave_density_scale, 0.01)
		var amp: float = AMPLITUDES[i] * height_scale * wave_intensity * envelope * wave_visual_scale
		var k := TAU / wl
		var c := sqrt(9.8 / k)
		var dir := DIRECTIONS[i].normalized()
		var f := k * dir.dot(pos) + c * t
		height += amp * sin(f)

	return height
