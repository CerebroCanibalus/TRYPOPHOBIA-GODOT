# 🎮 TRYPOPHOBIA - Guía Completa del Sistema de Menú

## 📋 Índice
1. [Introducción](#introducción)
2. [Estructura de Archivos](#estructura-de-archivos)
3. [Sistema de Traducción](#sistema-de-traducción)
4. [Componentes del Menú](#componentes-del-menú)
5. [Efectos Visuales de Horror](#efectos-visuales-de-horror)
6. [Sistema de Audio](#sistema-de-audio)
7. [Configuraciones Globales](#configuraciones-globales)
8. [Cómo Agregar Nuevas Funciones](#cómo-agregar-nuevas-funciones)
9. [Solución de Problemas](#solución-de-problemas)

---

## 🚀 Introducción

Este documento explica cómo funciona el sistema de menú principal de TRYPOPHOBIA. Está diseñado para desarrolladores novatos que quieren entender y expandir el sistema.

### ¿Qué hace este sistema?
- **Menú principal** con navegación completa
- **Sistema multiidioma** (inglés/español)
- **Efectos visuales de horror** con shaders
- **Audio ambiente** inquietante
- **Configuraciones persistentes** que se guardan automáticamente
- **Arquitectura modular** fácil de expandir

---

## 📁 Estructura de Archivos

```
TRYPOPHOBIA/
├── main_menu.tscn          # Escena visual del menú
├── main_menu.gd            # Lógica principal del menú
├── scripts/
│   └── GameSettings.gd     # Configuraciones globales
├── assets/shaders/
│   └── horror_menu_background.gdshader  # Efectos visuales
└── docs/
    └── Menu_System_Guide.md # Esta guía
```

### Descripción de cada archivo:

#### `main_menu.tscn`
- **Qué es**: La escena visual del menú en Godot
- **Contiene**: Botones, contenedores, elementos de audio
- **Para qué sirve**: Define la apariencia y estructura del menú

#### `main_menu.gd`
- **Qué es**: El script principal que controla el menú
- **Contiene**: Lógica de navegación, efectos, traducciones
- **Para qué sirve**: Hace que el menú funcione y responda

#### `GameSettings.gd`
- **Qué es**: Sistema global de configuraciones
- **Contiene**: Traducciones, configuraciones de audio/video/controles
- **Para qué sirve**: Mantiene configuraciones en todo el juego

---

## 🌍 Sistema de Traducción

### ¿Cómo funciona?

El juego usa un **diccionario de traducciones** para cambiar idiomas sin recargar nada.

```gdscript
# Ejemplo de cómo funciona la traducción
var translations = {
    "english": {
        "play": "SINGLE PLAYER",
        "settings": "SETTINGS"
    },
    "spanish": {
        "play": "UN JUGADOR", 
        "settings": "CONFIGURACIÓN"
    }
}

# Para obtener texto traducido:
var text = GameSettings.get_text("play")  # Devuelve "SINGLE PLAYER" o "UN JUGADOR"
```

### ¿Cómo agregar un nuevo idioma?

1. **Abrir `GameSettings.gd`**
2. **Agregar el idioma a `AVAILABLE_LANGUAGES`**:
   ```gdscript
   const AVAILABLE_LANGUAGES = ["english", "spanish", "french"]  # ← Agregar aquí
   ```

3. **Agregar traducciones a `game_translations`**:
   ```gdscript
   var game_translations = {
       "english": { /* ... */ },
       "spanish": { /* ... */ },
       "french": {  # ← Nuevo idioma
           "title": "TRYPOPHOBIA",
           "play": "SOLO",
           "multiplayer": "MULTIJOUEUR",
           # ... más traducciones
       }
   }
   ```

### ¿Cómo agregar nuevas traducciones?

```gdscript
# En ambos idiomas, agregar la nueva clave:
"english": {
    "new_button": "NEW FEATURE",  # ← Agregar aquí
    # ... otras traducciones
},
"spanish": {
    "new_button": "NUEVA FUNCIÓN",  # ← Y aquí
    # ... otras traducciones
}

# En el código, usar así:
my_button.text = GameSettings.get_text("new_button")
```

---

## 🎛️ Componentes del Menú

### Estructura de Contenedores

El menú usa un sistema de **contenedores** que se muestran/ocultan:

```
MainMenu (Control principal)
├── MainContainer        # Menú principal
├── MultiplayerContainer # Menú multijugador  
├── SettingsContainer    # Menú configuración
└── LanguageContainer    # Menú idiomas
```

### ¿Cómo funciona la navegación?

```gdscript
# Función que cambia entre menús
func show_container(container: Control):
    hide_all_containers()     # Ocultar todos
    container.visible = true  # Mostrar el deseado
    
    # Animación de aparición
    container.modulate.a = 0.0
    var tween = create_tween()
    tween.tween_property(container, "modulate:a", 1.0, 0.3)
```

### ¿Cómo agregar un nuevo menú?

1. **En `main_menu.tscn`**: Crear nuevo contenedor
2. **En `main_menu.gd`**: Agregar referencia
   ```gdscript
   @onready var my_new_container = $MyNewContainer
   ```
3. **Agregar función de navegación**:
   ```gdscript
   func _on_my_button_pressed():
       show_container(my_new_container)
   ```

---

## 🎨 Efectos Visuales de Horror

### El Shader de Fondo

El archivo `horror_menu_background.gdshader` crea efectos terroríficos:

- **Ruido estático** como TV vieja
- **Viñetas oscuras** en los bordes
- **Líneas de escaneo** retro
- **Pulso siniestro** que cambia brightness
- **Parpadeo** como luz defectuosa
- **Manchas de sangre** aleatorias

### ¿Cómo personalizar los efectos?

```gdscript
# En el script, puedes cambiar parámetros del shader:
background_material.set_shader_parameter("horror_tint", Vector3(0.2, 0.4, 0.1))  # Verde
background_material.set_shader_parameter("pulse_speed", 3.0)  # Más rápido
background_material.set_shader_parameter("blood_effect", 0.5)  # Más sangre
```

### Efectos en Botones

```gdscript
# Efecto de hover (pasar mouse)
func _on_button_hover(button: Button):
    var tween = create_tween()
    # Cambiar color a rojizo brillante
    tween.tween_property(button, "modulate", Color(1.2, 0.8, 0.8), 0.2)
```

---

## 🔊 Sistema de Audio

### Estructura de Audio

```
AudioContainer
├── AmbientAudio  # Sonido ambiente continuo
├── UISounds      # Efectos de botones
└── BreathAudio   # Respiración inquietante
```

### ¿Cómo agregar nuevos sonidos?

1. **Agregar archivo de audio** a la carpeta del proyecto
2. **En `main_menu.gd`**, agregar al diccionario:
   ```gdscript
   var horror_sounds = {
       "hover": "res://audio/ui/whisper.ogg",
       "my_new_sound": "res://audio/ui/scream.ogg"  # ← Nuevo sonido
   }
   ```
3. **Usar en el código**:
   ```gdscript
   func play_my_sound():
       var sound = load(horror_sounds["my_new_sound"])
       ui_sounds.stream = sound
       ui_sounds.play()
   ```

### Configuración de Volumen

```gdscript
# El audio usa decibelios (escala logarítmica)
ambient_audio.volume_db = -15  # Más bajo
ui_sounds.volume_db = -10      # Más alto
breath_audio.volume_db = -20   # Muy bajo
```

---

## ⚙️ Configuraciones Globales

### GameSettings como Singleton

`GameSettings.gd` es un **autoload/singleton**, significa que:
- Se carga **automáticamente** al iniciar el juego
- Existe **durante toda la partida**
- Es **accesible desde cualquier script**

### ¿Cómo usar GameSettings?

```gdscript
# Desde cualquier script en el juego:

# Obtener texto traducido
var text = GameSettings.get_text("play")

# Cambiar idioma
GameSettings.set_language("spanish")

# Cambiar volumen
GameSettings.set_master_volume(0.5)

# Obtener configuración actual
var current_lang = GameSettings.current_language
```

### ¿Cómo agregar nueva configuración?

1. **Agregar variable en GameSettings.gd**:
   ```gdscript
   var my_new_setting: bool = true
   ```

2. **Agregar funciones get/set**:
   ```gdscript
   func set_my_setting(value: bool):
       my_new_setting = value
       save_settings()  # Guardar automáticamente
   
   func get_my_setting() -> bool:
       return my_new_setting
   ```

3. **Agregar a save/load**:
   ```gdscript
   # En save_settings():
   config.set_value("my_section", "my_setting", my_new_setting)
   
   # En load_settings():
   my_new_setting = config.get_value("my_section", "my_setting", true)
   ```

---

## 🔧 Cómo Agregar Nuevas Funciones

### Ejemplo: Agregar Menú de Créditos

1. **En `main_menu.tscn`**:
   - Agregar nuevo contenedor: `CreditsContainer`
   - Agregar botón "CREDITS" en menú principal

2. **En `main_menu.gd`**:
   ```gdscript
   # Agregar referencia
   @onready var credits_container = $CreditsContainer
   @onready var credits_button = $MainContainer/VBoxContainer/CreditsButton
   
   # En setup_button_connections():
   credits_button.pressed.connect(_on_credits_pressed)
   
   # Agregar función
   func _on_credits_pressed():
       print("Abriendo créditos...")
       play_click_sound()
       show_container(credits_container)
   ```

3. **Agregar traducciones**:
   ```gdscript
   # En game_translations:
   "english": {
       "credits": "CREDITS"
   },
   "spanish": {
       "credits": "CRÉDITOS"
   }
   ```

### Ejemplo: Agregar Configuración de Dificultad

```gdscript
# En GameSettings.gd:
var difficulty_level: String = "medium"

func set_difficulty(level: String):
    if level in ["easy", "medium", "hard", "nightmare"]:
        difficulty_level = level
        save_settings()
        print("Dificultad cambiada a: ", level)

# En save_settings():
config.set_value("gameplay", "difficulty", difficulty_level)

# En load_settings():
difficulty_level = config.get_value("gameplay", "difficulty", "medium")
```

---

## 🐛 Solución de Problemas

### Problema: "No se encuentra el nodo"
```
Error: get_node: (Node not found: "MainContainer/VBoxContainer/PlayButton")
```

**Solución**: Verificar que la estructura en `.tscn` coincide con el script:
1. Abrir `main_menu.tscn` en el editor
2. Verificar que existe el nodo con ese nombre exacto
3. Verificar la ruta completa del nodo

### Problema: "Traducciones no aparecen"

**Diagnóstico**:
```gdscript
# Agregar en _ready() para debug:
print("Idioma actual: ", GameSettings.current_language)
print("Texto de 'play': ", GameSettings.get_text("play"))
```

**Soluciones**:
- Verificar que `GameSettings` está configurado como autoload
- Verificar que las claves existen en ambos idiomas
- Verificar que se llama a `update_ui_language()`

### Problema: "Audio no reproduce"

**Verificar**:
1. El archivo de audio existe en la ruta especificada
2. El formato de audio es compatible (.ogg, .wav, .mp3)
3. El volumen no está en 0 o muy bajo

```gdscript
# Debug de audio:
func play_click_sound():
    if ui_sounds:
        print("Reproduciendo sonido...")
        var click_sound = load(horror_sounds["click"])
        if click_sound:
            ui_sounds.stream = click_sound
            ui_sounds.volume_db = -10  # Asegurar volumen audible
            ui_sounds.play()
            print("Sonido iniciado")
        else:
            print("Error: No se pudo cargar el sonido")
    else:
        print("Error: ui_sounds no existe")
```

### Problema: "Configuraciones no se guardan"

**Verificar permisos de escritura**:
```gdscript
# Test de guardado:
func test_save():
    var test_file = FileAccess.open("user://test.txt", FileAccess.WRITE)
    if test_file:
        test_file.store_string("test")
        test_file.close()
        print("Guardado funciona")
    else:
        print("Error: No se puede escribir archivos")
```

---

## 📚 Recursos Adicionales

### Documentación de Godot
- [Control Nodes](https://docs.godotengine.org/en/stable/classes/class_control.html)
- [Signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)
- [Autoload](https://docs.godotengine.org/en/stable/getting_started/step_by_step/singletons_autoload.html)
- [Shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/index.html)

### Convenciones de Código
- **Variables**: `snake_case` (ej: `current_language`)
- **Funciones**: `snake_case` (ej: `setup_buttons`)
- **Constantes**: `UPPER_CASE` (ej: `SETTINGS_FILE`)
- **Comentarios**: En español, detallados para novatos

---

## 🎯 Próximos Pasos Sugeridos

1. **Implementar menú de gráficos** completo
2. **Agregar más idiomas** (francés, alemán, etc.)
3. **Crear sistema de keybindings** personalizable
4. **Implementar perfiles de usuario**
5. **Agregar más efectos visuales** de horror
6. **Crear sistema de achievements**

---

**¡Feliz desarrollo! 🎮👹** 