shader_type spatial;
render_mode blend_mix, depth_draw_always;

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

	float lod_epsilon = max(normal_epsilon, dist_to_cam * 0.005);
	vec3 detailed_normal = get_normal_detailed_time_lod(world_vert, lod_epsilon, TIME, 1);
	float smooth_factor = 1.0 - text_fade;
	vec3 final_normal = mix(detailed_normal, vertex_normal_world, smooth_factor);

	// Wave height and steepness at pixel
	float pixel_wave = get_wave_height_detailed(world_vert.xz, 1.0);
	float h = clamp(pixel_wave / (sea_height * 2.5), 0.0, 1.0);
	float eps_steep = 1.0;
	float hx = get_wave_height_detailed(world_vert.xz + vec2(eps_steep, 0.0), 1.0);
	float hz = get_wave_height_detailed(world_vert.xz + vec2(0.0, eps_steep), 1.0);
	float steepness = length(vec2(pixel_wave - hx, pixel_wave - hz)) / eps_steep;

	// Water thickness for seabed visibility
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
		ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_pos = world.xyz / world.w;

	float water_linear_depth = -VERTEX.z;
	float bg_linear_depth = get_linear_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(0.0, bg_linear_depth - water_linear_depth);

	// ===== CARTOON POSTERIZED COLORS =====
	float band_count = 4.0;
	float band_f = h * band_count;
	float band = floor(band_f) / band_count;
	vec3 water_color = mix(wave_trough_color, wave_mid_color, clamp(band * 2.0, 0.0, 1.0));
	water_color = mix(water_color, wave_crest_color, clamp(band * 2.0 - 1.0, 0.0, 1.0));

	// ===== FRESNEL SKY TINT =====
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_vert);
	float NdV = max(dot(final_normal, view_dir), 0.0);
	float fresnel = pow(1.0 - NdV, 3.0);
	water_color = mix(water_color, underwater_fog_color * 1.5, fresnel * 0.3);

	// ===== CEL SPECULAR =====
	vec3 light_dir = normalize(vec3(0.4, 0.8, 0.3));
	vec3 half_dir = normalize(view_dir + light_dir);
	float spec = dot(final_normal, half_dir);
	float highlight = smoothstep(0.85, 0.92, spec);
	water_color += white_crest_color * highlight * 0.5;

	// ===== FOAM (steep faces + crests) =====
	float face_foam = smoothstep(foam_depth_end, foam_depth_start, steepness);
	float crest_boost = smoothstep(foam_crest_threshold - 0.2, foam_crest_threshold + 0.3, h) * foam_crest_amount;
	crest_boost = clamp(crest_boost, 0.0, 1.0);
	float foam_area = face_foam * (foam_cutoff + crest_boost * (1.0 - foam_cutoff));
	float foam_strength = smoothstep(0.1, 0.5, foam_area);
	vec3 foam_col = mix(foam_color, white_crest_color, crest_boost);
	water_color = mix(water_color, foam_col, foam_strength * 0.85);

	// ===== WHITE CRESTS =====
	float crest_mask = smoothstep(0.85, 1.0, h);
	float crest_rand = noise(world_vert.xz * 0.3 + TIME * 0.05) * 0.5 + 0.5;
	float white_amount = crest_mask * smoothstep(0.4, 0.8, crest_rand) * white_crest_amount;
	water_color = mix(water_color, white_crest_color, white_amount);

	// ===== SURFACE BUBBLES =====
	float bubble_raw = noise(world_vert.xz * 7.0 + TIME * 0.12);
	float dot_thresh = 0.8 - surface_bubble_density * 0.3;
	float bubble_dot = smoothstep(dot_thresh - 0.06, dot_thresh + 0.06, bubble_raw);
	float spread_noise = noise(world_vert.xz * 0.4 + TIME * 0.02 + 100.0) * 0.5 + 0.5;
	float spread_thresh = 1.0 - surface_bubble_spread * 0.35;
	bubble_dot *= step(spread_thresh, spread_noise);
	water_color = mix(water_color, surface_bubble_color, bubble_dot * 0.3);

	// ===== ALPHA: only transparent when looking straight down at shallow water =====
	float seabed_angle = smoothstep(0.92, 0.98, -view_dir.y);
	float seabed_depth = 1.0 - smoothstep(0.0, 1.5, thickness);
	float seabed_alpha = seabed_angle * seabed_depth;
	float opacity = mix(1.0, 0.25, seabed_alpha);

	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;
	ALBEDO = water_color;
	ALPHA = opacity;
	EMISSION = surface_bubble_color * bubble_dot * 0.08;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
}
