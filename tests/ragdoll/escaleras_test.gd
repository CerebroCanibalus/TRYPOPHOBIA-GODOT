extends Node3D
## BANCO DE ESCALERAS del ragdoll (2026-11-04).
##
## Prueba lo unico que el playground (plano) no puede medir: si la capsula
## (`Logic`) SUBE escalones de 20 / 30 / 40 cm y si el ragdoll la acompania
## en altura.
##
## Ejecutar:
##   godot --headless --path <proj> "res://tests/ragdoll/escaleras_test.tscn"
##
## Imprime un veredicto PASS/FAIL por escalon y sale con exit 0/1.

## Cada escalon: `z` de su cara de subida (el personaje camina hacia -Z) y
## la altura de su peldano. Son las tres que pidio el General.
const ESCALONES := [
	{ "nombre": "20cm", "z": 3.0, "alto": 0.2 },
	{ "nombre": "30cm", "z": 2.0, "alto": 0.3 },
	{ "nombre": "40cm", "z": 1.0, "alto": 0.4 },
]
## Fondo de cada peldano (debe coincidir con `make_escaleras.gd`).
const FONDO := 1.0
## Segundos de reposo antes de andar (deja que el ragdoll se asiente).
const REPOSO := 1.5
## Segundos andando antes del veredicto.
const MARCHA := 14.0

var _personaje: Node3D = null
var _logic: CharacterBody3D = null
var _pelvis: PhysicalBone3D = null
var _t := 0.0
var _andando := false
var _logrado := {}      ## nombre -> true si paso el escalon
var _max_y := {}        ## nombre -> altura maxima del Logic al pasarlo
var _max_y_pelvis := {} ## nombre -> altura maxima de la pelvis al pasarlo
var _terminado := false


func _ready() -> void:
	for c in find_children("*", "RagdollCharacter", true, false):
		_personaje = c as Node3D
		break
	if _personaje == null:
		push_error("[escaleras] no hay RagdollCharacter en la escena")
		get_tree().quit(1)
		return
	_logic = _personaje.get_node_or_null("Logic") as CharacterBody3D
	for b in _personaje.find_children("*", "PhysicalBone3D", true, false):
		if String((b as PhysicalBone3D).bone_name) == "spine":
			_pelvis = b as PhysicalBone3D
			break
	for e in ESCALONES:
		_logrado[e["nombre"]] = false
		_max_y[e["nombre"]] = 0.0
		_max_y_pelvis[e["nombre"]] = 0.0
	print("===== BANCO DE ESCALERAS (ragdoll) =====")
	print("[escaleras] personaje=%s logic=%s pelvis=%s" % [
		_personaje.name, str(_logic != null), str(_pelvis != null)])


func _physics_process(delta: float) -> void:
	if _terminado:
		return
	_t += delta
	if not _andando and _t >= REPOSO:
		_andando = true
		Input.action_press("move_forward")
		print("[escaleras] andando hacia -Z")
	if not _andando:
		return
	if _logic == null:
		return
	var p := _logic.global_position
	var y_pelvis := 0.0
	if _pelvis != null:
		y_pelvis = RagdollMotor.body_transform(_pelvis).origin.y
	for e in ESCALONES:
		var nom: String = e["nombre"]
		# Franja del escalon: de su cara de subida hacia -Z.
		if p.z <= float(e["z"]) + 0.05 and p.z >= float(e["z"]) - FONDO:
			_max_y[nom] = maxf(float(_max_y[nom]), p.y)
			_max_y_pelvis[nom] = maxf(float(_max_y_pelvis[nom]), y_pelvis)
			if p.y > float(e["alto"]) - 0.06:
				_logrado[nom] = true
	if _t >= REPOSO + MARCHA:
		Input.action_release("move_forward")
		_terminado = true
		_veredicto()
		return
	# Telemetria (cada segundo): sin esto, un FALLO no dice POR QUE.
	if int(_t * 10.0) % 10 == 0 and int(_t) != int(_t - delta):
		print("[esc] t=%4.1f logic=%s pelvis=%s" % [_t,
			str(p.snapped(Vector3(0.01, 0.01, 0.01))),
			str(_pos_pelvis().snapped(Vector3(0.01, 0.01, 0.01)))])


func _pos_pelvis() -> Vector3:
	if _pelvis == null:
		return Vector3.ZERO
	return RagdollMotor.body_transform(_pelvis).origin


func _veredicto() -> void:
	print("===== VEREDICTO ESCALERAS =====")
	var fallos := 0
	for e in ESCALONES:
		var nom: String = e["nombre"]
		var ok: bool = _logrado[nom]
		if not ok:
			fallos += 1
		print("  %-5s alto=%.2f  %s   logic_y_max=%.3f  pelvis_y_max=%.3f" % [
			nom, float(e["alto"]), "PASS" if ok else "FALLO",
			float(_max_y[nom]), float(_max_y_pelvis[nom])])
	if _logic != null:
		print("  final: pos=%s  floor=%s" % [
			str(_logic.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			str(_logic.is_on_floor())])
	print("RESULTADO: %s" % ("TODO OK (%d escalones)" % ESCALONES.size() \
		if fallos == 0 else "FALLAN %d de %d" % [fallos, ESCALONES.size()]))
	get_tree().quit(0 if fallos == 0 else 1)
