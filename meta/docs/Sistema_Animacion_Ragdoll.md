# Sistema de Animación Ragdoll — Tripofobia

**Estado:** v1 (2026-11-03) · Implementado en `src/ragdoll/` · Documento **normativo**:
si algo aquí contradice al código, el código tiene un bug (o el doc está viejo).

> Este documento es la **memoria técnica** del sistema de ragdoll: por qué está
> hecho como está, qué trampas tiene Godot/Box3D y cómo se pone un modelo nuevo.
> La librería que lo implementa está en `src/ragdoll/` (índice al final).

---

## 1. QUÉ ES (y qué NO es)

Un **ragdoll activo**: el personaje tiene un esqueleto real (cuerpos físicos
articulados) y una animación que lo *manda*. El motor (PD) lleva los cuerpos a
la pose del clip; la física decide cómo llega.

NO es un "muñeco que se cae": es un personaje que anda, se mantiene de pie y
reacciona a la física.

### Arquitectura (doble esqueleto)

```
Shiba (Node3D, ragdoll_character.gd)
├── Physical/            ← instancia del GLB: la malla VISIBLE
│   └── metarig/Skeleton3D
│       └── PhysicalBoneSimulator3D → 21 PhysicalBone3D (cuerpos + joints)
├── Animated/            ← instancia del GLB: esqueleto INVISIBLE
│   └── metarig/Skeleton3D   ← aquí escribe la animación (AnimationTree)
├── Anim/                ← AnimationPlayer + AnimationTree (mezcla de estados)
├── HuesosFisicos/       ← los 21 PhysicalBone3D AUTHORED (se reparentan al esqueleto)
├── CameraPivot/         ← cámara (1ª / 3ª persona)
└── Agua/Oxigeno/...     ← componentes del juego
```

**Por qué dos instancias del GLB:** una lleva la malla (y la deforma la
FÍSICA) y la otra lleva la ANIMACIÓN (que se calcula aparte). Si se usara un
solo esqueleto, la animación y la física se pisarían.

---

## 2. LA LIBRERÍA (`src/ragdoll/`)

Cada pieza es un componente con UNA responsabilidad. La raíz los compone.

| Fichero | Clase | Responsabilidad |
|---|---|---|
| `rig/ragdoll_bone.gd` | `RagdollBone` | UN hueso físico: forma, tamaño, masa, límites de cono, grupo |
| `rig/ragdoll_rig.gd` | `RagdollRig` | TODOS los datos de un rig (huesos, clips, cadenas IK, mirada) |
| `rig/rig_forge.gd` | `RigForge` | **Construye** un `RagdollRig` desde un modelo, solo |
| `rig/rig_report.gd` | `RigReport` | **Valida** un rig contra su modelo y explica qué falta |
| `runtime/ragdoll_skeleton.gd` | `RagdollSkeleton` | Los cuerpos físicos: simulator, joints, colliders |
| `runtime/ragdoll_motor.gd` | `RagdollMotor` | El PD: lleva cada cuerpo a su pose objetivo |
| `runtime/pose_mirror.gd` | `PoseMirror` | Copia las poses de la física al esqueleto visible |
| `runtime/animation_driver.gd` | `AnimationDriver` | `AnimationPlayer` + `AnimationTree`: clips, mezcla, estado |
| `runtime/head_look.gd` | `HeadLook` | La cabeza que sigue a la cámara (pesos acumulados) |
| `runtime/arm_ik.gd` | `ArmIK` | Los brazos que se estiran hacia el puntero |
| `runtime/fp_clip.gd` | `FpClip` | El recorte de 1ª persona (el shader del cráneo) |
| `runtime/balance_controller.gd` | `BalanceController` | El equilibrio (upright + centro de masas) |
| `character/ragdoll_character.gd` | `RagdollCharacter` | La raíz: input, movimiento, agarre, agua |
| `character/ragdoll_camera.gd` | — | Cámara en 1ª/3ª persona |
| `tools/ragdoll_scene_builder.gd` | `RagdollSceneBuilder` | **Construye la escena** completa desde (modelo + rig) |

### Cómo se pone un modelo nuevo (3 pasos)

```bash
# 1) El forge mide el modelo y genera el rig (incluye los "huesos puente")
godot --headless --path <proj> -s res://tools/ragdoll_forge/forge.gd -- \
  --model=res://assets/players/shiba/shiba_V2.glb \
  --body=spine --head=head \
  --hands=hand.L,hand.R --feet=foot.L,foot.R \
  --extra=spine.003,spine.005 \
  --look=spine.005,head --lookw=0.35,0.65 \
  --mass=50 --name=Shiba \
  --rig=res://src/ragdoll/rig/shiba_rig_config.tres \
  --scene=res://src/player/shiba_player.tscn

# 2) El informe dice si el rig esta completo
#    (el forge lo imprime y NO guarda si hay errores)

# 3) Listo. No se toca codigo.
```

Lo que el forge **hace solo** (y es donde se perdían horas a mano):

| Qué deduce | Cómo |
|---|---|
| **Huesos puente** | Sube por los padres de cada hueso con cuerpo hasta llegar a otro con cuerpo, y mete los intermedios. **Si falta uno, ese hueso queda SUELTO** (ver §4) |
| Colliders | La cápsula va del origen del hueso al de su hijo (offset = longitud/2) |
| Masas | Repartidas **proporcional a la carga que soporta** (la vértebra pesa lo que aguanta) |
| Cadena IK | De la mano hacia el hombro: mano → antebrazo → brazo |
| Clips | Los de la biblioteca de animación, o los del modelo |

---

## 3. EL PD (control de orientación)

> ⚠️ **ESTA SECCIÓN ESTÁ SUPERADA (2026-11-03).** El PD que se describe aquí
> (`τ = I·α`, `α = k·e − c·ω` con `k`/`c` fijos) **ya no es el del código**: el
> PD es ahora **por torque** (`τ = ganancia·(k·e − c·ω)`), con el
> **amortiguamiento crítico** de cada cuerpo y el error **relativo al padre**.
> Ver **T21** y **T22** (§4bis). Los números de abajo son los del PD viejo y
> **no** sirven para afinar el actual.

```
objetivo  = pose de la animación (+ lean + mirada de cabeza)
error     = eje * angulo  (AXIS-ANGLE, ver §4)
alpha     = k * error - c * omega        (k=2500, c=100)
torque    = I * alpha                    (I = inercia real del cuerpo)
```

### Por qué TORQUE y no velocidad

Escribir la **velocidad angular** de cada hueso por separado hace que *cada
articulación pelee con el PD*: el solver de joints proyecta las velocidades
para cumplir las restricciones y el PD las sobrescribe → la cadena se embala y
el personaje sale disparado.

**Medido:** con el PD por velocidad la pelvis iba de 0,46 m a 13,6 m en 5 s
(con rigidez 8000, llegó a 28 m).

Con **torque** el solver puede resolver el conjunto: las fuerzas se suman y la
cadena llega a la pose.

### Números que importan

| Parámetro | Valor | Por qué |
|---|---|---|
| `angular_spring_stiffness` | 2500 | La frecuencia natural es `w_n = sqrt(k)`; a 60 Hz hace falta `w_n·dt < 1` → `k < 3600`. Con 8000 el sistema **es inestable** |
| `angular_spring_damping` | 100 | `ζ = c / (2·sqrt(k))` → ζ ≈ 1 (crítico). Con 80 el rig oscilaba |
| `max_angular_accel` | 1500 rad/s² | Tope de la corrección |
| `max_angular_speed` | 6 rad/s | Sin él, un frame da 40 rad/s y la cadena es un latigazo |
| `arm_spring_scale` | 1.0 | Los brazos que no agarran pueden ir más blandos |

### La masa decide si el personaje se aguanta

El error de equilibrio del PD es `τ_gravedad / (I · k)` y `τ` es proporcional a
**la masa que CUELGA** del hueso. Con 1 kg en todo, la pelvis no puede sostener
el torso: hacen falta ~850 rad/s² y el PD se equivoca **54 grados**.

Con masas por carga (la vértebra pesa lo que aguanta) el error baja a **2-15°**.

---

## 4. LAS TRAMPAS (todas medidas)

### T1 — El joint se crea contra el cuerpo del PADRE

El joint de un `PhysicalBone3D` se crea contra el cuerpo del **padre** del
hueso. **Si el padre no tiene cuerpo, el joint NO se crea** y el hueso queda
como un cuerpo suelto: no tira de sus hijos ni lo sostienen a él.

En el Shiba faltaban **5** cuerpos (`spine.001/002/004`, `shoulder.L/R`) y los
brazos iban **sueltos del pecho**. Por eso el antebrazo no seguía al brazo.

→ `RigForge` los encuentra solos; `RigReport` avisa.

### T2 — El packer no serializa el subárbol de una instancia

Los `PhysicalBone3D` **no** se pueden author dentro del `Skeleton3D` de la
instancia del GLB con un script: al guardar, Godot se los come (medido: 0 de 21).

En la **coneja** sí están en la escena porque su GLB tiene las mallas como
**hermanas** del esqueleto y la escena se editó en el editor. En el **Shiba** las
10 mallas son **hijas** del esqueleto → al hacerlo editable se **inlinean**
(la referencia `active_ragdoll_reference` pesa 256 KB por eso).

→ **Truco:** se authoran en un nodo `HuesosFisicos/` (fuera de la instancia) y
en runtime se **reparentan** al esqueleto (`RagdollSkeleton._huesos_fisicos_authored()`).
Escena de 25 KB, cero mallas inlineadas, y los colliders son de verdad datos de
la escena.

### T3 — `AnimationTree.active` NO se serializa

Es una propiedad de **solo runtime**: al cargar la escena el árbol nace
**APAGADO** y la animación no llega al esqueleto (todos los huesos a 0° de su
pose de reposo; el personaje con los brazos en T).

→ `AnimationDriver.setup()` la activa.

### T4 — El `root_node` del AnimationMixer tiene que ser un ANCESTRO

`root_node = "Animated"` → `invalid root_node path` (lo rechaza). El
`root_node` es la **raíz del personaje**, y las pistas son relativas a ella
(`Animated/metag/Skeleton3D:<hueso>`).

Y **NO** puede ser `current_scene`: en headless es `null` y el árbol se queda
sin resolver.

### T5 — El AnimationPlayer hay que cablearlo, no buscarlo por nombre

El modelo puede traer SU propio `AnimationPlayer` (con los clips importados).
Si el personaje lo busca "por nombre", se queda con ese en vez del que mueve la
escena → la animación no llega.

→ `AnimationDriver` lo saca de `animation_tree.anim_player`.

### T6 — El error de orientación va en AXIS-ANGLE, no en euler

`Basis.get_euler()` reparte el ángulo entre los tres ejes y el vector
resultante **no apunta en la dirección real** de la rotación.

Medido: con euler los brazos se quedaban a **116°** del clip mientras el torso
iba bien (el torso gira poco → el euler "acierta").

→ `RagdollMotor.error_de_rotacion()` usa el cuaternión.

### T7 — `_anim_pose_cache` se congela

El cache de la pose modificada por el IK se llena con la señal
`modification_processed`. Con **influencia 0** el IK no escribe nada y **la
señal no se dispara** → el cache se queda en la pose del **primer frame** (la
de reposo) y el PD apuntaba ahí.

Síntoma: el torso iba bien (el clip IDLE no mueve la columna) pero **los brazos
se quedaban en T** (el IDLE los baja 59°).

→ Si el IK no está activo, se usa la pose **actual** del esqueleto animado.

### T8 — `PhysicalBone3D` no tiene `apply_torque()`

Extiende de `PhysicsBody3D`, no de `RigidBody3D`. Se usa la API del servidor:
`PhysicsServer3D.body_apply_torque(rid, torque)` y
`PhysicsServer3D.body_get_param(rid, BODY_PARAM_INERTIA)` (Box3D **sí** lo
devuelve).

### T9 — El nodo `PhysicalBone3D` no se actualiza

El motor debería escribir la pose del hueso desde el cuerpo, pero ese callback
**no se dispara** en Box3D: el nodo se queda con la pose inicial.

→ `RagdollMotor.body_transform()` lee la transform **del servidor de física**.

### T10 — El `Skin` del GLB es un recurso COMPARTIDO

Las dos instancias del modelo (física y animada) comparten el `Skin`, cuya ruta
apunta al esqueleto de **su** padre. Sin duplicarlo, la malla del "Physical" se
deformaba con el esqueleto ANIMADO (que está en otra pose) y salía hecha pedazos.

→ `FpClip.setup()` duplica el `mesh` y el `skin`.

### T11 — Los clips de glTF vienen con `loop_mode = NONE`

Se reproducen una vez y se congelan. Hay que forzar `LOOP_LINEAR` (solo en los
que duren más de 0.1 s: las "poses" de 1 key no).

### T12 — `get_bone_global_pose()` NO es el mundo

La propia documentación lo dice: "global pose below refers to the overall
transform of the bone **with respect to skeleton**, so it is not the actual
global/world transform of the bone". El servidor de física devuelve
transformaciones en **MUNDO**. En la escena del Shiba las dos instancias del
GLB tienen transformaciones **distintas** (la física lleva un flip de 180°
sobre Y; la animada es identidad): mezclar los dos marcos mete errores de
~180° en brazos y piernas (medido).

→ Objetivo del PD en MUNDO (`anim.global_transform * pose`), cuerpo en MUNDO;
y el espejador convierte a **relativa del esqueleto físico**
(`fisica.global_transform.affine_inverse() * mundo`) antes de
`set_bone_global_pose` (que espera la pose **relativa al esqueleto**).

### T13 — El joint de un `PhysicalBone3D` se crea en `_ready()`

El joint se crea cuando el hueso **entra al árbol**, contra el cuerpo del
**PADRE**. Si al entrar el padre no está en el árbol (o no tiene cuerpo), el
joint **NUNCA** se crea: el hueso queda suelto.

Medido: autorhados fuera del esqueleto → la cadena de columna se abría
**0,8 m** padre↔hijo (saco de huesos sueltos; el muelle de altura levantaba
solo la pelvis y el resto quedaba tirado en el suelo).

→ Los cuerpos se crean **en runtime dentro del simulador**, en orden de
**padre antes que hijo** (índice de hueso ascendente) y con **TODO
configurado antes de `add_child`** — al entrar con `joint_type = NONE`
(default) no se crea nada. Nada de huesos físicos en la escena.

### T14 — `skeleton_updated` del esqueleto físico NO vale para el PD

Esa señal **solo se emite cuando las poses del esqueleto cambian**: como las
poses las escribe el propio espejador, la cadena se rompe y el PD se queda
congelado (la malla se quedaba en la pose de reposo del modelo).

→ El PD corre en `_physics_process`.

### T15 — El muelle de altura se captura contra el SUELO, no contra el aire

Los ShapeCast de los pies ven el suelo hasta **0,45 m** por arriba: capturando
ahí el objetivo quedaba ~1,2 m y el personaje quedaba **colgado en el aire**
(medido: pelvis a 1,13 m con la cabeza en el suelo). Y al aparecer (spawn en
el aire), la captura daba la altura de aire (2,42 m) y el muelle empujaba
hacia arriba para siempre.

→ Captura **perezosa** en el primer contacto con el suelo, con los pies de
**verdad abajo** (< 0,3 m): objetivo = `pies_y + (pelvis_pose − pies_pose)`
del clip. En el juego el spawn es de pie en el suelo y la captura es
inmediata y correcta.

### T16 — El grupo "column" sale de recorrer la jerarquía

El BalanceController busca el torso por el grupo `column` y **excluye el
hueso-cuerpo**: si solo el pelvis era `column`, `_torso()` devolvía `null` y
`apply()` salía en silencio sin tocar nada (medido: el personaje se tumbaba
y el balance no hacía NADA).

→ `RigForge` reparte `column` por la cadena **de la cabeza al cuerpo**
(`spine..head` completo).

### T17 — Masa real ≠ ganancia del PD

La masa de cada cuerpo va por su **volumen** (la suma da el peso real). Lo que
un hueso **SOPORTA** es ganancia del PD (`pd_gain`, normalizada con
`pd_gain_max = 12`). Meter lo soportado en la masa → el ragdoll pesa
**216 kg** y la inercia descoloca los extremos (medido).

---

---

## 4bis. TRAMPAS NUEVAS (2026-11-03) — el día que los huesos pasaron a la ESCENA

Todo lo de arriba describe el ragdoll con los cuerpos **creados por código**.
Ese diseño se **descartó**: la escena quedaba sin datos (invisible en el
editor, con los offsets calculados a mano) y el personaje se caía de cabeza.

### T18 — LOS HUESOS FÍSICOS SON DATOS DE ESCENA (regla dura)

`PhysicalBone3D` + su `CollisionShape3D` + `transform` + `body_offset` +
`joint_offset` + `mass` + `joint_type` + `joint_constraints/*` van **authorados
en el `.tscn`**, como hijos del `Skeleton3D`. El runtime no crea ni ajusta
nada de eso (ver §REGLA DURA en `AGENTS.md`).

**Por qué importa (medido):** con el cuerpo y el ancla del joint en el origen
del hueso, el joint unía **cabeza con cabeza**: el hijo pivota sobre la
cabeza del padre y la columna no se estira. Con el cuerpo a **media hueso**
(como hace el editor) el joint une el **final del padre con la cabeza del
hijo** (la anatomía real).

### T19 — `body_offset` es el offset del cuerpo en espacio de HUESO

Godot coloca el cuerpo con `esqueleto × pose_del_hueso × body_offset`
(`PhysicalBone3D::reset_to_rest_position`, fuente 4.3-stable). Por eso:

- `body_offset` = `(esqueleto × pose)⁻¹ × cuerpo` — el offset respecto al
  **hueso**, no respecto a la pose del esqueleto.
- `joint_offset` = `body_offset⁻¹` (lo calcula Godot en `_fix_joint_offset`).
- **`PoseMirror` tiene que deshacerlo**: al copiar la pose del cuerpo al
  esqueleto hay que multiplicar por `body_offset.affine_inverse()`; si no, la
  malla se va media hueso por eslabón y sale retorcida (medido: la cámara en
  3ª persona veía el interior del modelo).

### T20 — el simulador lo crea GODOT, y hay que buscarlo por TIPO

`PhysicalBoneSimulator3D` es un hijo del `Skeleton3D` con nombre
AUTOGENERADO (`@PhysicalBoneSimulator3D@N`). **Buscarlo por nombre
`"PhysicalBoneSimulator3D"` no lo encuentra** (el test del Shiba fallaba por
eso). Se busca por **TIPO**.

Y como el simulador es hijo del esqueleto, Godot recorre el **subárbol del
esqueleto** buscando los `PhysicalBone3D` y los enlaza
(`PhysicalBoneSimulator3D::_pb_start_simulation`): por eso tienen que estar
authorados **como hijos del `Skeleton3D`**.

### T21 — el PD va por TORQUE, y el amortiguamiento es el CRÍTICO

El PD antiguo (`τ = I·α`, `α = k·e − c·ω`) tiene tres fallos medidos:

1. **La inercia de los huesos de la columna es diminuta** (0,001–0,013 kg·m²:
   son cajas de 20 cm) y la gravedad exige 3,7–15,7 N·m. Con el tope de
   aceleración (1500 rad/s²) el torque máximo era `I·1500` = 1,5–20 N·m: la
   columna se dobla sola (ratio medido 1,7–4,9).
2. **El amortiguamiento multiplicado por la ganancia** (`c = 100·13 = 1300`
   cuando el crítico era 11) → 33× sobreamortiguado e inestable: el cuerpo
   se ponía a girar a **47 rad/s** (el tope del motor es 6) y se quedaba con
   **170–178° de error clavados** para siempre.
3. **La ganancia no puede multiplicar la RIGIDEZ**: la velocidad de
   equilibrio del PD es `ω = k·e/c`, así que con la ganancia en `k` se iba a
   46 rad/s (conmutación). **La ganancia va en el TORQUE.**

El PD actual:

```
τ = ganancia · (k_base·e − c·ω)        [N·m]
c  = 2·ζ·√(k·ganancia·I)   (crítico, con la inercia REAL del cuerpo)
τ  = τ.limit_length(min(I·max_angular_accel, max_torque))
```

`max_angular_accel` (rad/s²) es el tope que define la velocidad a la que el
PD puede girar un cuerpo (`ω += α·dt`): con 3000 ganaba 50 rad/s por frame y
**el error crecía**; con 300 gana 5 rad/s por frame y converge.

### T22 — el error del PD es RELATIVO AL PADRE

Con el error **absoluto** (cada hueso persiguiendo su pose absoluta en el
mundo) los 7 huesos de la columna compiten: cada uno tira de su padre y la
cadena se dobla en vez de estirarse (medido: cabeza 0,55 m por debajo de la
pelvis con el personaje de pie).

El error de una articulación es el del hijo respecto al padre:

```
e = (actual_padre⁻¹ · actual_hijo)⁻¹ · (objet_padre⁻¹ · objet_hijo)
```

y el torque se aplica al **hijo** (que es quien puede girar respecto al
padre). El eje se lleva a MUNDO antes de aplicar el torque.

### T23 — el balance ancla al SUELO (raycast), no a los pies

La captura de la altura objetivo se hacía cuando el pie más bajo estaba a
menos de 0,3 m del suelo. Si el personaje se estrella **de espaldas**, los
pies quedan a 0,5–0,8 m y **la captura nunca ocurre**: el balance entero
(upright + centro de masas + muelle vertical) se queda apagado y el ragdoll
se queda tumbado boca arriba para siempre. Ahora se ancla al **suelo que hay
debajo de la pelvis** (raycast) → la captura es correcta tumbado o de pie.

### T24 — el `upright` no puede corregir un volteo de 180°

`arriba.cross(Vector3.UP)` da **vector CERO** cuando el torso está
invertido ⇒ el eje de corrección se anula y el torso se queda boca arriba
para siempre (medido: `up_col` = −0,98 durante 4 s). Con el torso invertido
el eje de giro puede ser cualquiera horizontal (se usa el "adelante" del
torso).

Y el torque del balance va **topado por la inercia** (`I·max_accel`): 120 N·m
sobre un torso de I = 0,03 son 4000 rad/s² y el torso sale disparado.

---

## 4ter. ESTADO MEDIDO (2026-11-03, tras el cambio a escena)

| Métrica | Antes (cuerpos por código) | Ahora (authorados) |
|---|---|---|
| `up_col` (verticalidad del torso) | **−0,9** (columna invertida) | oscila entre −0,9 y +0,8 según el momento |
| `cab_pel` (cabeza sobre la pelvis) | **−0,86** (cabeza bajo la pelvis) | **−0,04 … −0,55** (se estira a ratos) |
| `pel_y` (altura de la pelvis) | 0,25 (tumbado) | **0,65–0,71** (el balance lo levanta) |
| `ω` de los cuerpos | **47 rad/s** (conmutación) | 5–25 rad/s |
| Error de orientación | **175° clavados** | 0–30° (el PD converge) |
| Test automático | 13/13 | **13/13** ✓ |

**Lo que funciona:** los 21 huesos están en la escena con sus datos, los
joints se crean (21 con joint, 0 sueltos), la malla no se deforma, el
personaje se levanta del suelo, camina (5 m), la cabeza sigue a la cámara y
el IK de los brazos funciona.

**Lo que QUEDA (honesto):** la columna no se mantiene recta en reposo
permanente: tras aterrizar el torso acaba con `up_col` negativo (la figura
queda en U). El objetivo (esqueleto animado) está **perfecto** (medido:
caderas 0,83 → cabeza 1,61, todos con `up ≈ (0,1,0)`), así que el siguiente
paso es el **PD de la cadena**: hay que revisar el reparto de `pd_gain` por
eslabón y el `max_angular_accel` de los huesos de la columna, que es el
único dato que no se ha barrido todavía con el rig nuevo.

## 5. EL IKP (IK de brazos)

- **Necesita un nodo polo** por brazo. Con solo `pole_direction_vector` el
  solver procesa pero **no escribe pose**. Con un solo polo, los dos codos caen
  en el mismo plano (ala de pollo).
- La pose solo es válida en `modification_processed`; por eso el PD lee un
  cache.
- El **alcance se mide del rig** (hombro→muñeca). Un valor corto no acorta el
  brazo: lo **ploga** entero (el codo hace tope).
- El `TwoBoneIK3D` tiene que ser hijo **DIRECTO** del `Skeleton3D` (el esqueleto
  solo busca modificadores entre sus hijos). Se crea en runtime para no tocar la
  instancia del GLB.

---

## 6. INSTRUMENTOS (usar estos, no escribir sondas)

| Herramienta | Para qué |
|---|---|
| `tools/body_debugger/` | **Tabla por hueso** (físico vs animado) con la columna `rest`, que clasifica el bug: si `rest ≈ 0` los ejes de los dos rigs coinciden y la divergencia es de la POSE; si `rest ≠ 0` los rigs tienen ejes distintos |
| `tools/ragdoll_playground/` | Banco con telemetría (pos, dXZ, vel, angvel) |
| `tools/active_ragdoll_reference/` | El proyecto de referencia del que se portó TODO (PD, límites 180/90, jerarquía) |
| `tools/ragdoll_forge/forge.gd` | Genera rig + escena desde un modelo |

---

## 7. ESTADO ACTUAL (2026-11-03, medido)

> ⚠️ **ESTA SECCIÓN describe el estado ANTIGUO** (cuerpos creados en runtime).
> El estado de HOY está en **§4ter** (después del cambio a huesos authorados
> en la escena). Los dos convivieron el mismo día: el cambio de arquitectura
> se hizo a última hora y la sección 7 quedó desfasada.

**El ragdoll funciona y se pone de pie.** Las tres patas que faltaban
(del cuerpo a la cabeza) tienen todas juntas:

| Pieza | Estado |
|---|---|
| PD (orientación, pose) | ✅ funciona con marcos **MUNDO** consistentes (T12) |
| Balance (upright + CoM + height assist) | ✅ captura su objetivo **en el primer contacto con el suelo** (T15); la columna es grupo `column` (T16) |
| Joints (constraint padre↔hijo) | ✅ cuerpos creados **en runtime dentro del simulador**, padre antes que hijo (T13) |

**Medido:**

- El personaje **se sostiene de pie** (pelvis ~0,7–0,9 m, columna erguida,
  `up ≈ +1` en `spine`) — incluso soltado desde 1,1 m: cae, el muelle lo
  endereza y **se queda de pie** (`tests/ragdoll/shots/shiba_3persona.png`).
- El muelle de altura por sí solo no basta: sin el `column` bien repartido
  (T16) el balance no hacía **nada** en silencio.
- Test automático: **13/13** (`tests/ragdoll/shiba_test.tscn`) · capturas
  en `tests/ragdoll/shots/`.
- `RigForge` regenera rig + escena (`shiba_rig_config.tres` /
  `shiba_player.tscn`): columnas, colliders, masas (suma = 50 kg) y
  `pd_gain` (T17).

**Lo pendiente (honesto):**

1. Soltada **desde el aire**, la caída aplasta la pose y la recuperación es
   parcial (la captura del muelle es de pie, así que el aire no se valida
   como "gameplay"): el spawn real es de pie en el suelo y ahí se sostiene.
2. El **hombro** (clavícula) sigue con ~95° de *twist* en reposo (va bajo la
   armadura; no afecta a la silueta).
3. La cola: sus huesos no tienen cuerpo (van como el resto de huesos sin
   cuerpo, copiando la pose del esqueleto animado); su reposo la deja baja.
4. El `height assist` está **afinado para este rig**; un rig nuevo lo
   hereda (mismos nombres de export) — revisar `max_force` si cambia el
   peso.

---

## 8. CHECKLIST para un rig nuevo

1. El forge dice **"huesos con cuerpo: N"** y lista los puentes.
2. El informe no tiene errores (ni "CADENA ROTA").
3. `huesos fisicos = N` es **N creados en runtime dentro del simulador**
   (nada authored en la escena — ver T13). La escena NO contiene
   `HuesosFisicos`.
4. `spine` tiene el grupo **"column"** y TODA la cadena hasta la cabeza
   (`bone_name = spine.*`) también (ver T16).
5. Con el body_debugger: `rest = 0` en todos los huesos (los dos rigs coinciden).
6. El personaje cae y **queda de pie** (pelvis ~0,7-0,9 m tras el aterrizaje).
7. La cabeza gira con la cámara y la 3ª persona mide lo que debe.

---

## 4quater. LO QUE SE ROMPIÓ AL CONVERTIRLO EN LIBRERÍA (2026-11-03)

> **Esta es la sección más importante del documento.** Todo lo de arriba
> (T1-T24) describe un ragdoll que funcionaba con el script monolito. Al
> pasarlo a `src/ragdoll/` se cambió **la ley de control** y se rompió.

### T25 — LA LEY: servo de VELOCIDAD con objetivo ABSOLUTO en mundo

```
actual   = pose del HUESO en MUNDO  (cuerpo del servidor * body_offset^-1)
objetivo = pose del HUESO en MUNDO de la ANIMACIÓN
e        = eje*ángulo de (objetivo * actual^-1)      [MUNDO]
alpha    = k*e - c*omega                             [rad/s2]
omega   += alpha*dt                                  [rad/s]
```

Es la ley de `tools/active_ragdoll_reference` (k=3000, c=80) y la ÚNICA que
aguanta con Box3D. Lo que la librería puso en su lugar (PD por torque con
error RELATIVO al padre, torque aplicado como PAR, dos inercias y un
controlador de balance con upright + centro de masas + muelle de altura) **no
funciona**: medido, la pelvis giraba a 40 rad/s constantes desde el primer
frame (el balance le devolvía el par de todos los hijos con un tope de
aceleración de 3000 rad/s2) y el personaje se volcaba.

**Variantes medidas y DESCARTADAS:**

| Variante | Resultado |
|---|---|
| Error por articulación (relativo al padre) | el servo y los joints se pelean: la columna obedece (2-8°) pero las piernas no (27-80°) |
| Heredar la velocidad del padre (servo jerárquico) | se amplifica por la cadena (errores de 160°) |
| Ley por torque (N·m/rad) con tope por cuerpo | el damping crítico sin tope EXPLOTA en los huesos pequeños (180 rad/s); con tope no llega al error de equilibrio |
| Límites cónicos de Box3D (5° o 180°) | **no se aplican**: el resultado es idéntico |

### T26 — el tope de `max_angular_speed` (6 rad/s) mataba el servo

Con 6 rad/s el servo no puede girar un hueso grande en un frame: el personaje
se ve "aguado" y **los brazos y el pecho parece que no siguen al ragdoll**
(el síntoma que llevó a pensar que el rig estaba mal). El tope tiene que ser
de **decenas** de rad/s (40).

### T27 — la MASA decide si el personaje se tiene en pie

El error de equilibrio del servo en aceleración es `e = tau_g /(I*k)`. Con la
pelvis del Shiba (8 kg en una caja de 30 cm → I = 0,11 kg·m²) sosteniendo
**30 kg de tronco** a 0,3 m (88 N·m) salían **15 GRADOS de error en la
pelvis**: se inclinaba y se hundía (`pel_y` 0,9 → 0,26).

**Regla: el tronco es LIGERO y las piernas son PESADAS.** El hueso que SOPORTA
necesita inercia; el que se mueve, no. Reparto medido (Shiba, 38,7 kg):
columna 16,7 kg · piernas 14,9 kg · brazos 7,1 kg.

### T28 — el apoyo se calcula con los COLLIDERS, no con los huesos

El collider va a MEDIA HUESO (`body_offset`): su fondo queda centímetros por
DEBAJO del origen del hueso. Si el personaje se coloca con los orígenes de
los huesos, el collider del pie nace DENTRO del suelo y el solver lo expulsa
de una patada (medido: el pie gira 50° y se pone a girar a 13 rad/s en el
frame 3 — de ahí venía el "aguado" y el "se hace un montón de tiras").

→ `_colocar_en_el_suelo()` usa `_fondo_de_los_colliders()`.

OJO: `Shape3D` **no tiene `get_aabb()`** en Godot 4.7 → `WaterShapeTest.aabb_de()`.

### T29 — el modelo mira a +Z y la cámara a -Z (el personaje andaba de espaldas)

El nodo `Animated` lleva un giro de **180° en Y**, así que el yaw GLOBAL del
esqueleto es `gamma - rotation.y` (no `rotation.y`). Con
`atan2(dir.x, dir.z)` el personaje miraba exactamente al revés (medido:
`dot(frente_del_modelo, cámara) = -1.000`).

→ `_calibrar_rumbo()` mide `gamma` de la escena al montar (así vale para
cualquier rig) y el cuerpo **sigue a la cámara** por defecto
(`body_follows_camera = true`, como el script original).

### T30 — el IK de brazos necesita `update_hand_targets`

El puntero avisa por duck typing (`root.has_method("update_hand_targets")`).
Sin ese método el `TwoBoneIK3D` se queda con su influencia por defecto
(**1.0**) y los brazos se estiran al puntero **siempre**: el personaje camina
con el brazo derecho levantado y las manos parecen **desconectadas** de los
brazos.

→ `RagdollCharacter.update_hand_targets()` lo delega en
`ArmIK.update_targets(punto, click_izq, click_der, dt)`: con el ratón
soltado la influencia baja a 0 (los brazos siguen al clip); con el ratón
pulsado sube a 1; y el brazo que **no** agarra NO se estira (su objetivo es
su propia mano).

El estado de los botones se sondea en `_physics_process` (el input sintético
`Input.action_press` no dispara eventos, así que con el solo `_input` los
brazos no se estiraban nunca).

### 4quater-bis. ESTADO MEDIDO (2026-11-03)

| Métrica | Antes (ley PD por torque) | Ahora (servo absoluto) |
|---|---|---|
| `up_col` (verticalidad de la columna) | **−0,9** (invertida) | **0,95** |
| `pel_y` (altura de la pelvis) | 0,26 → se hundía | **0,75 estable** |
| Error del muslo | 40-60° | **0-1,3°** |
| Error del tronco | 20-29° | 1-7° |
| ω del cuerpo | 40 rad/s (trompo) | **0,2 rad/s** |
| Rig de referencia (10 huesos) | — | pelvis 1,63 m constante, ω 0,1 |

**Pendiente honesto:** los pies siguen con ~65° de error de orientación (el
collider del pie es una cápsula sobre un hueso inclinado 38°) y las manos con
~70°. El torso y las piernas (lo que sostiene al personaje) están resueltos.
