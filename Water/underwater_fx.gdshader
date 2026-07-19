shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

uniform float sea_height    : hint_range(0.0, 5.0)  = 1.3;
uniform float sea_choppy    : hint_range(0.0, 10.0) = 4.0;
uniform float sea_speed     : hint_range(0.0, 5.0)  = 1.5;
uniform float sea_freq      : hint_range(0.0, 0.5)  = 0.08;

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

uniform float height_offset = 0.0;

uniform vec3  underwater_color     : source_color = vec3(0.02, 0.18, 0.25);
uniform float absorption_strength  : hint_range(0.0, 2.0) = 0.35;
uniform float deep_tint_strength   : hint_range(0.0, 1.0) = 0.65;

uniform float refraction_amount    : hint_range(0.0, 0.015) = 0.004;
uniform float refraction_speed     : hint_range(0.0, 3.0)   = 0.7;

uniform float water_level_fudge    : hint_range(-1.5, 1.5) = 0.0;
uniform float water_base_height    : hint_range(-5.0, 5.0) = 0.7;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture;

void vertex() {
}

void fragment() {
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    vec3 scene_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
    vec3 final_color = scene_color;
    float final_alpha = 0.0;

    // Only apply underwater effect when camera is below water base height
    if (cam_pos.y < water_base_height) {
        float depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;

        // Reconstruct world position from depth buffer
        // Avoid division by zero for sky/background pixels (depth close to 1.0)
        bool underwater = false;
        vec3 wp;

        if (depth < 0.999) {
            vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
            vec4 world_pos = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
            wp = world_pos.xyz / world_pos.w;
        } else {
            // Sky pixel: use a point at water level straight ahead
            vec3 forward = (INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz;
            wp = cam_pos + forward * (max(cam_pos.y - water_base_height, 0.5) / max(-forward.y, 0.01));
        }

        float surface_y = get_wave_height(wp.xz) + height_offset + water_level_fudge;

        // Clamp surface_y relative to water_base_height for stability
        surface_y = max(surface_y, water_base_height - 5.0);

        if (wp.y <= surface_y) {
            underwater = true;
        }

        if (underwater) {
            final_alpha = 1.0;

            vec2 noise_dir = vec2(
                noise(SCREEN_UV * 12.0 + TIME * refraction_speed * vec2(1.0, 0.4)),
                noise(SCREEN_UV * 12.0 + TIME * refraction_speed * vec2(0.6, 1.0))
            ) * 2.0 - 1.0;

            vec2 uv_distorted = SCREEN_UV + noise_dir * refraction_amount;
            vec3 refracted = texture(SCREEN_TEXTURE, uv_distorted).rgb;

            float thickness = surface_y - wp.y;
            // If sky pixel, use a default thickness
            if (depth >= 0.999 || thickness < 0.0) {
                thickness = surface_y - cam_pos.y;
            }
            thickness = max(thickness, 0.01);

            float transmittance = exp(-thickness * absorption_strength);
            vec3 tinted = mix(refracted, underwater_color, deep_tint_strength);
            final_color = tinted * transmittance;

            float fog = 1.0 - exp(-thickness * absorption_strength * 0.7);
            final_color = mix(final_color, underwater_color, fog * 0.85);
        }
    }

    ALBEDO = final_color;
    ALPHA = final_alpha;
}

