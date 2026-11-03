# `src/ragdoll/` — Biblioteca del sistema de ragdoll

Todo lo que es **"ragdoll"** vive aquí, separado del juego. Un personaje
nuevo = un `RagdollRig` (que genera el forge) + una escena (que genera el
builder). **No se toca código.**

> Documento normativo con las trampas y la teoría: **`meta/docs/Sistema_Animacion_Ragdoll.md`**

## Estructura

```
src/ragdoll/
├── rig/                       DATOS (todo lo que se puede cambiar sin codigo)
│   ├── ragdoll_bone.gd        RagdollBone    un hueso: forma, masa, limites, grupo
│   ├── ragdoll_rig.gd         RagdollRig     el rig completo (un .tres)
│   ├── rig_forge.gd           RigForge       genera un rig desde un modelo
│   └── rig_report.gd          RigReport      valida un rig y explica que falta
├── runtime/                   COMPONENTES (una responsabilidad cada uno)
│   ├── ragdoll_skeleton.gd    RagdollSkeleton   cuerpos fisicos, simulator, joints
│   ├── ragdoll_motor.gd       RagdollMotor      el PD (torque + axis-angle)
│   ├── pose_mirror.gd         PoseMirror        fisico -> esqueleto visible
│   ├── animation_driver.gd    AnimationDriver   AnimationPlayer/Tree, clips, mezcla
│   ├── head_look.gd           HeadLook          la cabeza que sigue a la camara
│   ├── arm_ik.gd              ArmIK             IK de brazos (polos, alcance)
│   ├── fp_clip.gd             FpClip            recorte de 1a persona
│   └── balance_controller.gd  BalanceController el equilibrio
├── character/                 EL PERSONAJE
│   ├── ragdoll_character.gd   RagdollCharacter  raiz: input, movimiento, agarre
│   ├── ragdoll_camera.gd      camara en 1a/3a persona
│   ├── ragdoll_pointer.gd     puntero
│   └── pointer_reticle.gd     reticula
├── shaders/                   fp_body_clip.gdshader (+ _tex)
├── materials/                 fp_body_clip.tres
├── scenes/                    coneja_player.tscn, ragdoll_character.tscn
├── animations/                clips .res del rig viejo
├── models/                    Character.glb
└── tools/                     construct_coneja.gd, ragdoll_scene_builder.gd
```

## Poner un modelo nuevo

```bash
godot --headless --path <proj> -s res://tools/ragdoll_forge/forge.gd -- \
  --model=res://assets/players/mi_modelo.glb \
  --body=<hueso_pelvis> --head=<hueso_cabeza> \
  --hands=<mano_izq>,<mano_der> --feet=<pie_izq>,<pie_der> \
  --extra=<columna>,<cuello> \
  --mass=50 --name=MiPersonaje \
  --rig=res://src/ragdoll/rig/mi_rig.tres \
  --scene=res://src/player/mi_personaje.tscn
```

El forge **mide** el modelo, encuentra los **huesos puente** que faltan para
que la cadena de articulaciones esté completa, deduce los colliders y las
masas por carga, y deduce la cadena IK de los brazos. Imprime un informe y
**no guarda** si hay errores.

## Reglas de oro (medidas, no opinión)

1. El joint de un `PhysicalBone3D` **se crea en `_ready`** contra el cuerpo
   de su **padre**: si al entrar al árbol el padre no tiene cuerpo, el joint
   **nunca** se crea.
2. Los cuerpos se crean **en runtime dentro del simulador**, padre antes que
   hijo (índice de hueso ascendente) y con **todo configurado antes de
   `add_child`**. Nada de huesos físicos en la escena.
3. `AnimationTree.active` **no se serializa**: hay que activarlo en runtime.
4. El `root_node` del AnimationMixer tiene que ser un **ancestro** (la raíz del
   personaje), nunca `current_scene` (es `null` en headless).
5. El error de orientación va en **axis-angle**, no en euler.
6. El PD aplica **torque**, no velocidad angular (si no, el ragdoll sale
   disparado).
7. **Masa = volumen** (suma = peso real); lo que un hueso **soporta** es
   ganancia del PD (`pd_gain`). Meter la carga en la masa hincha el peso.
8. `get_bone_global_pose()` es **relativa al esqueleto, NO al mundo**: el PD
   trabaja en MUNDO (`anim.global_transform * pose` vs el cuerpo del
   servidor de física), y el espejo convierte a relativa del esqueleto
   físico para `set_bone_global_pose`.
9. El `Skin` del GLB hay que duplicarlo (es compartido entre las dos
   instancias).

El resto, con las medidas y el porqué, en
**`meta/docs/Sistema_Animacion_Ragdoll.md`**.
