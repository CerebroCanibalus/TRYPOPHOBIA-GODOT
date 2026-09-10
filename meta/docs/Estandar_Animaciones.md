# Estándar de Animaciones — Tripofobia

**Autor:** Lord Gatito · **Estado:** v2 (2026-09-10) — reescrito sobre MEDICIONES del modelo
**v1 descartada:** proponía 22 clips y cientos de frames inventados. El motor hace mucho de
eso solo, y el modelo real tiene mucho menos. Este documento parte de los datos.

---

## 1. BASES REALES (medidas del GLB, 2026-09-10)

`tools/body_debugger` + inspección de las `Animation` del GLB. **20 huesos**, **30 fps**
(`step = 0.0333`).

| Clip | Largo | Keys | Tipo real |
|---|---|---|---|
| `Walk` | 0.833 s | 22 | **loop** (la única animación real) |
| `idle` | 0.042 s | **1** | **pose** |
| `grab_lower` | 0.001 s | **1** | **pose** (blend por pitch) |
| `grab_middle` | 0.001 s | **1** | **pose** (blend por pitch) |
| `grab_upper` | 0.001 s | **1** | **pose** (blend por pitch) |

**Animan 11 de 20 huesos:** `Body, LArm1, LHip, LLeg1, LLeg2, LLeg2.001, RArm1, RHip, RLeg1,
RLeg2, RLeg2.001`

**Los 9 que NO tienen track en NINGÚN clip** (viven en reposo = T-pose):
`LShoulder, LArm2, LArm2.001, RShoulder, RArm2, RArm2.001, Neck, Head, Head.001`

> **Consecuencia medida:** el ragdoll copia la pose del máster con un spring PD. Un hueso sin
> track queda en reposo, así que **el físico pelea por alcanzar una T-pose** — los brazos se
> van a los costados. Es la causa raíz del "el brazo flexiona raro", no el IK.

**Lectura del diseño actual:** el juego se apoya en **poses mezcladas**, no en animaciones
largas. `grab_lower/middle/upper` se interpolan según el pitch de la cámara → **ese es el
"lean" que existe hoy**. `idle` es una pose. Sólo `Walk` tiene tiempo.

---

## 2. LO QUE EL MOTOR MANEJA **SIN** ANIMACIONES

No hay que autorizar clips para esto (el ragdoll + la física + el código ya lo resuelven):

| Estado | Quién lo resuelve |
|---|---|
| Caer / estar en el aire | **Física** (ragdoll) |
| Aterrizar / absorber impacto | **Física** |
| Recibir daño / empujones | **Física** (ragdoll reacciona) |
| Morir | **Ragdoll** (el cuerpo se suelta, local/cosmético) |
| Agacharse | **Código** (baja el cuerpo/cápsula) |
| Movimiento (velocidad, dirección, sprint) | **CharacterBody3D** |
| Agarrar / lanzar / empujar / usar | **IK de brazos** + poses de brazo |
| Transformar (infectado) | **Shader/VFX** + ragdoll |
| Wall-jump | **Física** |

**Regla:** si el motor lo hace solo, **no se anima**. Sólo se anima lo que aporte algo que la
física no pueda dar (peso, contacto con el suelo, anticipación).

---

## 3. REGLAS DURAS

### R1 — **TODOS los huesos, en TODOS los clips** (la más importante)
Cada clip debe tener track de **los 20 huesos**, aunque sea con **1 key** de valor constante.
Un hueso sin track se queda en reposo y el ragdoll pelea contra él.

- **Bug medido:** los 9 huesos listados en §1 no tienen track → los antebrazos y las manos
  viven en T-pose → los brazos se van a los costados.
- **Fix mínimo:** agregar esos 9 tracks (constantes) a los 5 clips existentes. **No hace falta
  animarlos**: alcanza con que **declaren una pose** en vez de quedar en reposo.

### R2 — Cabeza y torso superior QUIETOS en FP
La cámara vive **dentro de la cabeza**. Animar `Neck`/`Head`/`Head.001` o plegar el `Body`
**sacude la vista**.

- **Bug medido:** `grab_upper/middle/lower` pliegan el torso entero → al agarrar "la vista se
  va para adelante". El gradiente está bien; hay que **re-autorizarlo con el torso casi
  quieto** (el agarre lo hace el brazo).

### R3 — Cero root motion
El desplazamiento lo lleva el código. Un clip con root motion pelea con la física y rompe la
predicción en red.

### R4 — Loop: frame 1 == último frame
Y en Godot, `loop_mode` se fuerza por código (el import de glTF trae `NONE`).

### R5 — Brazos con recorrido para el IK
Dejar el codo a ~100°: ni extendido al máximo (el IK no puede estirar más) ni pegado al cuerpo.

### R6 — Nada de `scale`. Solo traslación/rotación.

### R7 — 30 fps en el fuente (lo que ya usa el modelo).

---

## 4. CATÁLOGO (mínimo, sobre las bases reales)

**No se inventan clips nuevos hasta que el motor no alcance.** Primero, completar lo que hay.

### 4.1 Ya existe — hay que ARREGLARLO

| Clip | Tipo | Acción |
|---|---|---|
| `Walk` | loop | **Agregar los 9 tracks que faltan** (R1) |
| `idle` | pose | **Agregar los 9 tracks** + darle vida (**20-30 keys** para respiración) |
| `grab_lower/middle/upper` | poses | **Agregar los 9 tracks** + re-autorizar con torso quieto (R2) |

> **Ese es el 90 % del trabajo y no requiere clips nuevos.** Con 9 tracks constantes en cada
> clip, los brazos dejan de pelear contra la T-pose.

### 4.2 A evaluar (sólo si aporta algo que la física no dé)

| Clip | Tipo | Keys | ¿Vale la pena? |
|---|---|---|---|
| `walk_sprint` | loop | ~22 | Sólo si el ciclo de `Walk` a 5 m/s se ve mal |
| `jump_pose` | pose | 1 | Sólo si el ragdoll en el aire se ve flácido (anticipación) |
| `land_pose` | pose | 1 | Sólo si el aterrizaje necesita leer el impacto |

### 4.3 Descartado (lo maneja el motor)

`crouch_idle` · `crouch_walk` · `jump_launch` · `jump_air` · `walljump` · `throw` · `push` ·
`use` · `hit_front` · `hit_back` · `downed` · `death` · `transform_in` · `transform_out` ·
`skill_1/2/3` → ver §2.

---

## 5. Convenciones

- **Nombres:** `snake_case`, sin prefijo de personaje (`walk`, no `shiba_walk`). Los clips son
  **compartidos**; lo específico va en el esqueleto/GLB.
- **Un solo GLB por personaje**, todos los clips dentro.
- **Export glTF:** 30 fps, sin root motion, sin escala, `+Y up`.
- **Pose = 1 key.** No hace falta un clip de 30 frames para algo estático.
- **`loop_mode`** se fuerza por código para clips con `length > 0.1`.

---

## 6. Estado actual vs objetivo

| | Hoy | Objetivo |
|---|---|---|
| Clips | `Walk` (loop) + `idle` + 3 poses de agarre | **los mismos** + los tracks que faltan |
| Huesos animados | **11 / 20** | **20 / 20** en todos |
| `idle` | 1 key (rígido) | 20-30 keys (respiración) |
| Gradiente de agarre | pliega el torso (marea en FP) | torso quieto (R2) |
| Loop | se fuerza por código | igual |
| Eventos | ninguno | `footstep_l/r` en `Walk` (los enemigos oyen) |

---

## 7. Decisiones abiertas

- [ ] **Los brazos**: ¿los anima el clip (poses) o los lleva **siempre el IK**? Si los lleva el
      IK, en los clips basta con **1 key neutral** por hueso (R1 cumplida sin trabajo de animación).
- [ ] **`Walk` puede patinar**: 0.833 s/ciclo vs `SPEED=50` ≈ 5 m/s. ¿Atamos la velocidad del
      `AnimationTree` a la velocidad real?
- [ ] ¿Los 10 personajes **comparten** clips (recomendado) o alguno tiene firma propia?
- [ ] Locomoción **8-direccional** (strafe) o sólo adelante/atrás.
