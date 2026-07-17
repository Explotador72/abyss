shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform float u_time : hint_range(0.0, 1000.0) = 0.0;
uniform float height_scale : hint_range(0.0, 10.0) = 1.0;
uniform float u_wavelength_scale : hint_range(0.1, 5.0) = 1.0;

uniform sampler2D u_normal_a : source_color;
uniform sampler2D u_normal_b : source_color;
uniform sampler2D u_foam : source_color;
uniform sampler2D u_caustics : source_color;

uniform vec2 u_normal_scale = vec2(2.5, 2.5);
uniform vec2 u_normal_scale2 = vec2(3.5, 3.5);
uniform vec2 u_foam_scale = vec2(0.35, 0.35);
uniform vec2 u_foam_scale2 = vec2(0.6, 0.6);
uniform vec2 u_caustic_scale = vec2(0.35, 0.35);
uniform float u_normal_speed = 0.04;
uniform float u_foam_speed = 0.008;
uniform float u_uv_distortion = 0.08;

// ---- Cartoon water palette ----
// Richer, more saturated stylized palette with an extra mid-tone so the
// posterized bands read as "painted" gradients instead of two flat blocks.
uniform vec3 u_deep_color : source_color = vec3(0.01, 0.20, 0.55);
uniform vec3 u_mid_color : source_color = vec3(0.02, 0.55, 0.75);
uniform vec3 u_shallow_color : source_color = vec3(0.25, 0.90, 0.92);
uniform vec3 u_trough_color : source_color = vec3(0.0, 0.14, 0.38);
uniform vec3 u_foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 u_foam_shadow_color : source_color = vec3(0.55, 0.75, 0.85);
uniform vec3 u_sun_color : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 u_sky_color : source_color = vec3(0.65, 0.88, 0.98);
uniform vec3 u_ink_color : source_color = vec3(0.02, 0.08, 0.15);

uniform float u_foam_threshold = 0.2;
uniform float u_foam_intensity = 0.9;
uniform float u_foam_softness = 0.15;
uniform vec2 u_residual_steepness = vec2(0.12, 0.4);
uniform vec2 u_residual_height = vec2(0.4, 1.0);
uniform float u_residual_spread = 0.3;
uniform float u_crest_foam_intensity = 0.55;
uniform float u_crest_tip_density : hint_range(0.0, 5.0) = 1.0;
uniform float u_crest_color_blend : hint_range(0.0, 1.0) = 0.0;
uniform float u_residual_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float u_residual_threshold : hint_range(0.0, 1.0) = 0.92;
uniform float u_residual_variation : hint_range(0.0, 1.0) = 0.3;
uniform float u_foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform float u_foam_color_variation : hint_range(0.0, 1.0) = 0.2;
uniform float u_foam_fade_distance = 200.0;
uniform float u_min_foam_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float u_max_foam_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float u_foam_texture_influence : hint_range(0.0, 1.0) = 0.5;
uniform float u_foam_edge_softness : hint_range(0.0, 1.0) = 0.35;

// ---- Lighting / shading style ----
uniform float u_roughness = 0.6;
uniform float u_metallic = 0.0;
uniform float u_normal_strength = 0.25;
uniform float u_vertex_normal_blend : hint_range(0.0, 1.0) = 0.0;
uniform float u_caustic_strength : hint_range(0.0, 2.0) = 0.35;
uniform float u_ambient_fill : hint_range(0.0, 1.0) = 0.08;
uniform float u_band_count = 4.0;
uniform float u_band_softness : hint_range(0.0, 0.5) = 0.08;
uniform float u_sparkle_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float u_sparkle_density : hint_range(1.0, 40.0) = 14.0;
uniform float u_sparkle_speed = 0.6;
uniform float u_fresnel_rim_power : hint_range(0.5, 8.0) = 3.0;

uniform vec2 u_caustic_scale2 = vec2(0.45, 0.45);

uniform float u_wave_visual_scale = 2.0;
uniform float u_crest_sharpness = 1.2;
uniform float u_normal_amplitude_scale = 1.5;

uniform float u_mesh_scale_factor = 2.0;
uniform float u_wave_density_scale = 0.5;  // Reduced density for larger mesh
uniform float u_sub_wave_scale = 1.0;
uniform vec3 u_camera_pos = vec3(0.0);
uniform float u_view_distance = 2000.0;
uniform float u_fade_start_ratio = 0.15;
uniform float u_fade_sharpness = 1.5;

uniform vec4 u_neighbor_step = vec4(0.0); // x:left, y:right, z:top, w:bottom step size (0 = no stitch)
uniform float u_half_chunk = 250.0;

varying vec3 v_world_pos;
varying vec3 v_vertex_normal;
varying vec3 v_tangent;
varying vec3 v_binormal;
varying float v_wave_height;
varying float v_wave_steepness;

// Hash function for noise
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// Smooth 2D noise (for distort_uv and sparkle)
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Voronoi foam: puntos en posiciones aleatorias sin cuadrícula visible
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

// Sparse sparkle points that flicker over time — cheap stylized sun-glitter
float sparkle_noise(vec2 p, float t) {
    vec2 cell = floor(p);
    float base = hash21(cell);
    float flicker = fract(base * 91.7 + t);
    float pulse = smoothstep(0.85, 1.0, flicker) * smoothstep(1.0, 0.85, flicker * 0.999 + 0.001);
    return step(0.9, base) * pulse;
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
        float wl = wls[i] * max(u_wavelength_scale, 0.1) / u_wave_density_scale;
        float amp = amps[i] * height_scale;
        float k = 2.0 * PI / wl;
        float c = sqrt(9.8 / k);
        float jitter_strength = 0.04 + (1.0 - amps[i] / 0.9) * 0.3;
        vec2 jitter = vec2(
            sin(pos_xz.x * 0.025 + pos_xz.y * 0.018 + seed),
            cos(pos_xz.x * 0.018 + pos_xz.y * 0.025 + seed * 1.3)
        ) * jitter_strength;
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
    float half_chunk = u_half_chunk;
    if (u_neighbor_step.x > 0.001 && abs(pos.x + half_chunk) < 0.001) {
        pos.z = -half_chunk + round((pos.z + half_chunk) / u_neighbor_step.x) * u_neighbor_step.x;
    }
    if (u_neighbor_step.y > 0.001 && abs(pos.x - half_chunk) < 0.001) {
        pos.z = -half_chunk + round((pos.z + half_chunk) / u_neighbor_step.y) * u_neighbor_step.y;
    }
    if (u_neighbor_step.z > 0.001 && abs(pos.z + half_chunk) < 0.001) {
        pos.x = -half_chunk + round((pos.x + half_chunk) / u_neighbor_step.z) * u_neighbor_step.z;
    }
    if (u_neighbor_step.w > 0.001 && abs(pos.z - half_chunk) < 0.001) {
        pos.x = -half_chunk + round((pos.x + half_chunk) / u_neighbor_step.w) * u_neighbor_step.w;
    }
    vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec2 pos_xz = world_origin.xz + pos.xz;
    float t = u_time * 0.39;

    vec2 dirs[16] = vec2[](
        vec2(1.0, 0.0), vec2(0.7, 0.7), vec2(0.0, 1.0), vec2(-0.7, 0.7),
        vec2(-1.0, 0.0), vec2(-0.7, -0.7), vec2(0.0, -1.0), vec2(0.7, -0.7),
        vec2(0.9, 0.4), vec2(0.4, 0.9), vec2(-0.4, 0.9), vec2(-0.9, 0.4),
        vec2(-0.9, -0.4), vec2(-0.4, -0.9), vec2(0.4, -0.9), vec2(0.9, -0.4)
    );

    float wls[16] = float[](24.0, 18.0, 13.0, 9.0, 6.5, 4.5, 3.2, 2.5, 1.8, 1.2, 0.8, 0.5, 0.3, 0.18, 0.1, 0.06);
    float amps[16] = float[](0.90, 0.65, 0.50, 0.40, 0.30, 0.22, 0.16, 0.12, 0.08, 0.06, 0.04, 0.03, 0.02, 0.015, 0.01, 0.007);

    vec2 env_dir = vec2(0.025, 0.035);
    float env1 = sin(dot(pos_xz, env_dir) + t * 0.04) * 0.5 + 0.5;
    float env2 = sin(dot(pos_xz, vec2(-0.018, 0.04)) + t * 0.03) * 0.5 + 0.5;
    float envelope = mix(env1, env2, 0.5);
    envelope = envelope * 0.4 + 0.6;

    float height = 0.0;
    vec2 grad = vec2(0.0);
    vec2 disp = vec2(0.0);

    float ddx_x = 1.0, ddx_y = 0.0, ddx_z = 0.0;
    float ddz_x = 0.0, ddz_y = 0.0, ddz_z = 1.0;

    for (int i = 0; i < 16; i++) {
        float seed = float(i) * 2.399;
        float wl = wls[i] * max(u_wavelength_scale, 0.1) / u_wave_density_scale;
        float amp = amps[i] * height_scale;
        amp *= envelope;

        float fade_dist = distance(world_origin.xz + pos.xz, u_camera_pos.xz);
        float fade_start_val = u_view_distance * u_fade_start_ratio;
        float fade_t = clamp((fade_dist - fade_start_val) / max(u_view_distance - fade_start_val, 0.001), 0.0, 1.0);
        float per_vertex_fade = 1.0 - pow(fade_t, u_fade_sharpness);

        amp *= u_wave_visual_scale * per_vertex_fade;
        if (i >= 12) { amp *= u_sub_wave_scale; }

        float k = 2.0 * PI / wl;
        float c = sqrt(9.8 / k);

        float jitter_strength = 0.04 + (1.0 - amps[i] / 0.9) * 0.3;
        vec2 jitter = vec2(
            sin(pos_xz.x * 0.025 + pos_xz.y * 0.018 + seed),
            cos(pos_xz.x * 0.018 + pos_xz.y * 0.025 + seed * 1.3)
        ) * jitter_strength;
        vec2 dir = normalize(dirs[i] + jitter);

        float phase_off = sin(pos_xz.x * 0.01 + pos_xz.y * 0.014 + seed) * 2.0;
        phase_off += sin(pos_xz.x * 0.02 - pos_xz.y * 0.012 + seed * 1.7) * 1.2;

        float f = k * dot(dir, pos_xz) + c * t + phase_off;
        float s = sin(f);
        float co = cos(f);

        height += amp * s;
        grad += amp * k * dir * co;

        float Qi = 1.0 / (k * amp * 8.0 + 0.001);
        Qi = min(Qi * u_crest_sharpness, 0.7);
        disp += Qi * amp * dir * co;

        float QkA = Qi * amp * k * u_normal_amplitude_scale;
        ddx_x -= QkA * dir.x * dir.x * s;
        ddx_y += amp * k * dir.x * co;
        ddx_z -= QkA * dir.x * dir.y * s;
        ddz_x -= QkA * dir.x * dir.y * s;
        ddz_y += amp * k * dir.y * co;
        ddz_z -= QkA * dir.y * dir.y * s;
    }

    pos.xz += disp;
    pos.y += height;
    VERTEX = pos;

    vec3 tangent = normalize(vec3(ddx_x, ddx_y, ddx_z));
    vec3 bitangent = normalize(vec3(ddz_x, ddz_y, ddz_z));
    vec3 normal = normalize(cross(tangent, bitangent));

    v_world_pos = (MODEL_MATRIX * vec4(pos, 1.0)).xyz;
    v_vertex_normal = normalize((MODEL_MATRIX * vec4(normal, 0.0)).xyz);

    vec3 world_up = vec3(0.0, 1.0, 0.0);
    vec3 tangent_vec = normalize(cross(normal, world_up));
    if (length(tangent_vec) < 0.001) {
        tangent_vec = vec3(1.0, 0.0, 0.0);
    }
    vec3 binormal_vec = normalize(cross(normal, tangent_vec));
    v_tangent = normalize((MODEL_MATRIX * vec4(tangent_vec, 0.0)).xyz);
    v_binormal = normalize((MODEL_MATRIX * vec4(binormal_vec, 0.0)).xyz);

    v_wave_height = height;
    v_wave_steepness = length(grad);
    NORMAL = normal;
}

vec2 distort_uv(vec2 uv, float t) {
    vec2 d;
    d.x = smooth_noise(uv * 0.4 + t * 0.6);
    d.y = smooth_noise(uv * 0.4 + t * 0.6 + vec2(50.0));
    return uv + (d - 0.5) * u_uv_distortion;
}

vec3 blend_normals(vec3 a, vec3 b) {
    vec3 r = vec3(a.xy + b.xy, a.z);
    if (length(r) < 0.001) { return vec3(0.0, 0.0, 1.0); }
    return normalize(r);
}

void fragment() {
    vec3 world_pos = v_world_pos;
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);

    vec3 geo_normal = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
    vec3 world_normal = normalize(mix(geo_normal, v_vertex_normal, u_vertex_normal_blend));
    vec3 world_up = vec3(0.0, 1.0, 0.0);
    vec3 T = normalize(cross(world_normal, world_up));
    if (length(T) < 0.001) { T = vec3(1.0, 0.0, 0.0); }
    vec3 B = normalize(cross(world_normal, T));

    vec2 uv_base = world_pos.xz;
    float t = u_time * u_normal_speed;
    vec2 uv_a = distort_uv(uv_base * u_normal_scale + t * vec2(0.7, 0.3), t);
    vec2 uv_b = distort_uv(uv_base * u_normal_scale2 - t * vec2(0.4, 0.6), t * 0.7);

    vec3 na = texture(u_normal_a, uv_a).rgb;
    vec3 nb = texture(u_normal_b, uv_b).rgb;
    na = na * 2.0 - 1.0;
    nb = nb * 2.0 - 1.0;

    vec3 n_blend = blend_normals(na, nb);

    vec3 final_normal = normalize(T * n_blend.x + B * n_blend.y + world_normal * n_blend.z);
    final_normal = normalize(mix(world_normal, final_normal, u_normal_strength));

    float NdV = max(dot(final_normal, view_dir), 0.0);
    float raw_fresnel = pow(1.0 - NdV, u_fresnel_rim_power);
    float fresnel = mix(0.04, 0.25, raw_fresnel);

    // ===== CARTOON COLOR (posterized, now with soft band edges + 3-color ramp) =====
    vec2 wave = fragment_wave(v_world_pos.xz);
    float pix_height = wave.x;
    float pix_steepness = wave.y;
    float height_norm = smoothstep(-1.0, 2.0, pix_height);

    float band_f = height_norm * u_band_count;
    float band = floor(band_f) / u_band_count;
    if (u_band_softness > 0.0) {
        float band_local = fract(band_f);
        float soft = smoothstep(0.5 - u_band_softness, 0.5 + u_band_softness, band_local);
        band = mix(band, ceil(band_f) / u_band_count, soft * step(1.0, ceil(band_f) - floor(band_f) + 1.0) * 0.0 + soft * 0.0);
        // simple smooth interpolation between current and next band
        band = mix(floor(band_f) / u_band_count, (floor(band_f) + 1.0) / u_band_count, soft);
    }

    // 3-stop ramp: trough -> mid -> shallow, gives a richer painted gradient
    vec3 water_color = mix(u_trough_color, u_mid_color, clamp(band * 2.0, 0.0, 1.0));
    water_color = mix(water_color, u_shallow_color, clamp(band * 2.0 - 1.0, 0.0, 1.0));

    float crest_mask = smoothstep(0.8, 1.8, max(pix_height, 0.0));
    water_color = mix(water_color, u_foam_color, crest_mask * u_crest_color_blend);

    // Fresnel-driven sky tint: cartoon water reads more "premium" when grazing
    // angles pick up a cool sky color instead of staying flat.
    water_color = mix(water_color, u_sky_color, raw_fresnel * 0.35);

    // ===== SPECULAR CEL (hard toon highlight, warm sun tint) =====
    vec3 light_dir = normalize(vec3(0.4, 0.8, 0.3));
    vec3 half_dir = normalize(view_dir + light_dir);
    float spec = dot(final_normal, half_dir);
    float highlight = step(0.92, spec);
    float highlight_soft = smoothstep(0.85, 0.92, spec) - highlight;
    water_color += u_sun_color * highlight;
    water_color += u_sun_color * 0.35 * highlight_soft;

    // ===== SUN SPARKLE (small flickering glints across the surface) =====
    vec2 sparkle_uv = uv_base * (u_sparkle_density * 0.1) + final_normal.xz * 2.0;
    float sparkle_t = u_time * u_sparkle_speed;
    float sparkle = sparkle_noise(sparkle_uv, sparkle_t);
    sparkle *= smoothstep(0.5, 0.95, spec); // only where facing the light
    water_color += u_sun_color * sparkle * u_sparkle_intensity;

    // ===== CAUSTICS (subtle underwater light pattern in shallow zones) =====
    vec2 uv_caustic = distort_uv(uv_base * u_caustic_scale + u_time * vec2(0.05, 0.03), t * 0.5);
    vec2 uv_caustic2 = uv_base * u_caustic_scale2 - u_time * vec2(0.04, 0.06);
    float caustic_a = texture(u_caustics, uv_caustic).r;
    float caustic_b = texture(u_caustics, uv_caustic2).r;
    float caustic_pattern = min(caustic_a, caustic_b);
    float shallow_zone = 1.0 - height_norm; // stronger in troughs / calmer areas
    water_color += u_sky_color * caustic_pattern * u_caustic_strength * shallow_zone * 0.5;

    // ===== FOAM CARTOON (blobs shaped/broken up by the foam texture) =====
    float face_foam = smoothstep(0.02, 0.4, pix_steepness);
    float crest_boost = smoothstep(0.3, 2.0, max(pix_height, 0.0));
    float foam_area = face_foam * (u_residual_spread + crest_boost * (1.0 - u_residual_spread));
    float foam_strength = smoothstep(0.0, 0.6, foam_area * u_foam_intensity);

    float foam_time = u_time * u_foam_speed;
    vec2 screen_jitter = FRAGCOORD.xy * 0.0005;
    vec2 uv_foam = vec2(
        uv_base.x * 0.6 - uv_base.y * 0.4,
        uv_base.x * 0.4 + uv_base.y * 0.6
    ) * 0.8 + screen_jitter * 3.0;
    float voronoi = voronoi_foam(uv_foam + foam_time * 0.3, 0.35);

    // Break up the procedural blobs with the actual foam texture so edges
    // look hand-painted instead of perfectly round.
    vec2 uv_foam_tex = uv_base * u_foam_scale + foam_time * vec2(0.3, -0.2);
    vec2 uv_foam_tex2 = uv_base * u_foam_scale2 - foam_time * vec2(-0.2, 0.25);
    float foam_tex = texture(u_foam, uv_foam_tex).r;
    float foam_tex2 = texture(u_foam, uv_foam_tex2).r;
    float foam_tex_mix = mix(1.0, min(foam_tex, foam_tex2) * 1.4, u_foam_texture_influence);
    voronoi *= foam_tex_mix;

    float blob_thresh = 0.5 - foam_strength * 0.35;
    float edge_soft = mix(0.05, 0.4, u_foam_edge_softness);
    float blobs = smoothstep(blob_thresh, blob_thresh + edge_soft, voronoi);
    float blob_core = smoothstep(blob_thresh + edge_soft * 0.5, blob_thresh + edge_soft, voronoi);
    float active_bubbles = blobs * u_crest_foam_intensity;

    float crest_tip_mask = face_foam * crest_boost;
    crest_tip_mask = smoothstep(0.1, 0.6, crest_tip_mask);
    active_bubbles = mix(active_bubbles, 1.0, crest_tip_mask * u_crest_tip_density);
    active_bubbles *= u_crest_foam_intensity;

    vec2 uv_res = vec2(
        uv_base.x * 0.55 - uv_base.y * 0.55,
        uv_base.x * 0.55 + uv_base.y * 0.55
    ) * 2.5 + FRAGCOORD.xy * 0.0004 + u_time * 0.005;
    float res_voronoi = voronoi_foam(uv_res, 0.3);
    float res_tex = texture(u_foam, uv_res * 0.3).r;
    res_voronoi *= mix(1.0, res_tex, u_foam_texture_influence * 0.6);
    float res_thresh = 0.85 - u_residual_intensity * 0.3;
    float rb_dot = smoothstep(res_thresh - 0.05, res_thresh + 0.05, res_voronoi);
    float rb_zone = smoothstep(u_residual_steepness.x, u_residual_steepness.y, pix_steepness);
    rb_zone = max(rb_zone, smoothstep(u_residual_height.x, u_residual_height.y, pix_height));
    float residual_foam = rb_dot * rb_zone * u_residual_intensity;

    // ===== INK RIM (hand-drawn outline toward the horizon) =====
    float rim = smoothstep(0.2, 0.7, raw_fresnel);
    float ink_rim = step(0.5, rim);
    float rim_dark = ink_rim * 0.35;

    float foam_dist = distance(world_pos, CAMERA_POSITION_WORLD);
    float foam_fade = clamp(1.0 - foam_dist / u_foam_fade_distance, 0.0, 1.0);
    foam_fade = foam_fade * foam_fade;

    vec3 color = water_color;

    // Two-tone foam: bright core + slightly shaded edge, like flat-shaded
    // cel foam in stylized games, instead of one flat white blob.
    float foam_total = clamp((active_bubbles * u_foam_amount) * foam_fade, 0.0, 1.0);
    float foam_total_clamped = clamp(foam_total, u_min_foam_intensity, u_max_foam_intensity);
    vec3 foam_shaded = mix(u_foam_shadow_color, u_foam_color, blob_core);
    float foam_bright = mix(1.0, 0.5 + blobs * 0.5, u_foam_color_variation);

    color = mix(color, foam_shaded * foam_bright, foam_total_clamped);
    color += vec3(1.0) * residual_foam * foam_fade;

    // Ink outline around foam edges for that hand-drawn cartoon look
    float foam_outline = smoothstep(blob_thresh - 0.03, blob_thresh, voronoi) - blobs;
    color = mix(color, u_ink_color, clamp(foam_outline * foam_fade * 0.6, 0.0, 1.0));

    color *= 1.0 - rim_dark;
    color += u_ambient_fill * u_sky_color;

    ALBEDO = color;
    METALLIC = u_metallic;
    SPECULAR = 0.0;
    ROUGHNESS = u_roughness;
    NORMAL = final_normal;
    EMISSION = water_color * 0.1;
}
