
shader_type spatial;

// ===========================================================================
//  INFECCION — "la plasta" — PROBE C (colores LITERALES, lit, EMISSION=0)
//
//  Evidencia acumulada: GDScript VE color_base=(0.86,0.83,0.73) en el
//  material y la textura bien cableada ([DIAG]), pero el shader pinta
//  negro -> los uniforms de color NO llegan a la GPU. Sospecha: el hint
//  source_color sobre vec3 (o empujar Color a un uniform vec3).
//  Este probe pone los colores como LITERALES: si sale crema, es eso. :v
// ===========================================================================

render_mode cull_disabled, depth_draw_opaque;

global uniform float wind_intensity;
global uniform vec3 wind_direction;

uniform sampler2D textura_huecos : source_color, filter_linear_mipmap, repeat_enable;

uniform vec3 color_base : source_color = vec3(0.86, 0.83, 0.73);
uniform vec3 color_rojo : source_color = vec3(0.4, 0.04, 0.045);
uniform vec3 color_agujero : source_color = vec3(0.85, 0.07, 0.05);
uniform float escala_huecos = 0.9;
uniform float umbral_huecos = 0.42;
uniform float intensidad_grumos = 0.05;
uniform float frecuencia_latido = 0.8;
uniform float brillo_mucosa = 0.2;
uniform float intensidad_emision = 1.4;
uniform vec3 jugador_pos = vec3(0.0, -10000.0, 0.0);
uniform float jugador_actividad = 0.0;

varying vec3 pos_mundo;
varying vec3 norm_mundo;


void vertex() {
	vec3 pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 nw = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 an = abs(nw);
	vec2 plano;
	if (an.y >= an.x && an.y >= an.z) {
		plano = pw.xz;
	} else if (an.x >= an.z) {
		plano = pw.zy;
	} else {
		plano = pw.xy;
	}
	float e = 1.0 / max(escala_huecos, 0.05);
	float g = texture(textura_huecos, plano * e).r;
	float pulso = sin(TAU * TIME * frecuencia_latido) * 0.5 + 0.5;
	float amp = intensidad_grumos * (0.75 + 0.25 * pulso);
	VERTEX += NORMAL * ((g - 0.5) * 2.0 * amp);

	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	norm_mundo = nw;
}


void fragment() {
	float largo_viento = length(wind_direction);
	vec2 viento = largo_viento > 1e-4 ? normalize(wind_direction).xz : vec2(0.0, 1.0);
	float fuerza_viento = clamp(wind_intensity, 0.0, 1.0);

	vec2 centro = (UV - 0.5) * 2.0;
	float radio = length(centro);
	float ruido = texture(textura_huecos, UV * 2.7).r;
	vec2 dir_centro = centro / max(radio, 1e-4);
	float alineado = max(dot(dir_centro, viento), 0.0);
	float borde = radio + (ruido - 0.5) * 0.6
			+ fuerza_viento * 0.05 * alineado
			* (0.5 + 0.5 * sin(TAU * TIME * 0.6 + ruido * 6.2831));
	if (borde > 1.0) {
		discard;
	}

	vec3 pesos = pow(abs(norm_mundo), vec3(4.0));
	pesos /= max(pesos.x + pesos.y + pesos.z, 1e-4);
	float e = 1.0 / max(escala_huecos, 0.05);
	float h = texture(textura_huecos, pos_mundo.zy * e).r * pesos.x
			+ texture(textura_huecos, pos_mundo.xz * e).r * pesos.y
			+ texture(textura_huecos, pos_mundo.xy * e).r * pesos.z;

	if (h < umbral_huecos) {
		discard;
	}

	float pendiente = 1.0 - smoothstep(umbral_huecos, umbral_huecos + 0.16, h);
	float inflamado = 1.0 - smoothstep(umbral_huecos, umbral_huecos + 0.34, h);

	// ---- PROBE C: colores como LITERALES (sin uniforms de color) -------
	vec3 c_base = vec3(0.86, 0.83, 0.73);
	vec3 c_rojo = vec3(0.4, 0.04, 0.045);
	vec3 albedo = mix(c_base, c_rojo, inflamado * 0.9);
	albedo *= 0.8 + 0.4 * ruido;
	float rim = smoothstep(umbral_huecos, umbral_huecos + 0.05, h)
			* (1.0 - smoothstep(umbral_huecos + 0.05, umbral_huecos + 0.13, h));
	albedo = mix(albedo, c_base * 1.2, rim * 0.75);
	ALBEDO = albedo;
	// ------------------------------------------------------------ fin probe

	ROUGHNESS = 0.72;
	EMISSION = vec3(0.0);
}
