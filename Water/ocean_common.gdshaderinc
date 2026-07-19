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
