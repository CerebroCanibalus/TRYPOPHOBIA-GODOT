extends Resource
class_name RagdollRig
## Configuracion completa de UN rig de ragdoll (un modelo + como se
## convierte en personaje).
##
## TODO lo que el runtime consulta vive aqui: nombres de huesos, masas,
## limites de articulacion, clips y cadenas de IK. El codigo NO debe
## hardcodear NINGUN nombre de hueso: asi, poner un modelo nuevo en el
## sistema es escribir este Resource y nada mas.
##
## Generar este Resource a mano es tedioso: para eso esta `RigForge`, que
## lo construye solo a partir del modelo (mide la jerarquia, deduce los
## colliders, las masas por carga y avisa de los huesos "puente" que
## faltan para que la cadena de articulaciones este completa).

## ---- MODELO -------------------------------------------------------------

## Ruta del modelo (.glb) que se instancia en la escena.
@export_file("*.glb") var model_path := ""

## Ruta del Skeleton3D DENTRO del modelo. El Shiba lo tiene en
## "metarig/Skeleton3D" y la coneja en "Armature/Skeleton3D".
@export var skeleton_path_in_model := ""

## -----------------------------------------------------------------------
## ---- HUESOS CLAVE -------------------------------------------------------
## -----------------------------------------------------------------------

## Hueso fisico que recibe la velocidad del cuerpo (la "capsula" del
## personaje). El script mueve este hueso para caminar; los demas lo siguen
## por el PD contra el Animated.
@export var body_bone_name: StringName = &"Body"

## Hueso al que se ancla la camara (su origen marca la posicion de la
## cabeza; el script suaviza hacia alla con `head_distance`).
@export var head_bone_name: StringName = &"Head"

## Hueso fisico al que se ancla el `LGrabArea` / `RGrabArea`. Por diseno
## historico es el ANTEBRAZO (no la mano: las falanges no son
## PhysicalBone3D).
@export var grab_bone_left_name: StringName = &"LArm2"
@export var grab_bone_right_name: StringName = &"RArm2"

## ShapeCast3D que chequea si el pie izquierdo toca el suelo.
@export var on_floor_left_bone_name: StringName = &"LLeg2"
@export var on_floor_right_bone_name: StringName = &"RLeg2"

## -----------------------------------------------------------------------
## ---- CADENAS IK ---------------------------------------------------------
## -----------------------------------------------------------------------

## Cadenas IK de los brazos (raiz -> medio -> extremo). Se aplican al
## `TwoBoneIK3D` y se usan para medir el alcance real del brazo.
@export var ik_arm_left := {"root": &"LArm1", "mid": &"LArm2", "end": &"LArm2.001"}
@export var ik_arm_right := {"root": &"RArm1", "mid": &"RArm2", "end": &"RArm2.001"}

## -----------------------------------------------------------------------
## ---- FILTROS POR NOMBRE (fallback cuando el hueso no tiene grupo) ------
## -----------------------------------------------------------------------

## El script detecta "este hueso es brazo" mirando si su nombre contiene
## `arm_name_token` Y NO contiene `leg_name_token`.
@export var arm_name_token: String = "Arm"
@export var leg_name_token: String = "Leg"
## Token EXTRA que tambien marca un hueso como brazo (el Shiba tiene
## "hand.L", que NO contiene "arm").
@export var arm_name_token_extra: String = ""

## `lean_share_body` se aplica a huesos cuyo nombre TERMINA en este string.
@export var lean_body_suffix: String = "Body"
@export var lean_head_suffix: String = "Head"

## -----------------------------------------------------------------------
## ---- CLIPS --------------------------------------------------------------
## -----------------------------------------------------------------------
## Estos nombres DEBEN existir como clips en la `AnimationLibrary`.

## Clip de reposo (el que se reproduce cuando no se camina).
@export var clip_idle: StringName = &"idle"
## Clip de paseo (se mezcla con el de reposo segun la velocidad).
@export var clip_walk: StringName = &"Walk"
## Los tres clips de la BlendSpace de direccion (por pitch de camara).
@export var clip_grab_lower: StringName = &"grab_lower"
@export var clip_grab_middle: StringName = &"grab_middle"
@export var clip_grab_upper: StringName = &"grab_upper"
## Clip futuro: dedos cerrandose para "sostener".
@export var clip_grab_hold: StringName = &""

## -----------------------------------------------------------------------
## ---- MIRADA DE CABEZA ---------------------------------------------------
## -----------------------------------------------------------------------

## Huesos que participan en el giro de cabeza, de la BASE a la PUNTA.
## Cada uno recibe la fraccion del giro indicada en `head_look_weights`.
## El peso se ACUMULA hacia la punta: el ultimo de la lista recibe el
## 100% del giro y los anteriores la parte que les toca (asi el cuello
## gira un poco y la cabeza el resto, como una persona de verdad).
@export var head_look_bones: PackedStringArray = PackedStringArray(["Head"])
## Peso POR HUESO (fraccion del giro total). Se normalizan para que sumen 1.
@export var head_look_weights: PackedFloat32Array = PackedFloat32Array([1.0])

## -----------------------------------------------------------------------
## ---- HUESOS FISICOS -----------------------------------------------------
## -----------------------------------------------------------------------
## La lista TIENE que ser una CADENA COMPLETA: el joint de un
## `PhysicalBone3D` se crea contra el cuerpo del PADRE del hueso, asi que
## si el padre no tiene cuerpo, el joint no se crea y el hueso queda
## suelto (no tira de sus hijos). `RigForge` detecta los huecos.
@export var physical_bones: Array[RagdollBone] = []

## -----------------------------------------------------------------------
## ---- COLLIDERS DE REFERENCIA (para los rigs que no declaran huesos) -----
## -----------------------------------------------------------------------
## Tamnos de las capsulas de los cuerpos. Se dejan por compatibilidad con
## los rigs antiguos, que no declaran `physical_bones`.

@export var body_shape := {"size": Vector3(1.165, 1.2, 0.68)}
@export var arm_capsule := {"radius": 0.174, "height": 0.378}
@export var forearm_capsule := {"radius": 0.136, "height": 0.759742}
@export var thigh_capsule := {"radius": 0.202, "height": 0.484}
@export var calf_capsule := {"radius": 0.148, "height": 0.533628}
@export var head_capsule := {"radius": 0.489, "height": 1.168}
@export var grab_sphere := {"radius": 0.18}

## -----------------------------------------------------------------------
## ---- MASAS DE REFERENCIA (por grupo) ------------------------------------
## -----------------------------------------------------------------------
## Se usan cuando el rig NO declara `physical_bones` (rigs antiguos).

@export var mass_body: float = 10.0
@export var mass_head: float = 2.0
@export var mass_arm_root: float = 0.5
@export var mass_arm_mid: float = 0.5
@export var mass_arm_end: float = 0.5
@export var mass_leg_root: float = 2.0
@export var mass_leg_mid: float = 1.0


## Devuelve el `RagdollBone` de un hueso, o null.
func bone(nombre: StringName) -> RagdollBone:
	for b in physical_bones:
		if b.bone_name == nombre:
			return b
	return null


## Nombres de todos los huesos con cuerpo, en orden de la tabla.
func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	for b in physical_bones:
		out.append(String(b.bone_name))
	return out


## Devuelve el grupo del hueso ("column" / "arm" / "leg" / "") o, si no lo
## declara, lo deduce por los tokens de nombre.
func group_of(bone_name: StringName) -> String:
	var b := bone(bone_name)
	if b != null and b.group != "":
		return b.group
	var n := String(bone_name)
	if arm_name_token != "" and (n.contains(arm_name_token) \
			or (arm_name_token_extra != "" and n.contains(arm_name_token_extra))):
		if leg_name_token == "" or not n.contains(leg_name_token):
			return "arm"
	if leg_name_token != "" and n.contains(leg_name_token):
		return "leg"
	return ""
