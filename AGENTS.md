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
- **`addons/godot-box3d/`** — **Physics engine ACTIVO** (Box3D v2 parchado: M2 + M3). Build custom en `addons/godot-box3d/bin/`.
- **`addons/godot-jolt/`** — Jolt Physics. Referencia / fallback (built-in Godot 4.4+).
- **`addons/roommate/`** — Constructor de niveles 3D procedural (reglas basadas en estilos, genera mesh + colisión en un clic)
- **`addons/csg_toolkit/`** — Herramientas CSG para diseño de niveles

### Shaders y Efectos Visuales
Post-proceso de horror (viñeta, estática, scan lines, glitch) en `src/shaders/` y `assets/shaders/`. El fondo interactivo del menú usa `scripts/MouseTracker.gd` con shader de paralaje. Globales de viento (`wind_intensity`, `wind_direction`) en project settings.

### Acciones de Input (project.godot)
`WASD`/flechas: moverse · `Espacio`: saltar · `Ctrl`: agacharse · `Shift`: sprint · `E`: interactuar/lanzar · `Ratón`: mirar · `Escape`: menú/soltar ratón

## Documentación Clave (en `docs/`)
- `Menu_System_Guide.md` — Arquitectura del menú, sistema de traducción, cómo agregar menús
- `Interactive_Background_System.md` — Efecto de paralaje/sacudida con MouseTracker
- `README_MOVEMENT_SYSTEM.md` — Sistema de stamina y recursos CharacterStat

---

## Física — Decisión, estado y plan (Box3D)

**Decisión final:** usar **Box3D con patches propios (Box3D v2)** como motor. Jolt = referencia.

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
Patch listo para PR: `tools/box3d/patches/M2-sub-step-count.patch`.

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

**Falta en World.tscn:** `MultiplayerSpawner`, `MultiplayerSynchronizer` en RigidBody3D,
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

**Archivo:** `tools/box3d/godot-box3d-src/src/spaces/box3d_physics_direct_space_state_3d.cpp`

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

**Archivo:** `tools/box3d/godot-box3d-src/CMakeLists.txt` — flag MSVC `/Zc:forScope- /permissive-`.

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
pos_y 1.0-1.67, angvel 4-13 rad/s, sin crashes). Build: `tools/box3d/build-and-install.bat`.
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

**PENDIENTE (teardown, no bloqueante):** al usar grab, el server spamea
`ERROR: Parameter "body_b" is null.` + 4x `Parameter "joint" is null.`
(origen: `ERR_FAIL_NULL` en `box3d_physics_server_3d.cpp` — `_joint_make_cone_twist`
llamado por `PhysicalBone3D::_reload_joint` con un RID aun no registrado; PREEXISTENTE,
no de H2). Fix sugerido: retorno silencioso en vez de `ERR_FAIL_NULL`.

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
