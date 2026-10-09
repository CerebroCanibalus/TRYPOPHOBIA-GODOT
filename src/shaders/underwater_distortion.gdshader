shader_type canvas_item;

// Distorsion submarina (canvas_item). La controla SOLO el uniform 'fuerza',
// que empuja src/water/underwater_fx.gd a partir de WaterBody.cabeza_sumergida.
// Es el espejo visual de lo que ya decide la fisica: te avisa cuando el juego
// te esta contando como sumergido. :v
render_mode blend_mix;

// Copia de lo que hay detras de este ColorRect (3D + canvas inferior). :v
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// 0 = fuera del agua, 1 = hondo. :v
uniform float fuerza : hint_range(0.0, 1.0) = 0.0;
// Amplitud de la distorsion en UV: 0.0035 son ~6 px a 1920. :v
uniform float intensidad_onda = 0.0035;
// Velocidad de las ondas. :v
uniform float vel_onda = 1.0;
// Tinte del agua: lo hondo se lee azul-verdoso. :v
uniform vec3 tinte_agua : source_color = vec3(0.55, 0.80, 1.05);
// Oscurecimiento en los bordes, para dar volumen a la columna. :v
uniform float vineta = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * vel_onda;

	// Dos senos por eje a distinta frecuencia y velocidad: el agua ondula,
	// no late como un piston. Sin el segundo seno la pantalla respira y se
	// lee como un filtro barato. :v
	vec2 onda = vec2(
		sin(uv.y * 26.0 + t * 2.1) + 0.5 * sin(uv.y * 61.0 - t * 3.3),
		cos(uv.x * 24.0 - t * 1.7) + 0.5 * cos(uv.x * 57.0 + t * 2.6)
	) * intensidad_onda * fuerza;

	vec4 c = texture(pantalla, uv + onda);

	// Tinte y vineta sobre el color YA distorsionado. :v
	c.rgb = mix(c.rgb, c.rgb * tinte_agua, 0.65 * fuerza);
	float d = distance(uv, vec2(0.5));
	c.rgb *= mix(1.0, 1.0 - vineta, smoothstep(0.30, 0.85, d) * fuerza);

	// alpha = fuerza: el ColorRect funde original y procesado, asi entrar y
	// salir del agua es un fundido y no un corte. :v
	COLOR = vec4(c.rgb, fuerza);
}