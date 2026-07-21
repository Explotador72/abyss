shader_type spatial;
render_mode blend_mix, depth_draw_always, unshaded;

uniform float sea_height    : hint_range(0.0, 5.0)  = 0.515;
uniform float sea_choppy    : hint_range(0.0, 10.0) = 3.207;
uniform float sea_speed     : hint_range(0.0, 5.0)  = 1.0;
uniform float sea_freq      : hint_range(0.0, 2)  = 0.2;

uniform float wind_angle    : hint_range(0.0, 360.0) = 0.0;
uniform float wind_influence : hint_range(0.0, 1.0) = 0.5;

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

	vec2 wdir = vec2(cos(radians(wind_angle)), sin(radians(wind_angle)));

	for (int i = 0; i < ITER_GEOMETRY; i++) {
		float oct_wind = wind_influence * (1.0 - 0.5 * float(i) / float(ITER_GEOMETRY));
		float w = (1.0 + oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		float c = (1.0 - oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		vec2 t1 = normalize(mix(vec2(1.0, 0.0), wdir, oct_wind));
		vec2 t2 = normalize(mix(vec2(-1.0, 0.0), -wdir, oct_wind));
		float d = sea_octave((uv + t1 * TIME * sea_speed) * freq, chop) * w;
		d +=      sea_octave((uv + t2 * TIME * sea_speed) * freq, chop) * c;
		height += d * amp;
		uv     *= octave_m;
		freq   *= 1.9;
		amp    *= 0.22;
		chop   = mix(chop, 1.0, 0.2);
	}

	return height;
}

uniform sampler2D depth_tex : hint_depth_texture;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float detail_freq : hint_range(0.0, 5.0) = 1.001;

uniform float fade_start : hint_range(0.0, 5000.0) = 100.0;
uniform float fade_end   : hint_range(0.0, 5000.0) = 400.0;
uniform float texture_fade_start : hint_range(0.0, 5000.0) = 0.0;
uniform float texture_fade_end   : hint_range(0.0, 5000.0) = 514.613;

uniform float water_level : hint_range(-10.0, 10.0, 0.1) = 0.0;

uniform int ITER_FRAGMENT = 5;

uniform float normal_epsilon : hint_range(0.001, 1.0) = 0.18;
uniform float normal_smoothness_dist : hint_range(0.0, 1000.0) = 50.0;

uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.3;

// foam uniforms
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float foam_depth_start : hint_range(0.0, 5.0, 0.01) = 2.83;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 0.32;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float voronoi(vec2 uv) {
	vec2 n = floor(uv);
	vec2 f = fract(uv);
	float m_dist = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
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
		val = pow(val, 2.0);
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
	vec2 wdir = vec2(cos(radians(wind_angle)), sin(radians(wind_angle)));
	for (int i = 0; i < ITER_FRAGMENT; i++) {
		float oct_wind = wind_influence * (1.0 - 0.5 * float(i) / float(max(ITER_FRAGMENT, 1)));
		float w = (1.0 + oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		float c = (1.0 - oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		vec2 t1 = normalize(mix(vec2(1.0, 0.0), wdir, oct_wind));
		vec2 t2 = normalize(mix(vec2(-1.0, 0.0), -wdir, oct_wind));
		float d = sea_octave((uv + t1 * TIME * sea_speed) * freq, choppy) * w;
		d += sea_octave((uv + t2 * TIME * sea_speed) * freq, choppy) * c;
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

float get_wave_height_detailed_time_lod(vec2 pos_xz, float time, int max_iter) {
	vec2 uv = pos_xz;
	uv.x *= 0.75;
	float freq = sea_freq;
	float amp = sea_height;
	float choppy = sea_choppy;
	float h = 0.0;
	vec2 wdir = vec2(cos(radians(wind_angle)), sin(radians(wind_angle)));
	for (int i = 0; i < ITER_FRAGMENT; i++) {
		if (i >= max_iter) break;
		float oct_wind = wind_influence * (1.0 - 0.5 * float(i) / float(max(ITER_FRAGMENT, 1)));
		float w = (1.0 + oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		float c = (1.0 - oct_wind) / sqrt(1.0 + oct_wind * oct_wind);
		vec2 t1 = normalize(mix(vec2(1.0, 0.0), wdir, oct_wind));
		vec2 t2 = normalize(mix(vec2(-1.0, 0.0), -wdir, oct_wind));
		float d = sea_octave((uv + t1 * time * sea_speed) * freq, choppy) * w;
		d += sea_octave((uv + t2 * time * sea_speed) * freq, choppy) * c;
		h += d * amp;
		uv *= octave_m;
		freq *= 1.9;
		amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return h;
}

float map_detailed_time_lod(vec3 p, float time, int max_iter) {
	return p.y - get_wave_height_detailed_time_lod(p.xz, time, max_iter);
}

vec3 get_normal_detailed_time_lod(vec3 p, float eps, float time, int max_iter) {
	vec3 n;
	n.y = map_detailed_time_lod(p, time, max_iter);
	n.x = map_detailed_time_lod(vec3(p.x + eps, p.y, p.z), time, max_iter) - n.y;
	n.z = map_detailed_time_lod(vec3(p.x, p.y, p.z + eps), time, max_iter) - n.y;
	n.y = eps;
	return normalize(n);
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

varying vec3 world_vert;
varying vec3 vertex_normal_world;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(world_pos.xz - cam_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	float vertex_eps = 0.1;
	float h_raw = get_wave_height(world_pos.xz);
	float h_x_raw = get_wave_height(world_pos.xz + vec2(vertex_eps, 0.0));
	float h_z_raw = get_wave_height(world_pos.xz + vec2(0.0, vertex_eps));

	float h = h_raw * fade + water_level;
	VERTEX.y = h;
	world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_geom = normalize(vec3((h_raw - h_x_raw) * fade, vertex_eps, (h_raw - h_z_raw) * fade));
	vertex_normal_world = n_geom;
}

uniform vec4 debug_color : source_color = vec4(0.0, 0.3, 0.6, 1.0);

uniform float foam_falloff_bias : hint_range(0.0, 2.0) = 0.5;
uniform float leading_edge_falloff : hint_range(0.0, 1.0) = 0.15;

uniform float edge_pattern_scale : hint_range(0.1, 20.0) = 4.0;
uniform float edge_pattern_scroll : hint_range(0.0, 2.0) = 0.1;

void fragment() {
	float dist_to_cam = length(VERTEX);

	// normals & distance smoothing (water2 approach)
	float lod_epsilon = max(normal_epsilon, dist_to_cam * 0.005);
	vec3 detailed_normal = get_normal_detailed_time_lod(world_vert, lod_epsilon, TIME, ITER_FRAGMENT);
	float smooth_factor = clamp((dist_to_cam - normal_smoothness_dist) / 200.0, 0.0, 1.0);
	vec3 final_normal = mix(detailed_normal, vertex_normal_world, smooth_factor);
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;

	float water_linear = -VERTEX.z;
	float scene_linear = get_linear_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(0.0, scene_linear - water_linear);

	float foam_add = 0.0;
	float leading = 1.0;
	if (scene_linear > water_linear) {
		vec2 w_uv = world_vert.xz * 1.5;
		vec2 uv_a = w_uv * edge_pattern_scale - vec2(edge_pattern_scroll, cos(w_uv.x));
		vec2 uv_b = w_uv * edge_pattern_scale * 0.5 + vec2(sin(w_uv.y), edge_pattern_scroll);

		float channelA = fbm_voronoi(uv_a);
		float channelB = fbm_voronoi(uv_b);

		float mask_val = (channelA + channelB) * 0.95;
		mask_val = pow(mask_val, 2.0);
		mask_val = clamp(mask_val, 0.0, 1.0);

		if (thickness < foam_depth_start * leading_edge_falloff) {
			float leading_edge_frac = thickness / max(foam_depth_start * leading_edge_falloff, 0.001);
			leading = clamp(leading_edge_frac, 0.0, 1.0);
			mask_val *= leading;
		}

		float falloff = 1.0 - (thickness / foam_depth_start) + foam_falloff_bias;
		falloff = clamp(falloff, 0.0, 1.0);
		foam_add = clamp(falloff * debug_color.a - mask_val, 0.0, 1.0);
	}

	// Screen texture
	vec3 screen_color = texture(screen_tex, SCREEN_UV).rgb;

	// Absorcion substractiva (estilo Malido)
	vec3 absorb = vec3(0.55, 0.12, 0.02); // rojo se absorbe, azul no
	vec3 leftover = vec3(1.0) - absorb;   // lo que queda tras absorber
	float depth_dist = 20.0;
	float depth_blend = clamp(thickness / depth_dist, 0.0, 1.0);
	depth_blend = 1.0 - exp(-depth_blend * 4.5);
	vec3 water_color = clamp(screen_color - absorb * depth_blend, 0.0, 1.0);
	water_color = mix(water_color, leftover, depth_blend * depth_blend);

	// Foam
	water_color += foam_color * foam_add;

	// Fresnel
	vec3 view_dir = normalize(-VERTEX);
	float NdotV = max(dot(view_dir, NORMAL), 0.0);
	float fresnel = pow(1.0 - NdotV, 2.0);
	vec3 fresnel_color = vec3(0.05, 0.5, 0.65);
	water_color = mix(water_color, fresnel_color, fresnel * 0.6);

	// Fake specular muy sutil
	vec3 light_dir = normalize(vec3(0.3, 0.8, 0.5));
	vec3 half_vec = normalize(light_dir + view_dir);
	float spec = pow(max(dot(half_vec, NORMAL), 0.0), 32.0) * 0.04;
	spec *= 1.0 - fresnel;
	water_color += spec;

	// Alpha
	float depth_alpha = 1.0 - exp(-thickness * 2.5);
	float water_alpha = mix(depth_alpha, 1.0, fresnel * 0.4) * leading;

	ALBEDO = water_color;
	ALPHA = water_alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.001;
}
