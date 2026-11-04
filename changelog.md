# Changelog — Tripofobia

Registro de iteraciones grandes completadas. Los detalles técnicos y las MEDIDAS
viven en `AGENTS.md` (memoria viva del proyecto); aquí va el qué y el cuándo.


---

## 2026-11-03 - Ragdoll: los huesos fisicos pasan a la ESCENA (regla dura)

**Que:** el `RagdollSkeleton` ya **no crea ni un solo `PhysicalBone3D`**. Los 21
huesos del Shiba (con su collider, `transform`, `body_offset`, `joint_offset`,
masa y tipo de joint) van **authorados en `src/player/shiba_player.tscn`**, como
hijos del `Skeleton3D`, igual que en la referencia `ragdoll_character.tscn`.

**Por que (medido):** el runtime que los creaba dejaba la escena sin datos
(invisible en el editor, offsets calculados a mano) y el personaje se caia de
cabeza: la columna invertida, la cabeza 0,55 m por debajo de la pelvis y la
malla retorcida.

**Lo que se arreglo de paso (todo medido):**
- El cuerpo va a **media hueso** (como hace el editor): el joint une el final
  del padre con la cabeza del hijo en vez de unir cabeza con cabeza.
- `PoseMirror` deshace el `body_offset` al copiar la pose (la malla ya no se
  deforma).
- El balance ancla su altura objetivo al **suelo** (raycast) y no a los pies:
  antes, al caer de espaldas, la captura nunca ocurria y el ragdoll se quedaba
  tumbado boca arriba para siempre.
- El `upright` ya puede corregir un volteo de 180 grados (el eje de correccion
  se anulaba) y su torque se topa por la inercia del torso.
- El PD es **por torque**, con amortiguamiento **critico** por cuerpo y error
  **relativo al padre**; la ganancia del rig va en el torque, no en la rigidez.
- El rig del Shiba tiene masas realistas (~33 kg) y colliders de torso.
- La cabeza tiene su **propio tipo de joint** (cono 90/100, como la
  referencia).

**Estado:** test automatico **13/13**; los 21 huesos con joint (0 sueltos); el
personaje se levanta del suelo y camina. **Pendiente:** la columna no se
mantiene recta en reposo permanente (queda en U tras aterrizar); el siguiente
paso es barrer el reparto de `pd_gain` por eslabon y el `max_angular_accel`
de la columna con el rig nuevo.

**Documentacion:** §REGLA DURA en `AGENTS.md`; trampas T18-T24 y §4ter
(estado medido) en `meta/docs/Sistema_Animacion_Ragdoll.md`.---

## 2026-11-03 — Ragdoll: tres bugs de fondo (joints, marcos, balance)

**Qué:** el ragdoll estaba roto en tres capas y NADIE las separaba: los
**joints no existían**, los **marcos** (mundo vs relativa del esqueleto)
estaban mezclados, y el **balance capturaba su objetivo en el aire**.

**Los tres fixes (todos con medida en el doc, T12–T17):**

1. **Joints nunca creados.** El joint de un `PhysicalBone3D` se crea en
   `_ready()` contra el cuerpo del PADRE. Los huesos se autorhabían fuera del
   esqueleto → el joint jamás se creaba y el ragdoll era un saco de huesos
   sueltos (medido: la columna se abría **0,8 m** entre padre e hijo).
   → Los cuerpos se crean **en runtime dentro del simulador**, padre antes
   que hijo (índice de hueso ascendente) y con todo configurado antes de
   `add_child`. Nada authored en la escena.
2. **Marcos mezclados.** `get_bone_global_pose()` es **relativa al esqueleto,
   NO al mundo** (la propia doc lo dice); el servidor de física devuelve
   MUNDO; y las dos instancias del GLB llevan transformaciones distintas
   (180° de flip). → El PD trabaja en MUNDO; el espejador convierte a
   relativa del esqueleto físico antes de `set_bone_global_pose`.
3. **Balance inerte y objetivo en el aire.** Solo la pelvis era grupo
   `column` y el BalanceController excluye el hueso-cuerpo → `apply()`
   salía en silencio sin hacer NADA. Además la altura objetivo se capturaba
   en el primer tick de animación (spawn en el aire: 2,42 m) o con el pie a
   0,45 m del suelo → personaje colgado en el aire con la cabeza en el suelo.
   → `column` repartida por la cadena cabeza→cuerpo; captura **perezosa**
   en el primer contacto con el pie de verdad abajo (< 0,3 m).

**De paso:** masa = volumen (suma 50 kg), soporte del hueso → `pd_gain`
(`pd_gain_max = 12`) en vez de inflar la masa (216 kg); el PD vuelve a
**torque** para sostener contra la gravedad.

**Medido:** el personaje **cae desde 1,1 m y queda de pie** (pelvis ~0,7–0,9 m,
columna erguida). Test automático **13/13**. Captura:
`tests/ragdoll/shots/shiba_3persona.png`. El juego spawnea de pie en el suelo
(ahí se sostiene sin drama).

---

## 2026-11-03 — Biblioteca del ragdoll (`src/ragdoll/`) + forge automático

**Qué:** el sistema de ragdoll deja de ser un monolito de 1480 líneas y pasa a ser
una **librería** con componentes sueltos, más un **forge** que genera el rig y
la escena de un modelo sin escribir código.

**La librería (`src/ragdoll/`)** — una responsabilidad por componente:
`RagdollRig`/`RagdollBone` (los datos), `RagdollSkeleton` (cuerpos y joints),
`RagdollMotor` (el PD), `PoseMirror`, `AnimationDriver`, `HeadLook`, `ArmIK`,
`FpClip`, `BalanceController`, `RagdollCharacter` (la raíz) y
`RagdollSceneBuilder` (construye la escena).

**El forge** (`tools/ragdoll_forge/forge.gd`): mide el modelo y genera
`RagdollRig` + escena. Deduce solo lo que antes se hacia a mano y mal:
los **huesos puente** (los que faltan para que la cadena de articulaciones esté
completa), los colliders (del origen del hueso al de su hijo), las **masas
proporcionales a la carga que soporta** y la cadena IK de los brazos.
`RigReport` valida un rig y explica qué falta.

**Documentación:** `meta/docs/Sistema_Animacion_Ragdoll.md` (normativo: la
arquitectura, el PD con sus números y las 17 trampas medidas de Godot/Box3D),
indexado en `AGENTS.md` §📚 RAGDOLL, e índice de la librería en
`src/ragdoll/README.md`.

**Bugs de fondo encontrados por el camino** (todos con su medida en el doc):
`AnimationTree.active` no se serializa · el `root_node` del AnimationMixer
tiene que ser un ancestro · el `AnimationPlayer` hay que cablearlo (el modelo
trae el suyo) · el PD por velocidad hace salir disparado al ragdoll · el error
de orientación va en axis-angle · la masa decide si el personaje se aguanta.

**Estado:** el Shiba se mantiene de pie y el PD lleva torso, cabeza y piernas a
la pose. Test automático **13/13** (tras los fixes de joints, marcos y balance —
ver entrada siguiente).

---

## 2026-11-03 — Shiba: jugador ragdoll completo (cabeza que mira + 3ª persona)

**Qué:** `src/player/shiba_player.tscn` pasa de "instancia del GLB con clips" a
**jugador ragdoll completo**: doble esqueleto (físico + animado), 21 cuerpos físicos
con sus colliders, cabeza que sigue a la cámara y modo 3ª persona (tecla V).

**Cómo:**
- Los **21 cuerpos físicos se crean EN RUNTIME** dentro del simulador (padre
  antes que hijo; nada authored en la escena — la versión "authorada en
  `HuesosFisicos/`" del mismo día **no tenía joints** y se descartó; ver la
  entrada de los tres bugs de fondo).
- El PD pasa de **escribir velocidad angular** a **aplicar torque** (Box3D), con el
  error de orientación en **axis-angle** y masas por vértebra.
- `AnimationTree` con `root_node` válido y `active` activado en runtime.

**Medido:** test automático `tests/ragdoll/shiba_test.tscn` **13/13 ✓**. Con
`body_debugger`: pecho 2°, cabeza 4°, brazo 17°, mano 9°. Personaje **de pie con los
pies en el suelo** (pie y=0,10 · pelvis 0,55 · cabeza 1,31). La cabeza gira 41° con
la cámara y la 3ª persona mide 3,66 m.

**Bugs de fondo encontrados (todos medidos,详见 AGENTS.md):**
1. `AnimationTree.active` no se serializa → la animación nunca llegaba al esqueleto.
2. `root_node` del AnimationMixer inválido → las pistas no resolvían.
3. Cadena de cuerpos físicos rota en 5 puntos → los brazos iban sueltos del pecho.
4. El PD por velocidad embalsaba el ragdoll (salía disparado).
5. `_anim_pose_cache` congelado → los brazos se quedaban en T.

**Pendiente:** controlador de balance (el personaje queda algo agachado) y el twist
de la clavícula.

## 2026-11-03 — RAGDOLL: la ley de control, el test canónico y los brazos

**El fallo de fondo era la LEY de control.** La librería había sustituido el
servo de velocidad con objetivo absoluto (el del proyecto de referencia, el
único que aguanta con Box3D) por un PD por torque con error relativo al
padre, pares, inercias de subárbol y un controlador de balance aparte.
Medido: la pelvis giraba a 40 rad/s y el personaje se volcaba.

**Qué se ha hecho:**

- `ragdoll_motor.gd`: servo de velocidad con objetivo **absoluto en mundo**
  (k=3000, c=80, tope de 40 rad/s). El tope de 6 rad/s era el que hacía que
  el personaje se viera "aguado" (el servo no podía girar un hueso grande en
  un frame).
- `ragdoll_character.gd`:
  - el balance controller **desactivado** (le devolvía a la pelvis el par de
    todos sus hijos);
  - el apoyo se calcula con los **colliders** y no con los orígenes de los
    huesos (el collider va a media hueso: nacía dentro del suelo y el solver
    lo expulsaba de una patada — el pie salía a 13 rad/s);
  - el **yaw del cuerpo** corregido (`_calibrar_rumbo`): el modelo mira a +Z
    y la cámara a -Z, así que el personaje andaba **de espaldas**
    (medido: `dot(frente, cámara) = -1.000` → ahora `+1.000`);
  - el cuerpo **sigue a la cámara** por defecto (`body_follows_camera`), como
    el script original;
  - **`update_hand_targets()`**: el puntero lo llama por duck typing; sin ese
    método el IK se quedaba con influencia 1 y los brazos se estiraban
    siempre (brazo derecho levantado, manos "desconectadas").
- `shiba_rig_config.tres` + `shiba_player.tscn`: **reparto de masas** medido
  (tronco ligero, piernas pesadas) y colliders coherentes con el rig.
- `tools/ragdoll_playground/`: ahora es el **TEST CANÓNICO** del ragdoll
  (telemetría real del servidor de física y veredicto).

**Medido (Shiba, 5 s):** pelvis 0,75 m estable · columna 0,95 · error del
muslo 0-1,3° · tronco y piernas 1-13° · ω del cuerpo 0,2 rad/s.
Con el rig de referencia: pelvis 1,63 m constante, ω 0,1.

**Pendiente:** los pies siguen con ~65° de error de orientación (el collider
del pie es una cápsula sobre un hueso inclinado 38°) y las manos con ~70°
(el IK apagado las deja seguir al clip, pero la质量 del collider es justa).
