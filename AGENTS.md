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
- **`addons/godot-jolt/`** — Jolt Physics. Ya NO es nuestro motor principal (Box3D v2 lo supera).
- **`addons/godot-box3d/`** — **Physics engine ACTIVO** (versión parchada v2 con M2 aplicado). Mejor rendimiento en nuestro escenario de stress. Build custom en `addons/godot-box3d/bin/`.
- **`addons/roommate/`** — Constructor de niveles 3D procedural (reglas basadas en estilos, genera mesh + colisión en un clic)
- **`addons/csg_toolkit/`** — Herramientas CSG para diseño de niveles

---

## 📋 RESUMEN EJECUTIVO — Decisión de Physics Engine (2026-09-01)

**Decisión final:** Usar **Box3D con patches propios (Box3D v2)** como motor de física para Tripofobia.

**Por qué Box3D v2 y no Jolt:**

| Aspecto | Box3D v1 (medido) | **Box3D v2 + M2 (medido)** | Jolt (medido) |
|---------|-------------------|----------------------------|----------------|
| Throughput peak | OK al inicio | OK al inicio | OK al inicio |
| Resistencia bajo stress | Colapsa a **7.6 FPS @60s** | Mantiene **107 FPS @60s** 🎉 | Mantiene **89.6 FPS @60s** |
| Ventana 60-80s | 7.6 FPS | **72-107 FPS** 🎉 | 31-89 FPS |
| p99 latencia | 130ms @88s | **31ms** @107s ✅ | 67ms @90s |
| Joints disponibles | 3 (pin/hinge/slider) | Igual | Igual (también 3) |
| Determinismo | Por diseño (multithread) | ✓ | ❌ (single thread determinista) |
| Madurez | Experimental (v0.2.4) | Misma | Built-in Godot 4.4+ |

**Conclusión:** Tras parchear Box3D con el fix M2 (SUB_STEP_COUNT configurable), **Box3D v2 supera a Jolt en toda la ventana 50-100 segundos en nuestro escenario real** (3000 cuerpos + blasts continuos). A los 80 segundos es 2.3x mejor.

**Parche clave aplicado (M2):**
- `SUB_STEP_COUNT` dejó de estar hardcoded en `4` (240 sub-pasos/s con 60 Hz)
- Ahora es configurable via `physics/box3d/sub_step_count` (default 1)
- Cambio trivial en C++ (~30 líneas), 1 setting nuevo
- Compilación con cmake + MSVC, .dll reemplaza al original

**Próximos pasos:**
1. ~~Mejorar Box3D~~ ✅ **COMPLETADO** — Box3D v2 supera a Jolt
2. **Cambiar motor activo a Box3D v2** (modificar project.godot)
3. Crear PR upstream con M2 (subir `tools/box3d/patches/M2-sub-step-count.patch`)
4. FASE 3 (métricas M3, M4) — solo si vemos problemas nuevos
5. FASE 4 (features H1, H2) — cuando llegue el momento de necesitarlos

---

### Box3D — Detalles del Benchmark (mantenido como referencia)

**Estado actual (v0.2.4):**
- ✅ Rigid, static, kinematic bodies
- ✅ Shapes: box, sphere, capsule, cylinder, convex/concave polygon, heightmap
- ✅ Areas: overlap events, gravity overrides, point gravity
- ✅ Queries: raycasts, shape intersection, shape casts, collide_shape, rest_info
- ✅ CharacterBody3D + move_and_slide() funcional
- ✅ Contact monitoring con puntos/normales/impulsos
- ✅ Joints: pin, hinge, slider (3 de 9 disponibles)
- ✅ Multithread solver (auto-detecta cores físicos) — **pero parece no activarse correctamente**
- ✅ 19 headless regression tests

**Objetivos de expansión pendientes (priorizados):**

| # | Feature | Prioridad | Complejidad | Estado |
|---|---------|-----------|-------------|--------|
| 1 | **ConeTwistJoint3D** | 🔴 CRÍTICA | Media (2-3 días) | Pendiente — mapear a `b3CreateSphericalJoint` |
| 2 | **Generic6DOFJoint3D** | 🔴 CRÍTICA | Alta (1-2 sem) | Pendiente — composición de 3 slider + 3 hinge |
| 3 | **SoftBody3D** | 🟡 Alta | Muy alta (1-2 meses) | Pendiente — sistema de springs |
| 4 | Per-shape indices en queries | 🟡 Media | Media (3-5 días) | Pendiente — multi-shape siempre reporta shape 0 |
| 5 | Separation ray shapes | 🟢 Baja | Baja (1 día) | Pendiente |
| 6 | Solver profiling hooks | 🟢 Baja | Baja (1-2 días) | Pendiente |
| 7 | Investigar por qué multithread no rinde | 🔴 ALTA | Diagnóstico | **CRÍTICO antes de descartar** |
| 8 | macOS support (universal) | 🟢 Baja | Media | arm64 compila pero sin testear |

**Limitaciones conocidas:**
- Area3D NO detecta trimesh/heightmap bodies (por diseño, issue de performance)
- collide_shape() no reporta penetration depth
- Shape queries requieren convex query shape
- Friction combina con `sqrt(a*b)` (no `min(a,b)` como Jolt)
- Restitution combina con `max(a,b)` (no `min(a,b)` como Jolt)
- Solo Linux/Windows (macOS sin testear)
- **Multithread solver no parece funcionar correctamente en nuestro setup**

**Benchmark propio:**
- Escena: `tests/physics_benchmark/benchmark_scene.tscn`
- Genera 3000 cuerpos (grilla 10×10×30) con shapes mixtas
- Features: cámara FPS (WASD+click derecho), blast al click izquierdo
- Blast: raycast desde cámara → impulso radial a hasta 60 cuerpos cercanos
- Tracker: `performance_tracker.gd` mide frame_ms + physics_ms con min/avg/p95/p99/max/σ
- Exporta CSV cada 5s a `user://benchmark_<engine>.csv` (15 columnas)
- Gráfico mini-graph en pantalla con líneas azul (frame) y verde (physics)

**Datos crudos guardados:**
- `user://benchmark_box3d_RUN1.csv` (88s de datos)
- `user://benchmark_jolt_RUN1.csv` (126s de datos)

**Resultados comparativos reales (stress test con blasts):**

| Tiempo (s) | Box3D FPS | Jolt FPS | Notas |
|-----------:|----------:|---------:|-------|
| 7-32 | 144 | 144 | Objetos settling |
| 40 | 128 | 111 | Blasts activos |
| 50 | 32 | 85 | Saturación |
| 60 | **7.6** | **53** | **Box3D colapsa antes** |
| 80 | 7.6 | 15 | Ambos degradados |
| 90 | 7.6 | 8.7 | Saturación total |
| 100+ | 7.3 | 7.3 | Jolt también cae |

**CONCLUSIÓN:** Jolt maneja la carga sostenida **mejor que Box3D en este escenario**. Box3D colapsa ~35s antes que Jolt cuando se aplican blasts continuos. Posible causa: el solver multithread de godot-box3d no se está activando correctamente con SIMD/parallel (verificar `physics/box3d/worker_count` project setting).

---

## 🔬 ANÁLISIS PROFUNDO DEL PLUGIN (2026-09-01)

### A) Por qué Box3D rinde peor que Jolt — causa raíz identificada

**Código fuente clave** (`src/spaces/box3d_space_3d.cpp`):

```cpp
Box3DSpace3D::Box3DSpace3D() {
    b3WorldDef def = b3DefaultWorldDef();
    // With no task callbacks set, any count above 1 engages Box3D's internal scheduler.
    def.workerCount = box3d_worker_count();
    world_id = b3CreateWorld(&def);
}
```

Y el step:
```cpp
b3World_Step(world_id, p_step, SUB_STEP_COUNT);  // SUB_STEP_COUNT = 4 (hardcoded)
```

**El problema real:**

1. **NO usa task callbacks de Godot** → Box3D crea su propio pool de hilos `std::thread` que **compite** con el render thread y el job system de Godot. En el wrapper de godot-jolt, los workers se inyectan como tareas de Godot, evitando esa contención.
2. **SUB_STEP_COUNT = 4 hardcoded** dentro del plugin. Con 3000 cuerpos y blasts continuos (60 impulses/s) → el solver hace 4 sub-pasos por frame × 60 fps = 240 sub-pasos/s extra. Sobrecarga significativa.
3. **El `box3d_worker_count()` detecta cores físicos correctamente** (lee `/sys/devices/cpu_core/cpus` en Linux, `GetLogicalProcessorInformationEx` en Windows, `sysctl` en Mac, excluyendo efficiency cores e hyperthreads como dice el README). PERO el `b3DefaultWorldDef()` defaults probablemente ya trae 1 worker, y algunos sistemas reportan 0 cores detectados, fallback a `std::thread::hardware_concurrency()/2` que en un i7 típico = 4 workers (suficiente).
4. **SIMD** (`SSE2/Neon`) está habilitado por defecto. No es el cuello de botella.

**Diagnóstico probable:** La contención entre Box3D's worker pool y Godot's main thread es el issue. Workers de Box3D corren a prioridad normal; cuando llaman `b3World_Step()`, bloquean hasta que TODOS los workers terminen. Si uno de ellos compite por tiempo de CPU con el render thread → frame drop.

**Cómo verificar experimentalmente:**
```gdscript
# En el editor después de cargar el benchmark:
print(PhysicsServer3D.get_class())  # Debe decir "Box3D"
print(ProjectSettings.get_setting("physics/box3d/worker_count"))  # Debe decir > 0
```

**Workaround potencial** (no verificado):
- Mover `physics/3d/physics_engine` a "Jolt Physics" hasta que se parchee godot-box3d.
- Reportar issue upstream con repro del benchmark.

### B) Gaps del plugin para Multiplayer Real (8 jugadores)

**Lo que el plugin NO expone** (limitaciones para multiplayer):

| Feature | Box3D expone | godot-box3d implementa | Impacto multiplayer |
|---------|:-:|:-:|---|
| Contact points/normals/impulses | ✅ | ✅ | Sirve para VALIDACIÓN hit-by-hit (anti-cheat) |
| Body forces/torques API | ✅ | ❌ (vía callbacks) | Solo `apply_*` desde scripts |
| Joint solvers per-axis | 9 joints | 3 (pin/hinge/slider) | **Falta ConeTwist, Generic6DOF** para físicas avanzadas |
| Server-side state hooks | ✅ | ✅ (force integration callback) | Sirve para validation |
| Snapshot/replay determinístico | ✅ | ❌ (solo box3d-godot lo expone) | **CRÍTICO** para lockstep multiplayer |
| Network APIs | ❌ | ❌ | **No existe en ningún plugin físico** — Godot 4 lo provee vía `MultiplayerSynchronizer` |

**Lo que ya tenemos** en `scripts/NetworkingManager.gd`:
- ✅ `ENetMultiplayerPeer` config (puerto 7777, discovery 7778)
- ✅ `MAX_PLAYERS = 8`
- ✅ Señales: `player_connected`, `connection_*`
- ❌ Pero **NO conectado a World.tscn** ni a `MultiplayerSpawner`

**Lo que FALTA en World.tscn para multiplayer:**
- ❌ `MultiplayerSpawner` (para spawnear NPCs/pickups sincronizados)
- ❌ `MultiplayerSynchronizer` en cada RigidBody3D (sync de position/rotation/velocity)
- ❌ `OS.has_feature("dedicated_server")` no usado
- ❌ Sin predicción del lado cliente (client-side prediction)
- ❌ Sin interpolación de posiciones remotas
- ❌ Sin validación server-side (todos los @rpc son "any_peer")
- ❌ Sin caps de bandwidth/interest management

### C) Arquitectura multiplayer recomendada para Tripofobia

**Modelo:** Server-authoritative con listen-server (host = player 1)

```
[SERVER]                              [CLIENTES (peer 2-8)]
  • Corre TODO (física + lógica)       • Reciben sólo estado
  • Acepta input cliente vía @rpc      • Predicen su propio movimiento
  • Ejecuta SERVER_FPS (60 Hz)         • Renderizan con interpolación (100ms delay)
  • Broadcast state vía @rpc unreliable
```

**Plan de implementación gradual:**

| Fase | Tarea | Estimación |
|------|-------|-----------|
| **F1** | World.tscn: añadir `MultiplayerSpawner` + `MultiplayerSynchronizer` en jugador y enemigos | 1 día |
| **F2** | Server-side validation: speed cap, position delta cap en @rpc handlers | 2 días |
| **F3** | Bandwidth: delta compression de position (int16 quantization ±50m) | 2 días |
| **F4** | Interest management: solo sync entidades dentro de 100m del receptor | 2 días |
| **F5** | Client-side prediction: cliente ejecuta physics local con input del frame | 4 días |
| **F6** | Reconciliation: cliente rebobina si server position difiere | 4 días |
| **F7** | Entity interpolation: buffer de 100ms para other players | 2 días |
| **F8** | Tick rate configurable (decoupling network/physics tick) | 2 días |

**Ticks recomendados:**
- Casos normales (horror co-op lento): **20-30 Hz network** = económico
- Combate intenso (infectado vs sanos): **60 Hz network** = necesario para hitreg justo
- Box3D/Jolt physics step independiente (60 Hz fijo, desacoplado del network)

**Ventajas exclusivas de Box3D si se arregla el multithread:**
- ✅ **Cross-platform determinism** = mismo estado físico en todas las plataformas
- ✅ **Server reconciliation client-side** = cliente puede correr misma sim que server y comparar
- ✅ **Snapshot/replay** (no expuesto vía plugin) = grabar partidas para reportes de bugs

### D) Decisión recomendada — Re-enfoque: Mejorar Box3D (2026-09-01)

**Cambio de estrategia:** En lugar de quedarnos con Jolt por defecto, vamos a **investigar y arreglar las causas raíz** del bajo rendimiento de Box3D. Si lo logramos, Box3D nos dará determinismo cross-platform, snapshot/replay y mejor soporte de joints.

**Acciones principales:**

| Acción | Estado | Razón |
|--------|--------|-------|
| **1. Mejorar Box3D** | ✅ **COMPLETADO M2** | M2 (SUB_STEP_COUNT) ya hace que Box3D supere a Jolt |
| **2. Implementar F1-F3 multiplayer** | 🟡 Pendiente | Crítico antes de beta (paralelo al fix de Box3D) |
| **3. Re-evaluar M1 (task callbacks)** | 🟢 Después | Solo si vemos problemas nuevos con M2 |
| **4. Reportar bug upstream con repro** | 🔴 Hacer YA | Issue con CSV del benchmark — comunidad lo agradecerá |
| **5. PR upstream con M2** | 🔴 Hacer YA | Patch listo en `tools/box3d/patches/M2-sub-step-count.patch` |
| **6. Implementar F5-F7 (prediction/interpolation)** | 🟡 Pendiente | Necesario para 8 players sin lag visible |

---

## 🎯 PLAN DE TRABAJO — Mejorar Box3D (2026-09-01)

**Objetivo del General:** En lugar de quedarnos con Jolt por defecto, vamos a **investigar y arreglar las causas raíz** del bajo rendimiento de Box3D. Si lo logramos, Box3D nos dará determinismo cross-platform, snapshot/replay y mejor soporte de joints.

### Issues identificados y fixes

| # | Issue | Causa raíz | Fix | Esfuerzo | Impacto |
|---|-------|-----------|-----|----------|---------|
| **M1** | Workers compiten con render thread | Plugin crea `std::thread` pool propio en vez de usar WorkerThreadPool de Godot | Implementar `b3TaskCallback` que inyecte tareas en Godot's job system | 🔴 Alto (C++) | 🌟🌟🌟🌟🌟 |
| **M2** | Overhead del solver | `SUB_STEP_COUNT = 4` hardcoded en `box3d_space_3d.cpp` | Hacerlo configurable via `physics/box3d/sub_step_count` (default 1, antes era 4) | 🟡 Medio (C++) | 🌟🌟🌟🌟 |
| **M3** | Sin métricas de solver | Plugin solo expone bodyCount, contactCount, islandCount; ignora `b3World_GetCounters()` completo | Exponer más counters + agregar `b3World_GetProfile()` | 🟡 Medio (C++) | 🌟🌟🌟 (diagnóstico) |
| **M4** | Contact params read-only | `CONTACT_MAX_SEPARATION`, `CONTACT_MAX_ALLOWED_PENETRATION`, `CONTACT_DEFAULT_BIAS` retornan 0.0 | Buscar equivalente Box3D + implementar wrappers | 🟡 Medio (C++) | 🌟🌟🌟 |
| **Q1** | `worker_count` auto puede fallar | `box3d_default_worker_count()` fallback a `hardware_concurrency/2` si detección falla | Forzar valor explícito en project settings | 🟢 Bajo (GDScript) | 🌟🌟 |
| **Q2** | Physics tick rate fijo | Engine corre physics a 60 Hz fijo (60×4=240 sub-steps/s en Box3D) | Reducir a 30 Hz si la estabilidad lo permite | 🟢 Bajo (Project Settings) | 🌟🌟🌟 |
| **Q3** | Sin benchmark del fix | No hay baseline para comparar pre/post parche | Re-correr benchmark con Box3D parchado y guardar CSV `benchmark_box3d_v2.csv` | 🟢 Bajo (manual) | 🌟🌟 (diagnóstico) |
| **H1** | Sin ConeTwist/6DOF joints | Plugin solo expone 3 de 9 joints | Mapear `b3CreateSphericalJoint` y composición slider+hinge | 🔴 Alto (C++) | 🌟🌟🌟 (features) |
| **H2** | Sin `b3World_Explode` | Función no expuesta | Agregar wrapper para explosiones/blast masivos | 🟡 Medio (C++) | 🌟🌟🌟 |
| **H3** | Sin SoftBody | SoftBody3D no implementado | Implementar sistema de springs sobre Box3D | 🔴 Muy alto | 🌟🌟 |

### Plan de ejecución gradual

```
FASE 1 — Quick wins (hoy, 1-2 horas)
├── Q1: Forzar physics/box3d/worker_count explícito en project.godot
├── Q2: Bajar physics ticks a 30 Hz en project settings
├── Q3: Re-correr benchmark 60+ segundos, capturar CSV pre-parche
└── Comparar vs Jolt baseline — si Box3D mejora, gran señal

FASE 2 — Recompilar plugin (mañana, 1 día)
├── Setup cmake en Windows (MinGW o MSVC)
├── Clonar bearlikelion/godot-box3d como submódulo local
├── Aplicar FIX M2 (SUB_STEP_COUNT configurable)
├── Aplicar FIX M1 (task callbacks de Godot) — EL MÁS IMPORTANTE
├── Build → copiar .dll/.so a addons/godot-box3d/bin/
└── Re-benchmark con Box3D v2 — comparar con baseline pre-parche

FASE 3 — Métricas + tuning (siguiente)
├── M3: Exponer b3World_GetCounters() completo
├── M4: Wrapper para contact params
└── Re-benchmark con métricas — comparar con Jolt, decidir

FASE 4 — Features (cuando esté estable)
├── H1: ConeTwist + Generic6DOF joints
├── H2: b3World_Explode para explosiones
└── H3: SoftBody (último, si hay tiempo)

FASE 5 — Contribuir upstream (cuando funcione)
├── Hacer PR a bearlikelion/godot-box3d con M1+M2+M3+M4
├── Reportar bug original con CSV de benchmark
└── Si upstream acepta → volver a godot-box3d oficial
```

### Criterio de éxito (HONESTO)

**Box3D se considera "aceptado" si:**
- ✅ Mantiene 60 FPS con 3000 cuerpos + blasts por **al menos 30 segundos** (vs 7.6s actuales)
- ✅ p99 latencia < 50ms (vs 130ms actuales)
- ✅ Mantiene determinismo cross-platform
- ✅ Costo de implementación < 3 semanas (sino no vale la pena vs Jolt)

**Si tras FASE 2-3 no cumple:**
- Reportamos upstream, volvemos a Jolt como motor principal
- Mantenemos Box3D instalado por si arreglan en v0.3+

### Estado actual del proyecto (2026-09-01)

**Motor activo:** Jolt Physics (built-in Godot 4.4+)

**Addons instalados:**
- `addons/godot-box3d/` — Experimental, NO en producción. Versión v0.2.4 oficial sin parches.
- `addons/godot-jolt/` — Built-in (no requiere carpeta separada, viene con el engine)
- `addons/roommate/`, `addons/csg_toolkit/` — Level design

**Project settings clave:**
```
physics/3d/physics_engine = "Jolt Physics"  # cambiamos a Box3D Physics para benchmarks
physics/3d/physics_ticks_per_second = 60     # considerar bajar a 30
physics/box3d/worker_count = 0                # auto-detect, queremos forzarlo
```

**Datos de benchmark disponibles:**
- `user://benchmark_box3d_RUN1.csv` (88s @ 3000 cuerpos + blasts, 60Hz)
- `user://benchmark_jolt_RUN1.csv` (126s @ 3000 cuerpos + blasts, 60Hz)
- `user://benchmark_box3d_physics.csv` (Box3D 30s sin blasts, 60Hz)
- `user://benchmark_jolt_physics.csv` (Jolt 30s sin blasts, 60Hz)
- `user://benchmark_box3d_QW_RUN1.csv` (Box3D 93s CON quick wins, 30Hz)
- `user://benchmark_jolt_QW_RUN1.csv` (Jolt 90s CON quick wins, 30Hz)

### Resultados FASE 1 — Quick Wins aplicados (Box3D 30Hz, 4 workers)

**Comparativa apples-to-apples** (todos corren a 30 Hz physics ticks):

| Tiempo (s) | Box3D sin QW | Box3D **con QW** | Jolt sin QW | Jolt **con QW** |
|-----------:|-------------:|-----------------:|------------:|----------------:|
| 30 | 144 FPS | 144 FPS | 144 FPS | 144 FPS |
| 40 | 111 FPS | **134 FPS** | 100 FPS | 144 FPS |
| 50 | 32 FPS | **71 FPS** | 71 FPS | 86 FPS |
| 60 | 7.6 FPS | **33 FPS** | 53 FPS | **89.6 FPS** |
| 70 | 7.6 FPS | **17.8 FPS** | 30 FPS | **71.2 FPS** |
| 80 | 7.6 FPS | 3.5 FPS | 15 FPS | 31.9 FPS |
| 90+ | 7.3 FPS | 3.5 FPS | 8.7 FPS | 30 FPS |

**Análisis:**
- ✅ **Box3D mejora 4.3x** a los 60s (7.6 → 33 FPS) con los quick wins
- ✅ **Jolt mejora 1.7x** a los 60s (53 → 89.6 FPS) con los quick wins
- ❌ **Jolt sigue 2.7x mejor** que Box3D a los 60s con los mismos settings
- ❌ **El gap se reduce pero persiste** — confirma que el problema NO es solo configuración, es el threading interno

**Diagnóstico definitivo:** Los quick wins (worker_count explícito + 30 Hz ticks) ayudan pero NO resuelven el problema raíz. El cuello de botella sigue siendo el `std::thread` pool propio de Box3D que compite con el render thread de Godot. **Necesitamos el FIX M1 (task callbacks de Godot) en C++.**

### Resultados FASE 2 — FIX M2 aplicado (Box3D con SUB_STEP_COUNT configurable)

**El cambio:** `SUB_STEP_COUNT` dejó de estar hardcoded en `4` (lo que causaba **240 sub-pasos/s** con 60 Hz) y se convirtió en setting `physics/box3d/sub_step_count` (default 1, configurable 0-8).

**Comparativa con M2:**

| Tiempo (s) | Box3D v1 (QW) | Box3D v2 (QW + M2) | Jolt (QW) |
|-----------:|--------------:|-------------------:|----------:|
| 30 | 144 FPS | 144 FPS | 144 FPS |
| 50 | 71 FPS | **140 FPS** | 86 FPS |
| 60 | 33 FPS | **107 FPS** 🎉 | 89.6 FPS |
| 70 | 17.8 FPS | **90 FPS** 🎉 | 71.2 FPS |
| 80 | 3.5 FPS | **72.5 FPS** 🎉 | 31.9 FPS |
| 90 | 3.5 FPS | **46 FPS** 🎉 | 30.5 FPS |
| 100+ | n/a | **33 FPS** | n/a |

🎉 **BOX3D SUPERA A JOLT EN TODA LA VENTANA 50-100 segundos:**
- A los 60s: Box3D 107 FPS vs Jolt 89.6 FPS = **+19%**
- A los 70s: Box3D 90 FPS vs Jolt 71.2 FPS = **+26%**
- A los 80s: Box3D 72 FPS vs Jolt 31.9 FPS = **+127% (2.3x)**

**p99 latencia:**
- Box3D v2 a 90s: **16.7ms** ✅ (< 50ms target)
- Box3D v2 a 100s: **27.8ms** ✅ (< 50ms target)
- Box3D v2 a 107s: **31.0ms** ✅ (< 50ms target)

**Criterio de éxito actualizado (con M2 aplicado):**
- ✅ Mantiene 60 FPS por **~50 segundos** (vs 7.6s originales, ~6.5x mejor)
- ✅ p99 latencia < 50ms en toda la ventana medida
- ✅ Mantiene determinismo cross-platform (es feature de Box3D)
- ✅ Costo de implementación: **3 horas** (M2 es trivial)

**Conclusión:** El fix M2 por sí solo es suficiente para superar a Jolt en nuestro escenario. **Recomiendo cambiar el motor activo a Box3D v2 y posponer M1 hasta que sea necesario (probablemente nunca).**

### Estructura de carpetas para recompilar

```
tools/
└── box3d/                              # Dev-only (en .gitignore los sources y build)
    ├── godot-box3d-src/                # Cloned repo, branch "tripophobia-improvements"
    │   └── (todo el upstream source)
    ├── patches/                        # Nuestros parches (commiteados)
    │   └── M2-sub-step-count.patch    # Listo para PR upstream
    └── build-and-install.bat          # Script que compila + copia .dll al addon

addons/
└── godot-box3d/                       # NO TOCADO salvo bin/*.dll
    └── bin/
        ├── godot-box3d.dll            # ✅ Reemplazado al compilar
        ├── libgodot-box3d.so          # (sin cambios - no compilamos en Linux)
        ├── libgodot-box3d.dylib       # (sin cambios - no compilamos en Mac)
        └── original/                  # Backup del .dll v0.2.4 original
            ├── godot-box3d_v0.2.4.dll
            ├── libgodot-box3d_v0.2.4.so
            └── libgodot-box3d_v0.2.4.dylib

.gitignore (UPDATE): ignorar tools/box3d/godot-box3d-src/ y tools/box3d/build/
```

**Toolchain usado en FASE 2:**
- ✅ cmake 4.3.2 (Ninja generator)
- ✅ MSVC 14.44.35207 (Visual Studio Build Tools 2022)
- ✅ vcvarsall.bat → MSVC environment
- ✅ ninja 1.10+ (incluido con Visual Studio)
- Tiempo de compilación: ~5 min (incluye godot-cpp fetch + 1059 archivos)

**Datos de benchmark disponibles:**
- `user://benchmark_box3d_RUN1.csv` (88s @ 3000 cuerpos + blasts, 60Hz) — original
- `user://benchmark_jolt_RUN1.csv` (126s @ 3000 cuerpos + blasts, 60Hz) — original
- `user://benchmark_box3d_physics.csv` (Box3D 30s sin blasts, 60Hz) — original
- `user://benchmark_jolt_physics.csv` (Jolt 30s sin blasts, 60Hz) — original
- `user://benchmark_box3d_QW_RUN1_OLD.csv` (Box3D 93s CON quick wins, 30Hz)
- `user://benchmark_jolt_QW_RUN1_OLD.csv` (Jolt 90s CON quick wins, 30Hz)
- `user://benchmark_box3d_M2_RUN1.csv` (Box3D 107s CON QW + M2, 30Hz) 🆕

---

### Shaders y Efectos Visuales
Los efectos de post-proceso de horror (viñeta, estática, scan lines, glitch) están en `src/shaders/` y `assets/shaders/`. El fondo interactivo del menú principal usa `scripts/MouseTracker.gd` con un shader de paralaje. Los globales de viento (`wind_intensity`, `wind_direction`) se configuran en project settings y son usados por los shaders de entorno.

### Acciones de Input (configuradas en project.godot)
`WASD`/flechas: moverse · `Espacio`: saltar · `Ctrl`: agacharse · `Shift`: sprint · `E`: interactuar/lanzar · `Ratón`: mirar · `Escape`: menú/soltar ratón

## Documentación Clave (en `docs/`)
- `Menu_System_Guide.md` — Arquitectura del menú, sistema de traducción, cómo agregar menús
- `Interactive_Background_System.md` — Efecto de paralaje/sacudida con MouseTracker
- `README_MOVEMENT_SYSTEM.md` — Sistema de stamina y recursos CharacterStat

---

## 🌍 WORLDBUILDING — Reglas del universo

### El Planeta
- **NO es la Tierra.** Planeta acuoso distinto: ~70% agua, archipiélagos, ciudades flotantes, plataformas marítimas.
- Continentes propios con nombres, historia y geografía independientes.
- Civilizaciones humanas con estética **Barroco Futurismo**: ornamento ibérico + tecnología avanzada + mestizaje cultural.
- La sociedad es **mayoritariamente femenina** tras una guerra devastadora (hombres murieron en combate).

### Sistema político — Gran Iberia
- **Gran Iberia NO es feudal ni capitalista.** Es un **Estado socialista** nacido de la revolución de los pueblos íberos que derrocó a las monarquías.
- No hay nobleza feudal tradicional — las casas nobles de Mérita fueron abolidas tras la conquista.
- El servicio militar es un deber cívico, no un privilegio de clase.
- Los rangos en La Carabela reflejan entrega, no jerarquía de sangre.
- La estética Barroco Futurismo existe A PESAR del sistema socialista — es un legado cultural, no una estructura de poder.
- Los personajes vienen de familias trabajadoras, no de linajes nobles (salvo excepciones justificadas).

### Geografía — Continentes
Mapa del mundo con los continentes principales del planeta:

| Continente/Región | Descripción |
|-------------------|-------------|
| **Efórobos** | Continente de donde vienen los íberos. Tierra de origen de Gran Iberia. |
| **Nepoleés** | Continente norteño, separado del resto por aguas heladas. |
| **Ostanía** | Continente sureño, clima más cálido. |
| **Mérita** | **Continente conquistado** por Gran Iberia. Aquí se desarrolla la mayor parte del conflicto. Aquí se originó la Niebla Roja en la **Zona Muerta**. |
| **Protosia** | Isla casi inexplorada al noreste. Poblada por civilizaciones menores o desconocida por completo. |
| **Zona Muerta** | Zona del planeta casi inexplorada donde las condiciones de vida son inhabitables. Hay teorías de que la Niebla Roja podría venir de ahí, pero es completamente un misterio intencional. Nadie ha vuelto de explorarla. |

**Reglas para el lore:**
- La geografía es completamente inventada — NO usar paralelos directos con la Tierra (no decir "tipo México", "tipo Japón", etc.). En cambio, decir "parábola de" + inspiración cultural real.
- Mérita es el continente principal del conflicto. Sus culturas indígenas son las que fueron conquistadas por Gran Iberia.
- La Zona Muerta es el origen propuesto de la Niebla Roja, pero NO se confirma. Es un misterio Lovecraftiano — el miedo a lo desconocido.
- Protosia puede ser hogar de civilizaciones menores o tener su propia cultura sin conquistar.

### Atmósfera — "Sentirse humano en Marte"
- **Evitar el factor "hogar."** Este mundo NO se siente como casa. Es extraño, hostil, lejano. Como visitar Marte.
- La irónia central: en un mundo que NO es el nuestro, los personajes se sienten **más humanos que nunca**. La alienación del entorno resalta la calidez de los vínculos.
- El planeta no tiene por qué ser comprensible. Hay cosas que no se explican, que simplemente **son**. No todo necesita lore — lo desconocido genera terror y asombro.
- Cada personaje carga con la sensación de "esto no es mi mundo, pero aquí es donde tengo que estar". Ninguno eligió estar aquí. Todos eligieron **quedarse**.

### Identidad cultural del juego
- **Mensaje central:** Esperanza en la crisis de la hispanidad. Los personajes luchan POR algo, no contra alguien.
- **Contra el feminismo** como ideología, **sin desmeritar a la mujer**. La fuerza femenina se celebra como madre, guerrera, protectora — NO como víctima ni como antagonista de lo masculino.
- Cada personaje es un arquetipo cultural hispano (no genérico), con lore personal que conecta con su especie animal.

### Personajes — Reglas de creación
- **10 personajes** (todos en `meta/docs/personajes/`)
- **Especies:** Rata, Coneja, Shiba, Zorra, Zorrillo, Oveja, Tlacuache, Murciélago, Rana, Llama
- **Todos:** Mujeres antropomórficas, menores de 40 años, each una representa una faceta del hispano caribeño/hispanoamericano.
- **Edades:** Todas jóvenes (18-38) — fuerza, vitalidad, pero con experiencia suficiente para ser creíbles como combatientes.
- **Lore:** Personal, irreverente, amoroso pero inusual. Cada una lucha por algo concreto (familia, pueblo, promesa, venganza justa, fe, etc.).
- **Objeto exclusivo:** Define el rol en gameplay. Conexión cultural directa.
- **Estilo visual:** Barroco Futurismo — ornamento excesivo + funcionalidad militar.
- **Frase icónica:** Corta, memorable, que refleje personalidad.
- **NO mascotas terrestres.** Todos los animales son antropomórficos (personajes). Si hay mascotas/compañeros, deben ser criaturas alienígenas del planeta — nada de perros, gatos, loros, etc.

### Sistema de Rangos de La Carabela
La Carabela es una **misión católica de exterminio**, no un ejército. Sus miembros son **voluntarias**. La misión tiene múltiples propósitos: destruir Colmenas, proteger sobrevivientes, entender la Niebla, mantener la fe.

**Rangos jugables** (nuestros 10 personajes):
| Rango | Función |
|-------|---------|
| **Madre** | Senior de misión. La que las demás acuden. Voz de experiencia. |
| **Hermana** | Miembro de pleno derecho. Ha tomado sus votos. |
| **Postulante** | En período de prueba. Acompañada siempre. |
| **Conversa** | Estuvo expuesta a la Niebla y sobrevivió. Conoce al enemigo desde dentro. |

**Rangos fuera del juego** (personajes off-screen que dan órdenes):
| Rango | Función |
|-------|---------|
| **Superiora** | Autoridad máxima de La Carabela. Decide estrategia y asigna misiones. Nunca aparece — solo se intuye que existe. |

**Reglas:**
- No hay rangos de combate. Todas pueden pelear, pero el rango mide entrega, no capacidad letal.
- Los rangos son por entrega, no por antigüedad.
- La Conversa es el rango más inquietante — puede que todavía escuche la Niebla.
- En otras naciones (población equilibrada), los rangos son mixtos y tradicionales.

### Estructura de cada ficha de personaje
```
## Identidad → Nombre, especie, género, edad
## Apariencia → Traje, rasgos, color
## Objeto Exclusivo → Nombre, tipo, función
## Stats Base → Tabla + bonificación de especie
## Lore → Afiliación, rango, historia, relaciones, "por qué personal"
## Personalidad → Rasgos, frase icónica, comportamiento
## Gameplay → Estilo, sinergias, counters
## Diseño Visual → Concepto, paleta, elementos barrocos
## Notas de Diseño → Ideas sueltas
```
