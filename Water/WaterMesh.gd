@tool
extends MeshInstance3D

# Mirrors main.gdshader parameters. Setters update the material_override directly.
# OceanManager syncs by calling set() on this node — viewport refreshes because
# a Node property changed (unlike raw set_shader_parameter from a separate script).

@export var sea_height: float = 0.515:
	set(v):
		sea_height = v
		if material_override:
			material_override.set_shader_parameter("sea_height", v)
@export var sea_choppy: float = 3.207:
	set(v):
		sea_choppy = v
		if material_override:
			material_override.set_shader_parameter("sea_choppy", v)
@export var sea_speed: float = 1.0:
	set(v):
		sea_speed = v
		if material_override:
			material_override.set_shader_parameter("sea_speed", v)
@export var sea_freq: float = 0.2:
	set(v):
		sea_freq = v
		if material_override:
			material_override.set_shader_parameter("sea_freq", v)

@export var detail_freq: float = 1.001:
	set(v):
		detail_freq = v
		if material_override:
			material_override.set_shader_parameter("detail_freq", v)
@export var fade_start: float = 100.0:
	set(v):
		fade_start = v
		if material_override:
			material_override.set_shader_parameter("fade_start", v)
@export var fade_end: float = 400.0:
	set(v):
		fade_end = v
		if material_override:
			material_override.set_shader_parameter("fade_end", v)
@export var water_level: float = 0.0:
	set(v):
		water_level = v
		if material_override:
			material_override.set_shader_parameter("water_level", v)

@export var wave_patch_strength: float = 0.065:
	set(v):
		wave_patch_strength = v
		if material_override:
			material_override.set_shader_parameter("wave_patch_strength", v)
@export var wave_crest_color: Color = Color(0.232, 0.232, 0.232):
	set(v):
		wave_crest_color = v
		if material_override:
			material_override.set_shader_parameter("wave_crest_color", v)
@export var wave_mid_color: Color = Color(0.0, 0.55, 0.75):
	set(v):
		wave_mid_color = v
		if material_override:
			material_override.set_shader_parameter("wave_mid_color", v)
@export var wave_trough_color: Color = Color(0.0, 0.3, 0.5):
	set(v):
		wave_trough_color = v
		if material_override:
			material_override.set_shader_parameter("wave_trough_color", v)

@export var white_crest_amount: float = 0.245:
	set(v):
		white_crest_amount = v
		if material_override:
			material_override.set_shader_parameter("white_crest_amount", v)
@export var white_crest_color: Color = Color(0.895, 0.895, 0.895):
	set(v):
		white_crest_color = v
		if material_override:
			material_override.set_shader_parameter("white_crest_color", v)

@export var surface_bubble_spread: float = 0.335:
	set(v):
		surface_bubble_spread = v
		if material_override:
			material_override.set_shader_parameter("surface_bubble_spread", v)
@export var surface_bubble_density: float = 0.08:
	set(v):
		surface_bubble_density = v
		if material_override:
			material_override.set_shader_parameter("surface_bubble_density", v)
@export var surface_residue_amount: float = 0.16:
	set(v):
		surface_residue_amount = v
		if material_override:
			material_override.set_shader_parameter("surface_residue_amount", v)
@export var surface_bubble_color: Color = Color(0.697, 0.697, 0.697):
	set(v):
		surface_bubble_color = v
		if material_override:
			material_override.set_shader_parameter("surface_bubble_color", v)

@export var texture_fade_start: float = 0.0:
	set(v):
		texture_fade_start = v
		if material_override:
			material_override.set_shader_parameter("texture_fade_start", v)
@export var texture_fade_end: float = 514.613:
	set(v):
		texture_fade_end = v
		if material_override:
			material_override.set_shader_parameter("texture_fade_end", v)

@export var max_depth: float = 10.0:
	set(v):
		max_depth = v
		if material_override:
			material_override.set_shader_parameter("max_depth", v)
