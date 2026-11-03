extends Node3D

## PRUEBA AUTOMATICA y JUGABLE del jugador Shiba (ragdoll).
##
## En modo automatico (SHIBA_TEST=1 o el CLI) comprueba lo que de verdad
## importa:
##   1. El ragdoll arranca (simulador, huesos fisicos, IK, AnimationTree).
##   2. El personaje se MUEVE al pulsar adelante (no se queda clavado).
##   3. La CABEZA gira con el raton (la nueva funcionalidad).
##   4. El modo 3a persona aleja la camara.
##   5. El AnimationTree mezcla los clips (piernas al caminar).
## Y en modo manual (F5) es la escena jugable: raton capturado (Esc lo
## suelta), salud 300 y stamina 50 en las barras, de Yuki Romero.
##
## Uso: Godot --headless --path <proj> res://tests/ragdoll/shiba_test.tscn
##      con SHIBA_TEST=1 para el modo automatico.

@export var auto_quit_seconds := 0.0
@export var capture_mouse_on_ready := false

@onready var shiba: Node3D = $Shiba
@onready var salud_bar: ProgressBar = $HUD/Salud
@onready var stamina_bar: ProgressBar = $HUD/Stamina

var _t := 0.0
var _fails := 0
var _checks := 0
var _head_yaw0 := 0.0
var _head_yaw1 := 0.0
var _cam_pos_far := 0.0
var _leg_pose0 := Vector3.ZERO
var _leg_pose1 := Vector3.ZERO
var _pos0 := Vector3.ZERO
var _phase := 0
var _start_ms := 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	print("===== PRUEBA SHIBA =====")
	var cam := shiba.get_node_or_null("CameraPivot") as Node3D
	var pivot_script: Script = cam.get_script()
	print("[test] camara=", cam, " script=", pivot_script)
	if capture_mouse_on_ready:
		get_window().grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["OK" if ok else "FALLO", msg])


func _physics_process(delta: float) -> void:
	_t += delta
	var cam := shiba.get_node_or_null("CameraPivot") as Node3D
	if cam == null:
		return

	# --- Fase 1: el rig arranca ------------------------------------------
	if _phase == 0 and _t > 0.5:
		_phase = 1
		var bones := 0
		for b in shiba.find_children("*", "PhysicalBone3D", true, false):
			bones += 1
		_check(bones == 21, "huesos fisicos = %d (esperado 21)" % bones)
		# El simulador lo crea Godot con nombre AUTOGENERADO (@PhysicalBoneSimulator3D@N):
		# se busca por TIPO, nunca por nombre.
		var sim: Node = null
		for n in shiba.find_children("*", "PhysicalBoneSimulator3D", true, false):
			sim = n
			break
		_check(sim != null, "simulador de huesos presente")
		var at := shiba.find_child("AnimationTree", true, false) as AnimationTree
		_check(at != null and at.tree_root != null, "AnimationTree con arbol")
		if at:
			_check(at.get("parameters/walking/blend_amount") != null, "parametro walking/blend_amount existe")
			_check(at.get("parameters/grab_dir/blend_position") != null, "parametro grab_dir/blend_position existe")
		var ik := shiba.find_child("ArmIK", true, false) as TwoBoneIK3D
		_check(ik != null and ik.setting_count == 2, "IK con 2 cadenas")
		# Tope de la cabeza
		_head_yaw0 = _cabeza_yaw()

	# --- Fase 2: camina ---------------------------------------------------
	if _phase == 1 and _t > 1.0:
		_phase = 2
		_leg_pose0 = _pierna_pose()
		var body := shiba.find_child("Physical Bone spine", true, false) as PhysicalBone3D
		_check(body != null, "hueso cuerpo 'spine' encontrado")
		if body:
			_pos0 = body.global_position
		Input.action_press("move_forward")
		print("[test] andando hacia delante...")

	# --- Fase 3: la cabeza gira con el raton ------------------------------
	if _phase == 2 and _t > 3.0:
		_phase = 3
		Input.action_release("move_forward")
		# Giro de camara de 60 grados a la derecha.
		cam.rotation_degrees.y -= 60.0
		print("[test] girando la camara 60 grados...")

	if _phase == 3 and _t > 4.2:
		_phase = 4
		_head_yaw1 = _cabeza_yaw()
		var delta_giro := rad_to_deg(absf(_head_yaw1 - _head_yaw0))
		_check(delta_giro > 8.0, "la cabeza giro %.1f grados con la camara (esperado > 8)" % delta_giro)
		_leg_pose1 = _pierna_pose()
		var mov := _pierna_pose().distance_to(_leg_pose0)
		_check(mov > 0.01, "las piernas se movieron al andar (%.3f m)" % mov)
		var body := shiba.find_child("Physical Bone spine", true, false) as PhysicalBone3D
		if body:
			var avance := Vector2(body.global_position.x - _pos0.x, body.global_position.z - _pos0.z).length()
			_check(avance > 0.15, "el cuerpo avanzo %.2f m al andar" % avance)
		# 3a persona
		cam.call("toggle_third_person")
		_cam_pos_far = cam.global_position.distance_to(shiba.global_position)
		_check(cam.get("first_person") == false, "modo 3a persona activado")
		print("[test] camara en 3a persona")

	if _phase == 4 and _t > 5.0:
		_phase = 5
		# En 3a persona el PIVOTE se queda en la cabeza: la que se aleja es
		# la camara (hija del SpringArm).
		var cam3d := cam.get_node_or_null("SpringArm3D/Camera3D") as Node3D
		var cabeza := shiba.get_node_or_null("Physical/metarig/Skeleton3D") as Skeleton3D
		var ref := Vector3.ZERO
		if cabeza:
			var idx := cabeza.find_bone("spine.006")
			if idx >= 0:
				ref = cabeza.get_bone_global_pose(idx).origin
		_cam_pos_far = cam3d.global_position.distance_to(ref) if cam3d else 0.0
		_check(_cam_pos_far > 1.5, "la camara se alejo en 3a persona (%.2f m)" % _cam_pos_far)
		cam.call("toggle_third_person")
		_check(cam.get("first_person") == true, "vuelta a 1a persona")
		print("RESULTADO: %d/%d comprobaciones OK" % [_checks - _fails, _checks])
		if _fails > 0:
			print("RESULTADO: %d FALLOS" % _fails)

	var jugador := shiba as RagdollCharacter
	if salud_bar and jugador:
		salud_bar.value = jugador.health
	if stamina_bar and jugador:
		stamina_bar.value = jugador.current_stamina

	if auto_quit_seconds > 0.0 and (Time.get_ticks_msec() - _start_ms) >= int(auto_quit_seconds * 1000.0):
		print("RESULTADO: %d/%d comprobaciones OK" % [_checks - _fails, _checks])
		get_tree().quit()


## Yaw RELATIVO al pecho del hueso de cabeza (spine.006).
## El yaw global incluiria tambien el giro del cuerpo, y lo que se quiere
## medir es el giro de la CABEZA respecto al torso.
func _cabeza_yaw() -> float:
	var phys := shiba.get_node_or_null("Physical/metarig/Skeleton3D") as Skeleton3D
	if phys == null:
		return 0.0
	var i_cabeza := phys.find_bone("spine.006")
	var i_pecho := phys.find_bone("spine.003")
	if i_cabeza < 0 or i_pecho < 0:
		return 0.0
	var cabeza := phys.get_bone_global_pose(i_cabeza).basis.get_euler()
	var pecho := phys.get_bone_global_pose(i_pecho).basis.get_euler()
	return cabeza.y - pecho.y


## Posicion global de la tibia: si el walk cycle funciona, cambia.
func _pierna_pose() -> Vector3:
	var phys := shiba.get_node_or_null("Physical/metarig/Skeleton3D") as Skeleton3D
	if phys == null:
		return Vector3.ZERO
	var idx := phys.find_bone("shin.L")
	if idx < 0:
		return Vector3.ZERO
	return phys.get_bone_global_pose(idx).origin
