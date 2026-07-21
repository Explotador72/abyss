shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// --- Flipbook textures ---
uniform sampler2D u_normal_flipbook : filter_linear_mipmap;
uniform sampler2D u_height_flipbook : filter_linear_mipmap;
uniform sampler2D u_foam_flipbook   : filter_linear_mipmap;

// --- Flipbook layout ---
uniform vec2  u_frames         = vec2(8.0, 8.0);
uniform float u_fps            = 15.0;
uniform float u_margin         = 4.0;
uniform float u_tex_resolution = 512.0;

// --- Water appearance ---
uniform float u_height_scale    : hint_range(0.0, 5.0)  = 1.5;
uniform float u_tiling          : hint_range(0.1, 20.0) = 4.0;
uniform float u_normal_strength : hint_range(0.0, 2.0)  = 0.8;
uniform float u_detail_scale    : hint_range(0.0, 1.0)  = 0.3;
uniform float u_detail_strength : hint_range(0.0, 1.0)  = 0.3;
uniform vec3  u_deep_color      : source_color = vec3(0.0, 0.15, 0.35);
uniform vec3  u_shallow_color   : source_color = vec3(0.0, 0.50, 0.60);
uniform vec3  u_foam_color      : source_color = vec3(1.0, 1.0, 1.0);
uniform float u_foam_threshold  : hint_range(0.0, 1.0) = 0.45;
uniform float u_foam_softness   : hint_range(0.0, 0.5) = 0.1;
uniform float u_roughness       : hint_range(0.0, 1.0) = 0.1;
uniform float u_metallic        : hint_range(0.0, 1.0) = 0.0;
uniform float u_specular        : hint_range(0.0, 1.0) = 0.5;

varying vec2  v_uv_smooth;
varying float v_height;

// ---- Null texture helpers ----
bool _has_normal() { return textureSize(u_normal_flipbook, 0).x > 0; }
bool _has_height() { return textureSize(u_height_flipbook, 0).x > 0; }
bool _has_foam()   { return textureSize(u_foam_flipbook, 0).x > 0; }

// ---- Oversampling helpers ----
vec2 _margin_uv() {
    return vec2(u_margin / (u_tex_resolution * u_frames.x),
                u_margin / (u_tex_resolution * u_frames.y));
}
vec2 _content_size() {
    vec2 m = _margin_uv();
    return vec2(1.0 / u_frames.x - 2.0 * m.x,
                1.0 / u_frames.y - 2.0 * m.y);
}

float _wrap_frame(float frame) {
    float total = u_frames.x * u_frames.y;
    return mod(frame, total);
}

vec2 _frame_uv(float frame, vec2 tile_uv) {
    frame = _wrap_frame(frame);
    float fx = mod(frame, u_frames.x);
    float fy = floor(frame / u_frames.x);
    vec2 m  = _margin_uv();
    vec2 cs = _content_size();
    vec2 fo = vec2(fx, fy) / u_frames;
    return fo + m + tile_uv * cs;
}

// ---- Sample helpers ----
float _height_vtx(float frame, vec2 tile_uv) {
    if (!_has_height())
        return 0.0;
    return texture(u_height_flipbook, _frame_uv(frame, tile_uv)).r;
}
float _height_frag(float frame, vec2 tile_uv, float lod) {
    if (!_has_height())
        return 0.0;
    return textureLod(u_height_flipbook, _frame_uv(frame, tile_uv), lod).r;
}
vec3 _normal_frag(float frame, vec2 tile_uv, float lod) {
    if (!_has_normal())
        return vec3(0.0, 0.0, 1.0);
    vec3 n = textureLod(u_normal_flipbook, _frame_uv(frame, tile_uv), lod).rgb;
    return n * 2.0 - 1.0;
}
float _foam_frag(float frame, vec2 tile_uv, float lod) {
    if (!_has_foam())
        return 0.0;
    return textureLod(u_foam_flipbook, _frame_uv(frame, tile_uv), lod).r;
}

// ---- LOD con derivadas (evita artifacts de mipmap en flipbook) ----
float _compute_lod(vec2 uv_smooth) {
    vec2 cs  = _content_size();
    vec2 dx  = dFdx(uv_smooth) * cs;
    vec2 dy  = dFdy(uv_smooth) * cs;
    float md = max(dot(dx, dx), dot(dy, dy));
    if (md < 1e-12 || md != md)
        return 0.0;
    float lod = 0.5 * log2(md) + log2(u_tex_resolution);
    return clamp(lod, 0.0, 8.0);
}

// ============================================================
// VERTEX
// ============================================================
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 uv_smooth = world_pos.xz * u_tiling;
    vec2 tile_uv   = fract(uv_smooth);

    float frame    = floor(TIME * u_fps);
    float frac_t   = fract(TIME * u_fps);

    float h0 = _height_vtx(frame, tile_uv);
    float h1 = _height_vtx(frame + 1.0, tile_uv);
    float h  = mix(h0, h1, frac_t);

    VERTEX.y    += h * u_height_scale;
    v_height     = h;
    v_uv_smooth  = uv_smooth;
}

// ============================================================
// FRAGMENT
// ============================================================
void fragment() {
    vec2 tile_uv  = fract(v_uv_smooth);
    float frame   = floor(TIME * u_fps);
    float frac_t  = fract(TIME * u_fps);
    float n_frame = frame + 1.0;

    float lod = _compute_lod(v_uv_smooth);

    // --- Normal ---
    vec3 n0 = _normal_frag(frame,  tile_uv, lod);
    vec3 n1 = _normal_frag(n_frame, tile_uv, lod);
    vec3 normal = normalize(mix(n0, n1, frac_t));

    if (u_detail_strength > 0.001 && _has_normal()) {
        vec2 dup = tile_uv * u_detail_scale + normal.xy * u_detail_strength * 0.05;
        vec3 nd0 = _normal_frag(frame,  dup, lod + 1.0);
        vec3 nd1 = _normal_frag(n_frame, dup, lod + 1.0);
        vec3 nd  = normalize(mix(nd0, nd1, frac_t));
        normal = normalize(vec3(normal.xy + nd.xy * u_detail_strength, normal.z));
    }

    vec3 world_normal = normalize((MODEL_MATRIX * vec4(normal, 0.0)).xyz);
    NORMAL = (VIEW_MATRIX * vec4(world_normal, 0.0)).xyz;

    // --- Color por altura ---
    float h0 = _height_frag(frame,  tile_uv, lod);
    float h1 = _height_frag(n_frame, tile_uv, lod);
    float h  = mix(h0, h1, frac_t);
    float hn = clamp(h * 0.5 + 0.5, 0.0, 1.0);
    vec3 water_color = mix(u_deep_color, u_shallow_color, hn);

    // --- Foam ---
    float foam_mask = 0.0;
    if (_has_foam()) {
        float f0 = _foam_frag(frame,  tile_uv, lod);
        float f1 = _foam_frag(n_frame, tile_uv, lod);
        float foam = mix(f0, f1, frac_t);
        foam_mask = smoothstep(u_foam_threshold - u_foam_softness,
                               u_foam_threshold + u_foam_softness, foam);
    }

    ALBEDO = mix(water_color, u_foam_color, foam_mask);
    ROUGHNESS = mix(u_roughness, 0.9, foam_mask);
    METALLIC  = u_metallic;
    SPECULAR  = u_specular;
}
