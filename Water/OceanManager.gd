@tool
extends Node

# Shared ocean parameters — syncs both water surface and underwater FX shaders

@export var sea_height: float = 0.515:
    set(v):
        sea_height = v
        _sync()
@export var sea_choppy: float = 3.207:
    set(v):
        sea_choppy = v
        _sync()
@export var sea_speed: float = 1.0:
    set(v):
        sea_speed = v
        _sync()
@export var sea_freq: float = 0.2:
    set(v):
        sea_freq = v
        _sync()

@export var fade_start: float = 100.0:
    set(v):
        fade_start = v
        _sync()
@export var fade_end: float = 400.0:
    set(v):
        fade_end = v
        _sync()
@export var detail_freq: float = 1.001:
    set(v):
        detail_freq = v
        _sync()
@export var wave_patch_strength: float = 0.065:
    set(v):
        wave_patch_strength = v
        _sync()
@export var wave_crest_color: Color = Color(0.232, 0.232, 0.232):
    set(v):
        wave_crest_color = v
        _sync()
@export var wave_mid_color: Color = Color(0.0, 0.55, 0.75):
    set(v):
        wave_mid_color = v
        _sync()
@export var wave_trough_color: Color = Color(0.0, 0.3, 0.5):
    set(v):
        wave_trough_color = v
        _sync()

@export var white_crest_amount: float = 0.245:
    set(v):
        white_crest_amount = v
        _sync()
@export var white_crest_color: Color = Color(0.895, 0.895, 0.895):
    set(v):
        white_crest_color = v
        _sync()

@export var surface_bubble_spread: float = 0.335:
    set(v):
        surface_bubble_spread = v
        _sync()
@export var surface_bubble_density: float = 0.08:
    set(v):
        surface_bubble_density = v
        _sync()
@export var surface_residue_amount: float = 0.16:
    set(v):
        surface_residue_amount = v
        _sync()
@export var surface_bubble_color: Color = Color(0.697, 0.697, 0.697):
    set(v):
        surface_bubble_color = v
        _sync()
@export var texture_fade_start: float = 0.0:
    set(v):
        texture_fade_start = v
        _sync()
@export var texture_fade_end: float = 514.613:
    set(v):
        texture_fade_end = v
        _sync()
@export var water_level: float = 0.0:
    set(v):
        water_level = v
        _sync()
@export var water_base_height: float = 0.7:
    set(v):
        water_base_height = v
        _sync_fx()
@export var water_level_fudge: float = 0.0:
    set(v):
        water_level_fudge = v
        _sync_fx()
@export var underwater_color: Color = Color(0.02, 0.18, 0.25):
    set(v):
        underwater_color = v
        _sync_fx()
@export var absorption_strength: float = 0.35:
    set(v):
        absorption_strength = v
        _sync_fx()
@export var deep_tint_strength: float = 0.65:
    set(v):
        deep_tint_strength = v
        _sync_fx()
@export var refraction_amount: float = 0.004:
    set(v):
        refraction_amount = v
        _sync_fx()
@export var refraction_speed: float = 0.7:
    set(v):
        refraction_speed = v
        _sync_fx()

@export var water_surface_material: ShaderMaterial
@export var underwater_fx_material: ShaderMaterial

var _syncing: bool = false


func _ready():
    _sync()


func _sync():
    if _syncing:
        return
    _syncing = true

    for mat in [water_surface_material, underwater_fx_material]:
        if not mat:
            continue
        mat.set_shader_parameter(&"sea_height", sea_height)
        mat.set_shader_parameter(&"sea_choppy", sea_choppy)
        mat.set_shader_parameter(&"sea_speed", sea_speed)
        mat.set_shader_parameter(&"sea_freq", sea_freq)
        mat.set_shader_parameter(&"water_level", water_level)

    if water_surface_material:
        water_surface_material.set_shader_parameter(&"detail_freq", detail_freq)
        water_surface_material.set_shader_parameter(&"fade_start", fade_start)
        water_surface_material.set_shader_parameter(&"fade_end", fade_end)
        water_surface_material.set_shader_parameter(&"wave_patch_strength", wave_patch_strength)
        water_surface_material.set_shader_parameter(&"wave_crest_color", wave_crest_color)
        water_surface_material.set_shader_parameter(&"wave_mid_color", wave_mid_color)
        water_surface_material.set_shader_parameter(&"wave_trough_color", wave_trough_color)
        water_surface_material.set_shader_parameter(&"white_crest_amount", white_crest_amount)
        water_surface_material.set_shader_parameter(&"white_crest_color", white_crest_color)
        water_surface_material.set_shader_parameter(&"texture_fade_start", texture_fade_start)
        water_surface_material.set_shader_parameter(&"texture_fade_end", texture_fade_end)
        water_surface_material.set_shader_parameter(&"surface_bubble_spread", surface_bubble_spread)
        water_surface_material.set_shader_parameter(&"surface_bubble_density", surface_bubble_density)
        water_surface_material.set_shader_parameter(&"surface_residue_amount", surface_residue_amount)
        water_surface_material.set_shader_parameter(&"surface_bubble_color", surface_bubble_color)

    _sync_fx()

    _syncing = false


func _sync_fx():
    if not underwater_fx_material:
        return
    underwater_fx_material.set_shader_parameter(&"water_base_height", water_base_height)
    underwater_fx_material.set_shader_parameter(&"water_level_fudge", water_level_fudge)
    underwater_fx_material.set_shader_parameter(&"underwater_color", underwater_color)
    underwater_fx_material.set_shader_parameter(&"absorption_strength", absorption_strength)
    underwater_fx_material.set_shader_parameter(&"deep_tint_strength", deep_tint_strength)
    underwater_fx_material.set_shader_parameter(&"refraction_amount", refraction_amount)
    underwater_fx_material.set_shader_parameter(&"refraction_speed", refraction_speed)
