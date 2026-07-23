shader_type spatial;
render_mode world_vertex_coords, cull_disabled, shadows_disabled, unshaded, blend_mix, depth_draw_always;
/**
 * Stylized unshaded water with cartoon lighting.
 * Displacement, normals, foam, and flat shading.
 */

#define MAX_CASCADES 8

group_uniforms general;
uniform vec4 water_color : source_color = vec4(0.0, 0.58, 0.867, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 water_deep_color : source_color = vec4(0.01, 0.18, 0.34, 1.0);
uniform vec4 water_lit_tint : source_color = vec4(1.15, 1.05, 0.85, 1.0);
uniform float water_rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform vec3 sky_sun_direction = vec3(0.0, 0.2, -1.0);
uniform vec4 sky_sun_color : source_color = vec4(1.0, 0.92, 0.72, 1.0);
uniform float sky_sun_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float foam_intensity : hint_range(0.0, 2.0) = 0.539;
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.235;
uniform float foam_softness : hint_range(0.01, 2.0) = 0.35;
uniform bool use_bicubic_normals = true;
uniform int fragment_cascade_limit : hint_range(1, 8) = 3;
uniform bool enable_far_lod = true;
uniform float near_ocean_radius = 256.0;
uniform float far_lod_radius = 7000.0;
uniform float far_lod_blend_distance : hint_range(1.0, 4000.0) = 1400.0;
uniform float far_lod_curve : hint_range(0.25, 4.0) = 1.8;
uniform float far_low_frequency_tile_length : hint_range(1.0, 512.0) = 32.0;
uniform float far_normal_strength : hint_range(0.0, 2.0) = 0.14;
uniform float far_foam_coverage : hint_range(0.0, 1.0) = 0.24;
uniform float far_foam_threshold_boost : hint_range(0.0, 1.0) = 0.2;
uniform float height_crest : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float wave_freq : hint_range(0.1, 5.0, 0.01) = 1.0;
uniform float detail_freq : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float water_speed : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform int water_debug_view : hint_range(0, 3) = 0;
uniform float object_foam_depth_start : hint_range(0.0, 10.0, 0.01) = 2.83;
uniform float object_foam_falloff_bias : hint_range(0.0, 2.0) = 0.5;
uniform float object_foam_leading_edge : hint_range(0.0, 1.0) = 0.15;
uniform float object_foam_pattern_scale : hint_range(0.1, 20.0) = 4.0;
uniform float object_foam_pattern_scroll : hint_range(0.0, 2.0) = 0.1;
uniform float object_foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 0.32;
uniform vec3 water_absorb : source_color = vec3(0.918, 0.918, 0.918);
uniform float water_absorb_distance : hint_range(1.0, 100.0) = 6;
uniform vec3 water_fresnel_color : source_color = vec3(0.05, 0.5, 0.65);
uniform float water_fresnel_strength : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES];               // Scales for displacement/normal maps. Packed: [uv scale, displacement scale, normal scale]
uniform vec4 spectrum_blend_states[MAX_CASCADES];    // Packed: [active layer, pending layer, blend alpha, unused]
uniform int num_cascades = 0;
uniform sampler2DArray displacements;         // Each layer represents one wave cascade.
uniform sampler2DArray normals : hint_normal; // Each layer represents one wave cascade.
uniform sampler2DArray previous_displacements;
uniform sampler2DArray previous_normals : hint_normal;
uniform float wave_blend_alpha = 1.0;

varying float foam_factor;
varying float distance_to_camera;
varying float distance_lod;
varying vec3 water_world_position;

float get_distance_lod(float dist) {
	if (!enable_far_lod) {
		return 0.0;
	}
	float linear_lod = smoothstep(near_ocean_radius * 0.75, near_ocean_radius + far_lod_blend_distance, dist);
	return pow(linear_lod, far_lod_curve);
}

float get_cascade_lod_weight(vec4 scales, float lod) {
	if (!enable_far_lod || lod <= 0.0) {
		return 1.0;
	}
	float tile_length = 1.0 / max(min(scales.x, scales.y), 0.0001);
	float far_weight = smoothstep(far_low_frequency_tile_length * 0.55, far_low_frequency_tile_length * 1.35, tile_length);
	return mix(1.0, far_weight, lod);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float voronoi_foam(vec2 uv) {
	vec2 n = floor(uv);
	vec2 f = fract(uv);
	float m_dist = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			o = 0.5 + 0.5 * sin(TIME * object_foam_noise_speed + 6.2831 * o);
			vec2 r = g - f + o;
			float d = dot(r, r);
			m_dist = min(m_dist, d);
		}
	}
	return m_dist;
}

float fbm_voronoi(vec2 uv) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 2; i++) {
		float val = 1.0 - voronoi_foam(uv);
		val = pow(val, 2.0);
		v += a * val;
		uv = rot * uv * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

float get_linear_depth(sampler2D d_tex, vec2 uv, mat4 inv_proj) {
	float depth = texture(d_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -view.z / view.w;
}

void vertex() {
	UV = VERTEX.xz;
	distance_to_camera = length(VERTEX.xz);
	distance_lod = get_distance_lod(distance_to_camera);

	// Read displacements from displacement maps.
	vec3 displacement = vec3(0);
	for (uint i = 0U; i < uint(num_cascades); ++i) {
		vec4 scales = map_scales[i];
		if (scales.z == 0.0)
			continue;
		float cascade_weight = get_cascade_lod_weight(scales, distance_lod);
		if (cascade_weight <= 0.0)
			continue;
		vec4 blend_state = spectrum_blend_states[i];
		vec3 active_coords = vec3(UV * scales.xy * wave_freq, blend_state.x);
		vec3 pending_coords = vec3(UV * scales.xy * wave_freq, blend_state.y);
		vec3 previous_active = texture(previous_displacements, active_coords).xyz;
		vec3 current_active = texture(displacements, active_coords).xyz;
		vec3 previous_pending = texture(previous_displacements, pending_coords).xyz;
		vec3 current_pending = texture(displacements, pending_coords).xyz;
		vec3 active_displacement = mix(previous_active, current_active, wave_blend_alpha);
		vec3 pending_displacement = mix(previous_pending, current_pending, wave_blend_alpha);
		displacement += mix(active_displacement, pending_displacement, blend_state.z) * scales.z * height_crest * cascade_weight;
	}
	VERTEX += displacement;
	water_world_position = VERTEX;
}

/** Filter weights for a cubic B-spline. */
vec4 cubic_weights(float a) {
	float a2 = a*a;
	float a3 = a2*a;
	
	float w0 =-a3     + a2*3.0 - a*3.0 + 1.0;
	float w1 = a3*3.0 - a2*6.0         + 4.0;
	float w2 =-a3*3.0 + a2*3.0 + a*3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

/** Performs bicubic B-spline filtering on the provided sampler. */
// Source: https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-20-fast-third-order-texture-filtering
vec4 texture_bicubic(in sampler2DArray sampler, in vec3 uvw) {
	vec2 dims = vec2(textureSize(sampler, 0).xy);
	vec2 dims_inv = 1.0 / dims;
	uvw.xy = uvw.xy*dims + 0.5;
	
	vec2 fuv = fract(uvw.xy);
	vec4 wx = cubic_weights(fuv.x);
	vec4 wy = cubic_weights(fuv.y);

	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy)*dims_inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
    return mix(
		mix(texture(sampler, vec3(h.yw, uvw.z)), texture(sampler, vec3(h.xw, uvw.z)), w.x),
		mix(texture(sampler, vec3(h.yz, uvw.z)), texture(sampler, vec3(h.xz, uvw.z)), w.x), w.y); 
}

float saturate(float value) {
	return clamp(value, 0.0, 1.0);
}

vec3 safe_normalize_vec3(vec3 value, vec3 fallback) {
	if (dot(value, value) < 0.000001) {
		return fallback;
	}
	return normalize(value);
}

float safe_smoothstep(float edge0, float edge1, float value) {
	return smoothstep(edge0, max(edge1, edge0 + 0.0001), value);
}


void fragment() {
	float dist = length(water_world_position.xz - CAMERA_POSITION_WORLD.xz);
	float fragment_distance_lod = get_distance_lod(dist);
	vec2 gradient = vec2(0.0);
	float foam_signal = 0.0;
	foam_factor = 0.0;
	vec3 world_normal = vec3(0.0, 1.0, 0.0);

	// Water depth and scene thickness
	float water_linear = -VERTEX.z;
	float scene_linear = get_linear_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(0.0, scene_linear - water_linear);

	// Depth-based object foam
	float object_foam = 0.0;
	if (scene_linear > water_linear) {
		vec2 w_uv = water_world_position.xz * 1.5;
		vec2 uv_a = w_uv * object_foam_pattern_scale - vec2(object_foam_pattern_scroll, cos(w_uv.x));
		vec2 uv_b = w_uv * object_foam_pattern_scale * 0.5 + vec2(sin(w_uv.y), object_foam_pattern_scroll);
		float channelA = fbm_voronoi(uv_a);
		float channelB = fbm_voronoi(uv_b);
		float mask_val = (channelA + channelB) * 0.95;
		mask_val = pow(mask_val, 2.0);
		mask_val = clamp(mask_val, 0.0, 1.0);
		if (thickness < object_foam_depth_start * object_foam_leading_edge) {
			float frac = thickness / max(object_foam_depth_start * object_foam_leading_edge, 0.001);
			mask_val *= clamp(frac, 0.0, 1.0);
		}
		float falloff = 1.0 - (thickness / object_foam_depth_start) + object_foam_falloff_bias;
		falloff = clamp(falloff, 0.0, 1.0);
		object_foam = clamp(falloff * foam_intensity - mask_val, 0.0, 1.0);
	}

	if (num_cascades > 0) {
		float map_size = float(textureSize(normals, 0).x);
		// Read foam and normal information from normal maps.
		uint cascade_count = min(uint(num_cascades), uint(fragment_cascade_limit));
		for (uint i = 0U; i < cascade_count; ++i) {
			vec4 scales = map_scales[i];
			float cascade_weight = get_cascade_lod_weight(scales, fragment_distance_lod);
			if (cascade_weight <= 0.0)
				continue;
			vec4 blend_state = spectrum_blend_states[i];
			vec3 active_coords = vec3(UV * scales.xy * wave_freq, blend_state.x);
			vec3 pending_coords = vec3(UV * scales.xy * wave_freq, blend_state.y);
			vec4 previous_active_sample = texture(previous_normals, active_coords);
			vec4 current_active_sample = texture(normals, active_coords);
			vec4 previous_pending_sample = texture(previous_normals, pending_coords);
			vec4 current_pending_sample = texture(normals, pending_coords);
			if (use_bicubic_normals) {
				float ppm = map_size * min(scales.x, scales.y); // Pixels per meter
				// Mix between bicubic and bilinear filtering depending on the world space pixels per meter.
				// This is dependent on the tile size as well as displacement/normal map resolution.
				previous_active_sample = mix(texture_bicubic(previous_normals, active_coords), previous_active_sample, min(1.0, ppm*0.1));
				current_active_sample = mix(texture_bicubic(normals, active_coords), current_active_sample, min(1.0, ppm*0.1));
				previous_pending_sample = mix(texture_bicubic(previous_normals, pending_coords), previous_pending_sample, min(1.0, ppm*0.1));
				current_pending_sample = mix(texture_bicubic(normals, pending_coords), current_pending_sample, min(1.0, ppm*0.1));
			}
			vec4 active_sample = mix(previous_active_sample, current_active_sample, wave_blend_alpha);
			vec4 pending_sample = mix(previous_pending_sample, current_pending_sample, wave_blend_alpha);
			vec4 normal_sample = mix(active_sample, pending_sample, blend_state.z);
			float detail_weight = 1.0 + (detail_freq - 1.0) * float(i) / max(float(cascade_count - 1U), 1.0);
			vec2 normal_signal = normal_sample.xy * scales.w * cascade_weight * detail_weight;
			gradient += normal_signal;
			foam_signal += normal_sample.w * cascade_weight;
		}

		float visible_foam_signal = foam_signal * 0.75 * foam_intensity;
		float far_foam_softness = foam_softness * (1.0 + far_foam_threshold_boost * fragment_distance_lod * 4.0);
		float foam_distance_fade = mix(1.0, far_foam_coverage, fragment_distance_lod);
		float stylized_foam_raw = smoothstep(foam_threshold, foam_threshold + far_foam_softness, visible_foam_signal);
		stylized_foam_raw = stylized_foam_raw * stylized_foam_raw * (3.0 - 2.0 * stylized_foam_raw);
		foam_factor = stylized_foam_raw * exp(-dist*0.0075) * foam_distance_fade;
		foam_factor = max(foam_factor, object_foam);

		float near_normal_fade = exp(-dist*0.0175);
		float far_normal_fade = far_normal_strength * 0.35;
		gradient *= normal_strength * mix(max(near_normal_fade, 0.015), far_normal_fade, fragment_distance_lod);
		world_normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
		NORMAL = (VIEW_MATRIX * vec4(world_normal, 0.0)).xyz;
	}
	foam_factor = max(foam_factor, object_foam);

	vec3 view_direction_world = safe_normalize_vec3(CAMERA_POSITION_WORLD - water_world_position, vec3(0.0, 0.0, 1.0));
	vec3 sun_dir = safe_normalize_vec3(sky_sun_direction, vec3(0.0, 0.2, -1.0));
	float no_v = saturate(dot(world_normal, view_direction_world));

	if (water_debug_view == 1) {
		ALBEDO = world_normal * 0.5 + 0.5;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(0.0);
		ALPHA = 1.0;
	} else if (water_debug_view == 2) {
		ALBEDO = texture(screen_tex, SCREEN_UV).rgb;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(0.0);
		ALPHA = 1.0;
	} else if (water_debug_view == 3) {
		float dbg = thickness / 10.0;
		ALBEDO = vec3(clamp(dbg, 0.0, 1.0), clamp(1.0 - dbg, 0.0, 1.0), 0.0);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(0.0);
		ALPHA = 1.0;
	} else {
		float clean_ndotl = saturate(dot(world_normal, sun_dir));
		vec3 c_shadow = water_deep_color.rgb;
		vec3 c_mid = water_color.rgb;
		vec3 c_lit = water_color.rgb * max(water_lit_tint.rgb, vec3(1.0));
		vec3 c_foam = foam_color.rgb;
		vec3 clean_col = mix(c_shadow, c_mid, smoothstep(0.25, 0.45, clean_ndotl));
		clean_col = mix(clean_col, c_lit, smoothstep(0.55, 0.80, clean_ndotl));
		clean_col = mix(clean_col, c_foam, saturate(foam_factor));
		float clean_spec_dot = pow(max(dot(view_direction_world, reflect(-sun_dir, world_normal)), 0.0), 8.0) * exp(-dist * 0.004) * (1.0 - foam_factor);
		clean_col += sky_sun_color.rgb * clean_spec_dot * 0.25;
		float clean_rim_l = pow(1.0 - saturate(no_v), 2.5) * water_rim_strength;
		clean_col *= 1.0 + clean_rim_l * 0.4;

		// Sample scene behind water via screen texture
		vec3 scene_color = texture(screen_tex, SCREEN_UV).rgb;

		// Fresnel
		float fresnel = pow(1.0 - no_v, 2.0);

		// Compose final color
		vec3 final_col;
		if (scene_linear > water_linear) {
			// Underwater absorption
			vec3 absorb = water_absorb;
			float depth_blend = clamp(thickness / water_absorb_distance, 0.0, 1.0);
			depth_blend = 1.0 - exp(-depth_blend * 4.5);
			vec3 underwater_col = clamp(scene_color - absorb * depth_blend, 0.0, 1.0);
			vec3 leftover = vec3(1.0) - absorb;
			underwater_col = mix(underwater_col, leftover, depth_blend * depth_blend);

			// Water opacity based on thickness and fresnel
			float water_alpha = 1.0 - exp(-thickness / water_absorb_distance * 4.0);
			water_alpha = mix(water_alpha, 1.0, fresnel * water_fresnel_strength);
			water_alpha = max(water_alpha, foam_factor);

			// Mix absorbed scene with stylized water
			final_col = mix(underwater_col, clean_col, water_alpha);
		} else {
			final_col = clean_col;
		}

		// Fresnel highlight on top
		final_col = mix(final_col, water_fresnel_color, fresnel * water_fresnel_strength * (1.0 - foam_factor));

		ALBEDO = clamp(final_col, 0.0, 1.0);
		EMISSION = vec3(0.0);
		ALPHA = 1.0;
	}
}
