
shader_type spatial;

// ===========================================================================
//  INFECCION — PROBE D (DIAGNOSTICO NaN — unshaded)
//
//  Deduccion previa: los siluetas son CIRCULOS -> ruido sano (si fuera NaN,
//  el discard del borde nunca dispararia y veriamos CUADRADOS).
//  Canales de este probe (base 0.25 = oscuro si sano, 1.0 = NaN):
//    R = umbral_huecos es NaN?
//    G = h (triplanar/pesos) es NaN?
//    B = norm_mundo es NaN?
//  BLANCO puro = todos NaN; GRIS oscuro = todos sanos. :v
// ===========================================================================

render_mode cull_disabled, depth_draw_opaque, unshaded;

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
	// Silueta identica a la real (usa ruido sano deducido): :v
	vec2 centro = (UV - 0.5) * 2.0;
	float radio = length(centro);
	float ruido = texture(textura_huecos, UV * 2.7).r;
	float borde = radio + (ruido - 0.5) * 0.6;
	if (borde > 1.0) {
		discard;
	}

	vec3 pesos = pow(abs(norm_mundo), vec3(4.0));
	pesos /= max(pesos.x + pesos.y + pesos.z, 1e-4);
	float e = 1.0 / max(escala_huecos, 0.05);
	float h = texture(textura_huecos, pos_mundo.zy * e).r * pesos.x
			+ texture(textura_huecos, pos_mundo.xz * e).r * pesos.y
			+ texture(textura_huecos, pos_mundo.xy * e).r * pesos.z;

	// NaN por comparacion x != x (isnan no existe seguro en Godot). :v
	float n_umbral = umbral_huecos != umbral_huecos ? 1.0 : 0.25;
	float n_h = h != h ? 1.0 : 0.25;
	float nn = dot(norm_mundo, norm_mundo);
	nn = nn != nn ? 1.0 : 0.25;

	ALBEDO = vec3(n_umbral, n_h, nn);
	EMISSION = vec3(0.0);
	ROUGHNESS = 1.0;
}
