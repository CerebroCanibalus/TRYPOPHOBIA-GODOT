extends Node
class_name HeadLook
## La MIRADA DE CABEZA: el cuerpo mira a donde camina y la CABEZA sigue a
## la camara.
##
## Modelo: el giro se reparte entre los huesos de la cadena de cuello (de
## la base a la punta) con pesos ACUMULADOS, para que el cuello gire un
## poco y la cabeza el resto (como una persona de verdad). El giro se
## SUAVIZA con una exponencial (estable a cualquier FPS) y se limita en
## yaw y pitch.
##
## Es una ENTRADA DE CONTROL al PD: lo que hace es modifyar la pose
## OBJETIVO del hueso, no la animacion.

@export var enabled := true
## Limite del giro horizontal (grados).
@export var yaw_max_degrees := 55.0
## Limite del giro vertical (grados).
@export var pitch_max_degrees := 30.0
## Tiempo de suavizado (segundos). 0 = sin suavizado.
@export var smoothing := 0.12

var rig: RagdollRig
var animated_skel: Skeleton3D
var camera_pivot: Node3D

var _yaw := 0.0
var _pitch := 0.0
var _yaw_target := 0.0
var _pitch_target := 0.0
## nombre de hueso -> peso ACUMULADO del giro.
var _weights: Dictionary = {}


func setup(p_rig: RagdollRig, p_skel: Skeleton3D, p_camera: Node3D) -> void:
	rig = p_rig
	animated_skel = p_skel
	camera_pivot = p_camera
	_setup_weights()


## Actualiza el objetivo de la mirada (yaw y pitch) y lo suaviza.
func update(delta: float) -> void:
	if not enabled or camera_pivot == null or animated_skel == null:
		return
	var model_fwd := animated_skel.global_transform.basis.z
	var cam_view := -camera_pivot.global_transform.basis.z
	var lim_y := deg_to_rad(yaw_max_degrees)
	_yaw_target = clampf(_signed_angle_up(model_fwd, cam_view), -lim_y, lim_y)
	var lim_p := deg_to_rad(pitch_max_degrees)
	_pitch_target = clampf(camera_pivot.rotation.x, -lim_p, lim_p)
	var a := 1.0
	if smoothing > 0.0:
		a = 1.0 - exp(-delta / smoothing)
	_yaw = lerp_angle(_yaw, _yaw_target, a)
	_pitch = lerpf(_pitch, _pitch_target, a)


## Aplica el giro al objetivo de un hueso (si es de la cadena del cuello).
func apply(bone: PhysicalBone3D, target: Transform3D) -> Transform3D:
	if not enabled or animated_skel == null:
		return target
	var w: float = _weights.get(bone.bone_name, 0.0)
	if is_zero_approx(w):
		return target
	var yaw := _yaw * w
	var pitch := _pitch * w
	if is_zero_approx(yaw) and is_zero_approx(pitch):
		return target
	var body_fwd := animated_skel.global_transform.basis.z
	var body_right := body_fwd.cross(Vector3.UP).normalized()
	if body_right.is_zero_approx():
		return target
	# Yaw primero (alrededor del UP del mundo) y luego pitch alrededor del
	# eje derecho YA girado: el gesto es "giro la cabeza y luego asiente".
	var q_yaw := Quaternion(Vector3.UP, yaw)
	var q_pitch := Quaternion(q_yaw * body_right, pitch)
	var q := q_pitch * q_yaw
	return Transform3D(Basis(q) * target.basis, target.origin)


## El yaw actual (la cabeza mira hacia aqui). Lo usa el cuerpo para
## "alcanzar" con el torso cuando la cabeza se pasa de limite.
func current_yaw() -> float:
	return _yaw


## Los pesos por hueso (para diagnostico).
func debug_weights() -> Dictionary:
	return _weights


## Pesos ACUMULADOS de la cadena de cuello: el ultimo hueso de la lista
## recibe el 100% del giro y los anteriores la parte que les toca.
func _setup_weights() -> void:
	_weights.clear()
	if rig == null:
		return
	var bones := rig.head_look_bones
	var weights := rig.head_look_weights
	if bones.is_empty():
		return
	var raw: Array[float] = []
	var total := 0.0
	for i in bones.size():
		var w: float = weights[i] if i < weights.size() else 1.0
		raw.append(w)
		total += absf(w)
	if total <= 0.0:
		return
	var acc := 0.0
	for i in bones.size():
		acc += raw[i] / total
		_weights[bones[i]] = acc


## Angulo con signo (rad) entre dos direcciones, alrededor del eje UP.
static func _signed_angle_up(from: Vector3, to: Vector3) -> float:
	var f := from.normalized()
	var t := to.normalized()
	var axis := f.cross(t)
	if axis.is_zero_approx():
		return 0.0
	var s := axis.cross(f).dot(t)
	return atan2(s, f.dot(t))
