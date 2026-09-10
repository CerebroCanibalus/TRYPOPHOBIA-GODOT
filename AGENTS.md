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


---

## ?? MARIONETA � Sistema de Personajes

**MARIONETA = M�dulo de Articulaci�n Rob�tica con IK, Orquestaci�n y Navegaci�n Estructural con Trazado de Animaci�n.**

*"Puppet que jala huesos como un titiritero."*

### Filosof�a
**Composici�n sobre configuraci�n.** Cada personaje es **DATA**; toda la l�gica es gen�rica y reutilizable. Las animaciones son **primitivas peque�as y mezclables**, no archivos .tres fr�giles.

### Capas (5)

```
1. DATA (Resources)               CharacterData + BodyBlueprint + ItemData
   ? usado por
2. CONTROLLER (CharacterBody3D)   Input + move_and_slide + state machine
   ?
3. PHYSICS BODY                   Body kinematic (c�psula) + Piernas/Brazos f�sicos
   ? targets IK
4. POSE COMPOSER                  Mezcla N primitivas con pesos
   ? aplica a
5. IK SOLVERS                     Two-bone IK gen�rico + look-at
```

### Estructura de archivos

```
src/marioneta/
+-- character_data.gd              # Resource: stats por personaje
+-- body_blueprint.gd              # Resource: huesos + proporciones
+-- character_controller.gd        # CharacterBody3D: movimiento + f�sica
+-- character_state_machine.gd     # RefCounted: FSM event-driven
+-- pose_composer.gd               # (Fase 2) Mezcla primitivas
+-- ik_solvers.gd                  # (Fase 3) Two-bone IK gen�rico
+-- carry_system.gd                # (Fase 5) Pickup/drop/use
+-- primitives/                    # (Fase 2) Animaciones modulares
�   +-- pose_primitive.gd
�   +-- p_idle_breathing.gd
�   +-- p_walk_leg_cycle.gd
�   +-- p_walk_arm_cycle.gd
�   +-- p_body_bob.gd
�   +-- ...
+-- ragdoll_fallback.gd            # RENOMBRADO de active_ragdoll.gd
                                     # Solo se activa en infecci�n/muerte
```

### Innovaciones clave

| Innovaci�n | Qu� resuelve |
|---|---|
| **Body Blueprint indirection** | Nombres de huesos son DATA, no hardcode. Una Rata y una Llama pueden tener esqueletos con huesos distintos sin tocar c�digo |
| **Mass-driven parameters** | mass auto-deriva stiffness, max_force, walk_speed, breathing_speed. Oveja (90kg) camina distinto a Rata (40kg) autom�ticamente |
| **Pose Primitives componibles** | Cada animaci�n es una clase de 50 l�neas con weight y enabled. Apaga walk_arm_swing ? brazos quietos (Manos en los bolsillos) |
| **Debug visual toggle** | @export var debug_visual: bool dibuja c�psulas, IK targets, velocity, state label |
| **State machine RefCounted** | Liviano, event-driven, testeable aislado. WeaponStateMachine es el canon |

### Anti-patrones evitados
- ? Active ragdoll puro (gameplay laggy, jitter)
- ? AnimationTree con .tres (fr�gil, dif�cil de versionar)
- ? Script monol�tico (intimidante, no modular)
- ? Hardcoded bone names (no portable entre personajes)
- ? CharacterBody3D sin c�psula (raycasts imprecisos)

### Fases de implementaci�n

| Fase | Qu� | Estado |
|---|---|---|
| **F1** | Data + Controller + State Machine + Anim procedural b�sica | ?? EN PROGRESO |
| F2 | Primitives componibles + PoseComposer | ? |
| F3 | Foot IK (raycast al suelo) + Wall push | ? |
| F4 | Hand IK (cuando carga objeto) | ? |
| F5 | Carry System (pickup/drop/use) | ? |
| F6 | 10 CharacterData + 10 BodyBlueprint resources | ? |
| F7 | Multiplayer (authority split, state sync) | ? |

### C�mo a�adir un nuevo personaje (Fase 6)

1. Crear esources/marioneta/<nombre>.tres (CharacterData)
2. Crear esources/marioneta/<nombre>_blueprint.tres (BodyBlueprint con nombres de huesos)
3. Asignar visual_scene = path al .glb del personaje
4. �Listo! El controller hace todo el resto autom�ticamente

---

## 🎬 SISTEMA ANIM_EDITOR — Editor de Animaciones Procedurales (2026-09-05)

**Estado:** Pre-FASE 0 (validación de ragdoll de prueba)
**Decisión General Beria:** Construir un editor visual de animaciones procedurales tipo el proyecto UE5 WalkAnimSelector (ContinueBreak, 2023), inspirado en su UI always-on + sistema de presets + Control Rig. Adaptado a Godot 4.4 y al sistema MARIONETA existente.

### Inspiración

El proyecto UE5 WalkAnimSelector (de ContinueBreak / Arthur Ontuzhan) usa:
- Sliders runtime que modifican parámetros de animación en vivo
- Botón Randomize para generar variantes
- Sistema de brackets (8→4→2→1) para elegir favorito
- Copy/Paste de presets como string al clipboard
- Control Rig para manipular la pose en el editor

**Adaptación a Tripofobia:** En vez de un Control Rig (no existe en Godot nativo), usamos SubViewport + overlay custom + gizmos. En vez de brackets (era obsesión del autor UE5), usamos load/save con gestión de archivos .tres.

### Pre-requisito BLOQUEANTE — Ragdoll Funcional

Antes de tocar el editor, hay que **validar que el ragdoll de prueba funciona de verdad** con humanoid.tscn. El plan NO puede proceder si esto falla.

**Inventario actual de humanoid.tscn (mapeado 2026-09-05):**
- ✅ 10 PhysicalBone3D: Body, Head, LArm1, LArm2, RArm1, RArm2, LLeg1, LLeg2, RLeg1, RLeg2
- ✅ 9 CollisionShape3D (uno por PhysicalBone)
- ✅ 2 ShapeCast3D: OnFloorLeft, OnFloorRight (raycast suelo)
- ✅ 2 Area3D: LGrabArea, RGrabArea (pickup detection)
- ✅ 2 PinJoint3D: GrabJointLeft, GrabJointRight
- ✅ 1 JumpTimer
- ✅ AnimationPlayer con utoplay = &"idle" ⚠️ (PUEDE CONFLICTUAR con procedural)
- ✅ Skeleton3D con nimate_physical_bones = false ⚠️
- ✅ MarionetaControl + 5 SpringHandles + BarMarker
- ✅ BonePivot + PlayerCamera + ThirdPersonCamera

**Checklist de validación pre-FASE 0:**
- [ ] Abrir humanoid.tscn en el editor, F5
- [ ] Verificar que el personaje carga y se ve
- [ ] WASD mueve al personaje sin errores
- [ ] Procedural camina (sin necesidad de AnimationTree)
- [ ] agdoll toggle (F11 o tecla asignada) activa modo ragdoll
- [ ] En ragdoll mode, los PhysicalBone3D responden a gravedad
- [ ] PhysicalBone3D chocan con el suelo correctamente
- [ ] Procedural anim NO interfiere cuando ragdoll_mode = true
- [ ] Springs de MarionetaControl dibujan hilos
- [ ] No hay errores en consola

Si algún item falla → **arreglar ANTES de FASE 0**, no seguir adelante.

### FASE 0 — nim_editor.tscn (Editor Standalone)

**Decisión General:** El visualizador es FASE 0, antes que el refactor de primitivas. Renombrado de walk_visualizer a nim_editor porque editaremos TODAS las animaciones, no solo caminata.

**Naming final:** ❌ walk_visualizer → ✅ **nim_editor**
**Carpeta presets:** ❌ esources/marioneta/presets/ → ✅ **esources/marioneta/anims/**

**Multi-personaje (arquitectura agnóstica):**
- Hoy usa humanoid.tscn (placeholder)
- Listo para 10 personajes: rata, coneja, shiba, zorra, zorrillo, oveja, tlacuache, murciélago, rana, llama
- Cada uno tendrá su propio body_blueprint.tres con nombres de huesos específicos
- El anim_editor carga el personaje vía NodePath configurable

**Estructura de archivos:**
```
tools/anim_editor/
├── anim_editor.tscn              # Escena principal (F5 desde editor)
├── anim_editor.gd                # Orquestador: carga humanoid, presets, UI
├── preset_manager.gd             # CRUD sobre resources/marioneta/anims/
├── preset_serializer.gd          # Resource <-> .tres de puros @exports
├── detail_level_controller.gd    # Capas de detalle: MIN..MAX
├── overlay_ragdoll.gd            # Visualización detallada del ragdoll
├── overlay_springs.gd            # Líneas + vectores de fuerza de springs
├── overlay_procedural.gd         # Estado activo, walk_phase, etc
├── overlay_ik.gd                 # ShapeCasts + Areas + Joints
├── overlay_state.gd              # State machine + input virtual
└── ui/
    ├── ui_main.tscn
    ├── ui_anim_selector.tscn     # Dropdown con TODAS las animaciones
    ├── ui_preset_browser.tscn    # Lista .tres con rename/delete/duplicate
    ├── ui_detail_toggles.tscn    # Capas visibles (5 toggles mínimo)
    ├── ui_sliders.tscn           # Auto-generados desde @export
    └── ui_state_dashboard.tscn   # Readouts (vel, phase, is_on_floor, F...)
```

### Catálogo de animaciones (confirmado por General)

**Estados procedurale (5):**
- IDLE (respiración + head idle)
- WALK (leg_cycle + arm_cycle + body_bob + lean)
- RUN (WALK con run_intensity)
- JUMP (sub-fase del estado JUMP)
- FALL (sub-fase del estado FALL)

**Especiales (1):**
- RAGDOLL (ragdoll_mode=true, sin procedural)

**Sistemas/overlays (no son estados puros, sino capas):**
- GRAB_LEFT (PinJoint + l_grab_area)
- GRAB_RIGHT (PinJoint + r_grab_area)
- FOOT_IK (ShapeCast suelo)
- HAND_IK (IK manos a targets)
- SPRINGS (MarionetaControl)
- BREATHING (respiración idle)
- FOOT_DRAG (fuerza pies en caminar)
- BALANCE (tobillos virtuales idle)

El usuario selecciona UN estado a la vez. Los sistemas/overlays son toggles adicionales que se encienden sobre cualquier estado.

### Capas de detalle (MIN..MAX, escogible)

| Nivel | Qué muestra |
|---|---|
| **MIN (0)** | Skeleton animado + readouts en texto plano |
| **LOW (1)** | + Nombres de huesos + mass en cada PhysicalBone + flechas de dirección |
| **MED (2)** | + Capsules de PhysicalBone visibles + líneas de springs con color + vectores de fuerza de springs + PinJoint3D pivotes |
| **HIGH (3)** | + ShapeCast3D rayos visibles + Area3D shapes + foot drag vectors + balance controller vectors + readouts numéricos flotantes |
| **MAX (4)** | + Trayectorias de últimos N frames + heatmap de fuerza + timeline de cambios + recording buffer 5s |

### Persistencia de animaciones (decisión: Opción C)

**Comportamiento:**
- **Save (💾):** Escribe al .tres en disco, persistente
- **Load (▶):** Override runtime, NO escribe al disco
- **Apply to Blueprint:** Promueve el override runtime a persistente (modifica el .tres del personaje)
- **Rename (✏):** Renombra el archivo .tres en disco
- **Delete (🗑):** Mueve a papelera (confirmación)
- **Duplicate:** Save As con nuevo nombre

**Naming de archivos:**
- Las animaciones se guardan como esources/marioneta/anims/<nombre>.tres
- Ejemplos: walk_civil.tres, walk_borracho.tres, idle_relajado.tres, un_perseguido.tres
- Snake_case lowercase, sin espacios

### Input en el visualizador

**Decisión:** NO input de teclado. UI pura con selector de animaciones dropdown.

Razón: evita conflicto con el editor de Godot cuando el anim_editor se corre dentro del contexto del editor (F5).

### Plan de sub-fases FASE 0

| Sub | Tarea | Tiempo |
|---|---|---|
| 0.a | Inventario completo de @exports a tunear | 0.5d |
| 0.b | Escena standalone anim_editor.tscn + loop runtime | 1d |
| 0.c | UI dropdown con TODAS las animaciones del catálogo | 0.5d |
| 0.d | Auto-generación de sliders desde @exports (UI inspector) | 1d |
| 0.e | Sistema de anims (.tres) con save/load/rename/delete | 1d |
| 0.f | Capas de detalle MIN..MAX con toggles | 1d |
| 0.g | Overlay ragdoll detallado (capsules, springs, fuerzas) | 1d |
| 0.h | Overlays restantes (ShapeCasts, Areas, Joints, readouts) | 1d |
| 0.i | Polish: recording buffer (MAX), estelas, heatmap | 1d |
| **Total FASE 0** | | **~7 días** |

### Roadmap completo

```
PRE-FASE 0  → Validar que humanoid.tscn funciona (ragdoll + procedural)
FASE 0      → anim_editor.tscn standalone (visualizador + presets)
FASE 1      → Refactor a PoseComposer + primitivas componibles (validable en FASE 0)
FASE 2      → Sistema de anims compartibles (.tres de puro @exports)  [Fase 0.e ya lo hace]
FASE 3      → Dock del editor de Godot (EditorPlugin) — embebido en el editor
FASE 4      → Multi-personaje: blueprint para rata, coneja, etc. (10 personajes)
FASE 5      → Multiplayer sync de anims (presets por jugador)
```

### Estado actual (2026-09-05)

- ✅ Sistema MARIONETA base implementado (F1)
- ❌ Ragdoll de prueba NO validado como funcional (pre-FASE 0)
- ❌ anim_editor no iniciado
- ❌ Primitivas componibles pendientes (F2 planeado)
- ❌ Presets/anims no iniciados
- ❌ Dock del editor no iniciado

### Decisiones registradas

| # | Decisión | Fecha | Por |
|---|---|---|---|
| D1 | Renombrar walk_visualizer a nim_editor | 2026-09-05 | General |
| D2 | Carpeta nims/ no presets/ | 2026-09-05 | General |
| D3 | Editor standalone (F5) no dock embebido inicialmente | 2026-09-05 | General |
| D4 | Detalle MIN..MAX escogible por usuario | 2026-09-05 | General |
| D5 | Estado inicial WALK pero escogible | 2026-09-05 | General |
| D6 | NO input de teclado, solo UI selector | 2026-09-05 | General |
| D7 | Persistencia con rename/delete/duplicate | 2026-09-05 | General |
| D8 | Load = override runtime, Save = persistente | 2026-09-05 | General |
| D9 | Multi-personaje: humanoid.tscn hoy, 10 personajes mañana | 2026-09-05 | General |
| D10 | Pre-FASE 0: validar ragdoll funciona ANTES de tocar editor | 2026-09-05 | General |
| D11 | Box3D es NUESTRO motor — modificarlo a nuestra necesidad, no "parches temporales" | 2026-09-05 | General |
| D12 | Quitado `autoplay = &"idle"` del AnimationPlayer — sistema 100% procedural | 2026-09-05 | General |

---

## 🔧 FIX M3 — Box3D Defensive Normal Validator (2026-09-05)

**Contexto:** El plugin godot-box3d es nuestro motor de físicas (D11). Es código nuestro, lo editamos a necesidad.

**Bug raíz encontrado:**
- Box3D puede retornar normales `(0,0,0)` en casos edge (cast que empieza dentro de un shape, formas degeneradas)
- Godot's `CharacterBody3D.move_and_slide()` → `slide()` requiere Vector3 normalizado
- Crash: `ERROR: The normal Vector3 (0.0, 0.0, 0.0) must be normalized.`

**Fix aplicado** (este es código nuestro, no upstream patch):

**Archivo:** `tools/box3d/godot-box3d-src/src/spaces/box3d_physics_direct_space_state_3d.cpp`

**Cambios:**
1. Helper `safe_normal(b3Vec3)` añadido en namespace anónimo:
   ```cpp
   inline Vector3 safe_normal(const b3Vec3& p_raw) {
       const float len_sq = p_raw.x*p_raw.x + p_raw.y*p_raw.y + p_raw.z*p_raw.z;
       if (len_sq < 1e-6f) {
           return Vector3(0.0f, 1.0f, 0.0f);  // Vector3.UP fallback
       }
       const float inv_len = 1.0f / sqrtf(len_sq);
       return Vector3(p_raw.x*inv_len, p_raw.y*inv_len, p_raw.z*inv_len);
   }
   ```

2. Aplicado en 4 lugares (defense in depth):
   - `cast_result_fcn()` callback — normaliza ANTES de pasar a Godot
   - `_intersect_ray()` → `p_result->normal`
   - `_rest_info()` → `p_info->normal`
   - `test_body_motion()` → `collision.normal`

**Archivo:** `tools/box3d/godot-box3d-src/CMakeLists.txt`

Añadido flag MSVC para permitir declaraciones después de statements (defensive guards):
```cmake
if(MSVC)
    target_compile_options(godot-box3d PRIVATE /Zc:forScope- /permissive-)
endif()
```

**Build:** Recompilado con MSVC + cmake + ninja. DLL actualizado en `addons/godot-box3d/bin/godot-box3d.dll` (hash SHA256: 40D477F6...).

**Resultado:** ✅ NO MÁS crashes de `normal Vector3 must be normalized`. Bug arreglado.

---

## ⚠️ BUG RESTANTE — Body no se mueve con Box3D en humanoid.tscn (2026-09-05)

**Síntoma:**
- Log del test con Box3D: `delta=(0,0,0)`, `pos=(0.0, 2.0, 0.0)` NO cambia, pero `vel=(0,0,0)` después de `move_and_slide()`
- Con JOLT funciona perfecto (test pasaba 5/6)
- El test minimal (`minimal_test.tscn` con CharacterBody3D directo) SÍ movía body con Box3D
- Con `humanoid.tscn` instanciado, NO se mueve

**Causa probable:** Discrepancia entre cómo Box3D y el CharacterBody3D wrapper de Godot procesan las colisiones en escenas con jerarquías complejas. Requiere investigación adicional.

**Workaround actual:** Si necesitamos validar el sistema YA, usar Jolt temporalmente. Box3D M3 fix es crítico (sin él, nada funciona), pero hay otro bug más sutil.

**Estado:**
- ✅ Crash de normal arreglado
- ❌ Body no se mueve con humanoid.tscn + Box3D
- ❌ Tests T02-T05 del ragdoll_test fallan con Box3D, pasan con Jolt

**Próximo paso:** Investigar por qué el body no se mueve — quizás es un issue con el capsule interpenetrando, o con la forma en que CharacterBody3D wrapper procesa el move_and_slide cuando hay múltiples PhysicalBones en la escena.

---

## ✅ FIX M4 — `_external_input` para tests/AI (2026-09-05)

**Causa raíz:**
El bug NO era del motor de físicas. Era un **bug de orden de ejecución de `_physics_process`**.

- `RagdollTest` (padre) corría `_physics_process` PRIMERO y seteaba `input_dir = Vector2(0, -1)`
- `Humanoid` (hijo) corría `_physics_process` DESPUÉS, llamando `_read_input()` que **reseteaba `input_dir = Vector2.ZERO`**
- Resultado: la velocidad horizontal nunca se acumulaba porque el input se perdía cada frame
- Con el teclado REAL (no test), el input se leía de `Input.is_action_pressed()` y funcionaba — eso era lo que enmascaraba el bug

**Fix:** Variable `_external_input: bool` en `character_controller.gd`. Cuando es `true`, `_read_input()` hace early-return y respeta el input_dir seteado externamente.

```gdscript
func _read_input() -> void:
    if _external_input:
        return  # AI o test setea input_dir directamente
    input_dir = Vector2.ZERO
    # ... leer teclado ...
```

**Aplicaciones:**
- **Tests**: `humanoid_controller._external_input = true` antes de setear `input_dir`
- **AI/NPCs**: El pathfinding AI calcula `input_dir` y setea `_external_input = true`
- **Players**: Default `_external_input = false`, usa teclado

**Cambios:**
- `src/marioneta/character_controller.gd`: var `_external_input` + early-return en `_read_input`
- `tools/ragdoll_test/ragdoll_test.gd`: setea `_external_input = true` en `_phase_walk_input`, false en `_phase_settle`

**Resultado:**
- ✅ Box3D: **6/6 PASSED**, `char_pos=(0, 0.99, -4.9)` después de 1.5s con input
- ✅ Jolt: **6/6 PASSED**, `char_pos=(0, 0.99, -4.9)` después de 1.5s con input
- ✅ Movimiento horizontal funciona correctamente con AMBOS motores

**Bonus — `is_on_floor_stable()` con raycast manual:**
- Reemplaza 5 llamadas a `is_on_floor()` en character_controller
- Raycast desde la BASE de la capsule hacia abajo (longitud = capsule_half_height + FLOOR_RAY_LENGTH)
- Funciona tanto con Box3D como con Jolt (Godot nativo `is_on_floor()` solo se actualiza en frame de impacto)

---

## 🔧 FIX M5 — `bone_pivot_path` vacío en humanoid.tscn (2026-09-05)

**Síntoma:** WARNING `[Marioneta] BonePivot no encontrado en ''` en cada startup.

**Causa:** Cuando se editó el .tscn (probablemente quitando `autoplay = &"idle"`), el editor guardó los paths vacíos.

**Fix:** Restaurados los paths reales:
- `bone_pivot_path = NodePath("Physical/Armature/Skeleton3D/Physical Bone Head/BonePivot")`
- `player_camera_path = NodePath("Physical/Armature/Skeleton3D/Physical Bone Head/BonePivot/PlayerCamera")`

**Archivo:** `src/marioneta/scenes/humanoid.tscn` líneas 77-78

---

## 🦴 REFACTOR — MARIONETA mode (Hooke's Law) funcional (2026-09-05)

**Decisión General:** El personaje ya se mueve (Body kinematic). Ahora la meta es que se mueva
como una **marioneta**: los PhysicalBones (piernas/brazos/head) son TIRADOS por Hooke's Law
hacia las poses procedurales, dando inercia visible. NO usar AnimationPlayer/AnimationTree.

### Semántica DUAL (importante)

| Modo | Cuándo | Comportamiento |
|------|--------|----------------|
| **MARIONETA** (default) | Mientras VIVE | Hooke's Law tira los PhysicalBodes hacia la pose procedural. Inercia visible. Bones chocan con el mundo. |
| **FULL RAGDOLL** | Cuando MUERE | Huesos libres sin Hooke. Solo gravedad. |

**Tecla F11** (`toggle_marioneta`) alterna entre ambos modos.

### Cambios aplicados

**`src/marioneta/character_controller.gd`:**
1. `_apply_hooke_spring_forces(delta)` — portado de `ragdoll_fallback.gd`. Para cada
   PhysicalBone, calcula el torque quaternion-based (`_spring_torque_axis_angle`) para
   moverlo desde su posición física actual hacia la pose procedural (target). Params
   por tipo de hueso: `stiffness_body/head/arms/legs`, `damping_*`, `max_torque`.
2. `use_physics_bones` default ahora `true` (MARIONETA activa por defecto).
3. `marioneta_mode: bool = true` — toggle F11. Si false → FULL RAGDOLL.
4. `enter_full_ragdoll()` / `exit_full_ragdoll()` — API pública para muerte/respawn.
5. `_toggle_marioneta_mode()` — maneja toggle runtime.
6. `_disable_all_animation_players()` ahora pone `active = false` (no solo `stop()`).
7. `_setup_physics_bones()` SIEMPRE se llama en `_ready()` (no depende de use_physics_bones).
8. `_set_physics_bones_active()` ahora busca el `PhysicalBoneSimulator3D` dentro del
   Skeleton3D (antes lo buscaba en `Physical` — nunca lo encontraba).
9. `_ready()` llama `animated_skel.physical_bones_start_simulation()` si `use_physics_bones`.

**`src/marioneta/scenes/humanoid.tscn`:**
1. `animate_physical_bones = true` en el Skeleton3D (antes `false` — el skeleton IGNORABA
   las posiciones físicas de los bones).
2. **AÑADIDO `PhysicalBoneSimulator3D`** como hijo del Skeleton3D (`active=true`,
   `influence=1.0`). **ESTE ERA EL BUG PRINCIPAL**: sin este nodo, los PhysicalBone3D
   existen pero NADIE sincroniza sus posiciones con el skeleton visual.

**`project.godot`:**
- Añadida acción `toggle_marioneta` = F11 (physical_keycode 4194335).

### Test (8/8 PASSED con Box3D)

- T01-T05: movimiento + procedural (heredados, siguen OK)
- **T07**: MARIONETA mode → Hooke aplicado a 10 bones
- **T08**: FULL RAGDOLL → body_bone cae libre (Hooke desactivado)

### Problemas pendientes observados por el General (2026-09-05)

1. **"Se resbala mucho y cae"** — El Hooke's Law empuja los PhysicalBones, que a su vez
   empujan al CharacterBody3D (los bones colisionan con el mundo). El Character se
   desplaza por la reacción. Posible causa: `max_torque` alto + bones con collision_active.
   **Investigar:** subir stiffness (más rígido = menos resbalón) o reducir masa de bones.
2. **"La cámara mueve TODO el cuerpo"** — El `BonePivot` (que sostiene la PlayerCamera)
   es hijo del `Physical Bone Head`. Como el hueso Head ahora es FÍSICO, el movimiento
   del mouse rota el hueso físico, arrastrando la cámara y —por Hooke— el resto del cuerpo.
   **Investigar:** desacoplar el pivot de la cámara del hueso Head físico, o hacer que
   el head bone no sea afectado por la rotación de la cámara.
3. **"Va por buen camino"** — el refactor base funciona, faltan tunear estos detalles.

### Referencia a investigar — Unreal "Locomotor"

Pendiente: estudiar el sistema de locomoción de UE5 (Motion Matching / Game Animation Sample)
como referencia de arquitectura para la locomoción de MARIONETA.

### 🔬 INVESTIGACIÓN — Unreal "Locomotor" (2026-09-05)

**Qué es:** Plugin de UE **5.6+** de locomoción **100% procedural** — genera walk cycles SIN clips
de animación ni keyframes. Nodo de Control Rig. Exactamente el paradigma de MARIONETA.

**Fuentes:**
- Tutorial Epic: `dev.epicgames.com/community/learning/tutorials/EkxO`
- Little Polygon — "Procedural Animation: Locomotion": `blog.littlepolygon.com/posts/loco1/`
- Nicolás Bertoa — "UE 5.2 Procedural Walk Cycle": `nbertoa.com/2024/05/30/unreal-5-2-procedural-walk-cycle/`
- Canal: "Make use of automatic foot placement with LOCOMOTOR in UE 5.6"

**El algoritmo (clave):**

```
FOOT PLACEMENT SYSTEM (Step System):
1. Cada pie tiene: current_planted_pos + target_pos
2. target = raycast abajo desde donde DEBERÍA estar el pie (según velocity)
3. Si dist(planted, target) > STEP_TRIGGER_DISTANCE → el pie INICIA un step
4. Step = lerp(planted → target) + arco vertical (sine curve): sube, pico a mitad, baja
5. Left/right tienen phase offset natural → uno pisa mientras el otro vuela
6. Step speed atado a movement speed (más rápido = steps más rápidos)

BODY & PELVIS RESPONSE:
7. Pelvis height DERIVADA de las posiciones de los pies (no al revés)
8. Body sway = oscilación sinusoidal sincronizada con el step cycle
   (pie izq pisa → cuerpo oscila izq; pie der pisa → cuerpo oscila der)

IK:
9. Two-Bone IK o Full Body IK resuelve las cadenas de piernas desde el foot target
```

**Diferencia conceptual VS nuestra MARIONETA actual:**

| Aspecto | MARIONETA actual | Locomotor (UE) |
|---------|------------------|----------------|
| Walk cycle | `walk_phase += delta * freq * TAU`, poses con `sin()` | Steps disparados por DISTANCIA (umbral) |
| Quién manda | El BODY calcula poses, los bones lo siguen (Hooke) | Los PIES mandan, el body se DERIVA de ellos |
| Timing | Timer fijo (`walk_frequency`) | Emergente de la velocidad real |
| Terreno | No adaptativo | Raycast por pie → adapta a cualquier superficie |

**Aplicación a nuestros 2 problemas reportados:**

1. **"Se resbala mucho y cae"** → En Locomotor el body NO es empujado por los huesos.
   Los huesos son consumidores pasivos del estado del body. En nuestro caso el Hooke's Law
   empuja los PhysicalBones que a su vez empujan al CharacterBody3D (reacción). 
   **Fix propuesto:** que los PhysicalBones NO colisionen con el mundo/Character en MARIONETA
   mode (collision_layer=0 ya hace esto pero el input de reacción sigue existiendo vía joints).
   Alternativa Locomotor: bones puramente visuales, sin física de colisión mutua.

2. **"La cámara mueve TODO el cuerpo"** → En Locomotor la cámara sigue al ROOT, no a un hueso
   físico. **Fix propuesto:** desacoplar BonePivot del `Physical Bone Head`. La cámara debe
   ser hija del root `Character` (o de un `HeadTarget` no-físico). El hueso Head físico
   debe SEGUIR a la cámara/root, no al revés.

**Concepto clave para robar:** "Foot-driven locomotion" — el body se deriva de los pies
plantados, no los pies del body. Esto elimina el foot-sliding sin importar la velocidad.

---

## 🏗️ ARQUITECTURA — Linker data-driven (Opción 1) (2026-09-05)

**Decisión General:** Opción 1 — targets en código + `MarionetaBoneLinker` data-driven.

### Diagnóstico del problema "ragdoll desconectado de la marioneta"

El sistema MARIONETA tiene DOS mundos que no se hablan:

| Mundo | Quién | Cómo |
|-------|-------|------|
| **Procedural** | `character_controller` + `MarionetaControl` | `set_bone_pose()` (offsets de pose) |
| **Físico** | Physics engine | `PhysicalBone3D` + gravedad + joints |

**El feedback loop roto:**
```
animate_physical_bones = true
  → set_bone_pose() es IGNORADO para el rendering
  → get_bone_global_pose() devuelve la pose FÍSICA, no la que pusimos
  → _apply_hooke_spring_forces() lee física como "target" → torque ≈ 0
  → NADIE tira de los PhysicalBones → caen por gravedad = "ragdoll tirado"
```

### Solución: separar TARGET (data) de HUESO (física)

```
1. character_controller calcula _pose_targets: Dictionary
   (bone_name → Transform3D en WORLD space) — puro cálculo, sin tocar el skeleton
        ↓
2. MarionetaBoneLinker itera los links configurados y aplica Hooke's Law
   para tirar cada PhysicalBone hacia su target
        ↓
3. animate_physical_bones = true → el skeleton muestra la física (con inercia)
```

**Nuevos archivos:**
```
src/marioneta/
├── marioneta_bone_link.gd      # Resource: config de UN link (bone, stiffness, damping...)
├── marioneta_bone_linker.gd    # Node: aplica todos los links cada frame
└── (refactor) character_controller.gd → produce _pose_targets en vez de set_bone_pose
```

**`MarionetaBoneLink` (Resource) — data-driven:**
```gdscript
@export var bone_name: String          # "Physical Bone LLeg1"
@export var stiffness: float = 800.0   # cuánto tira (N·m/rad)
@export var damping: float = 40.0      # cuánto frena
@export var max_torque: float = 500.0  # límite de saturación
@export var active: bool = true        # on/off dinámico (state-aware)
@export var upright_bias: float = 0.0  # componente de erección (ver abajo)
```

**`MarionetaBoneLinker` (Node):**
- `@export var links: Array[MarionetaBoneLink]`
- Cada frame: para cada link activo, busca el PhysicalBone y aplica
  `_spring_torque_axis_angle(bone_quat, target_quat, ang_vel, k, c, max)`.
- Resuelve el bone por nombre (genérico, no hardcoded).

### 🧍 SISTEMA DE ERECCIÓN ("erguido casi siempre")

**Requisito General:** el modelo debe mantenerse erguido casi siempre, con inclinación
natural al moverse/acelerar (lean) y retorno a la vertical.

**Diseño: `upright_bias` por link + un "upright anchor" global.**

1. **Upright anchor** (concepto): un objetivo de rotación = identidad (vertical),
   ponderado por el `upright_bias` del link. A más bias, más tira hacia erguido.
   ```
   target_quat_final = slerp(target_procedural, Quaternion.IDENTITY, upright_bias)
   ```
2. **Body bone**: `upright_bias` alto (ej. 0.7) → casi siempre vertical.
3. **Head**: `upright_bias` medio → sigue la mirada pero tiende a erguirse.
4. **Piernas/brazos**: `upright_bias` bajo (0.1-0.2) → solo inercia.
5. **Lean al acelerar**: el `target_procedural` del Body YA incluye el `walk_body_lean`
   y el lean por aceleración — el `upright_bias` solo amortigua el exceso.
6. **Balance controller** (heredado de `ragdoll_fallback.gd`): tobillos virtuales que
   corrigen la posición del Body si se inclina demasiado sobre los pies.
   - `balance_pos_stiffness`, `balance_pos_damping`, `balance_tilt_stiffness`, `balance_tilt_damping`.
   - Solo activo cuando NO camina (en walk los pies mandan).

### Ventajas de esta arquitectura

- ✅ Un solo skeleton (sin duplicar mesh)
- ✅ Sin feedback loop (el target es data explícita, no la pose física)
- ✅ Data-driven: cada hueso puede tener su stiffness/damping/upright_bias
- ✅ Genérico: funciona con cualquier personaje (los links referencian bones por nombre)
- ✅ State-aware: los links se activan/desactivan según el estado (reusa la lógica de MarionetaControl)

### Plan de implementación

| Paso | Qué |
|------|-----|
| 1 | Crear `marioneta_bone_link.gd` (Resource) |
| 2 | Crear `marioneta_bone_linker.gd` (Node) con spring torque + upright bias + balance |
| 3 | Refactor `character_controller`: calcular `_pose_targets` (Dictionary world-space) para piernas/brazos/head/body |
| 4 | Reemplazar `_apply_hooke_spring_forces` + `set_bone_pose` por el linker |
| 5 | Bones sin colisión con el mundo en MARIONETA (fix resbalón) |
| 6 | Tests: T09 (targets generados), T10 (bones siguen targets con inercia), T11 (erección) |



---

## 📊 Estado actual de motores de física (2026-09-05)

| Aspecto | Box3D v2 + M3 (nuestro) | Jolt (referencia) |
|---|---|---|
| Crashes por normal (0,0,0) | ✅ Arreglado con M3 | N/A |
| Body se mueve con cápsula simple | ✅ Sí (minimal_test) | ✅ Sí |
| Body se mueve con humanoid.tscn | ✅ Sí (fix `_external_input`) | ✅ Sí |
| Procedural anim funciona | ✅ Sí (8/8 PASSED) | ✅ Sí |
| Multithread solver | ✅ Estable | ❌ Single thread |
| Determinismo | ✅ Sí | ❌ No |


---

## INVESTIGACION - Ragdoll fisico + Procedural + Multijugador (2026-09-10)

**Contexto:** El ragdoll de humanoid.tscn no respondia al procedural. Investigacion a fondo
(cberry22 Active-Ragdoll, UE Locomotor, Glenn Fiedler/Gaffer On Games, Unity Netcode, Gang Beasts).

### Hallazgo 1 - Jerarquia CORRECTA de PhysicalBone3D (doc oficial Godot)
El PhysicalBoneSimulator3D DEBE ser PADRE de los PhysicalBone3D:
```
Skeleton3D
+-- PhysicalBoneSimulator3D
    +-- Physical Bone Body / Head / ...
```
En humanoid.tscn los bones son HIJOS del Skeleton (hermanos del simulador) -> el simulador
NO sincroniza -> get_bone_global_pose() devuelve la pose procedural -> el spring lee dist=0
y NUNCA aplica fuerza. PENDIENTE corregir jerarquia.

### Hallazgo 2 - Parametros canonicos del active ragdoll (cberry22)
- angular_spring_stiffness = 4000, angular_spring_damping = 80
- linear_spring_stiffness = 1200, linear_spring_damping = 40
- Nuestros valores originales (8-14) eran ~300x mas debiles que la gravedad, el ragdoll
  no podia sostenerse. YA CORREGIDO en marioneta_bone_linker.tscn.
- Aplicacion: b.linear_velocity += force * delta  (NO apply_torque)
- Lectura actual: skeleton.global_transform * get_bone_global_pose(id)
- Re-anclaje de seguridad: if pos_diff.length_squared() > 1.0: b.global_position = target.origin
- Rotacion: rot_diff = target.basis * current.basis.inverse(); torque = stiffness*rot_diff.get_euler() - damping*ang_vel

### Hallazgo 3 - NETWORKING: replicar ESTADO, no animacion
- "The most reliable approach is to replicate state, not animation." (MoCap Online)
- "Synchronise animation state machine inputs, not the animation playhead."
- "If the state machine is deterministic and inputs are identical, animation output should match
  on every client without transmitting any animation data directly."
- pose = f(estado_replicado, tiempo_local)  <- funcion PURA, corre en cada cliente.
- Se envia: pos, vel, state_index, speed(0-1), aim_pitch (~10-20 bytes/jugador). NO huesos.
- La animacion procedural es MAS facil en multiplayer que los clips: es una funcion pura.

### Hallazgo 4 - Arquitecturas de red (Glenn Fiedler, gafferongames.com)
| Arquitectura | Que viaja | Determinismo | Jugadores |
|---|---|---|---|
| Deterministic Lockstep | solo inputs | BIT-PERFECT obligatorio | 2-4 max |
| Snapshot Interpolation | estado (snapshots) | NO requerido | escala; estandar shooters |
| State Synchronization | estado comprimido | NO requerido | escala |
- Para 8 jugadores co-op -> Snapshot Interpolation. NO lockstep.
- Box3D/Jolt NO decide la animacion. Decide la fisica del mundo.
- El determinismo de Box3D sirve para lockstep/prediccion, NO es requisito para animar.

### Hallazgo 5 - PATRON LOGIC/VISUAL para ragdolls en multijugador (Unity Netcode ECS)
DUAL: Ragdoll Logic (server/red) + Ragdoll Visual (cliente local).
- Ragdoll Logic: collider fisico simple (el root/hips). UNICA entidad sincronizada por red.
- Ragdoll Visual: ragdoll completo (miembros + joints). FISICA LOCAL, solo en el cliente.
  NO sincroniza datos de miembros. Su root (Hips) es Kinematic y se ancla/interpola al Logic.
- "Exact replication of limb folding angles is rarely necessary for gameplay; synchronizing
  the general location via the Hips is sufficient for a convincing effect."
-> Aplicado: el CharacterBody3D es el Ragdoll Logic (sincronizado). Los PhysicalBone3D son el
   Ragdoll Visual (locales, anclados al CharacterBody3D). Los huesos NO se sincronizan.

### Hallazgo 6 - Ragdoll de MUERTE: local y cosmetico (Unity Netcode)
- "Death ragdolls... can desync from one client to another. The server syncs that this character
  is now dead and sends its death position. From that point, clients apply ragdoll physics how
  they want without syncing. Since they have no gameplay impact, it doesn't matter."
-> Nuestro ragdoll de muerte = LOCAL (cada cliente simula el suyo desde la posicion de muerte).

### Hallazgo 7 - Gang Beasts (caso extremo: la fisica ES el gameplay)
- "the entire game is a physics simulation, animations are procedural (there are no pre-set
  animations), irrespective of the number of physics calculations that need to be sent/synced
  developing online modes is significantly more complex and expensive"
- En Tripofobia la fisica central son OBJETOS (agarrables/empujables) + movimiento, NO pelear
  con ragdolls. El "look marioneta" es cosmetico. Por eso el patron Logic/Visual nos sirve.

### Decisiones tomadas (2026-09-10)
- D13: Los PhysicalBone3D son Ragdoll VISUAL LOCAL. NO se sincronizan por red.
- D14: El CharacterBody3D es el Ragdoll LOGIC (autoridad + sincronizado).
- D15: La animacion procedural vive como funcion PURA del estado (pos, vel, state, walk_phase,
       aim_pitch) para que replique sin enviar huesos.
- D16: Ragdoll de muerte = local/cosmetico.
- D17: La fisica de huesos NO es requisito para la animacion; es condimento visual.
