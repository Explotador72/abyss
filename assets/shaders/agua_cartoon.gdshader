shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_toon, specular_toon, depth_draw_always;

// ============================================================
//  AGUA CARTOON - Godot 4.x
//  Material de agua estilo caricatura con espuma de borde
//  (intersección con geometría) y espuma residual (estelas
//  flotantes). Todos los parámetros son editables desde el
//  Inspector al asignar este shader a un ShaderMaterial.
// ============================================================

// ---------- COLORES ----------
group_uniforms Colores;
uniform vec4 color_agua_superficial : source_color = vec4(0.35, 0.75, 0.95, 0.75);
uniform vec4 color_agua_profunda : source_color = vec4(0.02, 0.25, 0.55, 0.95);
uniform vec4 color_espuma : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float bandas_toon : hint_range(2.0, 8.0) = 3.0; // niveles de sombreado tipo cartoon

// ---------- ONDAS (VERTEX) ----------
group_uniforms Oleaje;
uniform float velocidad_ondas : hint_range(0.0, 5.0) = 1.0;
uniform float altura_ondas : hint_range(0.0, 1.0) = 0.08;
uniform float escala_ondas : hint_range(0.1, 10.0) = 2.0;
uniform float direccion_ondas_x : hint_range(-1.0, 1.0) = 1.0;
uniform float direccion_ondas_z : hint_range(-1.0, 1.0) = 0.3;

// ---------- ESPUMA DE BORDE (intersección con la orilla/objetos) ----------
group_uniforms Espuma_de_borde;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform float ancho_espuma_borde : hint_range(0.0, 4.0) = 0.6;
uniform float dureza_espuma_borde : hint_range(0.01, 1.0) = 0.35;

// ---------- ESPUMA RESIDUAL (estelas/manchas flotantes) ----------
group_uniforms Espuma_residual;
uniform float cantidad_espuma_residual : hint_range(0.0, 1.0) = 0.45;
uniform float escala_espuma_residual : hint_range(0.5, 20.0) = 6.0;
uniform float velocidad_espuma_residual : hint_range(0.0, 2.0) = 0.15;
uniform float suavidad_espuma_residual : hint_range(0.0, 0.5) = 0.08;

// ---------- SUPERFICIE / BRILLO ----------
group_uniforms Superficie;
uniform float transparencia : hint_range(0.0, 1.0) = 0.85;
uniform float fresnel_fuerza : hint_range(0.0, 4.0) = 1.5;
uniform float brillo_especular : hint_range(0.0, 1.0) = 0.6;
uniform float rugosidad : hint_range(0.0, 1.0) = 0.15;

varying float altura_vertice;

// --- ruido simple basado en hash (sin texturas externas) ---
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float valor = 0.0;
	float amplitud = 0.5;
	for (int i = 0; i < 3; i++) {
		valor += amplitud * ruido(p);
		p *= 2.0;
		amplitud *= 0.5;
	}
	return valor;
}

void vertex() {
	vec2 dir = normalize(vec2(direccion_ondas_x, direccion_ondas_z) + 0.0001);
	float t = TIME * velocidad_ondas;
	float onda1 = sin((VERTEX.x * dir.x + VERTEX.z * dir.y) * escala_ondas + t) ;
	float onda2 = sin((VERTEX.x * dir.y - VERTEX.z * dir.x) * escala_ondas * 1.7 + t * 1.3) * 0.5;
	float desplazamiento = (onda1 + onda2) * altura_ondas;
	VERTEX.y += desplazamiento;
	altura_vertice = desplazamiento;
}

void fragment() {
	// --- Fresnel (agua más clara/brillante en ángulo rasante) ---
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_fuerza);

	// --- Mezcla superficie/profundo en bandas tipo cartoon ---
	float banda = floor(fresnel * bandas_toon) / bandas_toon;
	vec4 color_base = mix(color_agua_profunda, color_agua_superficial, banda);

	// --- Espuma de borde por diferencia de profundidad (orilla / intersección con objetos) ---
	float profundidad_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 posicion_ndc = vec3(SCREEN_UV * 2.0 - 1.0, profundidad_raw);
	vec4 posicion_vista = INV_PROJECTION_MATRIX * vec4(posicion_ndc, 1.0);
	posicion_vista.xyz /= posicion_vista.w;
	float profundidad_escena = -posicion_vista.z;
	float profundidad_agua = -VERTEX.z;
	float diferencia = profundidad_escena - profundidad_agua;
	float espuma_borde = 1.0 - smoothstep(0.0, max(ancho_espuma_borde, 0.001), diferencia);
	espuma_borde = smoothstep(1.0 - dureza_espuma_borde, 1.0, espuma_borde);

	// --- Espuma residual flotante (manchas/estelas con ruido animado) ---
	vec2 uv_espuma = UV * escala_espuma_residual + vec2(TIME * velocidad_espuma_residual, TIME * velocidad_espuma_residual * 0.6);
	float ruido_espuma = fbm(uv_espuma);
	float umbral = 1.0 - cantidad_espuma_residual;
	float espuma_residual = smoothstep(umbral, umbral + suavidad_espuma_residual + 0.001, ruido_espuma);

	// --- Combinar ambas espumas ---
	float espuma_total = clamp(espuma_borde + espuma_residual, 0.0, 1.0);

	vec3 color_final = mix(color_base.rgb, color_espuma.rgb, espuma_total);
	float alpha_final = mix(color_base.a * transparencia, color_espuma.a, espuma_total);

	ALBEDO = color_final;
	ALPHA = alpha_final;
	ROUGHNESS = rugosidad;
	SPECULAR = brillo_especular;
	EMISSION = color_espuma.rgb * espuma_total * 0.15; // ligero brillo en la espuma
}
