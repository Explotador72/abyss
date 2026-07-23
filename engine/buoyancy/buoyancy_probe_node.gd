@tool
class_name BuoyancyProbeNode
extends MeshInstance3D

const PROBE_COLOR := Color(0.1, 0.8, 1.0, 0.32)
const DISABLED_PROBE_COLOR := Color(0.25, 0.25, 0.25, 0.12)
const EDITOR_PROBE_RADIUS := 0.16

@export var enabled := true :
	set(value):
		enabled = value
		if _editor_setup_done:
			_update_editor_visuals()

@export_range(0.001, 100000.0, 0.001, "or_greater") var max_submerged_volume_cubic_meters := 1.0
@export_range(0.001, 100.0, 0.001, "or_greater") var buoyancy_height := 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var longitudinal_water_drag_multiplier := 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var lateral_water_drag_multiplier := 1.0

var _material : StandardMaterial3D
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


func get_max_submerged_volume() -> float:
	return max_submerged_volume_cubic_meters


func get_buoyancy_height() -> float:
	return buoyancy_height


func _ensure_editor_visuals() -> void:
	if _editor_setup_done:
		return
	if not Engine.is_editor_hint():
		return
	_editor_setup_done = true
	mesh = SphereMesh.new()
	var sphere := mesh as SphereMesh
	sphere.radius = EDITOR_PROBE_RADIUS
	sphere.height = EDITOR_PROBE_RADIUS * 1.0
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.no_depth_test = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = PROBE_COLOR if enabled else DISABLED_PROBE_COLOR
	material_override = _material


func _update_editor_visuals() -> void:
	if not Engine.is_editor_hint() or not _editor_setup_done:
		return
	if _material != null:
		_material.albedo_color = PROBE_COLOR if enabled else DISABLED_PROBE_COLOR
