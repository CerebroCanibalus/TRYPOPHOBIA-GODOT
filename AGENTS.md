# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) cuando trabaja con el código de este repositorio.

## Descripción del Proyecto

**Trypophobia** es un juego de terror survival cooperativo multijugador (hasta 8 jugadores) construido en Godot 4.4 con renderizado Forward Plus. El loop principal consiste en navegar entornos 3D, evitar enemigos que detectan sonidos y completar objetivos de extracción. Los scripts y la documentación están principalmente en español.

## Comandos de Desarrollo

Este es un proyecto de Godot 4.4. El desarrollo se realiza a través del Editor de Godot — no hay sistema de build por CLI. Operaciones comunes:

- **Ejecutar el juego:** Abrir `project.godot` en Godot 4.4+ y presionar F5 (inicia desde `main_menu.tscn`)
- **Exportar (Windows):** Proyecto → Exportar → Windows Desktop → genera en `../Lanzamientos/infdev/Tripofobia.exe`
- **Escena de entrada:** `res://main_menu.tscn`

## Arquitectura

### Singletons Autoload
- `scripts/NetworkingManager.gd` — Multijugador ENet (servidor en puerto 7777, descubrimiento UDP en 7778, máximo 8 jugadores)
- `scripts/GameSettings.gd` — Configuración persistente (idioma, volumen); accesible desde cualquier script

### Sistema de Jugador (Dos Implementaciones)
Existen dos controladores de jugador distintos — no consolidar sin entender ambos:
1. **`src/player/characterbody_jugador.gd`** — Movimiento básico (5 m/s, sin stamina)
2. **`src/interactibles/player.gd`** — Controlador FPS completo: agarrar/lanzar objetos, sprint, head bob, cambios de FOV, sistema de stamina; usa `RayCast3D` para interacción

El sistema de stamina usa recursos CharacterStat — ver `README_MOVEMENT_SYSTEM.md` para configuración.

### IA de Enemigos
`src/enemy/Enemy.gd` (extiende `CharacterBody3D`) usa `NavigationAgent3D` para pathfinding. Los enemigos navegan hacia objetos `SoundArea` (`src/sounds/Sound.gd`, extiende `Area3D`) — esta es la mecánica central de sigilo. Velocidad: 2 m/s.

### Organización de Escenas
- `main_menu.tscn` — Punto de entrada con efectos shader de horror y browser de servidores multijugador
- `src/world/World.tscn` — Mundo principal del juego
- `maps/lobby.tscn` — Lobby multijugador
- `maps/misiones/c1.tscn` — Misión 1 de campaña

### Addons
- **`addons/godot-jolt/`** — Reemplaza la física por defecto para mejor simulación de cuerpos rígidos
- **`addons/roommate/`** — Constructor de niveles 3D procedural (reglas basadas en estilos, genera mesh + colisión en un clic)
- **`addons/csg_toolkit/`** — Herramientas CSG para diseño de niveles

### Shaders y Efectos Visuales
Los efectos de post-proceso de horror (viñeta, estática, scan lines, glitch) están en `src/shaders/` y `assets/shaders/`. El fondo interactivo del menú principal usa `scripts/MouseTracker.gd` con un shader de paralaje. Los globales de viento (`wind_intensity`, `wind_direction`) se configuran en project settings y son usados por los shaders de entorno.

### Acciones de Input (configuradas en project.godot)
`WASD`/flechas: moverse · `Espacio`: saltar · `Ctrl`: agacharse · `Shift`: sprint · `E`: interactuar/lanzar · `Ratón`: mirar · `Escape`: menú/soltar ratón

## Documentación Clave (en `docs/`)
- `Menu_System_Guide.md` — Arquitectura del menú, sistema de traducción, cómo agregar menús
- `Interactive_Background_System.md` — Efecto de paralaje/sacudida con MouseTracker
- `README_MOVEMENT_SYSTEM.md` — Sistema de stamina y recursos CharacterStat
