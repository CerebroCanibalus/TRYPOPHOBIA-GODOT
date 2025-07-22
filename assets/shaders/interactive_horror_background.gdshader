// Shader para fondo interactivo de horror con efecto 3D y vibración
// Este shader crea un efecto de profundidad que responde al mouse
shader_type canvas_item;

// === UNIFORMS PARA EFECTOS 3D ===
// Los uniforms son parámetros que se pueden cambiar desde GDScript

// Parámetros de efecto 3D (parallax)
uniform float parallax_strength: hint_range(0.0, 0.1) = 0.02;  // Fuerza del efecto 3D
uniform float depth_layers: hint_range(1.0, 10.0) = 3.0;       // Capas de profundidad
uniform float mouse_sensitivity: hint_range(0.1, 5.0) = 1.0;   // Sensibilidad del mouse

// Parámetros de vibración
uniform float shake_intensity: hint_range(0.0, 0.05) = 0.0;    // Intensidad de vibración
uniform float shake_speed: hint_range(1.0, 50.0) = 20.0;       // Velocidad de vibración
uniform float shake_decay: hint_range(0.1, 2.0) = 1.5;         // Decaimiento de vibración

// Parámetros de tiempo y animación
uniform float time_scale: hint_range(0.1, 3.0) = 1.0;          // Escala de tiempo
uniform float pulse_speed: hint_range(0.5, 5.0) = 1.5;         // Velocidad de pulso

// Parámetros de color y atmósfera
uniform vec3 horror_tint: source_color = vec3(0.2, 0.08, 0.08); // Tinte rojizo más sutil
uniform float darkness: hint_range(0.0, 1.0) = 0.7;             // Nivel de oscuridad
uniform float contrast: hint_range(0.5, 2.0) = 1.2;             // Contraste

// Parámetros de efectos especiales
uniform float noise_intensity: hint_range(0.0, 0.1) = 0.01;    // Intensidad de ruido
uniform float scan_lines: hint_range(0.0, 0.5) = 0.1;          // Líneas de escaneo
uniform float vignette_strength: hint_range(0.0, 2.0) = 1.0;   // Fuerza del viñeteado

// === VARIABLES GLOBALES ===
// Variables que se usan en múltiples funciones

// Posición del mouse normalizada (0.0 a 1.0)
uniform vec2 mouse_position: source_color = vec2(0.5, 0.5);

// === FUNCIONES AUXILIARES ===

// Función para generar ruido pseudo-aleatorio
// Esta función crea patrones aleatorios para efectos de textura
float random(vec2 coordinates) {
    // Fórmula matemática para generar números pseudo-aleatorios
    // Usa funciones trigonométricas para crear patrones complejos
    return fract(sin(dot(coordinates.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Función para generar ruido suave (Perlin-like)
// Crea ruido más natural y menos "pixelado"
float smooth_noise(vec2 uv, float time) {
    // Crear múltiples capas de ruido con diferentes frecuencias
    float noise1 = random(uv + time * 0.1);
    float noise2 = random(uv * 2.0 + time * 0.15);
    float noise3 = random(uv * 4.0 + time * 0.05);
    float noise4 = random(uv * 8.0 + time * 0.02);
    
    // Combinar las capas con pesos decrecientes
    return (noise1 * 0.5 + noise2 * 0.25 + noise3 * 0.125 + noise4 * 0.0625);
}

// Función para crear efecto de profundidad (parallax mapping)
// Simula que el fondo tiene múltiples capas a diferentes profundidades
vec2 parallax_offset(vec2 uv, vec2 mouse_pos, float time) {
    // Calcular la dirección del mouse desde el centro
    vec2 mouse_offset = (mouse_pos - vec2(0.5, 0.5)) * 2.0;  // Rango -1 a 1
    
    // Crear múltiples capas de desplazamiento
    vec2 total_offset = vec2(0.0, 0.0);
    
    // Para cada capa de profundidad
    for (float layer = 1.0; layer <= depth_layers; layer++) {
        // Calcular la intensidad de esta capa (más lejos = más movimiento)
        float layer_intensity = layer / depth_layers;
        
        // Crear ruido específico para esta capa
        float layer_noise = smooth_noise(uv * (1.0 + layer * 0.5), time * 0.1);
        
        // Calcular el desplazamiento para esta capa
        vec2 layer_offset = mouse_offset * layer_intensity * parallax_strength;
        
        // Agregar ruido al desplazamiento
        layer_offset += vec2(
            smooth_noise(uv + vec2(100.0, 0.0), time * 0.05) - 0.5,
            smooth_noise(uv + vec2(0.0, 100.0), time * 0.05) - 0.5
        ) * noise_intensity * layer_intensity;
        
        // Combinar con el desplazamiento total
        total_offset += layer_offset * layer_noise;
    }
    
    return total_offset;
}

// Función para crear efecto de vibración terrorífica
// Genera movimiento aleatorio que simula temblor
vec2 shake_offset(float time) {
    // Solo aplicar vibración si hay intensidad
    if (shake_intensity <= 0.0) {
        return vec2(0.0, 0.0);
    }
    
    // Crear vibración con múltiples frecuencias para mayor realismo
    float shake1 = sin(time * shake_speed) * cos(time * shake_speed * 0.7);
    float shake2 = sin(time * shake_speed * 1.3) * cos(time * shake_speed * 0.9);
    float shake3 = sin(time * shake_speed * 0.5) * cos(time * shake_speed * 1.1);
    
    // Combinar las vibraciones
    float shake_x = (shake1 + shake2 + shake3) / 3.0;
    float shake_y = (shake2 + shake3 + shake1) / 3.0;
    
    // Aplicar decaimiento exponencial para que la vibración se detenga
    float decay = exp(-time * shake_decay);
    
    // Retornar el offset de vibración
    return vec2(shake_x, shake_y) * shake_intensity * decay;
}

// Función para crear efecto de viñeta
// Oscurece los bordes de la pantalla para efecto cinematográfico
float vignette_effect(vec2 uv) {
    // Calcular la distancia desde el centro
    float distance_from_center = distance(uv, vec2(0.5));
    
    // Crear una máscara circular que se oscurece hacia los bordes
    return smoothstep(0.8, 0.2, distance_from_center);
}

// Función para crear líneas de escaneo retro
// Simula el efecto de TV vieja o monitor CRT
float scanlines_effect(vec2 uv, float time) {
    // Crear líneas horizontales que se mueven
    float lines = sin(uv.y * 800.0 + time * 2.0) * 0.5 + 0.5;
    
    // Hacer las líneas más sutiles y realistas
    return mix(1.0, lines, scan_lines);
}

// === FUNCIÓN PRINCIPAL FRAGMENT ===
// Esta función se ejecuta para cada píxel en la pantalla
void fragment() {
    // Obtener las coordenadas UV del píxel actual
    vec2 uv = UV;
    
    // Calcular tiempo escalado para animaciones
    float scaled_time = TIME * time_scale;
    
    // === EFECTO DE VIBRACIÓN ===
    // Aplicar vibración terrorífica al hacer clic
    vec2 shake = shake_offset(scaled_time);
    uv += shake;
    
    // === EFECTO 3D (PARALLAX) ===
    // Crear efecto de profundidad basado en la posición del mouse
    vec2 parallax = parallax_offset(uv, mouse_position, scaled_time);
    uv += parallax;
    
    // === EFECTOS DE RUIDO Y DISTORSIÓN ===
    // Agregar ruido sutil para textura
    vec2 noise_offset = vec2(
        smooth_noise(uv, scaled_time) - 0.5,
        smooth_noise(uv + vec2(100.0), scaled_time) - 0.5
    ) * noise_intensity;
    uv += noise_offset;
    
    // === OBTENER COLOR BASE ===
    // Obtener el color de la textura de fondo
    vec4 base_color = texture(TEXTURE, uv);
    
    // === EFECTOS DE COLOR Y ATMÓSFERA ===
    
    // Aplicar tinte de horror (rojizo y oscuro) más sutil
    base_color.rgb = mix(base_color.rgb, horror_tint, 0.15);
    
    // Aplicar contraste
    base_color.rgb = (base_color.rgb - 0.5) * contrast + 0.5;
    
    // === EFECTO DE PULSO SINIESTRO ===
    // Crear un pulso que hace que el fondo "respire"
    float pulse = sin(scaled_time * pulse_speed) * 0.1 + 0.9;
    base_color.rgb *= pulse;
    
    // === EFECTOS DE RUIDO ESTÁTICO ===
    // Generar ruido estático como en TV vieja
    float static_noise = random(uv + scaled_time * 10.0);
    base_color.rgb = mix(base_color.rgb, vec3(static_noise), 0.02);
    
    // === EFECTO DE VIÑETA ===
    // Aplicar efecto de viñeta para oscurecer los bordes
    float vignette = vignette_effect(uv);
    base_color.rgb *= vignette * vignette_strength;
    
    // === EFECTO DE LÍNEAS DE ESCANEO ===
    // Aplicar líneas de escaneo para efecto retro
    float scanlines = scanlines_effect(uv, scaled_time);
    base_color.rgb *= scanlines;
    
    // === OSCURECIMIENTO GENERAL ===
    // Aplicar oscurecimiento general para ambiente tétrico
    base_color.rgb *= (1.0 - darkness);
    
    // === RESULTADO FINAL ===
    // Asegurar que los valores estén en el rango correcto (0-1)
    base_color.rgb = clamp(base_color.rgb, 0.0, 1.0);
    
    // Asignar el color final al píxel
    COLOR = base_color;
} 