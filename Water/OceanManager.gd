@tool
extends Node

# Synced Ocean parameters — updates both water surface (via WaterMesh node)
# and underwater FX material. Follows the same pattern as world/OceanManager:
# setters propagate through node properties so the editor viewport refreshes.

# Port of the shader's sea_octave-based wave function for buoyancy probes.
# Mirrors ocean_common.gdshaderinc exactly (hash12 / noise / sea_octave / get_wave_height).

const ITER_GEOMETRY: int = 3
const OCTAVE_M_X: float = 1.6
const OCTAVE_M_Y: float = -1.2
const OCTAVE_M_Z: float = 1.2
const OCTAVE_M_W: float = 1.6

static func _hash12(p: Vector2) -> float:
	var qx: int = (int(p.x) * 1597334677) & 0xFFFFFFFF
	var qy: int = (int(p.y) * 3812015801) & 0xFFFFFFFF
	var n: int = ((qx ^ qy) * 1597334677) & 0xFFFFFFFF
	return float(n) / 4294967295.0

static func _noise(p: Vector2) -> float:
	var i: Vector2 = p.floor()
	var f: Vector2 = p - i
	var ux: float = f.x * f.x * (3.0 - 2.0 * f.x)
	var uy: float = f.y * f.y * (3.0 - 2.0 * f.y)
	var a: float = _hash12(i)
	var b: float = _hash12(i + Vector2.RIGHT)
	var c: float = _hash12(i + Vector2.UP)
	var d: float = _hash12(i + Vector2.ONE)
	return -1.0 + 2.0 * lerp(lerp(a, b, ux), lerp(c, d, ux), uy)

func _sea_octave(uv: Vector2, choppy: float) -> float:
	var nv: float = _noise(uv)
	uv += Vector2(nv, nv)
	var wv_x: float = 1.0 - abs(sin(uv.x))
	var wv_y: float = 1.0 - abs(sin(uv.y))
	var swv_x: float = abs(cos(uv.x))
	var swv_y: float = abs(cos(uv.y))
	wv_x = lerp(wv_x, swv_x, wv_x)
	wv_y = lerp(wv_y, swv_y, wv_y)
	return pow(1.0 - pow(wv_x * wv_y, 0.65), choppy)

# Returns the wave displacement at world position (x, z), matching the shader's get_wave_height().
func get_wave_height(x: float, z: float) -> float:
	var uv := Vector2(x, z)
	uv.x *= 0.75
	var t := Time.get_ticks_msec() / 1000.0

	var freq: float = sea_freq
	var amp: float = sea_height
	var chop: float = sea_choppy
	var height: float = 0.0

	for i in ITER_GEOMETRY:
		var d: float = _sea_octave((uv + Vector2(t, t) * sea_speed) * freq, chop)
		d += _sea_octave((uv - Vector2(t, t) * sea_speed) * freq, chop)
		height += d * amp
		var ux: float = uv.x * OCTAVE_M_X + uv.y * OCTAVE_M_Y
		var uy: float = uv.x * OCTAVE_M_Z + uv.y * OCTAVE_M_W
		uv = Vector2(ux, uy)
		freq *= 1.9
		amp *= 0.22
		chop = lerp(chop, 1.0, 0.2)

	return height

# --- Water surface parameters (synced to WaterMesh node) ---

@export var sea_height: float = 0.515:
	set(v): sea_height = v; _sync_mesh("sea_height", v)
@export var sea_choppy: float = 3.207:
	set(v): sea_choppy = v; _sync_mesh("sea_choppy", v)
@export var sea_speed: float = 1.0:
	set(v): sea_speed = v; _sync_mesh("sea_speed", v)
@export var sea_freq: float = 0.2:
	set(v): sea_freq = v; _sync_mesh("sea_freq", v)

@export var fade_start: float = 100.0:
	set(v): fade_start = v; _sync_mesh("fade_start", v)
@export var fade_end: float = 400.0:
	set(v): fade_end = v; _sync_mesh("fade_end", v)
@export var detail_freq: float = 1.001:
	set(v): detail_freq = v; _sync_mesh("detail_freq", v)
@export var wave_patch_strength: float = 0.065:
	set(v): wave_patch_strength = v; _sync_mesh("wave_patch_strength", v)
@export var wave_crest_color: Color = Color(0.232, 0.232, 0.232):
	set(v): wave_crest_color = v; _sync_mesh("wave_crest_color", v)
@export var wave_mid_color: Color = Color(0.0, 0.55, 0.75):
	set(v): wave_mid_color = v; _sync_mesh("wave_mid_color", v)
@export var wave_trough_color: Color = Color(0.0, 0.3, 0.5):
	set(v): wave_trough_color = v; _sync_mesh("wave_trough_color", v)

@export var white_crest_amount: float = 0.245:
	set(v): white_crest_amount = v; _sync_mesh("white_crest_amount", v)
@export var white_crest_color: Color = Color(0.895, 0.895, 0.895):
	set(v): white_crest_color = v; _sync_mesh("white_crest_color", v)

@export var surface_bubble_spread: float = 0.335:
	set(v): surface_bubble_spread = v; _sync_mesh("surface_bubble_spread", v)
@export var surface_bubble_density: float = 0.08:
	set(v): surface_bubble_density = v; _sync_mesh("surface_bubble_density", v)
@export var surface_residue_amount: float = 0.16:
	set(v): surface_residue_amount = v; _sync_mesh("surface_residue_amount", v)
@export var surface_bubble_color: Color = Color(0.697, 0.697, 0.697):
	set(v): surface_bubble_color = v; _sync_mesh("surface_bubble_color", v)
@export var texture_fade_start: float = 0.0:
	set(v): texture_fade_start = v; _sync_mesh("texture_fade_start", v)
@export var texture_fade_end: float = 514.613:
	set(v): texture_fade_end = v; _sync_mesh("texture_fade_end", v)
@export var max_depth: float = 10.0:
	set(v): max_depth = v; _sync_mesh("max_depth", v)
@export var water_level: float = 0.0:
	set(v): water_level = v; _sync_mesh("water_level", v)

# Absolute world Y of the water surface at rest. Buoyancy probes use:
#   water_surface_y = water_base_y + get_wave_height(x, z)
# Set this to the world Y of the water MeshInstance3D.
@export var water_base_y: float = 0.0

# --- Underwater FX parameters (synced directly to material) ---

@export var water_base_height: float = 0.7:
	set(v): water_base_height = v; _sync_fx()
@export var water_level_fudge: float = 0.0:
	set(v): water_level_fudge = v; _sync_fx()
@export var underwater_color: Color = Color(0.02, 0.18, 0.25):
	set(v): underwater_color = v; _sync_fx()
@export var absorption_strength: float = 0.35:
	set(v): absorption_strength = v; _sync_fx()
@export var deep_tint_strength: float = 0.65:
	set(v): deep_tint_strength = v; _sync_fx()
@export var refraction_amount: float = 0.004:
	set(v): refraction_amount = v; _sync_fx()
@export var refraction_speed: float = 0.7:
	set(v): refraction_speed = v; _sync_fx()

@export var water_surface_material: ShaderMaterial
@export var underwater_fx_material: ShaderMaterial

var _water_mesh: MeshInstance3D = null


func _enter_tree():
	var p = get_parent()
	if p:
		_water_mesh = p.get_node_or_null("MeshInstance3D") as MeshInstance3D
	_sync_all_to_mesh()


func _ready():
	_sync_all_to_mesh()
	_sync_fx()


func _sync_mesh(prop: String, value):
	if not _water_mesh or not is_inside_tree():
		return
	_water_mesh.set(prop, value)


func _sync_all_to_mesh():
	if not _water_mesh:
		return
	for prop in [
		"sea_height", "sea_choppy", "sea_speed", "sea_freq",
		"fade_start", "fade_end", "detail_freq",
		"wave_patch_strength", "wave_crest_color", "wave_mid_color", "wave_trough_color",
		"white_crest_amount", "white_crest_color",
		"surface_bubble_spread", "surface_bubble_density", "surface_residue_amount",
		"surface_bubble_color", "texture_fade_start", "texture_fade_end",
		"water_level", "max_depth",
	]:
		_water_mesh.set(prop, get(prop))


func _sync_fx():
	if not underwater_fx_material:
		return
	var m = underwater_fx_material
	var base_surface_y = water_base_y + water_level
	m.set_shader_parameter(&"water_base_height", base_surface_y)
	m.set_shader_parameter(&"height_offset", base_surface_y)
	m.set_shader_parameter(&"water_level_fudge", water_level_fudge)
	m.set_shader_parameter(&"underwater_color", underwater_color)
	m.set_shader_parameter(&"absorption_strength", absorption_strength)
	m.set_shader_parameter(&"deep_tint_strength", deep_tint_strength)
	m.set_shader_parameter(&"refraction_amount", refraction_amount)
	m.set_shader_parameter(&"refraction_speed", refraction_speed)
