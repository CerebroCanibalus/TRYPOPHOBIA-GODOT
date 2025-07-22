// Shader futurista para fondo de post-horror con paleta roja
shader_type canvas_item;

// Parámetros futuristas para testing
uniform float shake_intensity: hint_range(0.0, 0.1) = 0.0;
uniform float shake_speed: hint_range(1.0, 50.0) = 30.0;
uniform vec2 mouse_position = vec2(0.5, 0.5);
uniform float parallax_strength: hint_range(0.0, 0.1) = 0.025;
uniform vec3 horror_tint: source_color = vec3(0.6, 0.1, 0.1);  // Rojo futurista
uniform float digital_glow: hint_range(0.0, 2.0) = 1.3;
uniform float scan_speed: hint_range(0.1, 5.0) = 2.0;

// Función de ruido digital
float digital_noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(127.1, 311.7))) * 43758.5453);
}

// Función de escaneo futurista rojo
float futuristic_scan(vec2 uv, float time) {
    float scan_line = sin(uv.y * 120.0 + time * scan_speed) * 0.5 + 0.5;
    float scan_intensity = sin(time * 3.5) * 0.4 + 0.8;
    return scan_line * scan_intensity;
}

// Función principal
void fragment() {
    vec2 uv = UV;
    
    // Efecto de distorsión digital futurista
    if (shake_intensity > 0.0) {
        float digital_shake_x = sin(TIME * shake_speed) * shake_intensity;
        float digital_shake_y = cos(TIME * shake_speed * 1.5) * shake_intensity;
        
        // Agregar ruido digital rojizo al temblor
        digital_shake_x += digital_noise(vec2(TIME * 10.0)) * shake_intensity * 0.5;
        digital_shake_y += digital_noise(vec2(TIME * 12.0 + 100.0)) * shake_intensity * 0.5;
        
        uv += vec2(digital_shake_x, digital_shake_y);
    }
    
    // Efecto 3D futurista basado en mouse
    vec2 mouse_offset = (mouse_position - vec2(0.5)) * parallax_strength;
    
    // Crear efecto de capas múltiples
    vec2 layer1_uv = uv + mouse_offset;
    vec2 layer2_uv = uv + mouse_offset * 1.5;
    
    // Obtener color base
    vec4 color = texture(TEXTURE, layer1_uv);
    vec4 layer2_color = texture(TEXTURE, layer2_uv);
    
    // Mezclar capas para efecto de profundidad
    color = mix(color, layer2_color, 0.3);
    
    // Aplicar tinte futurista rojo (como Matrix rojo)
    color.rgb = mix(color.rgb, horror_tint, 0.5);
    
    // Agregar efectos de escaneo futurista rojos
    float scan_effect = futuristic_scan(uv, TIME);
    color.rgb += vec3(0.3, 0.05, 0.05) * scan_effect * 0.4;  // Escaneo rojo
    
    // Agregar ruido digital sutil rojizo
    float noise = digital_noise(uv + TIME * 0.1) * 0.06;
    color.rgb += vec3(noise * 2.5, noise * 0.3, noise * 0.3);  // Ruido rojizo
    
    // Efecto de brillo digital rojo
    color.rgb *= digital_glow;
    
    // Mantener atmósfera oscura pero con toques rojos
    color.rgb *= 0.9;
    
    // Agregar efecto de bordes holográficos rojos
    float edge_glow = smoothstep(0.0, 0.1, uv.x) * smoothstep(0.0, 0.1, uv.y) * 
                      smoothstep(0.0, 0.1, 1.0 - uv.x) * smoothstep(0.0, 0.1, 1.0 - uv.y);
    color.rgb += vec3(0.4, 0.05, 0.05) * (1.0 - edge_glow) * 0.3;  // Bordes rojos
    
    // Agregar pulso rojo sutil
    float red_pulse = sin(TIME * 2.0) * 0.1 + 0.9;
    color.r *= red_pulse;
    
    COLOR = color;
} 