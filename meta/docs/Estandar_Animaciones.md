# Estándar de Animaciones — Tripofobia

**Autor:** Lord Gatito · **Estado:** Borrador v1 (2026-09-10) · **Rama:** main

Este documento define **qué animaciones debe tener el jugador, con cuántos frames y con
qué características**, condicionado por nuestras mecánicas (FPS + ragdoll activo +
multijugador). Cada regla "dura" nace de un **bug real medido**, no de una preferencia.

---

## 1. Restricciones que mandan (arquitectura)

Antes de la lista de clips, hay tres cosas del motor que **condicionan todo**:

| Sistema | Qué hace | Consecuencia para animar |
|---|---|---|
| **Cámara FP** | Vive **dentro de la cabeza** (`CameraPivot` sobre `Physical Bone Head`) | Cualquier movimiento de **cabeza o torso** en un clip **sacude la pantalla** |
| **Ragdoll activo** | Un esqueleto **ANIMADO invisible** es el máster; los `PhysicalBone3D` copian su pose con un spring PD | El máster **debe posar TODOS los huesos** en TODO momento; un track que falta deja el hueso en reposo y el físico **pelea contra él** |
| **IK de brazos** | `TwoBoneIK3D` recoloca los brazos por encima de la pose | Los brazos del clip deben quedar en pose **neutral** (ni extendida ni bloqueada) |
| **Red** | Se replica **estado** (pos, vel, state, speed, aim_pitch), **no huesos** | La animación es **función pura del estado** → no puede depender de datos locales |

---

## 2. REGLAS DURAS (no negociables)

### R1 — Todos los huesos, en todos los clips
Cada clip debe tener track de **los 20 huesos** del esqueleto, aunque sea con un valor
constante. Un hueso sin track se queda en **reposo (T-pose)**.

> **Bug real (2026-09-10, medido con `tools/body_debugger`):** con el jugador en Idle, el
> hueso animado `LArm1` marca **89.9° respecto a la vertical (= horizontal, T-pose)**,
> idéntico a los 0 s y a los 2 s. Es decir: **los clips Idle/Walk no animan los brazos**.
> El ragdoll peleaba por alcanzar una T-pose y **los brazos se iban a los costados**.

### R2 — Cabeza y torso superior QUIETOS en los clips de FP
En primera persona, **no** se anima traslación/rotación de `Neck`, `Head` ni `Head.001`,
y el torso (`Body`) se mueve **como máximo unos pocos grados** (respiración, peso).

> **Bug real:** el clip `Grab` pliega todo el torso hacia adelante. Como la cámara está
> sobre la cabeza, al agarrar **la vista se va hacia adelante** y resulta mareador. Ese
> síntoma se atribuyó al lean procedural durante dos rondas de diagnóstico erróneo.

### R3 — Cero root motion
El desplazamiento lo lleva el `CharacterBody3D` (código). El clip **no** traslada la raíz.
Un clip con root motion pelea contra la física y rompe la predicción en red.

### R4 — Loops: el frame 1 debe ser igual al último
Todo clip en bucle cierra el ciclo. **Además**, el `Animation` importado de glTF viene con
`loop_mode = NONE`: en Godot hay que forzar `LOOP_LINEAR` en código (`ragdoll_character.gd`
ya lo hace para clips con `length > 0.1`).

### R5 — Brazos con recorrido para el IK
La pose de brazos del clip debe dejar **recorrido**: no extendida al máximo (el IK no puede
estirar más) ni pegada al cuerpo (queda sin espacio). Pose neutral ≈ **codo a ~100°**.

### R6 — Nada de animar `scale`
Solo traslación y rotación de huesos. La escala rompe el ragdoll.

### R7 — 30 fps en el fuente
Todos los clips a **30 fps** en Blender. Godot interpola; no hace falta 60.

---

## 3. Catálogo de clips

**Frames a 30 fps.** `once` = se reproduce una vez y se queda/blendea; `loop` = cíclico.

### 3.1 Locomoción (MVP: imprescindibles)

| Clip | Tipo | Frames | Dur. | Loop | Notas |
|---|---|---|---|---|---|
| `idle` | loop | 120 | 4.0 s | ✔ | Respiración + micro-movimiento. **Torso casi quieto (R2)** |
| `walk` | loop | 36 | 1.2 s | ✔ | 2 pasos/ciclo. Sin root motion |
| `sprint` | loop | 30 | 1.0 s | ✔ | Inclinación leve permitida (≤ 8°) |
| `crouch_idle` | loop | 90 | 3.0 s | ✔ | Torso bajo, pero **R2 sigue aplicando** |
| `crouch_walk` | loop | 48 | 1.6 s | ✔ | 2 pasos/ciclo |

### 3.2 Salto y aire

| Clip | Tipo | Frames | Dur. | Loop | Notas |
|---|---|---|---|---|---|
| `jump_launch` | once | 10 | 0.33 s | — | Compresión antes de despegar |
| `jump_air` | loop | 30 | 1.0 s | ✔ | Pose de caída sostenida |
| `land` | once | 15 | 0.5 s | — | Absorción del impacto |
| `walljump` | once | 12 | 0.4 s | — | Empuje desde pared |

### 3.3 Interacción (manos)

| Clip | Tipo | Frames | Dur. | Loop | Notas |
|---|---|---|---|---|---|
| `grab_reach_R` | once | 12 | 0.4 s | — | **Solo brazo derecho.** Torso quieto (R2) |
| `grab_hold_R` | loop | 60 | 2.0 s | ✔ | Sostener. El IK manda la mano |
| `throw_R` | once | 15 | 0.5 s | — | Solo brazo |
| `push` | once | 18 | 0.6 s | — | Ambas manos |
| `use` | once | 20 | 0.67 s | — | Accionar palanca/botón |

> **`grab_*_L`**: hoy el sistema es **simétrico por acción** (`grab_left` / `grab_right`);
> los clips de la mano izquierda son espejo. Se pueden generar espejando en Blender.

### 3.4 Daño y muerte

| Clip | Tipo | Frames | Dur. | Loop | Notas |
|---|---|---|---|---|---|
| `hit_front` | once | 15 | 0.5 s | — | Retroceso por golpe frontal |
| `hit_back` | once | 15 | 0.5 s | — | Opcional MVP |
| `downed` | once | 45 | 1.5 s | — | Último frame engancha con el **ragdoll** |
| `death` | once | 40 | 1.33 s | — | Ídem: al terminar pasa a ragdoll local/cosmético |

### 3.5 Infectado (rol especial)

| Clip | Tipo | Frames | Dur. | Loop | Notas |
|---|---|---|---|---|---|
| `transform_in` | once | 45 | 1.5 s | — | Humano → mutado |
| `transform_out` | once | 45 | 1.5 s | — | Mutado → humano |
| `skill_1` / `skill_2` / `skill_3` | once | 30 | 1.0 s | — | Placeholder: 1 por habilidad |

### 3.6 Fuera de juego

| Estado | Animación |
|---|---|
| **Director** (jugador muerto) | No tiene cuerpo. Solo cámara/interfaz |

---

## 4. Convenciones

- **Nombres:** `snake_case`, sin prefijos de personaje (`walk`, no `shiba_walk`). Los clips
  son **compartidos** por los 10 personajes; lo específico va en el esqueleto/GLB.
- **Un solo GLB por personaje**, todos los clips dentro.
- **Export glTF:** sin root motion, sin escala, 30 fps, `+Y up`.
- **Nada de clips de 1 frame**: si un clip dura `< 0.1 s` el código no le fuerza el loop.

---

## 5. Marcas / eventos

Los eventos van como **`Animation` call-method tracks** (no por código en `_process`):

| Marca | Cuándo | Para qué |
|---|---|---|
| `footstep_l` / `footstep_r` | al apoyar cada pie | Sonido + `SoundArea` (¡los enemigos oyen!) |
| `grab_contact` | cuando la mano llega | Enclavar el `PinJoint` del agarre |
| `grab_release` | al soltar | Liberar el joint |
| `land_impact` | al tocar suelo | Ruido + sacudida |
| `debug_end` | último frame de los `once` | Volver al estado anterior |

> Las marcas son **datos de la animación**, no lógica: mantienen el clip utilizable por
> cualquier personaje y no dependen del framerate.

---

## 6. Transiciones (blend times)

| Salto | Tiempo |
|---|---|
| idle ↔ walk ↔ sprint | **0.15 – 0.25 s** |
| acción → idle (`once` → loop) | **0.08 – 0.12 s** (rápido, para que no se sienta pegajoso) |
| cualquier estado → `downed`/`death` | **0.10 s** y luego ragdoll |
| `transform_in/out` | **0.0 s** (son transiciones "duras" a propósito) |

---

## 7. Estado actual vs objetivo

| | Hoy | Objetivo |
|---|---|---|
| Clips existentes | `Idle`, `Walk`, `Grab` (mínimos) | Catálogo de §3 |
| Tracks de brazos | **NO existen** en Idle/Walk (bug R1) | Presentes en todos |
| Torso en `Grab` | **Pliado entero** (bug R2) | Quieto; el agarre lo hace el IK |
| Loop | se fuerza por código | Igual + clips cerrados (R4) |
| Eventos | ninguno | §5 |

### Plan sugerido
1. **Ahora (sin assets nuevos):** en FP **no** reproducir `Grab`; el agarre lo hace **solo
   el IK**. Elimina el tirón de cámara y el torso doblado.
2. **Corto:** agregar los tracks de **brazos** a `Idle`/`Walk` (o dejarlos al IK) → R1.
3. **Medio:** clips nuevos de §3 en Blender con las reglas R1–R7.

---

## 8. Decisiones abiertas

- [ ] ¿Los brazos los lleva **siempre el IK** (y el clip solo marca el hombro), o el clip
      los anima en idle/walk y el IK sólo al agarrar?
- [ ] ¿`walljump` necesita clip propio o sale del `jump`?
- [ ] Frames exactos por personaje: ¿el stride depende de la velocidad (`SPEED=50` ≈ 5 m/s)?
      Hoy `walk` dura 0.83 s/ciclo y **puede patinar** si la velocidad real no coincide.
- [ ] ¿Los 10 personajes comparten clips (recomendado) o alguno tiene firma propia?
- [ ] Locomoción **8-direccional** (strafe) o solo adelante/atrás.
