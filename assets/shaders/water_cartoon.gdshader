shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform float u_time : hint_range(0.0, 1000.0) = 0.0;
uniform float u_height_scale : hint_range(0.0, 10.0) = 1.0;
uniform float u_foam_scale : hint_range(0.1, 5.0) = 1.0;
uniform float u_foam_speed : hint_range(0.0, 2.0) = 0.15;

uniform sampler2D u_foam_texture : source_color;

uniform vec3 u_deep_color : source_color = vec3(0.02, 0.25, 0.55);
uniform vec3 u_shallow_color : source_color = vec3(0.25, 0.90, 0.92);
uniform vec3 u_foam_color : source_color = vec3(1.0, 1.0, 1.0);

uniform float u_band_count : hint_range(2.0, 8.0) = 4.0;
uniform float u_foam_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float u_residual_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float u_foam_fade_distance : hint_range(0.0, 500.0) = 200.0;

varying vec3 v_world_pos;
varying float v_wave_height;
varying float v_wave_steepness;

// Hash for smooth noise
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float voronoi_foam(vec2 p, float density) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float best = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 cell = i + vec2(float(x), float(y));
            if (hash21(cell + 200.0) > density) { continue; }
            vec2 off = vec2(hash21(cell), hash21(cell + 50.0));
            vec2 center = cell + (off - 0.5) * 0.7;
            vec2 diff = f - vec2(float(x), float(y)) - (center - cell);
            float d = length(diff);
            float blob = 1.0 - smoothstep(0.0, 0.55, d);
            blob *= 0.4 + hash21(cell + 100.0) * 0.6;
            best = max(best, blob);
        }
    }
    return best;
}

vec2 fragment_wave(vec2 pos_xz) {
    vec2 dirs[12] = vec2[](
        vec2(0.95, 0.31), vec2(-0.26, 0.97), vec2(0.42, -0.91), vec2(-0.77, -0.64),
        vec2(0.71, 0.70), vec2(-0.59, 0.81), vec2(0.17, -0.99), vec2(-0.37, -0.93),
        vec2(0.87, -0.50), vec2(-0.94, 0.35), vec2(0.99, 0.12), vec2(-0.09, -0.50)
    );
    float wls[12] = float[](24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5);
    float amps[12] = float[](0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03);
    float t = u_time * 0.39;
    float h = 0.0;
    vec2 grad = vec2(0.0);
    for (int i = 0; i < 12; i++) {
        float seed = float(i) * 2.399;
        float wl = wls[i] * max(u_foam_scale, 0.1);
        float amp = amps[i] * u_height_scale;
        float k = 2.0 * PI / wl;
        float c = sqrt(9.8 / k);
        vec2 jitter = vec2(
            sin(pos_xz.x * 0.025 + pos_xz.y * 0.018 + seed),
            cos(pos_xz.x * 0.018 + pos_xz.y * 0.025 + seed * 1.3)
        ) * (0.04 + (1.0 - amps[i] / 0.9) * 0.3);
        vec2 dir = normalize(dirs[i] + jitter);
        float phase_off = sin(pos_xz.x * 0.01 + pos_xz.y * 0.014 + seed) * 2.0;
        phase_off += sin(pos_xz.x * 0.02 - pos_xz.y * 0.012 + seed * 1.7) * 1.2;
        float f = k * dot(dir, pos_xz) + c * t + phase_off;
        float co = cos(f);
        h += amp * sin(f);
        grad += amp * k * dir * co;
    }
    return vec2(h, length(grad));
}

void vertex() {
    vec3 pos = VERTEX;
    vec2 pos_xz = pos.xz;
    float t = u_time * 0.39;

    vec2 dirs[16] = vec2[](
        vec2(1.0, 0.0), vec2(0.7, 0.7), vec2(0.0, 1.0), vec2(-0.7, 0.7),
        vec2(-1.0, 0.0), vec2(-0.7, -0.7), vec2(0.0, -1.0), vec2(0.7, -0.7),
        vec2(0.9, 0.4), vec2(0.4, 0.9), vec2(-0.4, 0.9), vec2(-0.9, 0.4),
        vec2(-0.9, -0.4), vec2(-0.4, -0.9), vec2(0.4, -0.9), vec2(0.9, -0.4)
    );
    
    float wls[16] = float[](24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5, 0.3, 0.18, 0.1, 0.06);
    float amps[16] = float[](0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03, 0.02, 0.015, 0.01, 0.007);

    float height = 0.0;
    for (int i = 0; i < 16; i++) {
        float seed = float(i) * 2.399;
        float wl = wls[i] * max(u_foam_scale, 0.1);
        float amp = amps[i] * u_height_scale;
        float k = 2.0 * PI / wl;
        float c = sqrt(9.8 / k);
        vec2 jitter = vec2(
            sin(pos_xz.x * 0.025 + pos_xz.y * 0.018 + seed),
            cos(pos_xz.x * 0.018 + pos_xz.y * 0.025 + seed * 1.3)
        ) * (0.04 + (1.0 - amps[i] / 0.9) * 0.3);
        vec2 dir = normalize(dirs[i] + jitter);
        float phase_off = sin(pos_xz.x * 0.01 + pos_xz.y * 0.014 + seed) * 2.0;
        phase_off += sin(pos_xz.x * 0.02 - pos_xz.y * 0.012 + seed * 1.7) * 1.2;
        float f = k * dot(dir, pos_xz) + c * t + phase_off;
        height += amp * sin(f);
    }

    pos.y += height;
    VERTEX = pos;
    v_world_pos = VERTEX;
    v_wave_height = height;
    v_wave_steepness = length(dirs[0]);
}

void fragment() {
    vec2 uv_base = v_world_pos.xz;

    vec2 wave = fragment_wave(uv_base);
    float pix_height = wave.x;
    float pix_steepness = wave.y;
    float height_norm = smoothstep(-1.0, 2.0, pix_height);
    float band = floor(height_norm * u_band_count) / u_band_count;

    vec3 water_color = mix(u_deep_color, u_shallow_color, band);
    vec3 color = water_color;

    float face_foam = smoothstep(0.02, 0.4, pix_steepness);
    float crest_boost = smoothstep(0.3, 2.0, max(pix_height, 0.0));
    float foam_area = face_foam * (0.3 + crest_boost * 0.7);
    float foam_strength = smoothstep(0.0, 0.6, foam_area * u_foam_intensity);

    float foam_time = u_time * u_foam_speed;
    vec2 uv_foam = vec2(uv_base.x * 0.6 - uv_base.y * 0.4, uv_base.x * 0.4 + uv_base.y * 0.6) * 0.8;
    float voronoi = voronoi_foam(uv_foam + foam_time * 0.3, 0.35);

    vec2 uv_foam_tex = uv_base * 0.35 + foam_time * vec2(0.3, -0.2);
    vec2 uv_foam_tex2 = uv_base * 0.6 - foam_time * vec2(-0.2, 0.25);
    float foam_tex = texture(u_foam_texture, uv_foam_tex).r;
    float foam_tex2 = texture(u_foam_texture, uv_foam_tex2).r;
    float foam_tex_mix = min(foam_tex, foam_tex2) * 1.4;
    float foam_mask = foam_tex_mix;

    voronoi *= foam_mask;

    float blob_thresh = 0.5 - foam_strength * 0.35;
    float blobs = smoothstep(blob_thresh, blob_thresh + 0.25, voronoi);
    float active_bubbles = blobs * 0.55;

    float crest_tip_mask = face_foam * crest_boost;
    crest_tip_mask = smoothstep(0.1, 0.6, crest_tip_mask);
    active_bubbles = mix(active_bubbles, 1.0, crest_tip_mask * 1.0);
    active_bubbles *= 0.55;

    vec2 uv_res = vec2(uv_base.x * 0.55 - uv_base.y * 0.55, uv_base.x * 0.55 + uv_base.y * 0.55) * 2.5 + u_time * 0.005;
    float res_voronoi = voronoi_foam(uv_res, 0.3);
    float res_thresh = 0.85 - u_residual_intensity * 0.3;
    float rb_dot = smoothstep(res_thresh - 0.05, res_thresh + 0.05, res_voronoi);
    float rb_zone = smoothstep(0.12, 0.4, pix_steepness);
    rb_zone = max(rb_zone, smoothstep(0.4, 1.0, pix_height));
    float residual_foam = rb_dot * rb_zone * u_residual_intensity;

    float foam_fade = clamp(1.0 - distance(v_world_pos, CAMERA_POSITION_WORLD) / u_foam_fade_distance, 0.0, 1.0);
    foam_fade = foam_fade * foam_fade;

    float foam_bright = mix(1.0, 0.5 + blobs * 0.5, 0.2);
    color += (u_foam_color * active_bubbles * foam_bright + vec3(1.0) * residual_foam) * foam_fade;

    ALBEDO = color;
    METALLIC = 0.0;
    SPECULAR = 0.0;
    ROUGHNESS = 0.6;
    NORMAL = vec3(0.0, 1.0, 0.0);
    EMISSION = water_color * 0.1;
}