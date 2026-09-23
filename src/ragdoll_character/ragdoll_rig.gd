extends Resource
class_name RagdollRigConfig
## Configuracion del rig para un modelo concreto (Character.glb, coneja.glb, ...).
##
## Centraliza TODO lo que el script del ragdoll consulta para NO tener que
## hardcodear nombres de huesos. Asi, agregar un modelo nuevo = crear un
## `.tres` con este Resource y pasarselo al personaje.
##
## Default = rig viejo de Character.glb (compatibilidad 100% con la escena
## existente). La coneja tiene su propio `.tres` que override estos campos.

## ---- Hueso fisico que recibe la velocidad del cuerpo (la "capsula" del
## personaje). El script mueve este hueso para caminar; los demas lo siguen
## por el PD contra el Animated.
@export var body_bone_name: StringName = &"Body"

## Hueso al que se ancla la camara (su origen marca la posicion de la
## cabeza; el script suaviza hacia alla con `head_distance`).
@export var head_bone_name: StringName = &"Head"

## ---- Cadenas IK de los brazos (raiz -> medio -> extremo).
## Se aplican a `arm_ik` (TwoBoneIK3D) y se usan para medir el alcance
## real del brazo con `_place_poles_and_measure()`.
@export var ik_arm_left := {"root": &"LArm1", "mid": &"LArm2", "end": &"LArm2.001"}
@export var ik_arm_right := {"root": &"RArm1", "mid": &"RArm2", "end": &"RArm2.001"}

## Hueso fisico al que se ancla el `LGrabArea` / `RGrabArea`. Por diseno
## historico es el ANTEBRAZO (no la mano: las falanges no son PhysicalBone3D).
## En la coneja, las colisiones de agarre iran a `brazo2_L` (antebrazo),
## NO a `mano_L` (que es el hueso siguiente). El IK ya apunta a `mano_L`
## como end-effector, asi que el agarre queda justo en la muneca real.
@export var grab_bone_left_name: StringName = &"LArm2"
@export var grab_bone_right_name: StringName = &"RArm2"

## ShapeCast3D que chequea si el pie izquierdo toca el suelo. Se busca
## como hijo del hueso fisico `LLeg2`. Si tu rig tiene otro hueso "final"
## de la pierna, sobreescribilo aca.
@export var on_floor_left_bone_name: StringName = &"LLeg2"
@export var on_floor_right_bone_name: StringName = &"RLeg2"

## ---- Filtros de brazos para el PD.
## El script detecta "este hueso es brazo" mirando si su nombre contiene
## `arm_name_token` (substring independiente del lado) Y NO contiene la
## exclusion de pierna `leg_name_token`. Asi matchea tanto `LArm1`/`RArm1`
## (rig viejo) como `brazo1_L`/`brazo1_R` (rig coneja).
@export var arm_name_token: String = "Arm"
@export var leg_name_token: String = "Leg"

## ---- Filtros del lean corporal.
## `lean_share_body` se aplica a huesos cuyo nombre TERMINA en este string.
## `lean_share_head` igual. Asi `Head` matchea pero `Head.001` no.
@export var lean_body_suffix: String = "Body"
@export var lean_head_suffix: String = "Head"

## ---- Nombres de los huesos que el AnimationTree tiene que animar.
## El BlendSpace de direccion de agarre usa 3 clips; el blend de piernas
## se alimenta de un `Walk`. Estos nombres DEBEN existir como clips en el
## `AnimationPlayer`. Si la coneja no los tiene bakeados, quedan vacios
## y el personaje se queda en pose T.
@export var clip_idle: StringName = &"idle"
@export var clip_walk: StringName = &"Walk"
@export var clip_grab_lower: StringName = &"grab_lower"
@export var clip_grab_middle: StringName = &"grab_middle"
@export var clip_grab_upper: StringName = &"grab_upper"
## Clip futuro: dedos cerrandose para "sostener". Se conecta a un trigger
## cuando se confirme una grab; mientras el AnimationTree no lo use, queda
## en "" y el sistema lo ignora silenciosamente.
@export var clip_grab_hold: StringName = &""

## Tracks que el AnimationTree debe FILTRAR del clip idle para que el blend
## de brazos no los pise. Por defecto: torso + hombros + caderas. En la
## coneja seran: espina*, cuello, cabeza, hombro_*, pierna1_*.
@export var idle_filter_bones: PackedStringArray = PackedStringArray([
	"Armature/Skeleton3D:Body",
	"Armature/Skeleton3D:LArm1", "Armature/Skeleton3D:LHip",
	"Armature/Skeleton3D:RArm1", "Armature/Skeleton3D:RHip",
])
## Tracks que la zona de "grab" del AnimationTree debe FILTRAR del clip idle
## para que los brazos puedan hacer blend. Se computan al setup.

## Tracks que el AnimationTree debe FILTRAR de los clips de grab para que
## NO muevan las piernas (las piernas solo las maneja el walk).
@export var grab_filter_bones: PackedStringArray = PackedStringArray([
	"Armature/Skeleton3D:LLeg1", "Armature/Skeleton3D:LLeg2", "Armature/Skeleton3D:LLeg2.001",
	"Armature/Skeleton3D:RLeg1", "Armature/Skeleton3D:RLeg2", "Armature/Skeleton3D:RLeg2.001",
])

## Capsulas de los colliders fisicos. Los tamanos del rig viejo son los
## que estaban hardcoded en `ragdoll_character.tscn`; se extraen aca para
## que la coneja los pueda sobreescribir sin tocar el .tscn.
@export var body_shape := {"size": Vector3(1.165, 1.2, 0.68)}
@export var arm_capsule := {"radius": 0.174, "height": 0.378}
@export var forearm_capsule := {"radius": 0.136, "height": 0.759742}
@export var thigh_capsule := {"radius": 0.202, "height": 0.484}
@export var calf_capsule := {"radius": 0.148, "height": 0.533628}
@export var head_capsule := {"radius": 0.489, "height": 1.168}
@export var grab_sphere := {"radius": 0.18}

## ---- Parametros de masa y rigidez por hueso.
## Pesos relativos. El script los normaliza para que sumen 1 al primer uso.
## Por defecto: el torso carga casi todo; las piernas lo justo para que
## el PD no pele contra el `body`; los brazos son 0 (los maneja el IK).
@export var mass_body: float = 10.0
@export var mass_head: float = 2.0
@export var mass_arm_root: float = 0.5
@export var mass_arm_mid: float = 0.5
@export var mass_arm_end: float = 0.5
@export var mass_leg_root: float = 2.0
@export var mass_leg_mid: float = 1.0