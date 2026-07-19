shader_type spatial;

uniform float sea_height    : hint_range(0.0, 5.0)  = 0.515;
uniform float sea_choppy    : hint_range(0.0, 10.0) = 3.207;
uniform float sea_speed     : hint_range(0.0, 5.0)  = 1.0;
uniform float sea_freq      : hint_range(0.0, 2)  = 0.2;

const int ITER_GEOMETRY = 3;
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(p)) * uvec2(1597334677u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);
    vec2 wv = 1.0 - abs(sin(uv));
    vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

float get_wave_height(vec2 pos_xz) {
    vec2 uv = pos_xz;
    uv.x *= 0.75;

    float freq = sea_freq;
    float amp  = sea_height;
    float chop = sea_choppy;
    float height = 0.0;

    for (int i = 0; i < ITER_GEOMETRY; i++) {
        float d = sea_octave((uv + TIME * sea_speed)     * freq, chop);
        d +=      sea_octave((uv - TIME * sea_speed)     * freq, chop);
        height += d * amp;
        uv     *= octave_m;
        freq   *= 1.9;
        amp    *= 0.22;
        chop   = mix(chop, 1.0, 0.2);
    }

    return height;
}

uniform sampler2D depth_tex : hint_depth_texture;
uniform float detail_freq : hint_range(0.0, 5.0) = 1.001;

// distance fade: waves flatten with distance from camera
uniform float fade_start : hint_range(0.0, 5000.0) = 100.0;
uniform float fade_end   : hint_range(0.0, 5000.0) = 400.0;
// detail frequency reduces from texture_fade_start to texture_fade_end
uniform float texture_fade_start : hint_range(0.0, 5000.0) = 0.0;
uniform float texture_fade_end   : hint_range(0.0, 5000.0) = 514.613;

uniform float max_depth : hint_range(0.1, 50.0, 0.1) = 10.0;
uniform float water_level : hint_range(-10.0, 10.0, 0.1) = 0.0;

uniform sampler2D screen_tex : hint_screen_texture;
uniform vec3 underwater_fog_color : source_color = vec3(0.0, 0.308, 0.48);
uniform float fade_start_depth : hint_range(0.0, 50.0, 0.1) = 0.0;

uniform int ITER_FRAGMENT = 1;

// refraction settings
uniform float refraction_strength : hint_range(0.0, 2.0, 0.01) = 0.97;
uniform float refraction_distance_fade : hint_range(0.0, 100.0, 1.0) = 5.0;
// for smoothness part
uniform float normal_epsilon : hint_range(0.001, 1.0) = 0.18;

uniform vec3 base_tint_color : source_color = vec3(0.0, 0.9, 0.75);
uniform vec3 deep_color : source_color = vec3(0.0, 0.1, 0.3);
uniform vec3 water_absorption : source_color = vec3(0.0, 0.0, 0.0);

// wave-height color patches (cartoon style — posterized bands)
uniform float wave_patch_strength : hint_range(0.0, 1.0) = 0.065;
uniform vec3  wave_crest_color   : source_color = vec3(0.232, 0.232, 0.232);
uniform vec3  wave_mid_color     : source_color = vec3(0.0, 0.55, 0.75);
uniform vec3  wave_trough_color  : source_color = vec3(0.0, 0.3, 0.5);

// white crests
uniform float white_crest_amount : hint_range(0.0, 2.0) = 0.245;
uniform vec3  white_crest_color   : source_color = vec3(0.895, 0.895, 0.895);
uniform float surface_bubble_spread   : hint_range(0.0, 2.0) = 0.335;
uniform float surface_bubble_density  : hint_range(0.0, 2.0) = 0.08;
uniform float surface_residue_amount  : hint_range(0.0, 2.0) = 0.16;
uniform vec3  surface_bubble_color    : source_color = vec3(0.697, 0.697, 0.697);

uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D normal_a;
uniform sampler2D normal_b;
uniform vec2 normal_scale = vec2(2.5, 2.5);
uniform vec2 normal_scale2 = vec2(3.5, 3.5);
uniform float normal_speed = 0.04;
uniform float uv_distortion = 0.08;
uniform float normal_strength = 0.25;




// caustics uniforms
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float caustics_intensity : hint_range(0.0, 5.0, 0.1) = 0.7;
uniform float caustics_depth_fade : hint_range(0.0, 2.0, 0.01) = 0.54;

// foam uniforms
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float foam_depth_start : hint_range(0.0, 5.0, 0.01) = 2.83;
uniform float foam_depth_end   : hint_range(0.0, 5.0, 0.01) = 0.0;
uniform float foam_noise_scale : hint_range(0.0, 10.0, 0.01) = 3.9;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 0.32;
uniform float foam_cutoff      : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float foam_crest_threshold : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float foam_crest_amount    : hint_range(0.0, 10.0, 0.1) = 5.2;

uniform vec3 foam_edge_color : source_color = vec3(0.0, 0.0, 0.05);
uniform vec2 foam_edge_offset = vec2(0.02, 0.02);
uniform float voronoi_scale   : hint_range(0.0, 50.0) = 9.0;
uniform float voronoi_strength : hint_range(0.0, 8.0) = 0.8;

float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
    uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

float hash3d(vec3 p) { return hash13(p); }

float noise3d(in vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(hash3d(i + vec3(0.0, 0.0, 0.0)), hash3d(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(hash3d(i + vec3(0.0, 1.0, 0.0)), hash3d(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(
            mix(hash3d(i + vec3(0.0, 0.0, 1.0)), hash3d(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(hash3d(i + vec3(0.0, 1.0, 1.0)), hash3d(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// this function computes 2D voronoi noise by measuring the distance to the nearest randomly placed point in each grid cell. The result is cell-like patterns, which are ideal for simulating foam clumps and bubbles
float voronoi(vec2 uv) {
    vec2 n = floor(uv);
    vec2 f = fract(uv);
    float m_dist = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            // animate the point within the cell
            o = 0.5 + 0.5 * sin(TIME * foam_noise_speed + 6.2831 * o);
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
        float val = 1.0 - voronoi(uv);
        val = pow(val, 2.0); // sharpen bubbles
        v += a * val;
        uv = rot * uv * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float get_wave_height_detailed(vec2 pos_xz, float freq_mult) {
	vec2 uv = pos_xz;
	uv.x *= 0.75;
	float freq = detail_freq * freq_mult;
	float amp = sea_height;
	float choppy = sea_choppy;
	float h = 0.0;
	for (int i = 0; i < ITER_FRAGMENT; i++) {
		float d = sea_octave((uv + TIME * sea_speed) * freq, choppy);
		d += sea_octave((uv - TIME * sea_speed) * freq, choppy);
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

// tutorial-style detailed wave with explicit time parameter (uses sea_freq for LOD)
float get_wave_height_detailed_time_lod(vec2 pos_xz, float time, int max_iter) {
	vec2 uv = pos_xz;
	uv.x *= 0.75;
	float freq = sea_freq;
	float amp = sea_height;
	float choppy = sea_choppy;
	float h = 0.0;
	for (int i = 0; i < ITER_FRAGMENT; i++) {
		if (i >= max_iter) break;
		float d = sea_octave((uv + time * sea_speed) * freq, choppy);
		d += sea_octave((uv - time * sea_speed) * freq, choppy);
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

float get_wave_height_detailed_time(vec2 pos_xz, float time) {
	return get_wave_height_detailed_time_lod(pos_xz, time, ITER_FRAGMENT);
}

float map(vec3 p) {
	return p.y - get_wave_height(p.xz);
}

float map_detailed(vec3 p, float freq_mult) {
	return p.y - get_wave_height_detailed(p.xz, freq_mult);
}

float map_detailed_time_lod(vec3 p, float time, int max_iter) {
	return p.y - get_wave_height_detailed_time_lod(p.xz, time, max_iter);
}

float map_detailed_time(vec3 p, float time) {
	return map_detailed_time_lod(p, time, ITER_FRAGMENT);
}

vec3 get_normal_detailed_time_lod(vec3 p, float eps, float time, int max_iter) {
	vec3 n;
	n.y = map_detailed_time_lod(p, time, max_iter);
	n.x = map_detailed_time_lod(vec3(p.x + eps, p.y, p.z), time, max_iter) - n.y;
	n.z = map_detailed_time_lod(vec3(p.x, p.y, p.z + eps), time, max_iter) - n.y;
	n.y = eps;
	return normalize(n);
}

vec3 get_normal_detailed_time(vec3 p, float eps, float time) {
	return get_normal_detailed_time_lod(p, eps, time, ITER_FRAGMENT);
}

vec3 get_normal_detailed(vec3 p, float eps, float freq_mult) {
	vec3 n;
	n.y = map_detailed(p, freq_mult);
	n.x = map_detailed(vec3(p.x + eps, p.y, p.z), freq_mult) - n.y;
	n.z = map_detailed(vec3(p.x, p.y, p.z + eps), freq_mult) - n.y;
	n.y = eps;
	return normalize(n);
}

// pass world-space position to fragment for normals and foam
varying vec3 world_vert;
varying float wave_height;
varying vec3 vertex_normal_world;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// distance fade
	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(world_pos.xz - cam_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	float vertex_eps = 0.1;
	float h_raw = get_wave_height(world_pos.xz);
	float h_x_raw = get_wave_height(world_pos.xz + vec2(vertex_eps, 0.0));
	float h_z_raw = get_wave_height(world_pos.xz + vec2(0.0, vertex_eps));

	float h = h_raw * fade + water_level;
	wave_height = h_raw * fade;
	VERTEX.y = h;
	world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_geom = normalize(vec3((h_raw - h_x_raw) * fade, vertex_eps, (h_raw - h_z_raw) * fade));
	vertex_normal_world = n_geom;
}

// GET LINEAR DEPTH FROM DEPTH TEXTURE
float get_linear_depth(sampler2D d_tex, vec2 uv, mat4 inv_proj) {
	float depth = texture(d_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -view.z / view.w;
}

vec3 blend_normals(vec3 a, vec3 b) {
    vec3 r = vec3(a.xy + b.xy, a.z);
    if (length(r) < 0.001) { return vec3(0.0, 0.0, 1.0); }
    return normalize(r);
}

void fragment() {
    float dist_to_cam = length(VERTEX);
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float dist = length(world_vert.xz - cam_pos.xz);

    float text_fade = 1.0 - smoothstep(texture_fade_start, texture_fade_end, dist_to_cam);

    // Per-pixel procedural normals (mesh-independent) with minimum iterations for performance
    float lod_epsilon = max(normal_epsilon, dist_to_cam * 0.005);
    vec3 detailed_normal = get_normal_detailed_time_lod(world_vert, lod_epsilon, TIME, 1);
    float smooth_factor = 1.0 - text_fade;
    vec3 final_normal = mix(detailed_normal, vertex_normal_world, smooth_factor);
    NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;

    // calculate water depth/thickness
    // reconstruct world position from depth buffer
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
		ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_pos = world.xyz / world.w;

    // linear depth of the water surface itself
	float water_linear_depth = -VERTEX.z;
    // linear depth of what's behind the water
	float bg_linear_depth = get_linear_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(0.0, bg_linear_depth - water_linear_depth);
	
	// refraction offset calculation
    vec3 view_vertex_normal = (VIEW_MATRIX * vec4(vertex_normal_world, 0.0)).xyz;
    vec2 normal_offset = NORMAL.xy - view_vertex_normal.xy;
    float ref_dist_factor = clamp(refraction_distance_fade / max(0.1, dist_to_cam), 0.0, 1.0);
    float ref_depth_mask = smoothstep(0.0, max_depth, thickness);
    vec2 refraction_offset = normal_offset * refraction_strength * ref_dist_factor * ref_depth_mask * 0.05;

    vec2 distorted_uv = SCREEN_UV + refraction_offset;
distorted_uv = clamp(distorted_uv, vec2(0.001), vec2(0.999));

    // fix ghosting for pixels that are on boundary so they dont make water look weird
    float distorted_bg_depth = get_linear_depth(depth_tex, distorted_uv, INV_PROJECTION_MATRIX);
    if (distorted_bg_depth < water_linear_depth - 0.001) {
        distorted_uv = SCREEN_UV;
        distorted_bg_depth = bg_linear_depth;
    }
	
	
	
    vec3 screen_color = texture(screen_tex, distorted_uv).rgb;
    thickness = max(0.0, distorted_bg_depth - water_linear_depth);
	
    // caustics
    vec4 bg_ndc = vec4(distorted_uv * 2.0 - 1.0, texture(depth_tex, distorted_uv).x, 1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    bg_ndc.z = bg_ndc.z * 2.0 - 1.0;
#endif
    vec4 bg_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * bg_ndc;
    vec3 bg_world_pos = bg_world.xyz / bg_world.w;
    if (thickness > 0.0) {
        vec2 caustics_uv1 = bg_world_pos.xz * caustics_scale;
        caustics_uv1.x += TIME * caustics_speed;
        vec2 caustics_uv2 = bg_world_pos.xz * caustics_scale * 0.7;
        caustics_uv2.y -= TIME * caustics_speed * 0.8;
        float caustics_sample1 = texture(caustics_texture, caustics_uv1).r;
        float caustics_sample2 = texture(caustics_texture, caustics_uv2).r;
        float caustics_value = caustics_sample1 * caustics_sample2;
        float caustics_fade = 1.0 - clamp(thickness * caustics_depth_fade, 0.0, 1.0);
        screen_color += caustics_value * caustics_intensity * caustics_fade;
    }

	float fade_range = max(0.001, max_depth - fade_start_depth);
	float depth_ratio = clamp((thickness - fade_start_depth) / fade_range, 0.0, 1.0);

    // Beer-Lambert absorption
    vec3 transmittance = exp(-thickness * water_absorption);
    vec3 water_volume_color = mix(base_tint_color, deep_color, depth_ratio);
    vec3 apparent_seabed_color = screen_color * water_volume_color;
    ALBEDO = mix(underwater_fog_color, apparent_seabed_color, transmittance);

    // distance fade for max_depth: less visible depth from afar
    float depth_dist_fade = max(0.15, 1.0 - smoothstep(fade_start, fade_end, dist));
    float effective_max_depth = max_depth * depth_dist_fade;
    float eff_fade_range = max(0.001, effective_max_depth - fade_start_depth);
    float eff_depth_ratio = clamp((thickness - fade_start_depth) / eff_fade_range, 0.0, 1.0);
    float depth_force = smoothstep(0.85, 1.0, eff_depth_ratio);
    ALBEDO = mix(ALBEDO, underwater_fog_color, depth_force);

    // wave patches using detail_freq (per-pixel, 2 sea_octave calls)
    float pixel_wave = get_wave_height_detailed(world_vert.xz, 1.0);
    float h = clamp(pixel_wave / (sea_height * 2.5), 0.0, 1.0);
    // cartoon stepped colors (flat zones, hard edges)
    vec3 wave_tint = mix(wave_trough_color, wave_mid_color, step(0.3, h));
    wave_tint = mix(wave_tint, wave_crest_color, step(0.6, h));
    ALBEDO = mix(ALBEDO, wave_tint, wave_patch_strength);

    // white crests on highest wave protrusions
    float crest_mask = smoothstep(0.85, 1.0, h);
    float crest_rand = noise(world_vert.xz * 0.3 + TIME * 0.05) * 0.5 + 0.5;
    float crest_dist_fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    float white_amount = crest_mask * smoothstep(0.4, 0.8, crest_rand) * white_crest_amount * crest_dist_fade;
    ALBEDO = mix(ALBEDO, white_crest_color, white_amount);

	    // foam calculation
    float foam_mask_primary = 0.0;
    float foam_mask_shadow  = 0.0;

    // create a density factor, 1.0 at shore/crests, 0.0 at deep water
    // foam appears primarily in shallow water and on wave crests. We compute a depth-based factor using the beer-lambert thickness and add a crest factor based on the surface normal. The result (foam_level) defines how strongly foam can appear at this fragment
    float depth_foam_factor = smoothstep(foam_depth_start, foam_depth_end, thickness);
    float wave_crest_factor = smoothstep(foam_crest_threshold, foam_crest_threshold - 0.1, final_normal.y);
    wave_crest_factor *= foam_crest_amount;
    float foam_level = clamp(depth_foam_factor + wave_crest_factor, 0.0, 1.0);

    // to create swirling, flowing motion that mimics foam being carried by water currents, we use domain warping
    vec2 flow_uv = world_vert.xz * 0.5 + TIME * 0.05 * foam_noise_speed;
    vec2 warp = vec2(
        noise(flow_uv),
        noise(flow_uv + vec2(5.2, 1.3))
    ) * 0.5;

    if (distorted_bg_depth > water_linear_depth) {
        vec2 foam_uv = world_vert.xz * foam_noise_scale + warp;

        // emergence, pulsing/clumping
        // foam should not appear everywhere at once. A 3D noise field controls foam emergence, creating pulsing and clumping behavior
        float emergence_noise = noise3d(vec3(world_vert.xz * 0.5, TIME * 0.2 * foam_noise_speed));
        emergence_noise = smoothstep(0.0, 1.0, emergence_noise * 0.5 + 0.5);

        // near shores and crests, emergence is forced to full strength
        float effective_emergence = mix(emergence_noise, 1.0, foam_level);

        // main foam sample
        float foam_noise_val = fbm_voronoi(foam_uv);
        foam_noise_val *= effective_emergence;

        // shadow sample (foam shadow is shown at slight offset, for faking thickness and separation from underlying water)
        vec2 foam_uv_shadow = (world_vert.xz + foam_edge_offset) * foam_noise_scale + warp;
        float foam_noise_shadow_val = fbm_voronoi(foam_uv_shadow);
        foam_noise_shadow_val *= effective_emergence;

        // clumping/mask generation
        float combined_noise  = foam_noise_val + foam_level;
        float combined_shadow = foam_noise_shadow_val + foam_level;

        foam_mask_primary = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_noise);
        float shadow_shape = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_shadow);
        foam_mask_shadow = clamp(shadow_shape - foam_mask_primary, 0.0, 1.0);
    }

    // voronoi internal texture/bubbles
    // inside the foam, a separate voronoi pattern simulates small air bubbles. This texture only affects the foam itself and adds visual richness without changing the foam silhouette
    float voronoi_val = 1.0 - sqrt(voronoi(world_vert.xz * voronoi_scale + warp));
    voronoi_val = smoothstep(0.2, 0.8, voronoi_val);

    float bubble_alpha = 1.0 - clamp((1.0 - voronoi_val) * voronoi_strength, 0.0, 1.0);

    // apply foam
    ALBEDO = mix(ALBEDO, foam_edge_color, foam_mask_shadow);
    ALBEDO = mix(ALBEDO, foam_color, foam_mask_primary * bubble_alpha);

    // surface bubbles as individual dots overlaid on top (Dredge-style)
    float bubble_raw = noise(world_vert.xz * 7.0 + TIME * 0.12);
    float dot_thresh = 0.8 - surface_bubble_density * 0.3;
    float bubble_dot = smoothstep(dot_thresh - 0.06, dot_thresh + 0.06, bubble_raw);
    float spread_noise = noise(world_vert.xz * 0.4 + TIME * 0.02 + 100.0) * 0.5 + 0.5;
    float spread_thresh = 1.0 - surface_bubble_spread * 0.35;
    bubble_dot *= step(spread_thresh, spread_noise);
    float residue_raw = noise(world_vert.xz * 5.0 + TIME * 0.08 + 200.0) * 0.5 + 0.5;
    float residue_thresh = 1.0 - surface_residue_amount * 0.25;
    float residue_dot = step(residue_thresh, residue_raw) * 0.25;
    float bubble_mask = clamp(bubble_dot + residue_dot, 0.0, 1.0);
    float bubble_dist_fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    ALBEDO = mix(ALBEDO, surface_bubble_color, bubble_mask * bubble_dist_fade);
    EMISSION += surface_bubble_color * bubble_mask * 0.15 * bubble_dist_fade;

    // make foam rougher
    ROUGHNESS = mix(roughness, 0.8, (foam_mask_primary * bubble_alpha) + foam_mask_shadow);

    // PBR parameters
    SPECULAR = specular;
    METALLIC = metallic;
	

}