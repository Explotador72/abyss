@tool
class_name OceanSystem
extends MeshInstance3D
## Handles updating the displacement/normal maps for the water material as well as
## managing wave generation pipelines.

const WATER_MAT := preload('res://engine/ocean/shaders/water.gdshader')
const EDITOR_WATER_PREVIEW_MESH := preload('res://engine/ocean/editor_water_preview_mesh.tres')
const MAX_CASCADES := 8
const SURFACE_QUERY_WORKGROUP_SIZE := 64
const SURFACE_QUERY_BYTES_PER_POINT := 16
const SURFACE_QUERY_BYTES_PER_CASCADE := 32
const SURFACE_QUERY_BYTES_PER_SAMPLE := 48
const EXTERNAL_WIND_SPEED_DIRTY_THRESHOLD := 0.25
const EXTERNAL_WIND_DIRECTION_DIRTY_THRESHOLD := 2.0
const EXTERNAL_WIND_SPECTRUM_REFRESH_INTERVAL := 0.5
const WATER_DEBUG_VIEW_NORMAL := 0

@export_group('General Water')
## Base deep-water tint before foam, reflections, and emission are added.
@export_color_no_alpha var water_color : Color = Color(0.04, 0.06, 0.09) :
	set(value):
		water_color = value
		_set_water_shader_parameter(&'water_color', water_color)
## Albedo tint for compute-generated foam mask, manual foam, and hull cutouts.
@export_color_no_alpha var foam_color : Color = Color(1.0, 1.0, 1.0) :
	set(value):
		foam_color = value
		_set_water_shader_parameter(&'foam_color', foam_color)
## Deep-water tint used as shadow base in stylized mode and depth blend in legacy.
@export_color_no_alpha var water_deep_color : Color = Color(0.01, 0.18, 0.34) :
	set(value):
		water_deep_color = value
		_set_water_shader_parameter(&'water_deep_color', water_deep_color)
## Sun-lit tint multiplier for water_color. Affects both stylized and legacy paths.
@export_color_no_alpha var water_lit_tint : Color = Color(1.15, 1.05, 0.85) :
	set(value):
		water_lit_tint = value
		_set_water_shader_parameter(&'water_lit_tint', water_lit_tint)
## Rim (edge) light intensity applied at grazing view angles.
@export_range(0.0, 2.0, 0.01) var water_rim_strength := 0.5 :
	set(value):
		water_rim_strength = value
		_set_water_shader_parameter(&'water_rim_strength', water_rim_strength)
## Overall wave height multiplier for vertex displacement and normal computation.
## When wind_speed_to_height curve is set, this is the MANUAL height used by override_height.
@export_range(0.0, 5.0, 0.01) var height_crest := 1.0 :
	set(value):
		height_crest = value
## Non-linear curve mapping normalized wind speed (0-50m/s -> 0-1) to derived wave height.
## When set, height_crest becomes a manual override blended via override_height.
@export var wind_speed_to_height : Curve
## Blend between wind-derived height and manual height_crest. 0=wind, 1=manual.
@export_range(0.0, 1.0, 0.01) var override_height := 0.0 :
	set(value):
		override_height = value
## Time constant (seconds) for height to rise when wind picks up.
@export_range(0.1, 60.0, 0.1) var height_rise_time := 5.0 :
	set(value):
		height_rise_time = max(value, 0.1)
## Time constant (seconds) for height to fall when wind calms (hysteresis).
@export_range(0.1, 120.0, 0.1) var height_fall_time := 30.0 :
	set(value):
		height_fall_time = max(value, 0.1) 
var _derived_height := 0.0
## Base wave frequency multiplier. Affects how many waves fit in each cascade tile.
@export_range(0.1, 5.0, 0.01) var wave_freq := 1.0 :
	set(value):
		wave_freq = value
		_set_water_shader_parameter(&'wave_freq', wave_freq)
## Detail wave frequency boost applied progressively to higher-index cascades.
@export_range(0.0, 5.0, 0.01) var detail_freq := 1.0 :
	set(value):
		detail_freq = value
		_set_water_shader_parameter(&'detail_freq', detail_freq)
## Wave animation speed. 1.0 = normal.
@export_range(0.0, 5.0, 0.01) var water_speed := 1.0
## Blends between previous and current wave output maps to hide FFT stutter.
@export var smooth_wave_interpolation := true
## Enables bicubic normal filtering for smoother close-up wave detail.
@export var use_bicubic_normals := true :
	set(value):
		use_bicubic_normals = value
		_set_water_shader_parameter(&'use_bicubic_normals', use_bicubic_normals)
## Maximum cascades sampled per pixel for foam and normals.
@export_range(1, 8, 1) var fragment_cascade_limit := 3 :
	set(value):
		fragment_cascade_limit = clampi(value, 1, MAX_CASCADES)
		_set_water_shader_parameter(&'fragment_cascade_limit', fragment_cascade_limit)
## Fallback normalized sun direction in world space.
@export var manual_sun_direction := Vector3(0.0, 0.2, -1.0) :
	set(value):
		manual_sun_direction = value
		_update_sky_lighting_shader_parameters()
## Fallback direct sun color.
@export_color_no_alpha var manual_sun_color : Color = Color(1.0, 0.92, 0.72) :
	set(value):
		manual_sun_color = value
		_update_sky_lighting_shader_parameters()
## Fallback sun visibility. 0 = night, 1 = full sun.
@export_range(0.0, 1.0, 0.01) var manual_sun_visibility := 1.0 :
	set(value):
		manual_sun_visibility = value
		_update_sky_lighting_shader_parameters()

## Strength of depth-based foam that appears around objects touching the water.
@export_range(0.0, 10.0, 0.01) var object_foam_depth_start := 2.83 :
	set(value):
		object_foam_depth_start = value
		_set_water_shader_parameter(&'object_foam_depth_start', object_foam_depth_start)
## How quickly the object foam fades with water depth (higher = more foam further from objects).
@export_range(0.0, 2.0, 0.01) var object_foam_falloff_bias := 0.5 :
	set(value):
		object_foam_falloff_bias = value
		_set_water_shader_parameter(&'object_foam_falloff_bias', object_foam_falloff_bias)
## Scales the leading-edge falloff zone where foam builds up at the water-object boundary.
@export_range(0.0, 1.0, 0.01) var object_foam_leading_edge := 0.15 :
	set(value):
		object_foam_leading_edge = value
		_set_water_shader_parameter(&'object_foam_leading_edge', object_foam_leading_edge)
## Tiling scale of the Voronoi foam pattern around objects.
@export_range(0.1, 20.0, 0.1) var object_foam_pattern_scale := 4.0 :
	set(value):
		object_foam_pattern_scale = value
		_set_water_shader_parameter(&'object_foam_pattern_scale', object_foam_pattern_scale)
## Scroll speed of the object foam noise pattern.
@export_range(0.0, 2.0, 0.01) var object_foam_pattern_scroll := 0.1 :
	set(value):
		object_foam_pattern_scroll = value
		_set_water_shader_parameter(&'object_foam_pattern_scroll', object_foam_pattern_scroll)
## Speed multiplier for the underlying Voronoi cell animation.
@export_range(0.0, 2.0, 0.01) var object_foam_noise_speed := 0.32 :
	set(value):
		object_foam_noise_speed = value
		_set_water_shader_parameter(&'object_foam_noise_speed', object_foam_noise_speed)

## RGB absorption per channel for underwater objects (red absorbs most, blue least).
@export_color_no_alpha var water_absorb : Color = Color(0.55, 0.12, 0.02) :
	set(value):
		water_absorb = value
		_set_water_shader_parameter(&'water_absorb', water_absorb)
## Distance from water surface where underwater effect begins.
@export_range(0.0, 50.0, 0.1) var underwater_depth_start := 0.0 :
	set(value):
		underwater_depth_start = value
		_set_water_shader_parameter(&'underwater_depth_start', underwater_depth_start)
## Distance from water surface where underwater effect maxes out.
@export_range(0.1, 100.0, 0.1) var underwater_depth_end := 20.0 :
	set(value):
		underwater_depth_end = value
		_set_water_shader_parameter(&'underwater_depth_end', underwater_depth_end)
## Water opacity at start depth (0 = transparent, 1 = fully opaque).
@export_range(0.0, 1.0, 0.01) var underwater_opacity_start := 0.0 :
	set(value):
		underwater_opacity_start = value
		_set_water_shader_parameter(&'underwater_opacity_start', underwater_opacity_start)
## Water opacity at end depth (0 = transparent, 1 = fully opaque).
@export_range(0.0, 1.0, 0.01) var underwater_opacity_end := 1.0 :
	set(value):
		underwater_opacity_end = value
		_set_water_shader_parameter(&'underwater_opacity_end', underwater_opacity_end)
## Absorption multiplier for underwater color shift.
@export_range(0.0, 3.0, 0.01) var underwater_absorption := 1.0 :
	set(value):
		underwater_absorption = value
		_set_water_shader_parameter(&'underwater_absorption', underwater_absorption)
## Fresnel highlight color for the water surface.
@export_color_no_alpha var water_fresnel_color : Color = Color(0.05, 0.5, 0.65) :
	set(value):
		water_fresnel_color = value
		_set_water_shader_parameter(&'water_fresnel_color', water_fresnel_color)
## Fresnel reflection strength for underwater visibility at grazing angles.
@export_range(0.0, 1.0, 0.01) var water_fresnel_strength := 0.6 :
	set(value):
		water_fresnel_strength = value
		_set_water_shader_parameter(&'water_fresnel_strength', water_fresnel_strength)

## Overall strength of normal-map lighting.
@export_range(0.0, 1.0, 0.01) var normal_strength := 1.0 :
	set(value):
		normal_strength = value
		_set_water_shader_parameter(&'normal_strength', normal_strength)
## Makes the water look flatter and more stylized. 0 = full detail, 1 = flat shaded.
@export_range(0.0, 1.0, 0.01) var stylized_flatness := 0.0 :
	set(value):
		stylized_flatness = value
		_set_water_shader_parameter(&'stylized_flatness', stylized_flatness)
## Multiplies the foam signal before threshold.
@export_range(0.0, 4.0, 0.01) var foam_intensity := 0.7 :
	set(value):
		foam_intensity = value
		_set_water_shader_parameter(&'foam_intensity', foam_intensity)
## Minimum foam signal required for whitecaps.
@export_range(0.0, 2.0, 0.01) var foam_threshold := 0.6 :
	set(value):
		foam_threshold = value
		_set_water_shader_parameter(&'foam_threshold', foam_threshold)
## Width of the foam transition softness.
@export_range(0.01, 2.0, 0.01) var foam_softness := 0.2 :
	set(value):
		foam_softness = value
		_set_water_shader_parameter(&'foam_softness', foam_softness)

@export_group('Wind')

#optional wind external system
@export var wind_external : NodePath :
	set(value):
		wind_external = value
		wind_source = null
		_reset_external_wind_tracking()
		_mark_spectra_dirty()

## Global wind speed (m/s). When a WindSystem is linked via wind_source_path, that node takes priority.
@export_range(0.0, 100.0, 0.1) var wind_speed := 10.0 :
	set(value):
		wind_speed = maxf(0.0, value)
		_mark_spectra_dirty()
## Global wind direction (degrees, 0=+Z, 90=+X). When a WindSystem is linked, that node takes priority.
@export_range(-360.0, 360.0, 1.0) var wind_direction := 20.0 :
	set(value):
		wind_direction = value
		_mark_spectra_dirty()

@export_group('System')

## Optional sky source node (get_sun_direction / get_sun_color / etc).
@export var sky_source_path : NodePath :
	set(value):
		sky_source_path = value
		sky_source = null
## Ordered list of wave cascades. Edit tile length, wind fetch, etc.
@export var parameters : Array[WaveCascadeParameters] :
	set(value):
		if parameters != null:
			for existing_param in parameters:
				if existing_param and existing_param.scale_changed.is_connected(_update_scales_uniform):
					existing_param.scale_changed.disconnect(_update_scales_uniform)

		var new_parameters := value
		if new_parameters.size() > MAX_CASCADES:
			push_warning("OceanSystem supports at most %d wave cascades. Extra cascades were ignored." % MAX_CASCADES)
			new_parameters.resize(MAX_CASCADES)

		var new_size := len(new_parameters)
		for i in range(new_size):
			if not new_parameters[i]: new_parameters[i] = WaveCascadeParameters.new()
			if not new_parameters[i].is_connected(&'scale_changed', _update_scales_uniform):
				new_parameters[i].scale_changed.connect(_update_scales_uniform)
			new_parameters[i].initialize_runtime_state(
				Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000)),
				120.0 + PI*i
			)
		parameters = new_parameters
		_setup_wave_generator()
		_update_scales_uniform()
## Resolution for displacement/normal texture layers and FFT simulation.
@export_enum('128x128:128', '256x256:256', '512x512:512', '1024x1024:1024') var simulation_map_size := 1024 :
	set(value):
		simulation_map_size = value
		_setup_wave_generator()
## Target wave simulation updates per second. 0 = uncapped.
@export_range(0, 60) var updates_per_second := 20.0 :
	set(value):
		next_update_time = next_update_time - (1.0/(updates_per_second + 1e-10) - 1.0/(value + 1e-10))
		updates_per_second = value
## Still-water height in world units.
@export 	var water_level := 0.0

## Near-ocean mesh radius.
@export_range(32.0, 4096.0, 1.0, "or_greater") var ocean_radius := 256.0 :
	set(value):
		ocean_radius = value
		_update_water_mesh()
## Highest-density center patch side length.
@export_range(16.0, 512.0, 1.0) var mesh_inner_extent := 128.0 :
	set(value):
		mesh_inner_extent = value
		_update_water_mesh()
## Center patch vertex spacing.
@export_range(0.5, 16.0, 0.5) var mesh_base_cell_size := 1.0 :
	set(value):
		mesh_base_cell_size = value
		_update_water_mesh()
## Number of coarser near rings.
@export_range(0, 8, 1) var mesh_ring_count := 2 :
	set(value):
		mesh_ring_count = value
		_update_water_mesh()
## Max arc length between consecutive vertices.
@export_range(1.0, 128.0, 0.5) var target_arc_length := 12.0 :
	set(value):
		target_arc_length = value
		_update_water_mesh()
## Minimum segments per ring.
@export_range(8, 128, 1) var min_ring_segments := 48 :
	set(value):
		min_ring_segments = value
		_update_water_mesh()
## Maximum segments per ring.
@export_range(16, 2048, 1) var max_ring_segments := 512 :
	set(value):
		max_ring_segments = value
		_update_water_mesh()
## Follow active camera in XZ space.
@export var follow_active_camera := true
## Camera-follow grid snap (0 = smooth).
@export_range(0.0, 64.0, 0.25) var follow_snap_size := 0.0
## Follow camera in editor.
@export var follow_camera_in_editor := false
## Enables far-ocean LOD rings and distance-based simplification.

@export_group('Lod')

@export var enable_far_lod := true :
	set(value):
		enable_far_lod = value
		_update_water_mesh()
		_update_far_lod_shader_parameters()
## Far-ocean maximum radius.
@export_range(256.0, 20000.0, 1.0, "or_greater") var far_lod_radius := 7000.0 :
	set(value):
		far_lod_radius = value
		_update_water_mesh()
		_update_far_lod_shader_parameters()
## Number of far-ocean LOD rings.
@export_range(4, 96, 1) var far_lod_ring_count := 36 :
	set(value):
		far_lod_ring_count = value
		_update_water_mesh()
## Near-to-far LOD blend distance.
@export_range(1.0, 4000.0, 1.0) var far_lod_blend_distance := 1400.0 :
	set(value):
		far_lod_blend_distance = value
		_update_far_lod_shader_parameters()
## LOD fade curve exponent.
@export_range(0.25, 4.0, 0.01) var far_lod_curve := 1.8 :
	set(value):
		far_lod_curve = value
		_update_far_lod_shader_parameters()
## Tile length threshold for low-frequency cascades in far LOD.
@export_range(1.0, 512.0, 1.0) var far_low_frequency_tile_length := 32.0 :
	set(value):
		far_low_frequency_tile_length = value
		_update_far_lod_shader_parameters()
## Minimum normal strength retained in far ocean.
@export_range(0.0, 2.0, 0.01) var far_normal_strength := 0.14 :
	set(value):
		far_normal_strength = value
		_update_far_lod_shader_parameters()
## Foam multiplier retained in far ocean.
@export_range(0.0, 1.0, 0.01) var far_foam_coverage := 0.24 :
	set(value):
		far_foam_coverage = value
		_update_far_lod_shader_parameters()
## Extra foam softness boost with distance.
@export_range(0.0, 1.0, 0.01) var far_foam_threshold_boost := 0.2 :
	set(value):
		far_foam_threshold_boost = value
		_update_far_lod_shader_parameters()

var wave_generator : WaveGenerator :
	set(value):
		if wave_generator:
			wave_generator.queue_free()
		wave_generator = value
		if wave_generator:
			add_child(wave_generator)
var rng = RandomNumberGenerator.new()
var time := 0.0
var next_update_time := 0.0
var wind_source : Node
var sky_source : Node
var _last_external_wind_speed := -1.0
var _last_external_wind_direction := -999999.0
var _last_external_wind_spectrum_time := -1.0e20

var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()
var previous_displacement_maps := Texture2DArrayRD.new()
var previous_normal_maps := Texture2DArrayRD.new()
var _has_wave_output := false
var _last_wave_output_time := 0.0
var _wave_blend_start_time := 0.0
var _wave_blend_duration := 1.0 / 60.0
var _surface_query_capacity := 0
var _surface_query_shader := RID()
var _surface_query_pipeline := RID()
var _surface_query_point_buffer
var _surface_query_cascade_buffer
var _surface_query_sample_buffer
var _surface_query_sets := {}
var _surface_query_queued_requests := {}
var _surface_query_pending_requests : Array[Dictionary] = []
var _surface_query_pending_points := PackedVector3Array()
var _surface_query_cached_results := {}
var _surface_query_has_pending_readback := false
var _surface_query_pending_draw_frame := -1

var _last_wave_blend_alpha_sent := -1.0

func _init() -> void:
	rng.set_seed(1234) # This seed gives big waves!

func _ready() -> void:
	process_priority = 100
	add_to_group(&"ocean_system")
	if not Engine.is_editor_hint():
		_ensure_unique_water_material()
	_resolve_wind_source()
	_resolve_sky_source()
	_set_water_shader_parameter(&'water_color', water_color)
	_set_water_shader_parameter(&'foam_color', foam_color)
	_set_water_shader_parameter(&'water_deep_color', water_deep_color)
	_set_water_shader_parameter(&'water_lit_tint', water_lit_tint)
	_set_water_shader_parameter(&'water_rim_strength', water_rim_strength)
	_set_water_shader_parameter(&'wave_freq', wave_freq)
	_set_water_shader_parameter(&'detail_freq', detail_freq)
	_set_wave_blend_alpha(1.0)
	_set_water_shader_parameter(&'normal_strength', normal_strength)
	_set_water_shader_parameter(&'stylized_flatness', stylized_flatness)
	_set_water_shader_parameter(&'use_bicubic_normals', use_bicubic_normals)
	_set_water_shader_parameter(&'fragment_cascade_limit', fragment_cascade_limit)
	_set_water_shader_parameter(&'foam_intensity', foam_intensity)
	_set_water_shader_parameter(&'foam_threshold', foam_threshold)
	_set_water_shader_parameter(&'foam_softness', foam_softness)
	_set_water_shader_parameter(&'object_foam_depth_start', object_foam_depth_start)
	_set_water_shader_parameter(&'object_foam_falloff_bias', object_foam_falloff_bias)
	_set_water_shader_parameter(&'object_foam_leading_edge', object_foam_leading_edge)
	_set_water_shader_parameter(&'object_foam_pattern_scale', object_foam_pattern_scale)
	_set_water_shader_parameter(&'object_foam_pattern_scroll', object_foam_pattern_scroll)
	_set_water_shader_parameter(&'object_foam_noise_speed', object_foam_noise_speed)
	_set_water_shader_parameter(&'water_absorb', water_absorb)
	_set_water_shader_parameter(&'underwater_depth_start', underwater_depth_start)
	_set_water_shader_parameter(&'underwater_depth_end', underwater_depth_end)
	_set_water_shader_parameter(&'underwater_opacity_start', underwater_opacity_start)
	_set_water_shader_parameter(&'underwater_opacity_end', underwater_opacity_end)
	_set_water_shader_parameter(&'underwater_absorption', underwater_absorption)
	_set_water_shader_parameter(&'water_fresnel_color', water_fresnel_color)
	_set_water_shader_parameter(&'water_fresnel_strength', water_fresnel_strength)
	_update_sky_lighting_shader_parameters()
	_update_far_lod_shader_parameters()
	_update_water_mesh()

func _process(delta : float) -> void:
	_update_follow_camera()
	_update_external_wind_state()
	_update_sky_lighting_shader_parameters()
	var speed := water_speed
	var scaled_delta := delta * speed
	# Update waves once every 1.0/updates_per_second.
	if updates_per_second == 0 or time >= next_update_time:
		var target_update_delta := 1.0 / (updates_per_second + 1e-10)
		var update_delta := scaled_delta if updates_per_second == 0 else target_update_delta + (time - next_update_time)
		next_update_time = time + target_update_delta
		_update_water(update_delta)
	time += scaled_delta
	_update_wave_blend_alpha()
	_update_wind_derived_height(delta)
	_dispatch_surface_query_requests()

func _update_wind_derived_height(delta : float) -> void:
	if wind_speed_to_height and wind_speed_to_height.point_count > 0:
		var wind: float = get_external_wind_speed()
		var t: float = clampf(wind / 50.0, 0.0, 1.0)
		var target: float = wind_speed_to_height.sample(t)
		var tau: float = height_rise_time if target > _derived_height else height_fall_time
		_derived_height += (target - _derived_height) * (1.0 - exp(-delta / tau))
		var height_final: float = lerpf(_derived_height, height_crest, override_height)
		_set_water_shader_parameter(&'height_crest', height_final)
	else:
		_set_water_shader_parameter(&'height_crest', height_crest)

func _setup_wave_generator() -> void:
	if parameters.size() <= 0:
		_clear_wave_generator()
		return
	if RenderingServer.get_rendering_device() == null:
		_clear_wave_generator()
		return
	for param in parameters:
		if param:
			param.mark_all_spectra_dirty()

	_reset_surface_query_resources()
	wave_generator = WaveGenerator.new()
	wave_generator.map_size = simulation_map_size
	# The output ping-pong path expects at least two texture-array layers.
	wave_generator.init_gpu(maxi(2, mini(parameters.size(), MAX_CASCADES)))
	wave_generator.output_maps_swapped.connect(_on_wave_output_maps_swapped)
	_has_wave_output = false

	_set_texture_rid(displacement_maps, wave_generator.descriptors[&'displacement_map'].rid)
	_set_texture_rid(normal_maps, wave_generator.descriptors[&'normal_map'].rid)
	_set_texture_rid(previous_displacement_maps, wave_generator.descriptors[&'previous_displacement_map'].rid)
	_set_texture_rid(previous_normal_maps, wave_generator.descriptors[&'previous_normal_map'].rid)

	_set_water_shader_parameter(&'num_cascades', parameters.size())
	_set_water_shader_parameter(&'displacements', displacement_maps)
	_set_water_shader_parameter(&'normals', normal_maps)
	_set_water_shader_parameter(&'previous_displacements', previous_displacement_maps)
	_set_water_shader_parameter(&'previous_normals', previous_normal_maps)
	_set_wave_blend_alpha(1.0)
	_update_scales_uniform()
	_update_spectrum_blend_uniform()

func _update_scales_uniform() -> void:
	var cascade_count := mini(len(parameters), MAX_CASCADES)
	var map_scales : PackedVector4Array; map_scales.resize(cascade_count)
	for i in cascade_count:
		var params := parameters[i]
		if params == null:
			continue
		var uv_scale := Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale)
	_set_water_shader_parameter(&'map_scales', map_scales)
	_update_spectrum_blend_uniform()

func _update_spectrum_blend_uniform() -> void:
	var cascade_count := mini(len(parameters), MAX_CASCADES)
	var spectrum_blend_states : PackedVector4Array; spectrum_blend_states.resize(cascade_count)
	for i in cascade_count:
		var params := parameters[i]
		if params == null:
			continue
		spectrum_blend_states[i] = params.get_spectrum_blend_state(i)
	_set_water_shader_parameter(&'spectrum_blend_states', spectrum_blend_states)

func _update_water(delta : float) -> void:
	if parameters.size() <= 0:
		return
	if wave_generator == null: _setup_wave_generator()
	if wave_generator == null:
		return
	wave_generator.update(delta, parameters, get_external_wind_speed(), get_external_wind_direction(), true)
	_update_spectrum_blend_uniform()

func sample_water_surface(world_position: Vector3, request_owner: Object) -> WaterSurfaceSample:
	var points := PackedVector3Array()
	points.push_back(world_position)
	var samples := sample_water_surface_batch(points, request_owner)
	if samples.is_empty():
		return null
	return samples[0]

func sample_water_surface_batch(points: PackedVector3Array, request_owner: Object) -> Array[WaterSurfaceSample]:
	if points.is_empty():
		return _empty_surface_samples()
	if request_owner == null:
		push_warning("sample_water_surface_batch() requires a stable request_owner so async GPU query results cannot overwrite each other.")
		return _empty_surface_samples()
	return _sample_water_surface_batch_gpu(points, request_owner)

func get_wind_source() -> Node:
	if wind_source == null:
		_resolve_wind_source()
	return wind_source

func get_external_wind_speed() -> float:
	var external_wind := get_wind_source()
	if external_wind != null:
		if external_wind.has_method(&'get_wind_speed'):
			return float(external_wind.call(&'get_wind_speed'))
		var value = external_wind.get(&'wind_speed')
		if value != null:
			return float(value)
	return wind_speed

func get_external_wind_direction() -> float:
	var external_wind := get_wind_source()
	if external_wind != null:
		if external_wind.has_method(&'get_wind_direction'):
			return float(external_wind.call(&'get_wind_direction'))
		var value = external_wind.get(&'wind_direction')
		if value != null:
			return float(value)
	return wind_direction

func get_sky_source() -> Node:
	if sky_source == null:
		_resolve_sky_source()
	return sky_source

func _update_sky_lighting_shader_parameters() -> void:
	var sun_direction := _get_sky_vector(&'get_sun_direction', &'sun_direction', manual_sun_direction)
	if sun_direction.length_squared() < 0.0001:
		sun_direction = Vector3(0.0, 0.2, -1.0)
	sun_direction = sun_direction.normalized()
	_set_water_shader_parameter(&'sky_sun_direction', sun_direction)
	_set_water_shader_parameter(&'sky_sun_color', _get_sky_color(&'get_sun_color', &'sun_color', manual_sun_color))
	_set_water_shader_parameter(&'sky_sun_visibility', _get_sky_float(&'get_sun_visibility', &'sun_visibility', manual_sun_visibility))

func _get_sky_vector(method: StringName, property: StringName, fallback: Vector3) -> Vector3:
	var source := get_sky_source()
	if source != null:
		if source.has_method(method):
			var method_value = source.call(method)
			if method_value is Vector3:
				return method_value
		var property_value = source.get(property)
		if property_value is Vector3:
			return property_value
	return fallback

func _get_sky_color(method: StringName, property: StringName, fallback: Color) -> Color:
	var source := get_sky_source()
	if source != null:
		if source.has_method(method):
			var method_value = source.call(method)
			if method_value is Color:
				return method_value
		var property_value = source.get(property)
		if property_value is Color:
			return property_value
	return fallback

func _get_sky_float(method: StringName, property: StringName, fallback: float) -> float:
	var source := get_sky_source()
	if source != null:
		if source.has_method(method):
			var method_value = source.call(method)
			if method_value != null:
				return float(method_value)
		var property_value = source.get(property)
		if property_value != null:
			return float(property_value)
	return fallback

func _resolve_wind_source() -> void:
	if wind_external.is_empty():
		return
	wind_source = get_node_or_null(wind_external)

func _resolve_sky_source() -> void:
	if sky_source_path.is_empty() or not is_inside_tree():
		return
	sky_source = get_node_or_null(sky_source_path)

func _update_external_wind_state() -> void:
	if not wind_external:
		return
	var current_speed := get_external_wind_speed()
	var current_direction := get_external_wind_direction()
	var speed_changed := absf(current_speed - _last_external_wind_speed) >= EXTERNAL_WIND_SPEED_DIRTY_THRESHOLD
	var direction_changed := _get_wrapped_degrees_delta(current_direction, _last_external_wind_direction) >= EXTERNAL_WIND_DIRECTION_DIRTY_THRESHOLD
	if not speed_changed and not direction_changed:
		return
	if time - _last_external_wind_spectrum_time < EXTERNAL_WIND_SPECTRUM_REFRESH_INTERVAL:
		return
	_last_external_wind_speed = current_speed
	_last_external_wind_direction = current_direction
	_last_external_wind_spectrum_time = time
	if speed_changed:
		_mark_spectra_dirty()

func _reset_external_wind_tracking() -> void:
	_last_external_wind_speed = -1.0
	_last_external_wind_direction = -999999.0
	_last_external_wind_spectrum_time = -1.0e20

func _get_wrapped_degrees_delta(a : float, b : float) -> float:
	return absf(wrapf(a - b + 180.0, 0.0, 360.0) - 180.0)

func _mark_spectra_dirty() -> void:
	if parameters == null:
		return
	for params in parameters:
		if params:
			params.mark_all_spectra_dirty()

func _clear_wave_generator() -> void:
	_reset_surface_query_resources()
	wave_generator = null
	_has_wave_output = false
	_last_wave_output_time = 0.0
	_wave_blend_start_time = 0.0
	_set_texture_rid(displacement_maps, RID())
	_set_texture_rid(normal_maps, RID())
	_set_texture_rid(previous_displacement_maps, RID())
	_set_texture_rid(previous_normal_maps, RID())
	_set_water_shader_parameter(&'num_cascades', 0)
	_set_water_shader_parameter(&'displacements', displacement_maps)
	_set_water_shader_parameter(&'normals', normal_maps)
	_set_water_shader_parameter(&'previous_displacements', previous_displacement_maps)
	_set_water_shader_parameter(&'previous_normals', previous_normal_maps)
	_set_wave_blend_alpha(1.0)

func _update_water_mesh() -> void:
	if Engine.is_editor_hint():
		mesh = EDITOR_WATER_PREVIEW_MESH
		extra_cull_margin = maxf(256.0, EDITOR_WATER_PREVIEW_MESH.size.length() * 0.5)
		_update_far_lod_shader_parameters()
		return

	mesh = _create_generated_clipmap_mesh()
	extra_cull_margin = _get_generated_mesh_half_extent()
	_update_far_lod_shader_parameters()

func _update_follow_camera() -> void:
	if not follow_active_camera:
		return
	if Engine.is_editor_hint() and not follow_camera_in_editor:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	var target_position := global_position
	target_position.x = camera.global_position.x
	target_position.z = camera.global_position.z
	global_position = target_position

func _segments_for_ring(radius: float) -> int:
	return clampi(int(ceil(TAU * radius / maxf(target_arc_length, 0.1))), min_ring_segments, max_ring_segments)

func _create_generated_clipmap_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var radii := _build_circular_clipmap_radii()
	var radial_count := radii.size()

	var ring_segments := PackedInt32Array()
	ring_segments.resize(radial_count)
	ring_segments[0] = 1
	ring_segments[1] = clampi(_segments_for_ring(radii[1]), min_ring_segments, max_ring_segments)
	for i in range(2, radial_count):
		var prev := ring_segments[i - 1]
		var wanted := _segments_for_ring(radii[i])
		var mult := int(ceilf(float(wanted) / float(prev))) * prev
		var max_allowed := (max_ring_segments / prev) * prev
		ring_segments[i] = clampi(mini(mult, mini(max_allowed, prev * 2)), min_ring_segments, max_ring_segments)

	var ring_offsets := PackedInt32Array()
	ring_offsets.resize(radial_count)
	ring_offsets[0] = 0

	vertices.push_back(Vector3.ZERO)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2.ZERO)
	colors.push_back(Color(0.001, 0, 0, 1))

	for ri in range(1, radial_count):
		ring_offsets[ri] = vertices.size()
		var s := ring_segments[ri]
		var r := radii[ri]
		var r_in := radii[ri - 1]
		var r_out := radii[ri + 1] if ri + 1 < radial_count else 1e10
		for k in range(s):
			var angle := TAU * float(k) / float(s)
			var pos := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			vertices.push_back(pos)
			normals.push_back(Vector3.UP)
			uvs.push_back(Vector2(pos.x, pos.z))
			var t_spacing := TAU * r / float(s)
			var r_spacing_in := r - r_in
			var r_spacing_out := r_out - r
			var min_spacing := mini(t_spacing, mini(r_spacing_in, r_spacing_out))
			colors.push_back(Color(min_spacing, 0, 0, 1))

	var s1 := ring_segments[1]
	var off1 := ring_offsets[1]
	for k in range(s1):
		var kn := (k + 1) % s1
		indices.push_back(0)
		indices.push_back(off1 + kn)
		indices.push_back(off1 + k)

	for ri in range(1, radial_count - 1):
		var s_inner := ring_segments[ri]
		var s_outer := ring_segments[ri + 1]
		var off_inner := ring_offsets[ri]
		var off_outer := ring_offsets[ri + 1]

		if s_outer == s_inner:
			for k in range(s_inner):
				var kn := (k + 1) % s_inner
				indices.push_back(off_inner + k)
				indices.push_back(off_outer + k)
				indices.push_back(off_outer + kn)
				indices.push_back(off_inner + k)
				indices.push_back(off_outer + kn)
				indices.push_back(off_inner + kn)
		elif s_outer > s_inner and s_outer % s_inner == 0:
			var ratio := s_outer / s_inner
			for k in range(s_inner):
				var kn := (k + 1) % s_inner
				var base := k * ratio
				for j in range(ratio - 1):
					indices.push_back(off_inner + k)
					indices.push_back(off_outer + (base + j) % s_outer)
					indices.push_back(off_outer + (base + j + 1) % s_outer)
				indices.push_back(off_inner + k)
				indices.push_back(off_outer + (base + ratio - 1) % s_outer)
				indices.push_back(off_inner + kn)
				indices.push_back(off_inner + kn)
				indices.push_back(off_outer + (base + ratio - 1) % s_outer)
				indices.push_back(off_outer + (base + ratio) % s_outer)
				for j in range(1, ratio - 1):
					indices.push_back(off_inner + kn)
					indices.push_back(off_outer + (base + ratio - 1 + j) % s_outer)
					indices.push_back(off_outer + (base + ratio + j) % s_outer)
		else:
			var inner_angle := 0.0
			var outer_angle := 0.0
			var step_inner := TAU / float(s_inner)
			var step_outer := TAU / float(s_outer)
			var i := 0
			var o := 0
			while i < s_inner and o < s_outer:
				var next_inner := inner_angle + step_inner
				var next_outer := outer_angle + step_outer
				if next_outer < next_inner:
					indices.push_back(off_inner + i)
					indices.push_back(off_outer + o)
					indices.push_back(off_outer + (o + 1) % s_outer)
					o += 1
					outer_angle = next_outer
				else:
					indices.push_back(off_inner + i)
					indices.push_back(off_inner + (i + 1) % s_inner)
					indices.push_back(off_outer + o)
					i += 1
					inner_angle = next_inner
			var last_i := maxi(i - 1, 0) if i > 0 else (s_inner - 1)
			var last_o := maxi(o - 1, 0) if o > 0 else (s_outer - 1)
			while i < s_inner:
				indices.push_back(off_inner + i)
				indices.push_back(off_inner + ((i + 1) % s_inner))
				indices.push_back(off_outer + last_o)
				i += 1
			while o < s_outer:
				indices.push_back(off_inner + last_i)
				indices.push_back(off_outer + o)
				indices.push_back(off_outer + ((o + 1) % s_outer))
				o += 1

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

func _build_circular_clipmap_radii() -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	radii.push_back(0.0)

	var base_cell := maxf(mesh_base_cell_size, 0.1)
	var inner_radius := mesh_inner_extent * 0.5
	var outer_radius := maxf(ocean_radius, inner_radius)
	var current_radius := 0.0

	for band in range(mesh_ring_count + 1):
		var band_outer := minf(inner_radius * pow(2.0, band), outer_radius)
		var cell_size := base_cell * pow(2.0, band)
		while current_radius + cell_size < band_outer - 0.001:
			current_radius += cell_size
			radii.push_back(current_radius)
		if radii[radii.size() - 1] < band_outer - 0.001:
			current_radius = band_outer
			radii.push_back(current_radius)

	var outer_cell_size := base_cell * pow(2.0, mesh_ring_count + 1)
	while current_radius + outer_cell_size < outer_radius - 0.001:
		current_radius += outer_cell_size
		radii.push_back(current_radius)

	if radii[radii.size() - 1] < outer_radius - 0.001:
		radii.push_back(outer_radius)

	if enable_far_lod:
		var far_radius := maxf(far_lod_radius, outer_radius)
		var far_ring_count := maxi(far_lod_ring_count, 1)
		for i in range(1, far_ring_count + 1):
			var t := float(i) / float(far_ring_count)
			var eased_t := t * t
			var radius := lerpf(outer_radius, far_radius, eased_t)
			if radius > radii[radii.size() - 1] + 0.001:
				radii.push_back(radius)

	return radii

func _get_generated_mesh_half_extent() -> float:
	var near_extent := maxf(ocean_radius, mesh_inner_extent * 0.5)
	return maxf(near_extent, far_lod_radius) if enable_far_lod else near_extent

func get_ocean_radius() -> float:
	return maxf(ocean_radius, mesh_inner_extent * 0.5)

func _update_far_lod_shader_parameters() -> void:
	_set_water_shader_parameter(&'enable_far_lod', enable_far_lod)
	_set_water_shader_parameter(&'near_ocean_radius', get_ocean_radius())
	_set_water_shader_parameter(&'far_lod_radius', _get_generated_mesh_half_extent())
	_set_water_shader_parameter(&'far_lod_blend_distance', far_lod_blend_distance)
	_set_water_shader_parameter(&'far_lod_curve', far_lod_curve)
	_set_water_shader_parameter(&'far_low_frequency_tile_length', far_low_frequency_tile_length)
	_set_water_shader_parameter(&'far_normal_strength', far_normal_strength)
	_set_water_shader_parameter(&'far_foam_coverage', far_foam_coverage)
	_set_water_shader_parameter(&'far_foam_threshold_boost', far_foam_threshold_boost)





func _is_node_visible_in_tree(node: Node) -> bool:
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	return true


func _set_water_shader_parameter(parameter: StringName, value: Variant) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter(parameter, value)
	else:
		WATER_MAT.set_shader_parameter(parameter, value)


func _ensure_unique_water_material() -> void:
	if material_override is ShaderMaterial:
		material_override = (material_override as ShaderMaterial).duplicate()
	else:
		material_override = WATER_MAT.duplicate()

func _sample_water_surface_batch_gpu(points: PackedVector3Array, request_owner: Object) -> Array[WaterSurfaceSample]:
	_read_surface_query_results_if_ready()
	var owner_key := _get_surface_query_owner_key(request_owner)
	_surface_query_queued_requests[owner_key] = {
		"points": points,
	}
	var cached_samples : Array[WaterSurfaceSample] = _surface_query_cached_results.get(owner_key, _empty_surface_samples())
	if cached_samples.size() != points.size():
		return _empty_surface_samples()
	return cached_samples


func _get_surface_query_owner_key(request_owner: Object) -> int:
	return request_owner.get_instance_id()


func _dispatch_surface_query_requests() -> void:
	_read_surface_query_results_if_ready()
	if _surface_query_has_pending_readback or _surface_query_queued_requests.is_empty():
		return
	if wave_generator == null or wave_generator.context == null:
		if parameters.size() > 0:
			_setup_wave_generator()
	if wave_generator == null or wave_generator.context == null:
		return

	var total_count := 0
	for request in _surface_query_queued_requests.values():
		var request_points : PackedVector3Array = request.get("points", PackedVector3Array())
		total_count += request_points.size()
	if total_count <= 0:
		_surface_query_queued_requests.clear()
		return
	if not _ensure_surface_query_resources(total_count):
		return

	var combined_points := PackedVector3Array()
	combined_points.resize(total_count)
	var dispatch_requests : Array[Dictionary] = []
	var offset := 0
	for owner_key in _surface_query_queued_requests.keys():
		var request : Dictionary = _surface_query_queued_requests[owner_key]
		var request_points : PackedVector3Array = request.get("points", PackedVector3Array())
		var count := request_points.size()
		if count <= 0:
			continue
		for i in count:
			combined_points[offset + i] = request_points[i]
		dispatch_requests.push_back({
			"owner_key": int(owner_key),
			"offset": offset,
			"count": count,
		})
		offset += count
	if offset <= 0:
		_surface_query_queued_requests.clear()
		return
	if offset != total_count:
		combined_points.resize(offset)
		total_count = offset

	var context := wave_generator.context
	var device := context.device
	var point_data := _pack_surface_query_points(combined_points)
	var cascade_data := _pack_surface_query_cascades()
	device.buffer_update(_surface_query_point_buffer.rid, 0, point_data.size(), point_data)
	device.buffer_update(_surface_query_cascade_buffer.rid, 0, cascade_data.size(), cascade_data)

	var current_displacement_rid : RID = wave_generator.descriptors[&'displacement_map'].rid
	var previous_displacement_rid : RID = wave_generator.descriptors[&'previous_displacement_map'].rid
	var uniform_set := _get_surface_query_uniform_set(current_displacement_rid, previous_displacement_rid)
	if not uniform_set.is_valid():
		return

	var groups := int(ceil(float(total_count) / float(SURFACE_QUERY_WORKGROUP_SIZE)))
	var compute_list := context.compute_list_begin()
	device.compute_list_bind_compute_pipeline(compute_list, _surface_query_pipeline)
	device.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	device.compute_list_set_push_constant(
		compute_list,
		RenderingContext.create_push_constant([
			total_count,
			mini(parameters.size(), MAX_CASCADES),
			water_level,
			_get_wave_blend_alpha(),
			maxf(_wave_blend_duration, 1.0 / 60.0),
			0.25,
		]),
		24
	)
	device.compute_list_dispatch(compute_list, groups, 1, 1)
	context.compute_list_end()

	if device != RenderingServer.get_rendering_device():
		context.submit()
		context.sync()
		var byte_count := total_count * SURFACE_QUERY_BYTES_PER_SAMPLE
		var sample_data : PackedByteArray = device.buffer_get_data(_surface_query_sample_buffer.rid, 0, byte_count)
		_store_surface_query_results(combined_points, dispatch_requests, sample_data)
		_surface_query_queued_requests.clear()
		return

	_surface_query_pending_points = combined_points
	_surface_query_pending_requests = dispatch_requests
	_surface_query_pending_draw_frame = Engine.get_frames_drawn()
	_surface_query_has_pending_readback = true
	_surface_query_queued_requests.clear()


func _read_surface_query_results_if_ready() -> void:
	if not _surface_query_has_pending_readback or _surface_query_sample_buffer == null:
		return
	if wave_generator == null or wave_generator.context == null:
		return
	var device := wave_generator.context.device
	if device == RenderingServer.get_rendering_device() and Engine.get_frames_drawn() <= _surface_query_pending_draw_frame:
		return
	var byte_count := _surface_query_pending_points.size() * SURFACE_QUERY_BYTES_PER_SAMPLE
	var sample_data : PackedByteArray = device.buffer_get_data(_surface_query_sample_buffer.rid, 0, byte_count)
	_store_surface_query_results(_surface_query_pending_points, _surface_query_pending_requests, sample_data)
	_surface_query_has_pending_readback = false
	_surface_query_pending_points.clear()
	_surface_query_pending_requests.clear()


func _store_surface_query_results(points: PackedVector3Array, requests: Array[Dictionary], data: PackedByteArray) -> void:
	var samples := _unpack_surface_query_samples(points, data)
	if samples.size() != points.size():
		return
	for request in requests:
		var owner_key := int(request.get("owner_key", 0))
		var offset := int(request.get("offset", 0))
		var count := int(request.get("count", 0))
		var owner_samples : Array[WaterSurfaceSample] = []
		for i in count:
			owner_samples.push_back(samples[offset + i])
		_surface_query_cached_results[owner_key] = owner_samples


func _ensure_surface_query_resources(point_count : int) -> bool:
	if point_count <= 0:
		return false
	if wave_generator == null or wave_generator.context == null:
		return false
	if not wave_generator.descriptors.has(&'displacement_map') or wave_generator.descriptors[&'displacement_map'] == null or not wave_generator.descriptors[&'displacement_map'].rid.is_valid():
		return false
	if not wave_generator.descriptors.has(&'previous_displacement_map') or wave_generator.descriptors[&'previous_displacement_map'] == null or not wave_generator.descriptors[&'previous_displacement_map'].rid.is_valid():
		return false

	var context := wave_generator.context
	if not _surface_query_shader.is_valid():
		_surface_query_shader = context.load_shader('res://engine/ocean/shaders/compute/surface_query.glsl')
	if not _surface_query_pipeline.is_valid():
		_surface_query_pipeline = context.deletion_queue.push(context.device.compute_pipeline_create(_surface_query_shader))
	if point_count <= _surface_query_capacity and _surface_query_point_buffer != null:
		return true

	var capacity := _get_surface_query_capacity(point_count)
	_surface_query_capacity = capacity
	_surface_query_point_buffer = context.create_storage_buffer(capacity * SURFACE_QUERY_BYTES_PER_POINT)
	_surface_query_cascade_buffer = context.create_storage_buffer(MAX_CASCADES * SURFACE_QUERY_BYTES_PER_CASCADE)
	_surface_query_sample_buffer = context.create_storage_buffer(capacity * SURFACE_QUERY_BYTES_PER_SAMPLE)
	_surface_query_sets.clear()
	_surface_query_has_pending_readback = false
	return true

func _get_surface_query_capacity(point_count : int) -> int:
	var capacity := SURFACE_QUERY_WORKGROUP_SIZE
	while capacity < point_count:
		capacity *= 2
	return capacity

func _get_surface_query_uniform_set(current_displacement_rid : RID, previous_displacement_rid : RID) -> RID:
	var key := "%s:%s" % [str(current_displacement_rid), str(previous_displacement_rid)]
	if _surface_query_sets.has(key):
		return _surface_query_sets[key]
	var device := wave_generator.context.device
	var uniforms : Array[RDUniform] = []
	_add_surface_query_uniform(uniforms, 0, _surface_query_point_buffer.type, [_surface_query_point_buffer.rid])
	_add_surface_query_uniform(uniforms, 1, _surface_query_cascade_buffer.type, [_surface_query_cascade_buffer.rid])
	_add_surface_query_uniform(uniforms, 2, _surface_query_sample_buffer.type, [_surface_query_sample_buffer.rid])
	_add_surface_query_uniform(uniforms, 3, wave_generator.descriptors[&'displacement_map'].type, [current_displacement_rid])
	_add_surface_query_uniform(uniforms, 4, wave_generator.descriptors[&'previous_displacement_map'].type, [previous_displacement_rid])
	var uniform_set := wave_generator.context.deletion_queue.push(device.uniform_set_create(uniforms, _surface_query_shader, 0))
	_surface_query_sets[key] = uniform_set
	return uniform_set


func _add_surface_query_uniform(uniforms: Array[RDUniform], binding: int, uniform_type: RenderingDevice.UniformType, ids: Array[RID]) -> void:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = uniform_type
	for id in ids:
		uniform.add_id(id)
	uniforms.push_back(uniform)

func _pack_surface_query_points(points: PackedVector3Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(points.size() * SURFACE_QUERY_BYTES_PER_POINT)
	for i in points.size():
		var offset := i * SURFACE_QUERY_BYTES_PER_POINT
		var point := points[i]
		data.encode_float(offset, point.x)
		data.encode_float(offset + 4, point.y)
		data.encode_float(offset + 8, point.z)
		data.encode_float(offset + 12, 0.0)
	return data

func _pack_surface_query_cascades() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(MAX_CASCADES * SURFACE_QUERY_BYTES_PER_CASCADE)
	for i in mini(parameters.size(), MAX_CASCADES):
		var params := parameters[i]
		if params == null:
			continue
		var uv_scale := Vector2.ONE / params.tile_length
		var blend_state := params.get_spectrum_blend_state(i)
		var offset := i * SURFACE_QUERY_BYTES_PER_CASCADE
		data.encode_float(offset, uv_scale.x)
		data.encode_float(offset + 4, uv_scale.y)
		data.encode_float(offset + 8, params.displacement_scale)
		data.encode_float(offset + 12, params.normal_scale)
		data.encode_float(offset + 16, blend_state.x)
		data.encode_float(offset + 20, blend_state.y)
		data.encode_float(offset + 24, blend_state.z)
		data.encode_float(offset + 28, 0.0)
	return data

func _unpack_surface_query_samples(points: PackedVector3Array, data: PackedByteArray) -> Array[WaterSurfaceSample]:
	if data.size() < points.size() * SURFACE_QUERY_BYTES_PER_SAMPLE:
		return _empty_surface_samples()

	var samples : Array[WaterSurfaceSample] = []
	samples.resize(points.size())
	for i in points.size():
		var offset := i * SURFACE_QUERY_BYTES_PER_SAMPLE
		var sample := WaterSurfaceSample.new()
		sample.position = points[i]
		sample.displacement = Vector3(
			data.decode_float(offset),
			data.decode_float(offset + 4),
			data.decode_float(offset + 8)
		)
		sample.height = data.decode_float(offset + 12)
		sample.normal = Vector3(
			data.decode_float(offset + 16),
			data.decode_float(offset + 20),
			data.decode_float(offset + 24)
		)
		sample.surface_velocity = Vector3(
			data.decode_float(offset + 32),
			data.decode_float(offset + 36),
			data.decode_float(offset + 40)
		)
		samples[i] = sample
	return samples


func _empty_surface_samples() -> Array[WaterSurfaceSample]:
	var samples : Array[WaterSurfaceSample] = []
	return samples


func _reset_surface_query_resources() -> void:
	_surface_query_capacity = 0
	_surface_query_shader = RID()
	_surface_query_pipeline = RID()
	_surface_query_point_buffer = null
	_surface_query_cascade_buffer = null
	_surface_query_sample_buffer = null
	_surface_query_sets.clear()
	_surface_query_queued_requests.clear()
	_surface_query_pending_requests.clear()
	_surface_query_pending_points.clear()
	_surface_query_cached_results.clear()
	_surface_query_has_pending_readback = false
	_surface_query_pending_draw_frame = -1

func _set_texture_rid(texture: Texture2DArrayRD, rid: RID) -> void:
	texture.texture_rd_rid = RID()
	texture.texture_rd_rid = rid

func _on_wave_output_maps_swapped(current_displacement: RID, previous_displacement: RID, current_normal: RID, previous_normal: RID) -> void:
	_set_texture_rid(displacement_maps, current_displacement)
	_set_texture_rid(normal_maps, current_normal)
	if _has_wave_output:
		_set_texture_rid(previous_displacement_maps, previous_displacement)
		_set_texture_rid(previous_normal_maps, previous_normal)
		_wave_blend_duration = maxf(time - _last_wave_output_time, 1.0 / 60.0)
		_wave_blend_start_time = time
		_set_wave_blend_alpha(0.0 if smooth_wave_interpolation else 1.0)
	else:
		_set_texture_rid(previous_displacement_maps, current_displacement)
		_set_texture_rid(previous_normal_maps, current_normal)
		_has_wave_output = true
		_wave_blend_start_time = time
		_set_wave_blend_alpha(1.0)
	_last_wave_output_time = time
	_set_water_shader_parameter(&'displacements', displacement_maps)
	_set_water_shader_parameter(&'normals', normal_maps)
	_set_water_shader_parameter(&'previous_displacements', previous_displacement_maps)
	_set_water_shader_parameter(&'previous_normals', previous_normal_maps)

func _update_wave_blend_alpha() -> void:
	_set_wave_blend_alpha(_get_wave_blend_alpha())

func _get_wave_blend_alpha() -> float:
	if not smooth_wave_interpolation or not _has_wave_output:
		return 1.0
	return clampf((time - _wave_blend_start_time) / maxf(_wave_blend_duration, 1e-5), 0.0, 1.0)


func _set_wave_blend_alpha(value : float) -> void:
	if is_equal_approx(_last_wave_blend_alpha_sent, value):
		return
	_last_wave_blend_alpha_sent = value
	_set_water_shader_parameter(&'wave_blend_alpha', value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()
		previous_displacement_maps.texture_rd_rid = RID()
		previous_normal_maps.texture_rd_rid = RID()
