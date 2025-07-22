// Shader para el fondo del menú de horror
// Este shader crea efectos visuales inquietantes para la atmósfera del juego
shader_type canvas_item;

// === UNIFORMS (PARÁMETROS CONFIGURABLES) ===
// Los uniforms son variables que se pueden cambiar desde GDScript

// Parámetros de tiempo y movimiento
uniform float time_scale: hint_range(0.1, 3.0) = 1.0;  // Velocidad de los efectos
uniform float pulse_speed: hint_range(0.5, 5.0) = 2.0;  // Velocidad del pulso

// Parámetros de ruido y distorsión
uniform float noise_intensity: hint_range(0.0, 0.1) = 0.02;  // Intensidad del ruido
uniform float static_intensity: hint_range(0.0, 0.3) = 0.05;  // Intensidad del estático
uniform float scan_lines: hint_range(0.0, 1.0) = 0.3;  // Intensidad de líneas de escaneo

// Parámetros de color de horror
uniform vec3 horror_tint: source_color = vec3(0.4, 0.1, 0.1);  // Tinte rojizo
uniform float darkness: hint_range(0.0, 1.0) = 0.8;  // Nivel de oscuridad
uniform float vignette_strength: hint_range(0.0, 2.0) = 1.2;  // Fuerza del viñeteado

// Parámetros de efectos especiales
uniform float blood_effect: hint_range(0.0, 1.0) = 0.1;  // Efecto de manchas de sangre
uniform float flicker_intensity: hint_range(0.0, 1.0) = 0.3;  // Parpadeo

// === FUNCIONES AUXILIARES ===

// Función para generar ruido pseudo-aleatorio
// Esta función toma coordenadas 2D y devuelve un valor entre 0 y 1
float random(vec2 coordinates) {
    // Fórmula matemática para generar números pseudo-aleatorios
    return fract(sin(dot(coordinates.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Función para generar ruido suave basado en tiempo
float noise_function(vec2 uv, float time) {
    // Crear múltiples capas de ruido para un efecto más complejo
    float noise1 = random(uv + time * 0.1);
    float noise2 = random(uv * 2.0 + time * 0.15);
    float noise3 = random(uv * 4.0 + time * 0.05);
    
    // Combinar las capas de ruido con diferentes pesos
    return (noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2);
}

// Función para crear efecto de viñeta (bordes oscuros)
float vignette_effect(vec2 uv) {
    // Calcular la distancia desde el centro de la pantalla
    float distance_from_center = distance(uv, vec2(0.5));
    
    // Crear una máscara circular que se oscurece hacia los bordes
    return smoothstep(0.8, 0.2, distance_from_center);
}

// Función para crear líneas de escaneo como en TV vieja
float scanlines_effect(vec2 uv, float time) {
    // Crear líneas horizontales que se mueven
    float lines = sin(uv.y * 800.0 + time * 2.0) * 0.5 + 0.5;
    
    // Hacer las líneas más sutiles
    return mix(1.0, lines, scan_lines);
}

// === FUNCIÓN PRINCIPAL FRAGMENT ===
// Esta función se ejecuta para cada píxel en la pantalla
void fragment() {
    // Obtener las coordenadas UV del píxel actual (0,0 a 1,1)
    vec2 uv = UV;
    
    // Calcular tiempo escalado para animaciones
    float scaled_time = TIME * time_scale;
    
    // === EFECTOS DE DISTORSIÓN ===
    
    // Aplicar ruido a las coordenadas UV para crear distorsión
    vec2 noise_offset = vec2(
        noise_function(uv, scaled_time) - 0.5,
        noise_function(uv + vec2(100.0), scaled_time) - 0.5
    ) * noise_intensity;
    
    // Aplicar la distorsión a las coordenadas
    uv += noise_offset;
    
    // === EFECTOS DE COLOR BASE ===
    
    // Obtener el color base de la textura
    vec4 base_color = texture(TEXTURE, uv);
    
    // Aplicar tinte de horror (rojizo y oscuro)
    base_color.rgb = mix(base_color.rgb, horror_tint, 0.6);
    
    // === EFECTOS DE RUIDO ESTÁTICO ===
    
    // Generar ruido estático como en TV vieja
    float static_noise = random(uv + scaled_time * 10.0);
    
    // Aplicar el ruido estático al color
    base_color.rgb = mix(base_color.rgb, vec3(static_noise), static_intensity);
    
    // === EFECTO DE VIÑETA ===
    
    // Aplicar efecto de viñeta para oscurecer los bordes
    float vignette = vignette_effect(uv);
    base_color.rgb *= vignette * vignette_strength;
    
    // === EFECTO DE LÍNEAS DE ESCANEO ===
    
    // Aplicar líneas de escaneo para efecto retro
    float scanlines = scanlines_effect(uv, scaled_time);
    base_color.rgb *= scanlines;
    
    // === EFECTO DE PULSO ===
    
    // Crear un efecto de pulso siniestro
    float pulse = sin(scaled_time * pulse_speed) * 0.1 + 0.9;
    base_color.rgb *= pulse;
    
    // === EFECTO DE PARPADEO ===
    
    // Crear parpadeo aleatorio como luz defectuosa
    float flicker = mix(1.0, random(vec2(scaled_time * 5.0)), flicker_intensity);
    base_color.rgb *= flicker;
    
    // === EFECTO DE MANCHAS DE SANGRE ===
    
    // Crear patrones que simulan manchas de sangre
    float blood_pattern = noise_function(uv * 3.0, scaled_time * 0.1);
    blood_pattern = smoothstep(0.7, 1.0, blood_pattern);
    
    // Aplicar el efecto de sangre con color rojizo oscuro
    vec3 blood_color = vec3(0.3, 0.05, 0.05);
    base_color.rgb = mix(base_color.rgb, blood_color, blood_pattern * blood_effect);
    
    // === OSCURECIMIENTO GENERAL ===
    
    // Aplicar oscurecimiento general para ambiente tétrico
    base_color.rgb *= (1.0 - darkness);
    
    // === RESULTADO FINAL ===
    
    // Asegurar que los valores estén en el rango correcto (0-1)
    base_color.rgb = clamp(base_color.rgb, 0.0, 1.0);
    
    // Asignar el color final al píxel
    COLOR = base_color;
} 