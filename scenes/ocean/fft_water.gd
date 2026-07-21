@tool
extends MeshInstance3D

@export var normal_flipbook: Texture2D:
	set(v):
		normal_flipbook = v
		_update_param(&"u_normal_flipbook", v)
@export var height_flipbook: Texture2D:
	set(v):
		height_flipbook = v
		_update_param(&"u_height_flipbook", v)
@export var foam_flipbook: Texture2D:
	set(v):
		foam_flipbook = v
		_update_param(&"u_foam_flipbook", v)

@export var frames: Vector2 = Vector2(8, 8):
	set(v):
		frames = v
		_update_param(&"u_frames", v)
@export var fps: float = 15.0:
	set(v):
		fps = v
		_update_param(&"u_fps", v)
@export var margin: float = 4.0:
	set(v):
		margin = v
		_update_param(&"u_margin", v)
@export var tex_resolution: float = 512.0:
	set(v):
		tex_resolution = v
		_update_param(&"u_tex_resolution", v)
@export var height_scale: float = 1.5:
	set(v):
		height_scale = v
		_update_param(&"u_height_scale", v)
@export var tiling: float = 4.0:
	set(v):
		tiling = v
		_update_param(&"u_tiling", v)
@export var normal_strength: float = 0.8:
	set(v):
		normal_strength = v
		_update_param(&"u_normal_strength", v)
@export var detail_scale: float = 0.3:
	set(v):
		detail_scale = v
		_update_param(&"u_detail_scale", v)
@export var detail_strength: float = 0.3:
	set(v):
		detail_strength = v
		_update_param(&"u_detail_strength", v)
@export var foam_threshold: float = 0.45:
	set(v):
		foam_threshold = v
		_update_param(&"u_foam_threshold", v)
@export var foam_softness: float = 0.1:
	set(v):
		foam_softness = v
		_update_param(&"u_foam_softness", v)
@export var deep_color: Color = Color(0.0, 0.15, 0.35):
	set(v):
		deep_color = v
		_update_param(&"u_deep_color", v)
@export var shallow_color: Color = Color(0.0, 0.50, 0.60):
	set(v):
		shallow_color = v
		_update_param(&"u_shallow_color", v)
@export var foam_color: Color = Color(1.0, 1.0, 1.0):
	set(v):
		foam_color = v
		_update_param(&"u_foam_color", v)
@export var roughness: float = 0.1:
	set(v):
		roughness = v
		_update_param(&"u_roughness", v)

func _update_param(name: StringName, value: Variant) -> void:
	if not is_inside_tree():
		return
	var mat = material_override
	if mat is ShaderMaterial:
		mat.set_shader_parameter(name, value)

func _ready() -> void:
	if material_override is ShaderMaterial:
		material_override.set_shader_parameter(&"u_normal_flipbook", normal_flipbook)
		material_override.set_shader_parameter(&"u_height_flipbook", height_flipbook)
		material_override.set_shader_parameter(&"u_foam_flipbook", foam_flipbook)
