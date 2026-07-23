@tool
class_name BuoyancyFxProbeNode
extends MeshInstance3D

const FX_PROBE_COLOR := Color(1.0, 0.62, 0.14, 0.38)
const DISABLED_FX_PROBE_COLOR := Color(0.25, 0.25, 0.25, 0.12)

@export var enabled := true :
	set(value):
		enabled = value
		if _editor_setup_done:
			_update_editor_visuals()

@export var tag := "side"
@export_range(0.01, 10.0, 0.01, "or_greater") var display_radius := 0.12 :
	set(value):
		display_radius = maxf(value, 0.01)
		if _editor_setup_done:
			_update_editor_visuals()

@export_range(-10.0, 10.0, 0.001) var enter_depth_threshold := 0.03
@export_range(-10.0, 10.0, 0.001) var exit_depth_threshold := -0.03

var _editor_setup_done := false


func _enter_tree() -> void:
	_ensure_editor_visuals()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if Engine.is_editor_hint():
		extra_cull_margin = 10000.0
		_ensure_editor_visuals()
	else:
		visible = false
		mesh = null
		material_override = null


func get_enter_depth_threshold(default_value: float) -> float:
	return enter_depth_threshold if enter_depth_threshold > exit_depth_threshold else default_value


func get_exit_depth_threshold(default_value: float) -> float:
	return exit_depth_threshold if enter_depth_threshold > exit_depth_threshold else default_value


func _ensure_editor_visuals() -> void:
	if _editor_setup_done:
		return
	if not Engine.is_editor_hint():
		return
	_editor_setup_done = true
	mesh = SphereMesh.new()
	var sphere := mesh as SphereMesh
	sphere.radius = display_radius
	sphere.height = display_radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = FX_PROBE_COLOR if enabled else DISABLED_FX_PROBE_COLOR
	material_override = material


func _update_editor_visuals() -> void:
	if not Engine.is_editor_hint() or not _editor_setup_done:
		return
	if material_override is StandardMaterial3D:
		material_override.albedo_color = FX_PROBE_COLOR if enabled else DISABLED_FX_PROBE_COLOR
	var sphere := mesh as SphereMesh
	if sphere != null:
		sphere.radius = display_radius
		sphere.height = display_radius * 2.0
