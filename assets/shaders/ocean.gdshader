shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================
// Océano global con FFT flipbook + modulación de olas
// - UV en espacio global (world_pos.xz), no depende del mesh
// - Cuando las texturas FFT están asignadas, se usan como base
// - Modulación Gerstner para variación (escala, velocidad, dirección)
// - Multi-escala para detalle
// - Envelope de amplitud para romper uniformidad
// ============================================================

// --- Modo: si no hay texturas FFT, usa Gerstner puro ---
uniform sampler2D u_fft_normal    : filter_linear_mipmap;
uniform sampler2D u_fft_height    : filter_linear_mipmap;
uniform sampler2D u_fft_foam      : filter_linear_mipmap;
uniform float u_use_fft = 1.0;

// --- Flipbook layout ---
uniform vec2  u_fft_frames         = vec2(8.0, 8.0);
uniform float u_fft_fps            = 15.0;
uniform float u_fft_margin         = 4.0;
uniform float u_fft_tex_resolution = 512.0;

// --- Wave modifiers (FFT gain + Gerstner override) ---
uniform float u_wave_scale        = 3.0;
uniform float u_wave_intensity    = 0.8;
uniform float u_wavelength_scale  = 1.5;
uniform float u_wave_speed_scale  = 1.0;
uniform float u_wave_smoothness   = 0.85;
uniform float u_fft_tiling        = 0.5;
uniform float u_fft_detail_scale  = 0.3;
uniform float u_fft_detail_strength = 0.15;

uniform float u_view_distance     = 2000.0;
uniform float u_fade_start_ratio  = 0.3;
uniform float u_fade_sharpness    = 1.5;
uniform vec3  u_camera_pos;

uniform vec3  u_shallow_color     = vec3(0.1, 0.5, 0.48);
uniform vec3  u_deep_color        = vec3(0.0, 0.05, 0.2);
uniform vec3  u_light_color       = vec3(0.7, 0.85, 0.9);
uniform float u_depth_gradient_power = 1.5;

uniform vec3  u_foam_color        = vec3(0.95, 0.95, 0.98);
uniform float u_foam_residual_density    = 0.5;
uniform float u_foam_residual_threshold  = 0.3;
uniform float u_foam_peak_threshold      = 0.75;
uniform float u_foam_peak_density        = 0.8;

uniform float u_specular_strength  = 0.8;
uniform float u_specular_shininess = 64.0;
uniform float u_refraction_strength = 0.05;
uniform float u_normal_detail_scale  = 0.5;
uniform float u_normal_detail_strength = 0.0;

uniform float u_time = 0.0;

varying vec3  v_world_pos;
varying vec3  v_normal;
varying float v_height;

// ============================================================
// Gerstner helpers (moduladores de FFT + fallback puro)
// ============================================================
#define NUM_WAVES 4

const vec2 WAVE_DIRS[NUM_WAVES] = vec2[](
    vec2(0.8, 0.6), vec2(-0.7, 0.7), vec2(-0.9, -0.4),
    vec2(0.4, -0.9)
);
const float WAVE_WLS[NUM_WAVES] = float[](
    120.0, 70.0, 40.0, 22.0
);
const float WAVE_AMPS[NUM_WAVES] = float[](
    0.6, 0.35, 0.18, 0.08
);
const float WAVE_PHASES[NUM_WAVES] = float[](
    0.0, 1.8, 3.2, 0.7
);

// ============================================================
// Envelope: rompe la uniformidad espacial
// ============================================================
float _envelope(vec2 pos, float time) {
    // Grupos de olas que viajan lentamente (swell)
    float g1 = sin(pos.x * 0.003 + pos.y * 0.004 + time * 0.05) * 0.5 + 0.5;
    float g2 = sin(pos.x * -0.005 + pos.y * 0.002 + time * 0.03) * 0.5 + 0.5;
    return clamp(g1 * 0.7 + g2 * 0.3, 0.0, 1.0);
}

// ============================================================
// FFT flipbook helpers
// ============================================================
bool _has_fft_tex(sampler2D t) {
    return textureSize(t, 0).x > 0;
}

vec2 _fft_margin_uv() {
    return vec2(u_fft_margin / (u_fft_tex_resolution * u_fft_frames.x),
                u_fft_margin / (u_fft_tex_resolution * u_fft_frames.y));
}
vec2 _fft_content_size() {
    vec2 m = _fft_margin_uv();
    return vec2(1.0 / u_fft_frames.x - 2.0 * m.x,
                1.0 / u_fft_frames.y - 2.0 * m.y);
}
float _fft_wrap_frame(float frame) {
    float total = u_fft_frames.x * u_fft_frames.y;
    return mod(frame, total);
}
vec2 _fft_frame_uv(float frame, vec2 tile_uv) {
    frame = _fft_wrap_frame(frame);
    float fx = mod(frame, u_fft_frames.x);
    float fy = floor(frame / u_fft_frames.x);
    vec2 m  = _fft_margin_uv();
    vec2 cs = _fft_content_size();
    vec2 fo = vec2(fx, fy) / u_fft_frames;
    return fo + m + tile_uv * cs;
}

float _fft_lod(vec2 uv_smooth) {
    vec2 cs  = _fft_content_size();
    vec2 dx  = dFdx(uv_smooth) * cs;
    vec2 dy  = dFdy(uv_smooth) * cs;
    float md = max(dot(dx, dx), dot(dy, dy));
    if (md < 1e-12 || md != md)
        return 0.0;
    float lod = 0.5 * log2(md) + log2(u_fft_tex_resolution);
    return clamp(lod, 0.0, 8.0);
}

// ============================================================
// VERTEX
// ============================================================
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_pos = world_pos;

    bool use_fft = u_use_fft > 0.5 && _has_fft_tex(u_fft_height);
    float h = 0.0;
    vec3 normal = vec3(0.0, 1.0, 0.0);

    if (use_fft) {
        // --- FFT flipbook con modulación ---
        vec2 uv = world_pos.xz * u_fft_tiling;
        float frame   = floor(u_time * u_fft_fps * u_wave_speed_scale);
        float frac_t  = fract(u_time * u_fft_fps * u_wave_speed_scale);

        // FFT base
        float h0 = texture(u_fft_height, _fft_frame_uv(frame, fract(uv))).r;
        float h1 = texture(u_fft_height, _fft_frame_uv(frame + 1.0, fract(uv))).r;
        h = mix(h0, h1, frac_t);

        // Envelope espacial
        float env = _envelope(world_pos.xz, u_time);
        h = h * u_wave_scale * u_wave_intensity * env;

        // Gerstner override para variación fina
        vec2 grad = vec2(0.0);
        for (int i = 0; i < NUM_WAVES; i++) {
            vec2 dir = WAVE_DIRS[i];
            float wl = WAVE_WLS[i] * u_wavelength_scale;
            float amp = WAVE_AMPS[i] * u_wave_intensity * (1.0 - env * 0.5);
            float speed = sqrt(9.81 * wl / 6.2832) * 0.5 * u_wave_speed_scale;
            float theta = speed * u_time + dir.x * world_pos.x + dir.y * world_pos.z + WAVE_PHASES[i];
            float s = sin(theta);
            float c = cos(theta);
            h += amp * s * 0.15;
            grad += dir * amp * c * 0.15;
        }
        normal = normalize(vec3(-grad.x, 1.0, -grad.y));

    } else {
        // --- Gerstner puro (fallback) ---
        vec2 grad = vec2(0.0);
        for (int i = 0; i < NUM_WAVES; i++) {
            vec2 dir = WAVE_DIRS[i];
            float wl = WAVE_WLS[i] * u_wavelength_scale;
            float amp = WAVE_AMPS[i] * u_wave_scale * u_wave_intensity;
            float speed = sqrt(9.81 * wl / 6.2832) * 0.5 * u_wave_speed_scale;
            float theta = speed * u_time + dir.x * world_pos.x + dir.y * world_pos.z + WAVE_PHASES[i];
            float c = cos(theta);
            h += amp * sin(theta);
            grad += dir * amp * c;
        }
        normal = normalize(vec3(-grad.x, 1.0, -grad.y));
    }

    v_height = h;
    VERTEX.y = h;
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = normal;
}

// ============================================================
// FRAGMENT
// ============================================================
void fragment() {
    vec3 world_pos = v_world_pos;
    bool use_fft = u_use_fft > 0.5 && _has_fft_tex(u_fft_normal);
    vec3 normal = normalize(v_normal);

    if (use_fft) {
        // --- FFT normal desde flipbook ---
        vec2 uv = world_pos.xz * u_fft_tiling;
        float frame   = floor(u_time * u_fft_fps * u_wave_speed_scale);
        float frac_t  = fract(u_time * u_fft_fps * u_wave_speed_scale);
        float lod = _fft_lod(uv);
        vec2 tile_uv = fract(uv);

        vec3 n0 = textureLod(u_fft_normal, _fft_frame_uv(frame, tile_uv), lod).rgb * 2.0 - 1.0;
        vec3 n1 = textureLod(u_fft_normal, _fft_frame_uv(frame + 1.0, tile_uv), lod).rgb * 2.0 - 1.0;
        normal = normalize(mix(n0, n1, frac_t));
        normal.y = abs(normal.y);

        // Detail normals (multi-escala)
        if (u_fft_detail_strength > 0.001) {
            vec2 dup = tile_uv * u_fft_detail_scale + normal.xy * u_fft_detail_strength * 0.05;
            vec3 nd0 = textureLod(u_fft_normal, _fft_frame_uv(frame, dup), lod + 1.0).rgb * 2.0 - 1.0;
            vec3 nd1 = textureLod(u_fft_normal, _fft_frame_uv(frame + 1.0, dup), lod + 1.0).rgb * 2.0 - 1.0;
            vec3 nd = normalize(mix(nd0, nd1, frac_t));
            normal = normalize(vec3(normal.xy + nd.xy * u_fft_detail_strength, normal.z));
        }

        // A world space
        vec3 world_normal = normalize((MODEL_MATRIX * vec4(normal, 0.0)).xyz);
        normal = world_normal;

        // Foam desde FFT
        float foam = 0.0;
        if (_has_fft_tex(u_fft_foam)) {
            float f0 = textureLod(u_fft_foam, _fft_frame_uv(frame, tile_uv), lod).r;
            float f1 = textureLod(u_fft_foam, _fft_frame_uv(frame + 1.0, tile_uv), lod).r;
            foam = mix(f0, f1, frac_t);
        }
    }

    // --- Iluminación común (FFT y Gerstner) ---
    vec3 view_dir = normalize(u_camera_pos - world_pos);
    vec3 light_dir = normalize(vec3(0.5, 0.8, 0.3));

    float ndl = max(dot(normal, light_dir), 0.0);

    float hn = clamp(v_height / (abs(u_wave_scale * 1.5) + 0.1) * 0.5 + 0.5, 0.0, 1.0);
    hn = pow(hn, u_depth_gradient_power);
    vec3 water_color = mix(u_deep_color, u_shallow_color, hn);

    // Foam
    float foam_mask = 0.0;
    if (use_fft && _has_fft_tex(u_fft_foam)) {
        vec2 uv = world_pos.xz * u_fft_tiling;
        float frame   = floor(u_time * u_fft_fps * u_wave_speed_scale);
        float frac_t  = fract(u_time * u_fft_fps * u_wave_speed_scale);
        float lod = _fft_lod(uv);
        vec2 tile_uv = fract(uv);
        float f0 = textureLod(u_fft_foam, _fft_frame_uv(frame, tile_uv), lod).r;
        float f1 = textureLod(u_fft_foam, _fft_frame_uv(frame + 1.0, tile_uv), lod).r;
        foam_mask = mix(f0, f1, frac_t);
    } else {
        // Foam sintético basado en altura y pendiente
        float height_factor = abs(v_height) / (abs(u_wave_scale * 1.5) + 0.1);
        float peak = smoothstep(u_foam_peak_threshold, 1.0, height_factor) * u_foam_peak_density;
        float residual = smoothstep(u_foam_residual_threshold, 1.0, 1.0 - ndl) * u_foam_residual_density;
        foam_mask = clamp(peak + residual, 0.0, 1.0);
    }

    vec3 color = mix(water_color, u_foam_color, foam_mask);

    // Lighting
    color += u_light_color * ndl * 0.25;

    float fresnel = pow(1.0 - max(dot(normal, view_dir), 0.0), 3.0);
    color += u_light_color * fresnel * 0.35;

    vec3 half_dir = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, half_dir), 0.0), u_specular_shininess);
    color += u_light_color * spec * u_specular_strength * 0.6;

    // Fade a distancia
    float cam_dist = distance(world_pos, u_camera_pos);
    float fade_start = u_view_distance * u_fade_start_ratio;
    float view_fade = 1.0 - smoothstep(fade_start, u_view_distance, cam_dist);
    view_fade = pow(view_fade, u_fade_sharpness);

    ALBEDO = color;
    ALPHA = view_fade;
}
