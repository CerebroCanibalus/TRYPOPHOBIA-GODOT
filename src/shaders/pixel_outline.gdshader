shader_type spatial;
render_mode unshaded, depth_draw_always, cull_disabled;

uniform sampler2D ScreenTexture : hint_screen_texture;

//Twixel Settings
uniform float TwixelAngle : hint_range(0.0, 45.0) = 45.0;
uniform float PixelSize : hint_range(1.0, 32.0) = 8.0;

//Fog Settings
uniform vec3 FogColor : source_color;
uniform sampler2D DepthTexture : hint_depth_texture, filter_linear_mipmap;
uniform float FogStart = 25.0;    // Distance where fog begins
uniform float FogEnd = 300.0;     // Distance where fog becomes fully opaque

//Palette Settings
uniform bool Quantize = true;
uniform sampler2D PaletteTexture : source_color;

void vertex(){
	//put this shader on a simple 1x1 quad mesh instance
	POSITION = vec4(VERTEX.xy*2.0, 1.0, 1.0);
}

vec3 quantized_color(vec3 original_color){
	// Palette quantization
    ivec2 palette_size = textureSize(PaletteTexture, 0);
    vec3 quantized_color = vec3(0.0, 1.0, 0.0); //bright debug-green color
    float min_dist = 9999.0;

    // Search through palette texture
    for (int y = 0; y < palette_size.y; y++) {
        for (int x = 0; x < palette_size.x; x++) {
			//get the color of the pixel at the center of each pixel rather than the corner.
            vec2 palette_uv = (vec2(float(x), float(y)) +0.5) / vec2(palette_size);
            vec3 palette_color = textureLod(PaletteTexture, palette_uv, 0.0).rgb;
            float dist = distance(original_color, palette_color);
	      	if (dist < min_dist) {
                min_dist = dist;
            	quantized_color = palette_color;
            }
        }
    }
	return quantized_color;
}

void fragment() {
    // Reconstruct screen-space coordinates
    vec2 frag_coord = FRAGCOORD.xy;
    vec2 screen_pixel_size = 1.0 / VIEWPORT_SIZE;
	
    // Center rotation at fragment center
    float aRad = radians(TwixelAngle);
    mat2 rotation = mat2(
        vec2(cos(aRad), -sin(aRad)),
        vec2(sin(aRad),  cos(aRad))
    );
    
    // Apply rotation and pixelation
    vec2 rotated_coord = rotation * frag_coord;
    vec2 pixelated_coord = round(rotated_coord / PixelSize) * PixelSize;
    vec2 final_coord = transpose(rotation) * pixelated_coord;
	final_coord = clamp(final_coord, vec2(1.0), VIEWPORT_SIZE - vec2(1.0));
    
	//Get the linear depth for fog
	float depth = texture(DepthTexture, final_coord * screen_pixel_size).x;
	vec3 ndc = vec3(final_coord * screen_pixel_size * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
    // Sample screen texture with NEAREST filtering for crisp pixels
    vec3 original_color = textureLod(ScreenTexture, final_coord * screen_pixel_size, 0.0).rgb;

	//get the fog
	float fog_factor = clamp((linear_depth - FogStart) / (FogEnd - FogStart), 0.0, 1.0);
	
	if(Quantize){
		vec3 quantized = quantized_color(original_color);
	    ALBEDO = mix(quantized, FogColor, fog_factor);	
	}else{
		ALBEDO = mix(original_color, FogColor, fog_factor);
	}
}