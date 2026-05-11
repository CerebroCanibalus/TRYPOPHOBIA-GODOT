# 🎨 Sistema de Fondo Interactivo - TRYPOPHOBIA

## 📋 Índice
1. [Descripción General](#descripción-general)
2. [Componentes del Sistema](#componentes-del-sistema)
3. [Shader Interactivo](#shader-interactivo)
4. [MouseTracker](#mousetracker)
5. [Efectos Visuales](#efectos-visuales)
6. [Configuración](#configuración)
7. [Optimización](#optimización)
8. [Solución de Problemas](#solución-de-problemas)

---

## 🎯 Descripción General

El sistema de fondo interactivo de TRYPOPHOBIA crea una experiencia visual única donde el fondo responde al movimiento del mouse, creando un efecto 3D de profundidad, y vibra terroríficamente cuando el usuario hace clic.

### Características Principales:
- **Efecto 3D Parallax**: El fondo se mueve en capas según la posición del mouse
- **Vibración Terrorífica**: Efecto de temblor al hacer clic (duración: 0.5 segundos)
- **Fondo en Pixel Art**: Textura retro de 8-bit con estilo horror
- **Rendimiento Optimizado**: Actualización eficiente cada frame

---

## 🔧 Componentes del Sistema

### Archivos Principales:
```
assets/shaders/interactive_horror_background.gdshader  # Shader principal
scripts/MouseTracker.gd                               # Rastreador de mouse
assets/textures/menu_background.png                   # Textura de fondo
main_menu.gd                                          # Integración principal
```

### Nodos en la Escena:
```
MainMenu (Control)
├── BackgroundTexture (TextureRect)     # Fondo con shader
├── MouseTracker (Node)                 # Rastreador de mouse
└── [otros nodos del menú...]
```

---

## 🎨 Shader Interactivo

### Parámetros Configurables:

#### Efectos 3D:
```gdscript
parallax_strength: 0.015    # Fuerza del efecto 3D
depth_layers: 3.0           # Número de capas de profundidad
mouse_sensitivity: 1.5      # Sensibilidad del mouse
```

#### Vibración:
```gdscript
shake_intensity: 0.0        # Intensidad de vibración (0.0-0.05)
shake_speed: 25.0           # Velocidad de vibración
shake_decay: 2.0            # Decaimiento de vibración
```

#### Atmósfera:
```gdscript
horror_tint: Vector3(0.25, 0.05, 0.05)  # Tinte rojizo
darkness: 0.6                           # Nivel de oscuridad
contrast: 1.3                           # Contraste
```

### Funciones del Shader:

#### `parallax_offset()`:
- Crea múltiples capas de desplazamiento
- Simula profundidad 3D
- Responde a la posición del mouse

#### `shake_offset()`:
- Genera vibración con múltiples frecuencias
- Aplica decaimiento exponencial
- Se detiene automáticamente

#### `smooth_noise()`:
- Crea ruido natural para textura
- Múltiples capas de frecuencia
- Efecto más realista que ruido simple

---

## 🖱️ MouseTracker

### Funcionalidades:
- **Rastreo en Tiempo Real**: Actualiza cada frame (60 FPS)
- **Optimización**: Solo actualiza si el mouse se movió > 1 píxel
- **Normalización**: Convierte coordenadas de pantalla a UV (0.0-1.0)
- **Sensibilidad Configurable**: Ajusta la respuesta del mouse

### Uso Básico:
```gdscript
# Crear instancia
var mouse_tracker = preload("res://scripts/MouseTracker.gd").new()
add_child(mouse_tracker)

# Conectar señal
mouse_tracker.mouse_position_changed.connect(_on_mouse_moved)

# Establecer material
mouse_tracker.set_background_material(background_material)
```

### Señales Disponibles:
```gdscript
mouse_position_changed(position: Vector2)  # Se emite cuando cambia la posición
```

---

## 🎭 Efectos Visuales

### Efecto 3D Parallax:
1. **Cálculo de Desplazamiento**: Basado en posición del mouse
2. **Múltiples Capas**: Cada capa se mueve a diferente velocidad
3. **Ruido Adicional**: Agrega variación natural al movimiento
4. **Límites de Movimiento**: Evita que el efecto sea excesivo

### Vibración Terrorífica:
1. **Activación**: Se activa al hacer clic en cualquier botón
2. **Múltiples Frecuencias**: Combina 3 frecuencias diferentes
3. **Decaimiento**: Se reduce exponencialmente
4. **Duración Fija**: Exactamente 0.5 segundos

### Efectos de Atmósfera:
- **Tinte de Horror**: Color rojizo siniestro
- **Viñeta**: Oscurece los bordes
- **Líneas de Escaneo**: Efecto retro
- **Ruido Estático**: Simula TV vieja
- **Pulso**: Respiración siniestra del fondo

---

## ⚙️ Configuración

### Configuración Inicial:
```gdscript
func setup_interactive_background():
    # Crear material con shader
    background_material = ShaderMaterial.new()
    background_material.shader = load("res://assets/shaders/interactive_horror_background.gdshader")
    
    # Configurar parámetros
    background_material.set_shader_parameter("parallax_strength", 0.015)
    background_material.set_shader_parameter("depth_layers", 3.0)
    background_material.set_shader_parameter("mouse_sensitivity", 1.5)
    
    # Aplicar al fondo
    background_texture.material = background_material
```

### Configuración del MouseTracker:
```gdscript
func setup_mouse_tracker():
    mouse_tracker = preload("res://scripts/MouseTracker.gd").new()
    add_child(mouse_tracker)
    mouse_tracker.set_background_material(background_material)
    mouse_tracker.set_mouse_sensitivity(1.5)
```

### Activación de Vibración:
```gdscript
func trigger_horror_shake():
    background_material.set_shader_parameter("shake_intensity", 0.03)
    
    # Timer para desactivar después de 0.5 segundos
    var shake_timer = Timer.new()
    add_child(shake_timer)
    shake_timer.wait_time = 0.5
    shake_timer.one_shot = true
    shake_timer.timeout.connect(_on_shake_finished)
    shake_timer.start()
```

---

## 🚀 Optimización

### Rendimiento:
- **Actualización Condicional**: Solo actualiza si el mouse se movió
- **Umbral de Movimiento**: 1 píxel mínimo para actualizar
- **Shader Optimizado**: Usa funciones eficientes
- **Material Compartido**: Un solo material para todo el fondo

### Memoria:
- **Textura Ligera**: 320x240 píxeles, < 50KB
- **Paleta Limitada**: Máximo 8 colores
- **Shader Eficiente**: Sin cálculos innecesarios

### Consejos de Optimización:
```gdscript
# Reducir frecuencia de actualización si es necesario
mouse_tracker.update_threshold = 2.0  # Solo actualizar si se movió 2+ píxeles

# Ajustar sensibilidad para mejor rendimiento
background_material.set_shader_parameter("depth_layers", 2.0)  # Menos capas
```

---

## 🐛 Solución de Problemas

### Problema: "El fondo no se mueve"
**Diagnóstico**:
```gdscript
# Verificar que el MouseTracker está funcionando
print("Posición del mouse: ", mouse_tracker.get_normalized_mouse_position())
print("¿Mouse en movimiento? ", mouse_tracker.is_mouse_moving())
```

**Soluciones**:
1. Verificar que `MouseTracker` está agregado como hijo
2. Verificar que el material está establecido
3. Verificar que el shader se cargó correctamente

### Problema: "La vibración no funciona"
**Diagnóstico**:
```gdscript
# Verificar parámetros del shader
print("Intensidad de vibración: ", background_material.get_shader_parameter("shake_intensity"))
```

**Soluciones**:
1. Verificar que `trigger_horror_shake()` se llama
2. Verificar que el timer se crea correctamente
3. Verificar que `_on_shake_finished()` se ejecuta

### Problema: "Rendimiento lento"
**Soluciones**:
1. Reducir `depth_layers` a 2.0
2. Aumentar `update_threshold` a 2.0
3. Reducir `parallax_strength` a 0.01

### Problema: "Efecto muy intenso"
**Ajustes**:
```gdscript
# Reducir intensidad de efectos
background_material.set_shader_parameter("parallax_strength", 0.01)  # Menos movimiento
background_material.set_shader_parameter("shake_intensity", 0.02)    # Menos vibración
background_material.set_shader_parameter("horror_tint", Vector3(0.15, 0.03, 0.03))  # Menos rojo
```

---

## 📚 Ejemplos de Uso

### Cambiar Sensibilidad en Tiempo Real:
```gdscript
func _on_sensitivity_slider_changed(value: float):
    mouse_tracker.set_mouse_sensitivity(value)
    background_material.set_shader_parameter("mouse_sensitivity", value)
```

### Efecto de Vibración Personalizado:
```gdscript
func custom_shake(intensity: float, duration: float):
    background_material.set_shader_parameter("shake_intensity", intensity)
    
    var timer = Timer.new()
    add_child(timer)
    timer.wait_time = duration
    timer.one_shot = true
    timer.timeout.connect(_on_shake_finished)
    timer.start()
```

### Cambiar Atmósfera:
```gdscript
func set_horror_level(level: int):
    match level:
        1:  # Suave
            background_material.set_shader_parameter("darkness", 0.3)
            background_material.set_shader_parameter("horror_tint", Vector3(0.1, 0.02, 0.02))
        2:  # Medio
            background_material.set_shader_parameter("darkness", 0.6)
            background_material.set_shader_parameter("horror_tint", Vector3(0.25, 0.05, 0.05))
        3:  # Intenso
            background_material.set_shader_parameter("darkness", 0.8)
            background_material.set_shader_parameter("horror_tint", Vector3(0.4, 0.08, 0.08))
```

---

## 🎯 Próximos Pasos

1. **Efectos Adicionales**: Agregar más tipos de vibración
2. **Configuración de Usuario**: Permitir ajustar efectos desde menú
3. **Transiciones**: Efectos suaves entre diferentes estados
4. **Optimización Avanzada**: LOD (Level of Detail) para diferentes dispositivos
5. **Efectos de Partículas**: Agregar partículas de polvo o cenizas

---

**¡Sistema de fondo interactivo listo para crear terror! 👹🎮** 