shader_type canvas_item;
// Mismo cuantizador que pixel_effects.gdshader pero en 2D, y la diferencia NO es
// de gusto: el de 3D es un quad spatial, asi que el tonemapper lo revela DESPUES
// y vuelve a desparramar la paleta. Medido en la isla: el cuantizador mandaba el
// cesped a #59A640 y en el fotograma salia #669A41, o sea 36 colores de entrada
// y miles de salida. En un lienzo 2D el cuantizador va al final de la cadena y
// lo que escribe es exactamente lo que se ve.
//
// Por eso PaletteTexture aqui NO lleva source_color: en canvas_item la textura
// de pantalla ya viene revelada y codificada, asi que la paleta se lee cruda y
// la distancia se calcula en el mismo espacio que la pantalla.

uniform sampler2D ScreenTexture : hint_screen_texture, filter_nearest;

uniform float TwixelAngle : hint_range(0.0, 45.0) = 45.0;
uniform float PixelSize : hint_range(1.0, 32.0) = 5.0;

uniform bool Quantize = true;
uniform sampler2D PaletteTexture : filter_nearest;

uniform bool Posterize = false;
uniform int ColorSteps : hint_range(2, 16) = 16;

// El "Remove blue-ish tones" del shader original: pinta de negro todo lo que
// tire a azul. Para la Petrolera vale; la Isla es el primer mapa con cielo Y mar
// y ahi ese apano los borra los dos, asi que se deja desenchufable.
uniform bool RemoveBlue = true;

vec3 quantized_color(vec3 original_color) {
	ivec2 palette_size = textureSize(PaletteTexture, 0);
	vec3 best = vec3(0.0, 1.0, 0.0);
	float min_dist = 9999.0;
	for (int y = 0; y < palette_size.y; y++) {
		for (int x = 0; x < palette_size.x; x++) {
			vec2 palette_uv = (vec2(float(x), float(y)) + 0.5) / vec2(palette_size);
			vec3 palette_color = textureLod(PaletteTexture, palette_uv, 0.0).rgb;
			float dist = distance(original_color, palette_color);
			if (dist < min_dist) {
				min_dist = dist;
				best = palette_color;
			}
		}
	}
	return best;
}

vec3 posterize_color(vec3 color, int steps) {
	return floor(color * float(steps)) / float(steps);
}

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag_coord = FRAGCOORD.xy;

	float aRad = radians(TwixelAngle);
	mat2 rotation = mat2(vec2(cos(aRad), -sin(aRad)), vec2(sin(aRad), cos(aRad)));

	vec2 rotated_coord = rotation * frag_coord;
	vec2 pixelated_coord = round(rotated_coord / PixelSize) * PixelSize;
	vec2 final_coord = transpose(rotation) * pixelated_coord;
	final_coord = clamp(final_coord, vec2(1.0), viewport_size - vec2(1.0));

	vec3 color = textureLod(ScreenTexture, final_coord * SCREEN_PIXEL_SIZE, 0.0).rgb;

	if (Posterize) {
		color = posterize_color(color, ColorSteps);
	}
	if (Quantize) {
		color = quantized_color(color);
	}
	if (RemoveBlue && color.b > color.r + 0.1 && color.b > color.g + 0.1) {
		color = vec3(0.0);
	}
	COLOR = vec4(color, 1.0);
}
