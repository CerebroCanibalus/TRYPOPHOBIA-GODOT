# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) cuando trabaja con el código de este repositorio.

## Descripción del Proyecto

**Trypophobia** es un juego de terror survival cooperativo multijugador (hasta 8 jugadores) construido en Godot 4.4 con renderizado Forward Plus. El loop principal consiste en navegar entornos 3D, evitar enemigos que detectan sonidos y completar objetivos de extracción. Los scripts y la documentación están principalmente en español.

## Comandos de Desarrollo

Este es un proyecto de Godot 4.4. El desarrollo se realiza a través del Editor de Godot — no hay sistema de build por CLI. Operaciones comunes:

- **Ejecutar el juego:** Abrir `project.godot` en Godot 4.4+ y presionar F5 (inicia desde `main_menu.tscn`)
- **Exportar (Windows):** Proyecto → Exportar → Windows Desktop → genera en `../Lanzamientos/infdev/Tripofobia.exe`
- **Escena de entrada:** `res://main_menu.tscn`
- **Probar una escena concreta (scripts que tocan el mar):**
  `& "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 300 "res://maps/misiones/petrolera_c1/petrolera.tscn"`
  Sin la ruta de escena como argumento sale `main_menu.tscn` y **el shader nunca se compila**: el log se ve limpio y no prueba nada.

## 🌊 EL OCÉANO DE LA PETROLERA (2026-09-28)

**Shader:** `src/shaders/ocean_stylized.gdshader` · **Controlador:** `src/shaders/ocean.gd`
(`class_name Ocean`) · **Material:** `src/shaders/materials/ocean_stylized_mat.tres`
· Cableado en `maps/misiones/petrolera_c1/petrolera.tscn` → `Mar/MarLejano` + `Mar/Ocean`.

**Base:** "Absorption based stylized water" (godotshaders.com) + "screen space refraction shader"
(ambos CC0). `src/shaders/agua1.gdshader` es el original descargado y **lo usa NADIE** — se
conserva solo como referencia. No conectarlo.

**Decisiones (por qué NO es agua1 con otros nombres):**

| # | Decisión | Motivo |
|---|---|---|
| O1 | 3 olas de **Gerstner analíticas por pixel** | agua1 desplaza con textura de ruido tiling. Gerstner da silueta real y la normal no depende de la densidad de malla. |
| O2 | **Desplazamiento con LOD por distancia** | La malla es de 1800 m. Bajo niebla 0.002 a 500 m no se ve nada; la geometría de lejos es geometría desperdiciada. |
| O3 | **SIN SSR** | El cielo del mapa es un color plano (`background_mode=1`). El SSR de agua1 son ~100 iteraciones × 2 muestras para reflejar un color liso. Sustituido por Fresnel contra el color de niebla: mismo resultado, 1/200 del coste. |
| O4 | **SIN caústicas simplex** | `os2NoiseWithDerivatives` de agua1 ≈ 120 ALU × 2 octavas. Aquí 4 senos (~12 ALU) y solo en agua somera. |
| O5 | Absorción en **metros de mundo** | agua1 usa distancia lineal de cámara → el color del agua cambia por mover la cámara sin que cambie el mar. |
| O6 | `unshaded` + `fog_disabled` + niebla **a mano** | `unshaded` evita que la luz multiplique un color ya iluminado a mano. `fog_disabled` evita la **niebla doble** (la pantalla refraccionada ya viene con niebla) y que el horizonte no case con el cielo. `ocean.gd` inyecta color/densidad de niebla y sol cada frame leyendo el `WorldEnvironment` y la `DirectionalLight3D`. |
| O7 | Normal map en **espacio de mundo** (T=X, B=Z) | Evita depender de `TANGENT`/`BITANGENT` (que en Godot 4 llegan ya rotados). Sobre un plano horizontal es exacto. |
| O8 | `PlaneMesh` subdividido **192×192** | Venía con subdivide **0** (un quad de 1800 m): el vertex displacement no tenía dónde trabajar. 192 → quad de 9.4 m para un swell de 34 m. 74k tris. |

**Presupuesto:** 2 depth + 1 screen + 2 normal + 2 espuma = **7 muestras/píxel**, un solo pase,
sin render targets extra. `cast_shadow = OFF` (una ola con la normal inclinada proyectando
sombra sobre sí misma da Shadow acne en todo el horizonte).

### GOTA — `INV_PROJECTION_MATRIX` dentro de una función NO compila

`SHADER ERROR: Unknown identifier in expression: 'INV_PROJECTION_MATRIX'`. El nombre es
**correcto**; el problema es el **ámbito**: dentro del cuerpo de una función el parser no lo
resuelve. En el cuerpo de `vertex()`/`fragment()` sí. Por eso `outline.gdshader` y `agua1.gdshader`
**nunca** lo leen dentro de una función: siempre lo pasan como argumento.

**Regla:** `world_from_depth(uv, d, inv_proj, inv_view)` y `cam_distance(p, cam_pos)` reciben las
matrices desde el cuerpo de `vertex()`/`fragment()`. No "simplificar" pasando a leerlas dentro.

Ojo: Godot **corta en el primer error**, así que las líneas siguientes nunca se evalúan. Un solo
error de shader esconde todos los demás. Iterar de a uno.

### GOTA — `global uniform` inexistente rompe el shader SIN avisar en consola

Declarar `global uniform float tide_level` sin crearlo en *Configuración del Proyecto →
Shader Globals* hace que **el shader no parsee**, y el error sale en un **popup del editor**,
no en la consola. `RenderingServer.global_shader_parameter_set()` con un nombre inexistente
tampoco avisa: empuja un `ERROR` **por frame**.

**Por eso el shader usa SÓLO los 2 globals que ya existen** (`wind_intensity`, `wind_direction`,
declarados en `project.godot [shader_globals]`). `tide_level` y los `ripple_*` son **uniforms
normales del material**, empujados por `ocean.gd`. Menos elegante, cero sección de configuración
que se pueda desincronizar. `heren.project shader_global` solo los crea **en runtime**, no los
persiste en `project.godot` — no sirve para esto.

### GOTA — `ShaderMaterial` guardado sin `shader_parameter/*` sale NEGRO

Las claves `shader_parameter/x` **no son propiedades del `Resource`**. `heren.resource update`
responde `{"applied": [...]}` y **no escribe nada en el `.tres`**. Por eso `ocean.gd` inyecta las
texturas en `_bind_material()` en cada arranque, con defaults en `DEFAULT_NORMAL_MAP` /
`DEFAULT_FOAM_NOISE`. Es la red de seguridad, no adorno.

### Texturas
- `assets/env/textures/nature/agua1_nm.png` → `normal_map` (normal map real, `compress/normal_map=1`)
- `assets/env/textures/nature/agua1.png` → `foam_noise` (celular en escala de grises: la espuma
  rompe en celdas, lee como dibujada a mano y no como ruido)

### Estado
- ✅ Compila limpio: **0 errores, 0 warnings** en la run del mapa.
- ⏳ **Sin verificar visualmente.** No se ha visto el agua renderizada ni se ha medido FPS.
  `heren` no tiene tool de captura y `heren.scene create` **no persiste la `.tscn`** (pasa a
  `save_to` la escena que ya estaba abierta → contamina el mapa; limpiar con `node remove` +
  `scene save` y verificar el conteo de nodos).
- ⏳ `tide_starts_high` / `tide_period` sin afinar. `wind_intensity` global sigue a **0.0** en
  `project.godot` hasta que `Ocean._process` lo empuje; el shader tiene guarda anti-NaN para
  `wind_direction = (0,0,0)`.

### "LA MAREA" — efecto propuesto (pendiente de decisión)

`maps/misiones/petrolera_c1` tiene props llamados **`TOR-03_Arranque_de_marea_001..011`**: el
mapa YA TIENE la marea como elemento de guion, solo que sin mecánica. La idea es Promote
ese prop a sistema:

1. **La marea es el reloj de la misión.** `tide_level` ya está implementado y sube/baja el plano
   del agua. Con marea baja se alcanzan rutas que con marea alta están cortadas. Coste: **1 uniform**.
   En co-op el nivel lo decide el servidor (`apply_network_tide()`), va en el mismo paquete que
   el resto del estado.
2. **El agua es el radar de sonido.** El anillo `ripple_center`/`ripple_time`/`ripple_strength`
   ya está en el shader: se inyecta en la MISMA solución de olas, así que no cuesta un draw call
   ni una textura. `Ocean.emit_noise(pos, fuerza)` se llama desde `SoundArea`. Los enemigos ya
   persiguen esos `SoundArea` → **no se cablea nada nuevo**, solo se pone en la superficie lo que
   el juego ya sabe. El anillo además revienta la película de aceite (iridiscencia invertida).
3. **Película de aceite (thin-film).** Paleta coseno, ~12 ALU, ya en el shader. Es la identidad
   visual: una refinería flotando sobre su propio producto.

**Lo que NO se ha conectado:** `emit_noise()` no tiene llamador. Hay que engancharlo al sistema
`src/sounds/Sound.gd` + `src/enemy/Enemy.gd`.

## Arquitectura

### Singletons Autoload
- `src/autoload/NetworkingManager.gd` — Multijugador ENet (servidor en puerto 7777, descubrimiento UDP en 7778, máximo 8 jugadores). **Único autoload** (`project.godot [autoload]`; ruta actualizada por MCP en la limpieza 2026-10-09).
- ~~`GameSettings.gd`~~ — **ya no existe**: figuraba en esta doc como autoload pero nunca estuvo en `[autoload]` ni tenía una sola referencia; borrado como código muerto (2026-10-09).

### Sistema de Jugador
Dos personajes jugables, y los controladores viejos YA NO existen:
1. **`src/player/IzaPlayer.tscn` + `iza_player.gd`** — Iza: FPS completo, stamina (recursos CharacterStat — ver `README_MOVEMENT_SYSTEM.md`), agarrar/lanzar, nado.
   ⚠️ **SU RIG `assets/players/zorrillo/iza_rig.tscn` ESTÁ DESECHADO** (2026-10-09): sus 14 `PhysicalBone3D` con `joint_type=5` (Generic6DOF) hacen que Box3D escupa `Generic6DOFJoint3D is not supported` al cargar. Reemplazar por rig nuevo con `joint_type=2`. Detalles y restricciones: sección **🛑 RIG DE IZA DESECHADO** más abajo.
2. **`src/ragdoll_character/`** — ragdoll de prueba (doble skeleton PiCode9560), FP, IK de brazos, nado; es el personaje de test de las mecánicas.

Borrados el 2026-10-09 por tener **0 referencias** (medido en escenas, scripts ni uid): `src/player/characterbody_jugador.gd`, `src/interactibles/player.gd`, `pause_screen.gd`, `src/ui/ui_barraVida.gd` y `src/import/luces_fotometricas.gd`.

### IA de Enemigos
`src/enemy/Enemy.gd` (extiende `CharacterBody3D`) usa `NavigationAgent3D` para pathfinding. Los enemigos navegan hacia objetos `SoundArea` (`src/sounds/Sound.gd`, extiende `Area3D`) — esta es la mecánica central de sigilo. Velocidad: 2 m/s.

### Organización de Escenas
- `main_menu.tscn` — Punto de entrada con efectos shader de horror y explorador de servidores (la UI está; **falta `src/menu/ServerBrowser.gd`**, nunca existió en el repo — ver Pendientes)
- `maps/lobbyv2.tscn` — Lobby actual (SM-13 + ragdoll) · `maps/lobby.tscn` — lobby antiguo (el menú aún apunta a este)
- `maps/misiones/c1/c1.tscn` — Misión 1 · `maps/misiones/isla_c2/isla_jugable.tscn` — Isla (segundo nivel) · `maps/misiones/petrolera_c1/petrolera_jugable.tscn` — wrapper jugable de la Petrolera (mapa + Iza + linterna + spawns)
- `src/water/demo/demo_agua.tscn` — demo/prueba del sistema de agua
- `tests/escenas/` — escenas de prueba sueltas (`prueba_assets`, `prueba_shader_orn01/03`)
- **NO existe `src/world/World.tscn`**: era una referencia vieja de esta doc; el "mundo" hoy son los mapas.

### Addons
- **`addons/godot-box3d/`** — **Physics engine ACTIVO** (Box3D v2 parchado: M2 + M3). Build custom en `addons/godot-box3d/bin/`.
- **`addons/godot-jolt/`** — Jolt Physics. Referencia / fallback (built-in Godot 4.4+).
- **`addons/roommate/`** — Constructor de niveles 3D procedural (reglas basadas en estilos, genera mesh + colisión en un clic)
- **`addons/csg_toolkit/`** — Herramientas CSG para diseño de niveles

### Shaders y Efectos Visuales
Post-proceso de horror (viñeta, estática, scan lines, glitch) en `src/shaders/` y `assets/shaders/`. El fondo interactivo del menú usa `src/menu/MouseTracker.gd` con shader de paralaje. Globales de viento (`wind_intensity`, `wind_direction`) en project settings.

### Acciones de Input (project.godot)
`WASD`/flechas: moverse · `Espacio`: saltar · `Ctrl`: agacharse · `Shift`: sprint · `E`: interactuar/lanzar · `Ratón`: mirar · `Escape`: menú/soltar ratón

## Documentación Clave (en `docs/`)
- `Menu_System_Guide.md` — Arquitectura del menú, sistema de traducción, cómo agregar menús
- `Interactive_Background_System.md` — Efecto de paralaje/sacudida con MouseTracker
- `README_MOVEMENT_SYSTEM.md` — Sistema de stamina y recursos CharacterStat

---

## Física — Decisión, estado y plan (Box3D)

**Decisión final:** usar **Box3D con patches propios (Box3D v2)** como motor. Jolt = referencia.

> **📂 El código de Box3D ya NO vive en este repo** (limpieza 2026-10-09). Fuente
> parcheada, `patches/`, build script y PR upstream: **https://github.com/CerebroCanibalus/godot-box3d-engine**
> (README con posicionamiento, GPL-3.0, release `v1.0.0` con DLL de Windows x64).
> Aquí solo queda el addon runtime `addons/godot-box3d/` (`.gdextension` + DLL) y el
> benchmark in-game `tests/physics_benchmark/`. Rutas viejas `tools/box3d/...` de
> esta doc = `<repo-dedicado>/...`.

| Aspecto | Box3D v1 (medido) | **Box3D v2 + M2/M3** | Jolt (medido) |
|---|---|---|---|
| Throughput peak | OK al inicio | OK al inicio | OK al inicio |
| Resistencia bajo stress | colapsa a **7.6 FPS @60s** | **107 FPS @60s** | 89.6 FPS @60s |
| Ventana 60-100s | 7.6 FPS | **72-107 FPS** | 31-89 FPS |
| p99 latencia | 130ms | **31ms** | 67ms |
| Determinismo | ✓ | ✓ | ❌ |
| Joints disponibles | 3 (pin/hinge/slider) | igual | igual |

**Fix M2 (SUB_STEP_COUNT configurable):** `SUB_STEP_COUNT` estaba hardcoded en 4 (240
sub-pasos/s a 60 Hz). Ahora es `physics/box3d/sub_step_count` (default 1). Con M2, Box3D supera
a Jolt en toda la ventana 50-100s (a 80s: 72 vs 32 FPS). Cambio trivial en C++ (~30 líneas).
Patch listo para PR: `godot-box3d-engine/patches/M2-sub-step-count.patch`.

**Fix M3 (degenerate normal guard):** ver `## FIX M3`.

**Benchmark propio:** `tests/physics_benchmark/` (3000 cuerpos, blasts, tracker CSV).

### Issues pendientes

| # | Issue | Fix propuesto |
|---|---|---|
| M1 | Workers de Box3D compiten con el render thread (`std::thread` pool propio) | inyectar `b3TaskCallback` en el job system de Godot (C++, alto) |
| M3b | Métricas de solver incompletas | exponer `b3World_GetCounters()` + `b3World_GetProfile()` |
| M4 | Contact params read-only | buscar equivalente Box3D |
| Q1 | `worker_count` auto puede fallar | forzar valor en project settings |
| **H2/H2b/H2c** | **Joints rígidos (softness ignorado)** | **ver `## PENDIENTE - Box3D vs Jolt en joints` (SIGUIENTE)** |
| H1b | Sin ConeTwist/6DOF blandos | ídem H2 |
| H2e | Sin `b3World_Explode` | wrapper para explosiones/blast masivos |
| H3 | Sin SoftBody3D | sistema de springs (muy alto) |

**Limitaciones conocidas:** Area3D no detecta trimesh/heightmap; `collide_shape()` no reporta
penetration depth; friction combina `sqrt(a*b)` (no `min`); restitution `max(a,b)`.

### Gaps para Multiplayer (8 jugadores)

Box3D expone contact points/impulses y force integration (sirve para validación anti-cheat),
pero NO snapshot/replay determinista vía plugin. La red la provee Godot 4 vía
`MultiplayerSpawner`/`MultiplayerSynchronizer` (no el motor físico).

**Falta en el escenario de red (hoy no existe World.tscn; serán los mapas/lobby):** `MultiplayerSpawner`, `MultiplayerSynchronizer` en RigidBody3D,
`OS.has_feature("dedicated_server")`, predicción cliente, interpolación remota, validación
server-side, caps de bandwidth.

**Arquitectura recomendada:** server-authoritative con listen-server (host = player 1). El server
corre todo (física+lógica); los clientes predicen su movimiento y renderizan con interpolación
(~100ms). Ticks: 20-30 Hz para horror co-op lento, 60 Hz para combate intenso.

**Ventajas exclusivas de Box3D (si se arregla el multithread):** determinismo cross-platform,
reconciliación server/client con la misma sim, snapshot/replay (útil para reportes de bugs).

---

## FIX M3 — Box3D Defensive Normal Validator (2026-09-05)

**Contexto:** el plugin godot-box3d es NUESTRO motor (D11); es código nuestro, lo editamos a
necesidad. **Bug:** Box3D puede retornar normales `(0,0,0)` en casos edge (cast que empieza
dentro de un shape, formas degeneradas). `CharacterBody3D.move_and_slide()` → `slide()` requiere
un Vector3 normalizado → crash `ERROR: The normal Vector3 (0.0, 0.0, 0.0) must be normalized.`

**Fix aplicado** (código nuestro, no upstream patch).

**Archivo:** `godot-box3d-engine/godot-box3d-src/src/spaces/box3d_physics_direct_space_state_3d.cpp`

1. Helper `safe_normal(b3Vec3)` en namespace anónimo:
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
2. Aplicado en 4 lugares: `cast_result_fcn()`, `_intersect_ray()`, `_rest_info()`, `test_body_motion()`.

**Archivo:** `godot-box3d-engine/godot-box3d-src/CMakeLists.txt` — flag MSVC `/Zc:forScope- /permissive-`.

**Build:** recompilado (cmake + MSVC + ninja). DLL en `addons/godot-box3d/bin/godot-box3d.dll`.
**Resultado:** ✅ no más crashes de normal `(0,0,0)`.

---

## Gotcha — orden de `_physics_process` padre/hijo (Fix M4)

Si el padre setea `input_dir` y el hijo lo resetea en su `_physics_process` (que corre DESPUES),
el input se pierde cada frame. Con teclado real no se nota (se relee), pero con input externo
(AI/tests) si. FIX: flag `_external_input` con early-return en `_read_input()`.

---

## Estado actual de motores de fisica

| Aspecto | Box3D v2 + M3 (nuestro) | Jolt (referencia) |
|---|---|---|
| Crashes por normal (0,0,0) | OK (fix M3) | N/A |
| Body se mueve con capsula simple | Si | Si |
| Body se mueve con humanoid.tscn | Si | Si |
| Procedural anim | Si | Si |
| Multithread solver | Estable | Single thread |
| Determinismo | Si | No |
| Ragdoll active (2026-09-10) | Articulado (fix doble-conversion + H2) | Articulado |

---

## Refs de investigacion

- **Jerarquia PhysicalBone3D:** `Skeleton3D -> PhysicalBoneSimulator3D -> PhysicalBone3D`. El
  simulador DEBE ser PADRE de los bones y `physical_bones_start_simulation()` se llama EN EL
  SIMULADOR (ver `## PIVOTE Y FIX - Active Ragdoll`).
- **cberry22 Active-Ragdoll** (spring Hooke sobre PhysicalBone3D): probado y DESCARTADO — el
  spring sobre huesos con joints es inestable (angvel 100+).
- **UE Locomotor** (foot-driven locomotion): los PIES mandan (targets por raycast al suelo,
  steps disparados por DISTANCIA) y el body se DERIVA de ellos; el body NO es empujado por los
  huesos. Referencia para el tuning del walk cycle (elimina foot-sliding sin importar la velocidad).
- **Multiplayer** (Gaffer On Games, Unity Netcode, MoCap Online): ver abajo.

### Hallazgo 4 — Arquitecturas de red (Glenn Fiedler, gafferongames.com)
| Arquitectura | Que viaja | Determinismo | Jugadores |
|---|---|---|---|
| Deterministic Lockstep | solo inputs | BIT-PERFECT obligatorio | 2-4 max |
| Snapshot Interpolation | estado (snapshots) | NO requerido | escala; estandar shooters |
| State Synchronization | estado comprimido | NO requerido | escala |

Para 8 jugadores co-op -> **Snapshot Interpolation**, NO lockstep. Box3D/Jolt NO decide la
animacion (decide la fisica del mundo). El determinismo de Box3D sirve para lockstep/prediccion,
NO es requisito para animar.

### Hallazgo 5 — PATRON LOGIC/VISUAL para ragdolls (Unity Netcode ECS)
DUAL: Ragdoll Logic (server/red) + Ragdoll Visual (cliente local).
- **Logic:** collider fisico simple (root/hips). UNICA entidad sincronizada por red.
- **Visual:** ragdoll completo (miembros + joints). FISICA LOCAL, solo en el cliente. NO
  sincroniza miembros; su root (Hips) es Kinematic y se ancla/interpola al Logic.
- "Exact replication of limb folding angles is rarely necessary for gameplay; synchronizing
  the general location via the Hips is sufficient for a convincing effect."
-> Nuestro CharacterBody3D = Logic (sincronizado); los PhysicalBone3D = Visual (locales).

### Hallazgo 6 — Ragdoll de MUERTE: local y cosmetico
El server sincroniza que el personaje murio + su posicion de muerte; desde ahi cada cliente
simula el ragdoll como quiera sin sincronizar (no tiene impacto en gameplay).

### Hallazgo 7 — Gang Beasts (caso extremo: la fisica ES el gameplay)
En Tripofobia la fisica central son OBJETOS (agarrables/empujables) + movimiento, NO pelear con
ragdolls. El "look marioneta" es cosmetico. Por eso el patron Logic/Visual nos sirve.

### Decisiones (2026-09-10)
- **D13:** Los PhysicalBone3D son Ragdoll VISUAL LOCAL. NO se sincronizan por red.
- **D14:** El CharacterBody3D es el Ragdoll LOGIC (autoridad + sincronizado).
- **D15:** La animacion vive como funcion PURA del estado (pos, vel, state, walk_phase,
  aim_pitch) para que replique sin enviar huesos.
- **D16:** Ragdoll de muerte = local/cosmetico.
- **D17:** La fisica de huesos NO es requisito para la animacion; es condimento visual.

**Que viaja por red:** pos, vel, state_index, speed(0-1), aim_pitch (~10-20 bytes/jugador).
NO huesos. `pose = f(estado_replicado, tiempo_local)` — funcion PURA en cada cliente.

---

## ESTÁNDAR DE ANIMACIONES (2026-09-10)

**`meta/docs/Estandar_Animaciones.md`** — v2, reescrito sobre MEDICIONES del GLB (la v1
inventaba 22 clips; el motor hace mucho de eso solo). Reglas duras nacidas de bugs MEDIDOS:

**BASES REALES (medidas):** 5 clips, **30 fps**, mismas 11 tracks en todas.
`Walk` 0.833 s **22 keys (la única animación real)** · `idle` **1 key (pose)** ·
`grab_lower/middle/upper` **1 key cada una (poses que se mezclan por el pitch)** =
el "lean" que existe hoy.

**Los 9 huesos SIN track en NINGÚN clip** (viven en reposo = T-pose):
`LShoulder, LArm2, LArm2.001, RShoulder, RArm2, RArm2.001, Neck, Head, Head.001`

- **R1 — Todos los huesos, en todos los clips.** Un hueso sin track queda en reposo y el
  ragdoll pelea por alcanzar una T-pose. **Bug medido:** los brazos se van a los costados por
  estos 9 tracks. **El fix es agregar 9 tracks constantes a los 5 clips — no clips nuevos.**
- **R2 — Cabeza y torso superior QUIETOS en FP.** La cámara vive en la cabeza (el clip `Grab`
  pliega el torso → "la vista se va adelante").
- R3 cero root motion · R4 el loop cierra (frame 1 == último) · R5 brazos con recorrido para
  el IK · R6 nada de `scale` · R7 30 fps.

**Principio:** si el motor lo hace solo (física del ragdoll, IK, código), **NO se anima**.
Quedan descartados: caer, aterrizar, daño, morir, agacharse, empujar, lanzar, usar,
transformar, wall-jump.

**Decisión operativa (2026-09-10):** en FP **no** se reproduce `Grab`; el agarre lo hace
**solo el IK**. Los brazos **sin click = idle** (el IK no escribe pose, `influence=0`);
**con click = se estiran** hacia el puntero, haya o no impacto. El `influence` se interpola
(`ik_influence_fade_speed`) para que soltar no dé un tirón.

---

## TOOL — body_debugger (diagnostico de rigs) (2026-09-10)

**`tools/body_debugger/`** — debugger de cuerpo completo, **agnostico al rig y multimodelo**.
Existe porque diagnosticar el ragdoll "a ojo" produjo DOS conclusiones falsas seguidas.

- Descubre **todos** los `Skeleton3D` bajo `target` (auto_find si queda null) y los compara
  **por NOMBRE de hueso**. Cero nombres hardcodeados: todo sale de `get_bone_name(i)`.
- Tabla en vivo con 5 columnas: `hueso` (con su **indice**: `2:LArm1`) · inclinacion vs
  vertical de A · la de B · **delta** (desacuerdo A/B del mismo hueso) · **rest** (el mismo
  delta en REPOSO).
- **`rest` es la columna que clasifica el bug**: `rest != 0` = los rigs tienen ejes distintos
  (el PD pelea un offset constante); `rest ~ 0` = los ejes coinciden y **la pose viva
  diverge** (el PD no llega). Marca los huesos que existen en un solo esqueleto.
- Dibuja cruz de 3 ejes por hueso + linea al padre en 3D (verde/rojo/amarillo), a traves de
  la malla (`no_depth_test`).

**Trampas que el tool ya resolvio (y que hay que recordar):**
1. `Skeleton3D.find_bone(nombre)` puede devolver un indice que NO parece el esperado: el
   indice real se lee de `get_bone_name(i)`. En este rig: `0:Body`, `2:LArm1`, `17:Neck`.
2. `Node.find_child()` en esta version de Godot toma **3** argumentos (no acepta `type`);
   `find_children()` si acepta los 4.
3. Comparar el esqueleto fisico contra el animado con IDs de fuentes distintas (uno por
   `find_bone`, otro por `PhysicalBone3D.get_bone_id()`) da numeros basura.

**HALLAZGO (primera corrida):** con `rest=0.00` en TODOS los huesos, `LArm1/LArm2/RArm1/RArm2`
dan **delta 90.00 grados** fisico-vs-animado. No es el modelo: es que el gate `active_arm_*`
saltea el PD de los brazos, se van a la deriva y al agarrar el PD los arranca 90 grados.
Eso explica el "flexiona raro" y el "se inclina al clickear".

---

## PIVOTE Y FIX — Active Ragdoll (Jolt/Box3D) (2026-09-10)

**Pivote (D18):** Abandonado el sistema procedural de marioneta (spring sobre PhysicalBone3D del
mismo skeleton). ADOPTADO el sistema de referencia PiCode9560 (Human Fall Flat style):
DOBLE SKELETON (Animated invisible = poses via AnimationTree; Physical = ragdoll visible).

### Causas raiz encontradas (bugs resueltos)

1. **Ticks de fisica:** el ragdoll es inestable/explota a 30 Hz. **OBLIGATORIO 60 Hz**
   (`project.godot: common/physics_ticks_per_second=60`). Box3D y Jolt OK a 60 Hz.
2. **`ragdoll_mode` por accidente:** la tecla R estaba mapeada a la accion `ragdoll` y toggleaba
   ragdoll_mode -> el script salta el bloque de movimiento ("se inclina pero no camina").
   FIX: `ragdoll_mode=false` forzado en _ready + accion `ragdoll` vaciada en project.godot.
3. **Ruta sin comillas:** `--path D:\Mis Juegos\...` se corta en `D:\Mis` -> "Invalid project
   path" -> ABORTA al instante ("la escena se cierra enseguida"). SIEMPRE comillas:
   `--path "D:\Mis Juegos\Tripofobia\Repositorio"`.
4. **Skeleton no sincronizaba (mesh tieso):** Godot 4.3+ exige `PhysicalBoneSimulator3D` como
   PADRE de los PhysicalBone3D y `simulator.physical_bones_start_simulation()` (el
   `Skeleton3D.physical_bones_start_simulation()` esta DEPRECADO y NO hace nada, sin warning).
   Ref: godot#100843, godot#94831. La escena de referencia es de 4.3 -> al portar a 4.7 el mesh
   quedaba en pose de reposo ("piernas tiesas / se arrastra").
   Implementado en `ragdoll_character.gd::_setup_physical_bone_simulator()` (reparent en runtime).
5. **Camara negra:** al reparentar, `physical_skel.get_children()` ya no devuelve los bones y el
   `SpringArm3D` no los excluia -> se metia dentro del personaje. FIX: busqueda recursiva en
   `ragdoll_camera.gd` + re-resolver `target_node` si es null.

### Archivos

- `src/ragdoll_character/ragdoll_character.gd` (port de character.gd + fixes)
- `src/ragdoll_character/ragdoll_camera.gd` (port de CameraPivot.gd + fixes)
- `src/ragdoll_character/scenes/ragdoll_character.tscn`
- `src/ragdoll_character/models/Character.glb` (identico al del repo, mismo SHA256)
- `tools/ragdoll_playground/` (test: suelo, pilares de referencia, HUD con dXZ, auto-walk T/Y)

### Limpieza

Borrado `src/marioneta/`, `resources/marioneta/`, `tools/ragdoll_test/`,
`tools/fix_humanoid_hierarchy.gd`, input `toggle_marioneta`. (Git c4373d0 tiene respaldo.)

### Estado actual

- ✅ **Single-player VALIDADO con Jolt (2026-09-10)** — el General confirmo que camina y el walk
  cycle se ve bien.
- ✅ Camina (dXZ ~9m/3s), erguido, estable, sin cerrarse.
- ✅ Piernas articulan (skeleton sincronizado con la fisica).
- ✅ Walk cycle FUNCIONA. El clip `Walk` del GLB traia **`loop_mode=NONE`** (se reproducia 1 vez,
  0.83s, y se congelaba). FIX: forzar `LOOP_LINEAR` en los clips con `length > 0.1` desde
  `ragdoll_character.gd::_ready`. Descubrimiento: los clips importados del GLB (glTF) NO
  hacen loop por defecto; hay que forzarlo.
- ⏳ Tuning fino del walk cycle: `SPEED=50` (~5 m/s) vs stride del clip (0.83s/ciclo) -> puede
  patinar. Ajustar SPEED o atar la velocidad del AnimationTree a la velocidad real.
- 🔴 **SIGUIENTE: parchear Box3D** (H2/H2b/H2c, ver abajo) — Jolt ya validado.
- ⏳ Multijugador, IK bones.

---

## FIX BOX3D — Ragdoll rigido = doble conversion de grados (2026-09-10)

**Sintoma (General):** en Box3D el ragdoll era muy RIGIDO; en Jolt, articulado.

**Contexto:** el ragdoll NO usa PinJoint. `PhysicalBone3D.joint_type = 2` = **ConeJoint**
(enum: None=0, Pin=1, Cone=2, Hinge=3, Slider=4, 6DOF=5). Los 10 huesos usan ConeJoint con
los defaults de `PhysicalBone3D::ConeJointData` (swing=45deg, twist=180deg, bias=0.3,
softness=0.8, relaxation=1.0) — en radianes en el server.

**Causa raiz (doble conversion):** `PhysicsServer3D` entrega SWING_SPAN/TWIST_SPAN YA en
radianes (`PhysicalBone3D::ConeJointData::_set` y `ConeTwistJoint3D` hacen `deg_to_rad()`
antes de llamar al server; `_reload_joint()` reenvia los 5 params siempre). Nuestro
`Box3DConeTwistJointImpl3D::set_param` convertia OTRA VEZ (`p_value * PI/180`) -> swing
45deg (0.785 rad) quedaba en 0.0137 rad (~0.78deg) -> **cone limit casi cero -> articulaciones
trabadas -> rigido**. Era el unico joint con el bug: `Box3DHingeJointImpl3D` ya pasaba los
limites sin convertir (correcto).

**Fix aplicado (2026-09-10):**
- `src/joints/box3d_cone_twist_joint_impl_3d.cpp::set_param` — eliminada la conversion; los
  spans se guardan tal cual (radianes).
- `box3d_cone_twist_joint_impl_3d.hpp` — default `swing_span` corregido de `Math_PI` a
  `Math_PI * 0.25` (45deg, igual que Godot) + comentarios de unidades.

**Resultado:** ✅ ragdoll ARTICULADO en Box3D (playground: camina ~13.8m en 6s, erguido
pos_y 1.0-1.67, angvel 4-13 rad/s, sin crashes). Build: `D:\Mis Juegos\Tripofobia\godot-box3d-engine\build-and-install.bat`.
`project.godot` ahora en `3d/physics_engine="Box3D Physics"`.

### FIX H2 — Limites cone/twist con softness propia (2026-09-10)

**Antes:** `BIAS`/`SOFTNESS`/`RELAXATION` de `ConeTwistJoint3D` se ignoraban
(`WARN_PRINT_ONCE`) y los limites usaban la `constraintSoftness` global del joint.

**Ahora:** `b3SphericalJoint` tiene un `limitConstraintSoftness` propio (core):
- `b3SphericalJointDef` += `limitSoftness` / `limitBias` / `limitRelaxation`
  (defaults 0.8 / 0.3 / 1.0, iguales a `PhysicalBone3D::ConeJointData` de Godot).
- `b3PrepareSphericalJoint` deriva `hertz = 12 / limitSoftness` (clamp 0.25/h) y
  `zeta = 2 * limitRelaxation`; `limitBiasScale = limitBias / 0.3` escala la correccion.
- API nueva: `b3SphericalJoint_SetLimitSoftness/SetLimitBias/SetLimitRelaxation` (+Get).
- El plugin mapea los 3 params Godot 1:1 a esa API (ya no hay `WARN_PRINT`).
- Recording actualizado (`b3RecW/R_SPHERICALJOINTDEF` + `_Static_assert` size 192).

**NO regresivo:** con los defaults el b3Softness derivado es identico al historico
(12/0.8 = 15 Hz, zeta 2.0). Validado: playground 13.7m/6s (vs 13.85 antes).

**Efecto real validado:** `softness=6.0` en runtime afloja el ragdoll (angvel hasta 26 rad/s).

**Nota:** el `softness` de Bullet tambien adelanta el umbral del twist; NO implementado
(se usa solo como stiffness) para no cambiar el rango efectivo por defecto.

## FIX BOX3D — PinJoint3D sin resorte angular (2026-09-10)

**Bug:** `Box3DPinJointImpl3D::_create_joint_id` creaba el spherical con
`enableSpring = true; hertz = bias*30; dampingRatio = damping`. Ese spring es ROTACIONAL
(un PD que lleva la rotacion relativa a identity) — pero Godot's `PinJoint3D` es
**punto-a-punto puro con rotacion LIBRE**:
`impulse = depth * bias / h * jacInv - damping * rel_vel * jacInv` (sin termino angular).
Resultado: todo par "pineado" quedaba rigido en orientacion.

**Afectaba directamente al ragdoll:** sus `Physical/GrabJointLeft/Right` SON `PinJoint3D`
(el script cablea `node_a`/`node_b` a `Physical Bone LArm2/RArm2` + el body agarrado). Con
el spring, lo agarrado quedaba soldado; en Jolt ya rotaba libre.

**Fix:**
- `enableSpring = false` (el spherical ya da el punto-a-punto).
- `BIAS`/`DAMPING` se mapean a `b3Joint_SetConstraintTuning`:
  `hertz = tau / (pi * h * (1 - tau))` (tau = fraccion del error corregida por step;
  reproduce la formula de Godot a 60 Hz) y `dampingRatio = damping`.
- `IMPULSE_CLAMP` sigue sin equivalente (warning, una vez).

**De paso (mismo code path):** `_joint_make_pin` / `_pin_joint_set_param` ya NO usan
`ERR_FAIL_NULL`. Godot cablea `node_a`/`node_b` de a uno -> un `make_pin` con un RID
invalido es ESPERADO (el autor ya lo contemplaba en `set_local_a`, faltaba en
make/set_param). Ahora retornan en silencio y el joint se materializa cuando ambos
extremos estan cableados. Elimina el spam `ERROR: Parameter "body_b"/"joint" is null`
al usar grab.

**Validado:** playground con grab forzado, 6 s -> 0 errores, 0 warnings; camina y
sostiene la caja (la velocidad cae a ~0.5 m/s al agarrarla).

---

## SISTEMA ANIM_EDITOR — Editor de Animaciones (PLAN, 2026-09-05)

**Concepto:** editor visual standalone (F5) de animaciones, inspirado en el proyecto UE5
WalkAnimSelector (ContinueBreak): UI always-on con sliders runtime, presets, randomize.
Adaptado a Godot 4: SubViewport + overlay + gizmos (no hay Control Rig nativo).
Naming: `anim_editor` (no `walk_visualizer`); presets en `resources/.../anims/`.

**Estado:** BLOQUEADO — dependía del sistema MARIONETA (borrado 2026-09-10). Reevaluar sobre
el ragdoll actual (doble skeleton PiCode9560): hoy el walk cycle es un clip, no procedural.

**Decisiones registradas:**
- D1 `anim_editor` (no `walk_visualizer`) · D2 carpeta `anims/` · D3 standalone (no dock)
- D4 detalle MIN..MAX escogible · D5 estado inicial WALK · D6 sin input de teclado (UI pura)
- D7 persistencia con rename/delete/duplicate · D8 Load=override runtime, Save=persistente
- D9 multi-personaje · D10 validar el ragdoll ANTES de tocar el editor

---

## SISTEMA FP + PUNTERO (plan) (2026-09-10)

**Objetivo:** el personaje pasa a **1a persona** (el juego sera full FP) con un
**puntero minimalista** = donde las manos del jugador actuan.

### Decisiones (General, 2026-09-10)

| # | Decision |
|---|---|
| 1 | **FP por defecto**; 3a persona SOLO debug (tecla conmutable, off en el juego) |
| 1b | El pivote de la camara va en la **frente** (fuera del craneo) + **shader de clip por distancia** (tambien limpia el hocico de las fursonas) |
| 2 | **Hibrido**: el rayo APUNTA (fija el destino de las manos), las manos van fisicamente |
| 3 | **La mano DEBE tocar**: sin contacto no hay interaccion. El rayo solo apunta |
| 4 | Shader de clip aprobado |
| 5 | Camara **estable** (rotacion 100% raton) pero el **pitch influye en el cuerpo**: mirar abajo -> inclinarse adelante; arriba -> atras |

### Arquitectura de camara elegida (B)

`CameraPivot` NO cuelga del esqueleto. **Rotacion = 100% raton** (1:1, sin
latencia ni mareo). **Posicion = frente del hueso Head**, suavizada en TIEMPO
(`1 - exp(-delta/tau)`), con el offset aplicado en el espacio de **yaw del
personaje** (`Animated/.../Skeleton3D`, que es quien marca el "adelante": el
nodo `Physical` lleva 180 grados de mas).

Por que NO colgar la camara del hueso fisico: la cabeza es un rigidbody con cone
joint (+-45/180) y su rotacion la lleva un PD hacia el master -> el raton iria
por delante y en un choque la camara giraria sola (mareo).

### Obstaculos verificados (2026-09-10)

- El mesh es **UNA sola superficie** (`ArrayMesh_d5t02`, skinned) -> no se puede
  ocultar la cabeza por material; de ahi el shader de clip.
- Material original: **`cull_mode = 2` (culling DESACTIVADO)** y **sin textura**
  (gris 0.906, roughness 0.5) -> el shader debe replicar `cull_disabled`.
- `Animated` esta `visible = false` -> un solo mesh visible (el `Physical`).
- `SpringArm3D.spring_length = 5.0` era la 3a persona.
- Pitch limitado a **+-45 grados** y `grab_dir` saturaba a los 43 -> reescalar.

### Estado de las fases (2026-09-10, fin de jornada)

1. ✅ **Camara FP** — `spring_length=0`, posicion a la frente del hueso Head, rotacion 100%
   raton, pitch ±85, toggle debug F2 (solo `OS.is_debug_build()`), shader de clip por distancia
   (`src/ragdoll_character/shaders/fp_body_clip.gdshader` + `materials/fp_body_clip.tres`).
   Valores ajustados por el General: `head_distance` ~0.2, `fp_clip_radius` 0.55.
1b. ✅ **Lean corporal por pitch** — es una ENTRADA DE CONTROL al spring PD (NO animacion por
   codigo), repartida `Body 0.75 / Head 0.25`. **NO hay hueso fisico Neck**: los 10 son
   `Body, LArm1/2, RArm1/2, LLeg1/2, RLeg1/2, Head`. `lean_max_degrees = 2`.
   **OJO:** a 2 grados el lean es **imperceptible en FP** (mueve la cabeza ~2 cm). Lo que el
   jugador SI siente al clickear es el **clip `Grab`, que pliega el torso entero** — no el lean.
2. ✅ **Puntero** — `ragdoll_pointer.gd` (`RayCast3D` desde la camara, `interact_range` 0.9,
   excluye los huesos propios por RID) + `pointer_reticle.gd` (reticle 2D, estados
   IDLE/TARGET/BLOCKED).
3. ✅ **IK de brazos FUNCIONANDO** — `TwoBoneIK3D` (`ArmIK`) bajo el esqueleto ANIMADO. Cuatro
   cosas que costaron y hay que recordar SIEMPRE:
   - **Requiere POLE NODE.** Con solo `pole_direction_vector` el solver procesa pero **NO
     escribe pose**. Y hace falta **UN POLO POR BRAZO** (`PoleTargetL`/`PoleTargetR`): con uno
     solo los dos codos caen en el mismo plano (ala de pollo).
   - **La pose modificada solo es valida en el instante de `modification_processed`.** Fuera de
     esa señal el `Skeleton3D` devuelve la del AnimationMixer. El PD del ragdoll lee de un
     **cache** (`_anim_pose_cache`) que se llena en esa señal.
   - **El alcance se MIDE del rig** (`_place_poles_and_measure`): hombro→muñeca = **1.397 m**;
     `arm_reach = 1.397 × 0.92 = 1.286`. Un valor corto NO acorta el brazo: **lo pliega entero**
     (el codo hace tope). Con 0.55 el codo desviaba 45° de la recta.
   - **CLICK vs IDLE:** sin click `influence = 0` (el IK no escribe pose → los brazos siguen la
     animacion, idle); con click `influence = 1` y **el brazo apretado se ESTIRA hacia el
     puntero HAYA O NO impacto** (el otro brazo se queda quieto: su objetivo es su propia mano).
     El `influence` se interpola (`ik_influence_fade_speed`) para que soltar no de un tiron.
   - **`set_influence()` es de `SkeletonModifier3D` y es UN valor para TODO el modificador**
     (no hay influence por cadena).
4. ⏳ **Interaccion** — mapa de CAPAS aplicado (**1 Entorno / 2 Jugador / 3 Interactuable**:
   grab areas `layer=0 mask=4`, huesos `layer=2 mask=7`, cajas `layer=4 mask=7`). Antes las
   grab areas tenian `mask=1` y **agarraban el SUELO**. FALTA: probar el agarre real de una caja
   y el sweep de `get_overlapping_bodies()` al activar (`body_entered` no dispara si el body ya
   estaba dentro).
5. ⏳ **Red** — estado replicable sin huesos (D13–D17).

### Deuda tecnica abierta (2026-09-10)

- **Brazos: decidir si los anima el clip o los lleva SIEMPRE el IK.** Si los lleva el IK, en los
  clips basta **1 key neutral** por hueso y **R1 se cumple sin animar nada**. (Recomendacion:
  IK — ya funciona y elimina el gradiente redundante.)
- **`Walk` patina**: 0.833 s/ciclo vs `SPEED=50` ≈ 5 m/s. Lo correcto es **escalar la velocidad
  del `AnimationTree`** con la velocidad real, no recortar frames. Falta **medir el stride del
  pie por ciclo** (se puede samplear `LLeg2.001` de la `Animation`).
- **Los clips no animan los brazos** (9 huesos sin track) → ver `## ESTANDAR DE ANIMACIONES`.
- **Diagnostico honesto:** dos rondas de diagnostico se fueron en **metricas propias ROTAS**
  (`find_bone("Body")` devuelve un indice que no parece; comparar el fisico contra el animado con
  IDs de fuentes distintas da numeros basura). De ahi el `body_debugger`: **medir con el tool,
  no a ojo.**

### Comandos de test (gotchas)

- Correr el playground:
  `& "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 300 "res://tools/ragdoll_playground/ragdoll_playground.tscn"`
- **`--quit-after N` cuenta FRAMES, no segundos** (a ~150 FPS, 300 ≈ 2 s). La fisica sigue a 60 Hz.
- **SIEMPRE comillas** en `--path`: sin comillas se corta en `D:\Mis` y aborta.
- Bash es **PowerShell**: sin `||`, usar `cmd.exe /c`, `Select-String`, `Select-Object`.

## 🛑 RIG DE IZA DESECHADO — error Box3D "Generic6DOFJoint3D not supported" (2026-10-09)

**Síntoma (consola, con Box3D activo):**
```
ERROR: Box3D: Generic6DOFJoint3D is not supported;
       use PinJoint3D, HingeJoint3D, or SliderJoint3D instead.
```

**Causa raíz (medida, no supuesta):** el rig actual de Iza,
`assets/players/zorrillo/iza_rig.tscn`, trae **14 `PhysicalBone3D` con
`joint_type = 5` = Generic6DOF** (líneas 80, 154, 228, 302, 378, 452, 526, 600,
675, 749, 823, 897, 971, 1045). Se identifican por sus `joint_constraints/x/y/z/*`
(límites lineal + angular **por eje**: firma inequívoca de 6DOF). Box3D implementa
Pin, Hinge, Slider y **ConeTwist/Cone (fix H2)**, pero **NO el 6DOF genérico** →
rechaza la creación del joint. Es el **único** origen del repo (medido):
`Generic6DOFJoint3D` = 0 nodos; `joint_type = 5` solo en este archivo; los ragdolls
válidos (`ragdoll_character.tscn`, `coneja_player.tscn`) usan `joint_type = 2`.
Ref: [godot-proposals#13392](https://github.com/godotengine/godot-proposals/issues/13392)
confirma que `PhysicalBone3D` usa internamente un 6DOF joint.

**Cadena de propagación:** `iza_rig.tscn` → instanciado en
`src/player/IzaPlayer.tscn` (l. 6, 52) → presente en los 3 mapas jugables
(`petrolera_jugable`, `isla_jugable`, `c1`). Por eso aparece al probar cualquier mapa.

**Por qué el error es "raro":** los `PhysicalBone3D` crean su joint **al entrar al
scene tree**, no al activar el solver. `iza_player.gd` (l. 63-65) pone
`simulator.active = false`, que desactiva la **simulación** pero **no** la
**creación** del joint → el error salta con solo cargar a Iza, sin tocar ragdoll.
*(Certeza de la causa: 100%. Del momento exacto de creación: inferido con certeza muy
alta; prueba empírica pendiente = aplicar el fix y confirmar que desaparece.)*
Impacto real hoy: solo spam en consola (Iza no hace ragdoll); bloquearía un ragdoll futuro.

**Decisión del General (2026-10-09):** ❌ **NO** se aplica el fix rápido
(`joint_type 5 → 2`). ✅ El rig **`iza_rig.tscn` se DESECHA entero** y se reemplaza
por uno completamente nuevo.

**Bugs latentes del rig viejo (a NO repetir):**
- `assets/players/skeleton_3d.gd` llama `physical_bones_start_simulation()` sobre el
  `Skeleton3D`: **deprecado desde Godot 4.3, no hace nada**. El válido es
  `PhysicalBoneSimulator3D.physical_bones_start_simulation()` (fix #4 de este doc;
  godot#100843, #94831).
- Contradicción de intención: `skeleton_3d.gd` **quiere** iniciar la simulación y
  `iza_player.gd` la **desactiva**. Definir una sola.

**⚠️ RESTRICCIÓN DURA para el rig NUEVO de Iza (Box3D):**
1. `joint_type` de cada `PhysicalBone3D` = **`2` (ConeJoint)**. **NUNCA `5`**
   (Generic6DOF, no soportado); evitar `1/3/4` salvo verificación. Es el patrón
   validado en `ragdoll_character.tscn` (Box3D + fix H2).
2. `PhysicalBoneSimulator3D` **PADRE** de los `PhysicalBone3D`, y arrancar con
   `simulator.physical_bones_start_simulation()` (el método del `Skeleton3D` está muerto).
3. Física a **60 Hz** para ragdolls estables (`physics_ticks_per_second=60`, ya OK).
4. Si el jugable no necesita ragdoll siempre, `simulator.active=false` está bien, pero
   con joints **válidos (tipo 2)** para que el ragdoll de muerte futuro (D16) funcione
   sin tocar nada.

**Estado (2026-10-09):** ⏳ rig nuevo pendiente de crear. Los assets del rig viejo
**YA están borrados del disco / working tree** (medido con `git status`:
`iza_rig.tscn`, `iza_rig.fbx`, `iza.tscn`, `Iza.gltf` y sus `.import`/png figuran como
`D`, sin commitear); **solo queda** `assets/players/skeleton_3d.gd` (a borrar al crear el
reemplazo). Iza sigue usable como personaje FPS (el error es cosmético mientras el
simulator esté inactivo).

## GOTCHA DE REPO — el .gitignore ocultaba el codigo fuente (2026-09-10)

`.gitignore` listaba **`*.gd` y `*.res`**. Git no re-aplica ignore a lo ya
versionado, asi que los 26 `.gd` viejos estaban bien, pero **todo script nuevo
se volvia invisible**. Consecuencias reales (corregidas en `0943c36`, `2fa84c9`):

- Los scripts del ragdoll y sus 5 `.res` **nunca** se habian commiteado (sus
  escenas referenciaban scripts inexistentes en una clonada).
- Faltaban `addons/heren` (el plugin MCP), `addons/hammerforge` (editor de
  niveles), `addons/ArmatureEditor`, `src/player`, `src/animation`,
  `tests/physics_benchmark` -> **175 `.gd` recuperados de una**.

Se quitaron `*.gd` y `*.res`; queda la excepcion `!src/**/materials/*.tres`
para que los materiales compartidos SI se versionen. `*.import` sigue sin
ignorarse (es la convención de Godot); **`.uid` TAMBIÉN se versionan** — el
`.gitignore` nunca tuvo regla `*.uid` y hay 253 trackeados: mover un `.gd`
exige mover su `.uid` junto (si no, los `uid://` de las escenas se rompen).

**Antes de crear cualquier archivo nuevo, verificar que git lo vea**
(`git status --short`): un `.gitignore` que ignora `*.gd` rompe el repo en
silencio.

## 💧 AGUA FÍSICA — buoyancy, ahogo y zonas secas (2026-10-08)

Encargo: *"parte del juego ocurre en instalaciones bajo el agua; ahora el agua
es solo una mesh visual — necesita buoyancy, que los personajes se puedan
ahogar y zonas bajo el agua donde no entre el agua"*. Sistema **genérico** en
`src/water/` + demo medible en `src/water/demo/`. Nada de esto existía (búsqueda
`swim|ahog|oxygen|buoy|buoyancy` → 0 aciertos).

### Arquitectura

| Archivo | Clase | Papel |
|---|---|---|
| `water_surface.gd` | `WaterSurface` (Node3D) | Réplica CPU de `solve_waves()` + marea. **Dueño del reloj**: empuja `wave_time` al shader |
| `water_volume.gd` | `WaterVolume` (Area3D) | Dónde hay agua (XZ + fondo), densidad, corriente. El TOPE lo da la superficie, no el shape |
| `air_volume.gd` | `AirVolume` (Area3D) | Zona SECA sumergida (sala, túnel, burbuja). **Manda sobre el agua** |
| `water_query.gd` | `WaterQuery` | Fachada: `volumen_en(p)` = aire → agua → nada |
| `water_shape_test.gd` | `WaterShapeTest` | Test de punto, **sección real** de la forma, AABB propio |
| `water_body.gd` | `WaterBody` (Node) | Componente universal de empuje/arrastre. Cuelga del cuerpo |
| `oxygen.gd` | `Oxygen` (Node) | Oxígeno, apnea, ahogo, señales para HUD |
| `demo/demo_agua.gd` + `.tscn` | — | Demo jugable + HUD + **prueba automática** (`AGUA_TEST=1`) |

### Decisiones (y por qué)

1. **Reloj compartido con el shader.** `ocean_stylized.gdshader` ganó un
   `uniform float wave_time = -1.0` (si es <0 usa `TIME`). `WaterSurface` lo
   empuja con `Time.get_ticks_msec()/1000`. Sin esto, la física CPU y la ola
   visible viven en relojes distintos (TIME no es legible desde GDScript y
   rueda cada 3600 s) y los cuerpos flotarían a otra altura que la cresta.
2. **Muestreo estratificado ponderado por SECCIÓN REAL.** Cada capa mide la
   sección (box/cylinder/sphere/capsule) y cada punto pesa
   `area * alto_capa / puntos`. Muestrear las esquinas del AABB da puntos
   FUERA de una cápsula: fracción inflada, equilibrio a ρ=700 resultaba
   "cabeza bajo el agua" (bug medido, corregido).
3. **Empuje solo por densidades**: `a = fraccion * (ρ_fluido/ρ_cuerpo) * g`.
   La masa se cancela → el mismo código sirve para huesos de 2 kg y cajas de
   60 kg ("distinta complexión").
4. **Aplicación por tipo**: RigidBody3D recibe `apply_force` por muestra (una
   sonda = un punto de volumen → rueda con la ola); CharacterBody3D y
   PhysicalBone3D reciben `velocity`/`linear_velocity` (no aceptan fuerzas de
   fuera de su script).
5. **Sin empuje apoyado**: si no, un cuerpo apoyado "salta" (el
   CharacterBody3D no tiene reacción normal). `is_on_floor()` para Iza;
   `WaterBody.apoyado` lo escribe el ragdoll con sus raycasts.
6. **Sin sistema de vida aún** (decisión del General): `Oxygen` llama
   `apply_damage(delta)` SOLO si el cuerpo lo entiende y emite `ahogado()`;
   enchufa el día que exista salud, sin inventarla hoy.

### Gotchas medidos (no volver a tropezar)

- `Shape3D` **no tiene `get_aabb()`** en Godot 4.7 → `var x := sh.get_aabb()`
  ni compila ("Cannot infer the type"). Por eso existe `WaterShapeTest.aabb_de()`.
- `AABB.transformed()` **tampoco existe** → se envuelven los 8 vértices.
- `CharacterBody3D` se llama **`velocity`** (`get/set_velocity`); `linear_velocity`
  es de RigidBody3D y PhysicalBone3D. El error en runtime es raro:
  "Invalid access to property 'linear_velocity' on CharacterBody3D".
- `CollisionObject3D` **no tiene `get_shape_owner_count()`** → `get_shape_owners()`.
- `RenderingServer.global_shader_parameter_get()` es **editor-only**: en runtime
  emite ERROR por frame. El viento sale de `Ocean.wind_intensity_actual()` /
  `wind_direction_actual()` (getters nuevos en `ocean.gd`).
- Compilar un GDScript sin abrir el editor:
  `Godot --headless --path <proj> --check-only -s res://ruta.gd` (imprime el
  Parse Error con línea). Sin esto, `heren.validate` solo da `reload_err=43`.
- Un worker de `scene_script` para escena **nueva** no sirve: el handler guarda
  con su variable local `root`, que sigue null aunque `ctx.set_scene_root()`
  funcione. Primero `heren.scene action=create`, despues el worker.

### Prueba automática (medida, no a ojo)

```
$env:AGUA_TEST="1"; & "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 40000 "res://src/water/demo/demo_agua.tscn"
```
**Resultado 2026-10-08: `RESULTADO: TODO OK (3 fases)` — 10/10 comprobaciones,
exit 0.** Cubre: flota con cabeza fuera · no gasta oxígeno al flotar · bucea →
gasta oxígeno → `ahogado()` · dentro de la bolsa de aire `fraccion=0`, respira
y recupera. La telemetría confirma el equilibrio teórico: se hunde a -2,5 m,
sube a 0,98 m/s y se estabiliza en `fraccion ≈ 0,70` (= 700/1000).

Captura visual: `AGUA_SHOT=1` (sin `--headless`) guarda el viewport a los 5 s
(`OS.get_environment("AGUA_SHOT_RUTA")` para cambiar la ruta).

### Integración hecha

- `IzaPlayer.tscn` y `ragdoll_character/scenes/ragdoll_character.tscn` traen
  ya los nodos **`Agua`** (WaterBody) y **`Oxigeno`** (Oxygen).
- `iza_player.gd`: nado (Espacio sube / Ctrl baja, sostenido), velocidad ×0,55
  en agua, sin sprint bajo el agua, refs `agua`/`oxigeno`.
- `ragdoll_character.gd`: `agua.fijar_cuerpo(physical_bone_body)` en `_ready`
  (los huesos se reparentan, su ruta no existe al montar), `agua.apoyado =
  is_on_floor`, nado con `NADO_EMPUJE`.
- Shader: +1 uniform `wave_time` (validate: 0 errores, 55 uniforms).

### Iteración 2 — ragdoll como personaje de prueba + Box3D + distorsión (2026-10-08)

Decisiones del General: **el ragdoll `Character` es el personaje de prueba, no
Iza**; y **el motor de física es Box3D** (`project.godot [physics]
3d/physics_engine="Box3D Physics"` — commit `65aae14` lo había puesto en
DEFAULT, ahora vuelve a Box3D).

**Por qué el ragdoll no flotaba (medido, no supuesto):**

1. **Solo flotaba 1 de 10 cuerpos.** El ragdoll son 10 `PhysicalBone3D` con
   ~21 kg repartidos (body 10, head 2, brazos 0,5×6, piernas 2+1 ×2). El
   componente muestreaba SOLO el hueso Body ⇒ 140 N de empuje contra 206 N de
   peso del total ⇒ **neto −3,15 m/s²**, que es EXACTAMENTE lo que marcaba la
   telemetría. Y encima se quedaba clavado en y=−6,98 porque el punto de caída
   era (0,3,−6) — **justo sobre el techo de la instalación** (top en −8,6 con
   las piernas colgando): el contacto lo sujetaba y `is_on_floor` seguía en
   false (los ShapeCast de los pies no lo veían).
   → Fixes: `WaterBody` ahora es **MULTI-CUERPO** (`fijar_cuerpos_extra()` y
   cada cuerpo muestrea y flota por su cuenta), y las posiciones de prueba
   pasan a x=20 (agua abierta).
2. **Punto de respiración = hueso `Head` + 0,45 m hacia arriba** (en cada
   tick, vía `WaterBody.fijar_cabeza()`). El origen del hueso Head es el
   centro de su cápsula y en flotación ese centro queda bajo el agua: marcaba
   "ahogado" con la cara fuera.
3. **La raíz del ragdoll NO sigue al ragdoll** (solo se mueven los huesos):
   por eso `altura_cuerpo()`, `velocidad_cuerpo()` y `teletransportar()`
   (raíz + `PhysicsServer3D.body_set_state` de cada hueso) viven en
   `ragdoll_character.gd`. Medir `global_position` de la raíz daba siempre
   el mismo número.

**Resultado: `RESULTADO: TODO OK (3 fases)` — 13/13 comprobaciones bajo
Box3D** (ahora incluye: la caja de madera flota en la superficie y el ancla
se hunde al lecho — eso valida `apply_force`/`apply_torque` DEL MOTOR, que es
lo único dependiente de Box3D).

**Distorsión submarina (para saber cuándo el juego te considera bajo el agua):**
- `src/shaders/underwater_distortion.gdshader` (canvas_item): dos senos por
  eje desplazan la `hint_screen_texture`, + tinte azul + viñeta; `alpha =
  fuerza` así entrar/salir es un fundido.
- `src/water/underwater_fx.gd` (`DistorsionAgua extends CanvasLayer`): cuelga
  del personaje, se auto-monta el ColorRect, y traduce el estado del
  WaterBody: `sumergido` → 0,45 (tinte), `cabeza_sumergida` → 0,7..1,0 según
  `profundidad`. Fundido exponencial estable a cualquier FPS.
- **Regla de capas: `DistorsionAgua` va en capa 1, TODO HUD en capa ≥ 10**
  (si no, el HUD se distorsiona: medido en captura).

**Gotchas nuevos de esta iteración:**
- `heren.shader action=create` **añade el `shader_type X;` él solo**: no
  repetirlo en el código o el fichero sale doble y no parsea.
- `heren.shader create` **rechaza ficheros que ya existen** → borrar antes con
  `heren.resource action=delete` (deja backup en `.heren/backup/`).
- Un `` ` `` dentro del código que envuelves en template literal de JS rompe
  la llamada ("Unterminated template").

**Capturas (para VER sin abrir el editor):**
```
AGUA_SHOT=1                -> agua_shot.png a los 5 s
AGUA_SHOT=1 AGUA_SHOT_HONDA=1   -> cámara DENTRO del agua (muestra la distorsión)
AGUA_SHOT=1 AGUA_SHOT_FLOTA=1   -> suelta al ragdoll en agua abierta (lo ve flotando)
AGUA_SHOT_RUTA=<ruta>      -> cambia la salida
```

### Iteración 3 — controles de nado: Ctrl hunde, Espacio saca del agua (2026-10-08)

Quejas del General: *"con control no me puedo hundir"* y *"con espacio al estar
en la superficie debería impulsarme hacia afuera para volver a reincorporarme
en tierra"*. Las dos eran ciertas, y las dos estaban medidas antes de tocar nada:

1. **Ctrl no hundía**: el empuje llega a 14 m/s² (rho 700) y el tirito de
   hundimiento (12 m/s²) con el arrastre encima quedaba en velocidad terminal
   de balance → solo cabeceabas. Fix: **`WaterBody.empuje_suprimido`** (var
   pública que escribe el host cada tick) — con Ctrl el empuje se ANULA, así
   que manda la gravedad y te hundes a ~5,4 m/s. Mismo flag en Iza.
2. **Espacio no sacaba del agua**: el empuje sostenido topa en ~1,5-3 m/s
   (arrastre 4/s) y con eso no clearas el agua. Fix: **impulso ÚNICO de
   `SALIDA_AGUA = 8 m/s`** con la cabeza FUERA, capturado por EVENTO en
   `_input()` (un `is_action_just_pressed` en `_physics_process` se pierde si
   el tick no cae en el frame del pulso). Dos gotchas medidas:
   - El pulso **no se borra a ciegas**: un tick con la cabeza hundida (ola a
     la baja) se lo comía. Vive hasta usarse / soltar la tecla / un tick fuera
     del agua (ahí sí era un salto normal de tierra).
   - **`impulso_vertical()` lanza TODOS los cuerpos**: aplicado solo al hueso
     Body, los otros 9 huesos (11 kg) se quedan quietos y las articulaciones
     se comen el impulso en un par de ticks (medido: vy=8 aplicado y a los
     0,5 s el cuerpo seguía en la superficie). Ahora `WaterBody` lanza el
     conjunto entero.
3. **Bug de teletransporte encontrado de paso**: `teletransportar()` calculaba
   el desplazamiento contra la RAÍZ, que no sigue al ragdoll y ya estaba en el
   destino → `d = (0,0,0)` y el personaje no se movía (la fase 6 del test
   empezaba en y=−6,47 en vez de 0,8). El ancla ahora es el **hueso Body** y
   la raíz se mueve el MISMO `d` (así el esqueleto animado conserva su
   desfase con el físico).

**Resultado: `RESULTADO: TODO OK — 17 comprobaciones, exit 0`** (fases 1..7):
flota con cabeza fuera · no gasta oxígeno flotando · caja flota / ancla se
hunde · bucea → gasta oxígeno → `ahogado()` · sala seca `fraccion=0` respira y
recupera · **vuelve a flotar tras teletransportar** · **Ctrl lo HUNDE** ·
**Espacio en superficie lo SACA del agua**.

Test de controles: input simulado con `Input.parse_input_event(InputEventKey)`
(tecla REAL — los `InputEventAction` sintéticos no llegan a `_input()` de los
nodos, medido) e `Input.action_press/crouch` para el estado mantenido.

### Iteración 4 — formalización en prefabs reutilizables (2026-10-08)

Todo el sistema ya funciona → se convirtió en **prefabs de escena** bajo
`src/water/nodos/` (arrastrables desde el FileSystem a cualquier nivel) +
guía de uso en **`src/water/README.md`**.

| Prefab | Raíz | Qué resuelve |
|---|---|---|
| `mar.tscn` | Node3D | **Océano completo de una instancia**: `Ocean` + `MarLejano` + `Superficie` + `Volumen` enlazado (`superficie = ../Superficie`) |
| `superficie_agua.tscn` | Node3D | Réplica CPU de olas + marea, dueña del reloj `wave_time` |
| `volumen_agua.tscn` | Area3D | Dónde hay agua (BoxShape 200×80×200, tapa en y=+2) |
| `volumen_aire.tscn` | Area3D | Zona seca sumergida (8×4×8 = sala del demo) |
| `cuerpo_agua.tscn` | Node | Empuje/arrastre multi-cuerpo |
| `oxigeno.tscn` | Node | Apnea + ahogo + señales |
| `distorsion_submarina.tscn` | CanvasLayer | Post-proceso "estoy bajo el agua" |

**Adopción (con verificación, no a ciegas):**
- `ragdoll_character.tscn` → `Agua`/`Oxigeno`/`DistorsionAgua` ahora son
  **instancias** de los prefabs (mismos nombres, así no se rompe ninguna ruta).
- `IzaPlayer.tscn` → idem, y de paso gana `DistorsionSubmarina` (no la tenía).
- `demo_agua.tscn` → `Mar` entero es una instancia de `mar.tscn`;
  `Instalacion/Aire` es `volumen_aire.tscn` (posición (0,−11,−6)); los tres
  flotantes usan `cuerpo_agua.tscn` con **override de `densidad_cuerpo`**.

**Verificado:** `RESULTADO: TODO OK (7 fases, 17 comprobaciones)`, exit 0 ·
10 escenas `validate: valid:true` · playground del ragdoll sin errores ·
captura visual **idéntica** a la de antes de refactorizar.

**Gotchas de la formalización:**
- Un **override de propiedad en la RAÍZ de una instancia sí se guarda**
  (`densidad_cuerpo`, `position`, `superficie`); los HIJOS de una instancia no
  se pueden tocar desde el worker de heren (rechaza `own()` dentro de
  instancias a propósito) → para personalizar formas hay que usar *editable
  children* desde el editor. Por eso los defaults de los prefabs ya valen para
  el demo (8×4×8 = la sala, 200×80×200 = el mar).
- El código NO debe buscar estos nodos por nombre: siempre
  `WaterBody.buscar_en()` / `Oxygen.buscar_en()` (clase), así los prefabs se
  pueden renombrar al instanciar.
- Orden de hijos en `mar.tscn`: **`Ocean` antes que `Superficie`** — ella lee
  los shader globals (viento) que él empuja en el mismo tick.

### Pendiente

- **Cablear los prefabs en los mapas reales**: `maps/lobbyv2.tscn` (SM-13 +
  ragdoll) y la petrolera **siguen sin `mar.tscn` ni `volumen_aire.tscn`** —
  ahí no hay agua física. Con la formalización hecho, es arrastrar
  `src/water/nodos/mar.tscn` a la escena y colocar `volumen_aire.tscn` dentro
  del sumergible (aire del interior).
- Clip FP del rig de Iza (`fp_body_clip` solo está en el ragdoll) — ya no
  importa mientras Iza no sea el personaje.
- Red: volumen/superficie/oxígeno deben volverse server-authoritative.

---

## 🧹 LIMPIEZA Y REORGANIZACIÓN DEL REPO (2026-10-09)

Encargo: *"el repositorio es un desastre — ayúdame a organizarlo y propón basura
para borrar"* + *"sacar todo el código de Box3D a un repo dedicado"*. Todo medido
antes de borrar (**0 referencias = escenas + scripts + uid + `load()` + git history**),
commit por fase, tests entre fases. Resultado: 674 MB/16.309 ficheros →
estructura limpia, 5 commits de orden y 2 repos con escaneo de secretos activo.

### Qué se borró (`505b8da`, `2c274c4`)

| Basura de raíz (trackeada) | Código muerto (0 refs) | One-shots |
|---|---|---|
| `.DS_Store` · `battery.mtl` · `character_body_3d.gd` · `new_gd_script.gd` · `cyclops_settings.config` (0 B) · `test_capture.png` · `world.gltf`+`world0.bin` · 4 `.tmp` | Los 2 controladores viejos (`characterbody_jugador`, `interactibles/player`) · `GameSettings` (autoload fantasma: nunca estuvo en `[autoload]`) · `pause_screen` · `ui_barraVida` · `luces_fotometricas` (`src/import/` entero) · `c1_geo.tscn` · `src/ui/main_menu.tscn` (escena huérfana) · `src/shaders/agua1.gdshader` (**las texturas `agua1.png`/`agua1_nm.png` SÍ las usa el océano**) | 31 scripts `coneja`/fbx de `tools/` · `_bmad/` · `escenarios/` (vacía) |

**NO se tocó (parece muerto pero es feature SIN CABLEAR):** `Enemy.tscn`,
`DistractionSound.tscn`, `MetalImpactSound.tscn`, `post_process.tscn`,
`path_3d_rope.tscn` — 0 refs porque ningún mapa los instancia. Tampoco
`petrolera_jugable.tscn` (wrapper jugable del 6/10) ni `MiningFacility.map`
(hammerforge **sí** lee `.map`).

### Estructura nueva

- `scripts/` desapareció → `src/autoload/NetworkingManager.gd` + `src/menu/{MouseTracker,BackgroundManager,MenuAudioManager,MenuLanguageSystem}.gd` (`.uid` movidos junto, así los `uid://` sobreviven).
- `maps/prueba_*.tscn` → `tests/escenas/` · sueltos de `tools/` → `tools/diagnostico/`.
- `.gitignore`: fuera la regla obsoleta `AGENTS.md` (**SI se versiona**), dentro `.heren/` `.opencode/` `.hammerforge/` `*.orig`. Des-trackeados **55 ficheros** de caché/estado (`.godot/*`, autosaves de hammerforge, jsons de heren, memoria de opencode).
- Doc corregida: `World.tscn` no existe, `GameSettings` nunca fue autoload, los 2 controladores ya no existen, y los `.uid` **sí** se versionan (253 trackeados).

### 📂 Box3D → repo dedicado (decisión del General)

**Todo el código de Box3D fuera de Tripofobia** → **https://github.com/CerebroCanibalus/godot-box3d-engine** (público · GPL-3.0 · README con el posicionamiento *"no es un plugin simplón: instrumentaliza el motor entero"* · CONTRIBUTING/SECURITY/CoC (Contributor Covenant 2.1) · issue forms YAML + `config.yml` · secret scanning + push protection · tag anotado **`v1.0.0`** + release con la DLL de Windows x64).

- **Se movió:** `godot-box3d-src/` (172 trackeados), `patches/` (M2, M3), `PR_UPSTREAM/`, `build-and-install.bat` (ruta del addon actualizada → `..\Repositorio\addons\godot-box3d\bin`) y el `build/` de 416 MB (así **no hay que recompilar**).
- **Se queda aquí:** `addons/godot-box3d/` (runtime: `.gdextension` + DLL) y `tests/physics_benchmark/` (benchmark in-game).
- Ambos repos con **secret scanning + push protection activados** (estaban apagados).

### Bugs encontrados de paso

- **El menú cargaba un script que nunca existió:** `ServerBrowser.gd` no está en ningún commit de la historia → `load()` lanzaba SCRIPT ERROR en `setup_modules` y mataba el módulo. Guard con `FileAccess.file_exists` (`main_menu.gd`, commit `e56563c`) + warning explícito.
- **`isla_jugable.tscn` venía re-guardada de sesiones anteriores:** perdió sus `;` comentarios (recuperables con `git show 3027724:maps/misiones/isla_c2/isla_jugable.tscn`), ganó uids y **quitó la linterna inline**. Commit separado `0737723` por si hay que revertir.

### Gotchas nuevos (medidos)

- **`project.godot` por MCP = worker de heren con `ProjectSettings.set_setting` + `ProjectSettings.save()`** — heren NO tiene acción de escritura de settings (solo `autoload` de LECTURA y `shader_global`). El save deja exactamente 1 línea cambiada; verificar con `git diff`.
- **`heren.filesystem` solo implementa `action:"exists"`** — no lee ni escribe. Enumerar las tools disponibles con `Object.keys(tools.heren)` (animation, debug, filesystem, health, node, node_props, node_query, project, resource, scene, scene_script, shader, signal, ui, validate, visual).
- **El test del agua puede fallar 1 vez tras cambios grandes de disco** (ancla en `y=-9.92` en vez de hundirse): es **flaky de timing** — re-ejecutar antes de concluir regresión. Reintento → `TODO OK (7 fases, 17 comprobaciones)`.
- **Los `;` de un `.tscn` mueren en cada guardado** del editor/heren: la documentación de una escena no puede vivir solo dentro del `.tscn`.
- **Borrar `.godot/` obliga a re-importar ANTES de testear:** sin `global_script_class_cache.cfg` y sin `.imported/*.ctex`, los `class_name` (`WaterBody`, `Oxygen`, `RagdollRigConfig`…) no resuelven y sale una **cascada de Parse Errors** (45 en el playground) que NO es regression real. Fix: `Godot --headless --path <proj> --editor --quit-after 12000` (escanea + reimporta) y re-ejecutar. Medido el 2026-10-09.

### Pendientes que dejó la limpieza

- [ ] **`src/menu/ServerBrowser.gd`**: crear el módulo del explorador (la UI ya está en `main_menu.tscn`; conecta contra `NetworkingManager`, descubrimiento UDP 7778). El guard avisa en cada arranque del menú.
- [ ] Audio del menú que falta: `audio/sfx/ui/dark_ambient.ogg` y `heavy_breath.ogg` (los pide `MenuAudioManager.gd`) + animación `horror_idle` inexistente en el AnimationPlayer del menú.
- [ ] `rigid_body_3d.tscn` apunta a `res://scripts/projectile.gd` (ruta inexistente de siempre): el nodo corre **sin script**; decidir si se re-apunta a `src/interactibles/projectile.gd`.
- [ ] ¿La linterna de la Isla era descartable? Revisar el diff de `0737723`.
- [ ] Compactar AGENTS.md (pasa de 10k tokens — pedir permiso).

---

## 🎵 AUDIO AMBIENTAL POR ZONAS — `AmbienteAudio` (2026-10-09)

Encargo: *"sistema de audio ambiental configurable por mapa, encapsulado en un solo
nodo, muy modular — por zona soundscapes enteros, variación, fade in/out entre tracks;
y que se puedan poner varios nodos en la misma escena (ej. tormenta sobre el ambiente)"*.

### Decisiones del General

| # | Decisión |
|---|---|
| A1 | Zonas por **math puro** (sin `Area3D`) **con visualización en el editor** (gizmos propios) |
| A2 | Ducking **manual** vía API (`atenuar(db, s)`), sin sidechain ni compresor |
| A3 | Audio **solo `.ogg`**, usar los que ya hay en el repo |
| A4 | Primer mapa: **submarino** = `maps/misiones/lobby/lobbyV2.tscn` (SM-13) + `audio/music/ambience/submarino/oxido.ogg` |

### Contexto medido (2026-10-09)

Cero audio en mapas: 0 buses (solo `Master`), 0 nodos de audio en `maps/**`, 0
soundscapes. 3 `.ogg` existen (`oxido`, `la edad dorada`, `el mar rojo`) con **0
referencias**; `rugosis.flp` y `negro-corazon.flp` sin exportar. `MenuAudioManager`
pide 2 `.ogg` inexistentes. El patrón zona-`Area3D` más cercano es el del agua (sin cablear).

### Arquitectura — `src/audio/`

Prefab `ambiente_audio.tscn` (Node3D + script; los hijos se generan en runtime, la
escena es solo raíz):

| Archivo | Clase | Papel |
|---|---|---|
| `ambiente_audio.gd` | `AmbienteAudio` | Motor: buses, pool de players, mezcla por zonas, gizmos, overlay F3 |
| `sound_capa.gd` | `SoundCapa` | 1 capa: pool de `.ogg` + pitch/vol aleatorio + fades |
| `sound_scape.gd` | `SoundScape` | Paisaje completo = `Array[SoundCapa]` |
| `sound_zona.gd` | `SoundZona` | Forma (esfera/caja) + `Curve` + caída → peso 0..1 |
| `demo/demo_audio.gd` | — | Test headless automático (PASS/FAIL por fase) |

**Modelo de mezcla (sin zona "dominante"):** TODAS las zonas aportan peso
simultáneamente. Peso = distancia fuera de la forma → muestrea la `Curve` a lo largo
de `caida` (0 = dentro, 1 = final de caída). Cada `SoundScape` activo es un *handle*
con sus capas moviéndose a `objetivo = base × peso × duck × volumen_instancia` con
fade exponencial `1 - exp(-delta/tau)`, `tau = fade/3` (estable a cualquier FPS).
Crossfade entre soundscapes = dos handles vivos con pesos opuestos. **Multi-instancia:**
mismo `grupo` comparte bus agrupador; grupos distintos se **apilan aditivamente** (la
tormenta nunca corta el ambiente del mapa).

**Buses (runtime, `@tool` NO toca AudioServer):** `Master ← <grupo> ← <nombre-nodo>`,
creados en `_ready`, destruidos en `_exit_tree` con refcount `static var` por grupo.

**Gizmos:** hijo `GizmosZonas` con `ImmediateMesh` (círculos/cubo de aristas, 2 tonos:
forma + caída), regenerados con throttle 0.25 s comparando firma de las zonas.
**Sin `owner`** → nunca se guardan dentro del `.tscn`.

### Fases

| Fase | Contenido | Estado |
|---|---|---|
| A+B | buses + recursos + motor (capas, fades, zonas math, curvas) + gizmos + overlay F3 + demo headless | ✅ **30/30 comprobaciones** (2026-10-09) |
| C | one-shots con peso/cooldown, rotación de tracks, semilla por partida | ☐ |
| D | reverb/lowpass por estado de zona, snapshot al pausar, ducking desde gameplay | ☐ |
| E | ~~submarino~~ ✅ · isla → petrolera (falta exportar `negro-corazon.flp`) | ⏳ |

**Fase E — submarino CABLEADO (2026-10-09):** `lobbyV2.tscn` → hijo
`AmbienteSubmarino` (prefab instanciada en (19.8, −1.5, 0), zona CAJA
27×9.5×7 m + caída 6 m ajustada al AABB real del SM-13 medido con worker)
+ recurso compartible `src/audio/soundscapes/submarino.tres` (capa
`oxido.ogg`, −6 dB, fades 2/3 s). Smoke: 0 errores, exit 0.

### Gotchas medidas (NO volver a tropezar)

- **`heren.validate` → `reload_err=22` es FALSO POSITIVO, no parse error.**
  22 = `ERR_ALREADY_IN_USE` (`ERR_PARSE_ERROR` = **43**). Le pasa a
  **cualquier `@tool` + `class_name` con instancia viva en una escena
  abierta** — confirmado con bisect (mismo script OK → 22 al adjuntarlo a
  escena abierta) y con `atmosfera.gd` (preexistente, idéntico 22).
  La verdad la da la CLI: `Godot --headless --path <proj> --check-only -s
  res://ruta.gd` (exit 0 = limpia) y el test de runtime.
- **Leak de 4 objetos OGG al salir en HEADLESS es del ENGINE, no del
  sistema:** cualquier `AudioStreamPlayer` con `.ogg` reproduciéndose al
  hacer quit en headless (driver de audio dummy) reporta `Leaked instance:
  AudioStreamOggVorbis/OggPacketSequence/...`. Medido con player estándar
  de Godot puro (cero código nuestro) → 4 leaks; **con render real →
  0**. No arreglar: es ruido del test.
- **`ogg.loop = true` en runtime ya NO se usa** (aunque el leak no era por
  eso): el loop es manual `finished → play()` en
  `AmbienteAudio._replay_si_termino()` — más un guard de `stream != null`.
- **`Array[X]` no acepta un literal `[a]` sin tipar**: `nodo.set("zonas",
  [zona])` falla **en silencio** (queda `[]`). Hay que declarar
  `var zonas_t: Array[SoundZona] = [zona]` y asignar eso. El `get_prop`
  devolvió `value: []` — siempre verificar tras guardar.
- **`ctx.instance_scene()` de heren falla en silencio** (`ran=true`, logs
  vacíos, nada añadido). Usar `load(...).instantiate()` + `owner` a mano.
- **Workers inline de `scene_script` fallan con `reload_err=43`** si la
  lógica es larga: escribirlos a `.heren/tmp/*.gd` y pasar `script_path`
  (siempre con `--check-only` antes).
- **`ScriptServer` NO existe en GDScript** (`Identifier not declared`);
  no sirve para consultar clases globales.
- **Un worker que llama `AudioServer.add_bus()` corre en el PROCESO DEL
  EDITOR** y puede persistir el bus en `default_bus_layout.tres`
  (contaminó el repo con `BusExp2`; borrado). Nunca crear buses desde un
  worker — eso es trabajo del juego en runtime.
- `play()` dentro de `_initialize()` de un `SceneTree` script falla
  (`Playback can only happen when a node is inside the scene tree`):
  crear nodos en el primer frame, no en `_initialize`.

## 🌤️ ATMOSFERA — cielo, soles, nubes y rayos (2026-09-28)

Sistema canonico de clima, **preconfigurado por nivel** (sin ciclo dia/noche ni
transiciones). Todo el cielo y toda la niebla de un mapa viven DENTRO de un nodo:

`src/weather/atmosfera.tscn` → `Atmosfera` (`atmosfera.gd`, `@tool`)
├── `WorldEnvironment`  ← HIJO: este nodo es el DUEÑO UNICO del cielo
└── `Precipitacion`     ← GPUParticles3D, emisor que sigue a la camara

**NO dejar el `WorldEnvironment` del mapa**: Godot se queda con el PRIMERO
REGISTRADO (`world_environment.cpp` → `get_first_node_in_group`) — quien manda
depende del orden del arbol, silenciosamente. `_avisar_competicion()` lo detecta
y avisa una sola vez (NO lo borra: quitarle la Environment a un mapa es destructivo).

- Preset: `AtmosferaPreset` → `resources/clima/petrolera.tres`
- Cielo: `src/shaders/sky_alien.gdshader` (dos soles + KH)
- La `DirectionalLight3D` la pone el MAPA (`Sol` en la raiz). El script solo la
  LEE (`basis.z`) para pintar el disco del sol primario → disco y sombras casan
  sin sincronizar dos cosas a mano.
- `maps/misiones/c1/c1.tscn` tiene su cielo viejo embebido, pero **se va a
  eliminar** → no migrar.

### GOTA — `PROPERTY_USAGE_SCRIPT_VARIABLE` da 0 aciertos en Godot 4.7

Enumerar las propiedades de un `Resource` con script filtrando por
`int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE` (4096) **no funciona**: las
exportadas vienen con `STORAGE|EDITOR` (6) y ese bit no aparece por ningun sitio.
Usar `PROPERTY_USAGE_STORAGE` (2) + denylist (`script`, `resource_*`).

**Bug medido:** la firma de refresco salia con solo la direccion de la luz
(34 chars en vez de 2467) → tocar el preset **no refrescaba nada** y habia que
correr el juego para verlo. Ante una firma VACIA se re-aplica igual: mejor gastar
que dejar el cielo muerto.

### GOTA — `sun_a_direccion` NO existe: es `sun_a_direction`

El script escribia `sun_a_direccion`; el shader declara `sun_a_direction` (ingles).
El guard `_tiene()` lo descartaba **sin avisar** → disco del sol primario clavado
en el default `(0,1,0)`, a plomo, mientras la luz venia de `Sol`.
`get_shader_parameter()` de una clave inexistente devuelve `null`, **no** error.

### Refresco en vivo del EDITOR

`_aplicar()` solo se llamaba en `_ready` (una vez al abrir) y en el setter de
`preset` (solo si se REASIGNABA el recurso). Ahora `_process` en editor, cada
`REFREJO_EDITOR = 0.1 s`, compara una firma (73 props del preset + props del
nodo + direccion de la luz) y re-aplica SOLO si ha cambiado. En editor **no se
sigue la camara** — moveria el emisor cada frame y dejaria la escena sin guardar.

### Nubes — UN SOLO sistema Kelvin-Helmholtz

Antes convivian KH + nubes de referencia en el MISMO shader, con tres familias de
nombres (`clouds_*`, `kh_*`, `nubes_*`). `clouds_weight = 0` solo las OSCURECIA,
no las apagaba, y `_clouds_amount *= 1 - _kh_amount` las dejaba enteras donde la
KH no cubria (sobre todo cerca del horizonte) → **dos estilos en un cielo**.

Ahora: **15 uniforms `nubes_*` en espanol**, iguales en shader, preset y script.
Borrados `clouds_*` y `kh_*`. `petrolera.tres` traia `nubes_direccion = -0.255`
(rango viejo de la referencia) y `nubes_velocidad = 0` (congelaba la capa KH):
reseteados a `0.13` / `2.0`.

**Pendiente:** `petrolera.tres` tiene `precipitacion = 0` (NINGUNA) — el
anti-culling esta, pero no hay nada que se vea hasta que se active.

---

## 🦠 INFECCIÓN NIEBLA ROJA — plan (2026-10-09)

Plan completo (Fase 0, sin implementar): **`meta/docs/Infeccion_Niebla_Roja.md`**.
Resumen: plasta blanquecina/roja con agujeros Voronoi y grumos = shader sobre
**parches procedurales por raycast** (`src/infeccion/`, patrón `src/water/`).
Decisiones del General: **D-I1** visual reactiva SIN spread (cero red) ·
**D-I2** `Atmosfera` es DUEÑA de los globals de viento (**HECHO 2026-10-09**:
la racha/rumbo se movieron de `ocean.gd`; Ocean LEE si hay Atmosfera y si no,
fallback — 5 tests CLI verdes: 2 `--check-only` + `AGUA_TEST` 17/17 + smoke
petrolera + `tests/viento/test_viento.tscn` 5/5) · **D-I3** solo entorno estático.
Cero modelos 3D externos; LAS 4 texturas con placeholders (§7 del plan:
`agua1.png` / `agua1_nm.png` / GradientTexture2D — cero ficheros nuevos) +
4 .ogg. **`Decal` de Godot 4.7 NO acepta shader custom** (docs leídas): solo
relleno estático, nunca núcleo del efecto. **Descubierto en la Fase 1:**
`petrolera.tscn` NO tiene controlador `Ocean` (solo `MarLejano`) — su mar
recibe viento de `Atmosfera` desde esta fase; hook de marea sin cablear
(preexistente). `tests/viento/` está SIN COMMITEAR.

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
