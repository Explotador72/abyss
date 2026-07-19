shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float refraction_amount : hint_range(0.0, 0.015) = 0.004;
uniform float refraction_speed  : hint_range(0.0, 3.0)   = 0.7;
uniform vec3  underwater_color  : source_color = vec3(0.02, 0.18, 0.25);
uniform float tint_strength     : hint_range(0.0, 1.0) = 0.5;
uniform float water_level       : hint_range(-5.0, 5.0) = 0.7;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

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
        mix(hash12(i + vec2(0.0,0.0)), hash12(i + vec2(1.0,0.0)), u.x),
        mix(hash12(i + vec2(0.0,1.0)), hash12(i + vec2(1.0,1.0)), u.x), u.y);
}

void vertex() {
}

void fragment() {
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    vec3 final_color;

    if (cam_pos.y > water_level) {
        final_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
    } else {
        vec2 noise_dir = vec2(
            noise(SCREEN_UV * 12.0 + TIME * refraction_speed * vec2(1.0, 0.4)),
            noise(SCREEN_UV * 12.0 + TIME * refraction_speed * vec2(0.6, 1.0))
        ) * 2.0 - 1.0;

        vec2 uv_distorted = SCREEN_UV + noise_dir * refraction_amount;
        vec3 scene_color = texture(SCREEN_TEXTURE, uv_distorted).rgb;

        final_color = mix(scene_color, underwater_color, tint_strength);
    }

    ALBEDO = final_color;
}
