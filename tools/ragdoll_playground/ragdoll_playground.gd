## ragdoll_playground.gd
## =========================================================================
## TEST CANONICO DEL RAGDOLL (2026-11-03)
## =========================================================================
##
## Este es el BANCO de pruebas de referencia del ragdoll del juego. Si el
## ragdoll falla, se reproduce aqui: el playground usa la MISMA libreria
## (`src/ragdoll/`) y el MISMO motor de fisica que el juego, asi que lo que
## se ve aqui es lo que se ve en el juego.
##
## FASES (automáticas, sin tocar nada):
##   0. REPOSO    -> el personaje se tiene de pie y no se mueve
##   1. CAMINAR   -> velocidad real, zancada, error de orientacion por hueso
##   2. Brazos    -> el IK con el raton pulsado (influencia y altura de la mano)
##   3. VEREDICTO -> una linea por comprobacion
##
## Que mide (de la VERDAD, no del nodo):
##   * `pel_y`   -- altura de la pelvis (cuerpo) sobre el suelo
##   * `up_col`  -- verticalidad de la columna (1 = de pie, 0 = tumbado,
##                  -1 = invertido). Es LA metrica: si cae por debajo de
##                  0 el personaje esta tumbado o de cabeza.
##   * `vel`     -- velocidad horizontal REAL (del servidor de fisica)
##   * `err_*`   -- error de orientacion de un hueso frente a su objetivo
##                  (el servo no lo consigue si el hueso esta atascado)
##
## OJO (medido) -- el nodo `PhysicalBone3D` NO se actualiza en este motor de
## fisica: su `global_position` se queda en el valor inicial. Para leer la
## pose real hay que ir al SERVIDOR de fisica (`RagdollMotor.body_transform`).
## El playground lo hace asi; si se lee el nodo, las cifras no se mueven.
##
## Controles:
##   WASD  -> mover (usa la direccion de la camara)
##   Mouse -> rotar camara (click izq captura, Escape libera)
##   Space -> saltar
##   T     -> auto-walk (Y lo quita)
##
## Headless (el test automatico):
##   godot --headless --path <proj> --quit-after <frames> \
##       res://tools/ragdoll_playground/ragdoll_playground.tscn

extends Node3D

@export var auto_quit_seconds: float = 0.0
@export var auto_walk: bool = false
@export var capture_mouse_on_ready: bool = true
@export var diagnostic_direct_velocity: bool = false
## Altura de la pelvis que se considera "de pie" (m). El rig del Shiba mide
## ~0,85 m de pie; el personaje de la referencia ~0,5 m.
@export var altura_pelvis_esperada: float = 0.0
## Velocidad andando que se espera (m/s) (las stats del Shiba: 3).
@export var velocidad_esperada: float = 0.0
## DIAGNOSTICO: desactiva el collider de los pies (para medir si el
## rozamiento de las plantas es el freno del personaje).
@export var pies_sin_colision: bool = false

## El personaje (por TIPO, no por nombre: el nodo se llama distinto
## segun el rig que se pruebe) y el HUD (si esta).
var character: Node3D = null
var info: Label = null

var _t: float = 0.0
var _start_ms: int = 0
var _body: PhysicalBone3D = null
var _head: PhysicalBone3D = null
var _start_pos: Vector3 = Vector3.ZERO
var _peor_up: float = 1.0
var _max_omega: float = 0.0

# --- Fases del test --------------------------------------------------------
enum Fase { REPOSO, CAMINAR, BRAZOS, FIN }
var _fase: int = Fase.REPOSO
var _fase_t: float = 0.0

# --- Medidas ---------------------------------------------------------------
var _vel_muestras: Array[float] = []
var _vel_pie_muestras: Array[float] = []
var _pie_min := Vector3.ZERO
var _pie_max := Vector3.ZERO
var _pie_z0 := 0.0
var _mano_y_sin := 0.0
var _mano_y_con := 0.0
var _mano_r_sin := 0.0
var _mano_r_con := 0.0
var _ik_influencia := 0.0
var _err_max := 0.0
var _err_hueso := ""
var _err_por_hueso := {}
## Error maximo del pecho (`spine.003`) y del brazo (`upper_arm.L`) por FASE.
## El transitorio del estiron no debe mezclarse con el error estacionario.
var _err_fase_pecho := {}
var _err_fase_brazo := {}
var _pos_caminar := Vector3.ZERO

const DEBUG_ACTIONS := [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "ragdoll", "grab_left", "grab_right",
]


func _ready() -> void:
	character = _buscar_personaje()
	info = _buscar_hud()
	# Interruptor de diagnostico por entorno (sin tocar la escena):
	#   PG_PIES_SIN_COLISION=1 -> los pies no colisionan con nada.
	if OS.get_environment("PG_PIES_SIN_COLISION") == "1":
		pies_sin_colision = true
	print("===== PLAYGROUND RAGDOLL (TEST CANONICO) =====")
	print("[playground] auto_quit=%.1fs auto_walk=%s diagnostic=%s" % [
		auto_quit_seconds, str(auto_walk), str(diagnostic_direct_velocity)])
	_start_ms = Time.get_ticks_msec()
	_body = character.find_child("Physical Bone Body", true, false) as PhysicalBone3D
	if _body == null and character is RagdollCharacter:
		_body = (character as RagdollCharacter).physical_bone_body
	if _body == null:
		_body = _primer_hueso()
	_head = character.find_child("Physical Bone Head", true, false) as PhysicalBone3D
	if _body:
		_start_pos = _pos(_body)
		print("[playground] cuerpo='%s' en %s" % [_body.bone_name, str(_start_pos)])
	else:
		push_error("[playground] NO se encontro ningun hueso fisico")
	if capture_mouse_on_ready and not DisplayServer.get_name() == "headless":
		get_window().grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if pies_sin_colision:
		_desactivar_colision_pies()
		print("[playground] (pies SIN colision)")


## Quita la colision de los pies (diagnostico: mide si el rozamiento de
## las plantas es el freno del personaje).
func _desactivar_colision_pies() -> void:
	for b in character.find_children("*", "PhysicalBone3D", true, false):
		var pb := b as PhysicalBone3D
		if pb != null and String(pb.bone_name).begins_with("foot"):
			pb.collision_layer = 0
			pb.collision_mask = 0


## El personaje ragdoll de la escena (por tipo).
func _buscar_personaje() -> Node3D:
	for c in find_children("*", "RagdollCharacter", true, false):
		return c as Node3D
	for c in get_children():
		if c is RagdollCharacter:
			return c
	return null


## La etiqueta del HUD (si la hay).
func _buscar_hud() -> Label:
	for c in find_children("*", "Label", true, false):
		return c as Label
	return null


## El primer hueso fisico que se encuentre (por tipo, nunca por nombre).
func _primer_hueso() -> PhysicalBone3D:
	for n in character.find_children("*", "PhysicalBone3D", true, false):
		var pb := n as PhysicalBone3D
		if pb != null:
			return pb
	return null


## La pose REAL del cuerpo (del servidor de fisica).
func _pos(b: PhysicalBone3D) -> Vector3:
	if b == null:
		return Vector3.ZERO
	return RagdollMotor.body_transform(b).origin


## Verticalidad de la columna: el eje "arriba" del torso contra el UP.
func _verticalidad() -> float:
	if _body == null:
		return 0.0
	var xf := RagdollMotor.body_transform(_body)
	return xf.basis.y.normalized().dot(Vector3.UP)


func _process(_delta: float) -> void:
	if auto_quit_seconds > 0.0 and (Time.get_ticks_msec() - _start_ms) >= int(auto_quit_seconds * 1000.0):
		_veredicto()
		get_tree().quit()


func _physics_process(delta: float) -> void:
	_t += delta
	_fase_t += delta

	# T = auto-walk, Y = fuera
	if Input.is_key_pressed(KEY_T):
		auto_walk = true
	if Input.is_key_pressed(KEY_Y):
		auto_walk = false
	if auto_walk:
		Input.action_press("move_forward")

	if diagnostic_direct_velocity and _body:
		if Input.is_action_pressed("move_forward"):
			_body.linear_velocity.x += 4.0 * delta
		if Input.is_action_pressed("move_backward"):
			_body.linear_velocity.x -= 4.0 * delta
		if Input.is_action_pressed("move_left"):
			_body.linear_velocity.z += 4.0 * delta
		if Input.is_action_pressed("move_right"):
			_body.linear_velocity.z -= 4.0 * delta

	_maquetar_fases()

	if _body == null:
		return
	var pos := _pos(_body)
	var dist := pos - _start_pos
	var up := _verticalidad()
	var omega := RagdollMotor.body_angular_velocity(_body).length()
	_peor_up = minf(_peor_up, up)
	_max_omega = maxf(_max_omega, omega)
	if fmod(_t, 0.5) < delta:
		var extra := ""
		if character is RagdollCharacter:
			var ch2 := character as RagdollCharacter
			var objs := ch2._calcular_objetivos()
			var pid := ch2.skeleton.find_in_skeleton(ch2.rig_config.body_bone_name)
			if pid != null and objs.has(pid.get_bone_id()):
				extra = " | obj_pelvis=%.2f esq_anim.y=%.2f esq_fis.y=%.2f" % [
					(objs[pid.get_bone_id()] as Transform3D).origin.y,
					ch2.animated_skel.global_position.y,
					ch2.physical_skel.global_position.y]
			if ch2.physical_bone_body != null:
				var vb := RagdollMotor.body_linear_velocity(ch2.physical_bone_body)
				extra += " | v_pelvis=%.2f" % Vector2(vb.x, vb.z).length()
				var xf := RagdollMotor.body_transform(ch2.physical_bone_body)
				extra += " yaw_pelvis=%.2f" % rad_to_deg(atan2(xf.basis.z.x, xf.basis.z.z))
			if ch2.animated_skel != null:
				extra += " yaw_maestro=%.2f" % rad_to_deg(ch2.animated_skel.global_rotation.y)
				# ¿El clip mueve la pierna? (la POSE del esqueleto ANIMADO)
				var tid := ch2.animated_skel.find_bone("shin.L")
				if tid >= 0:
					extra += " anim_shin=%s" % str(
						ch2.animated_skel.get_bone_global_pose(tid).origin.snapped(Vector3(0.01, 0.01, 0.01)))
			# Las velocidades lineales de las piernas (¿se mueven?).
			var tb := ch2.skeleton.find_in_skeleton("thigh.L")
			if tb != null:
				var vt := RagdollMotor.body_linear_velocity(tb)
				var sb := ch2.skeleton.find_in_skeleton("shin.L")
				var vs := Vector2.ZERO
				if sb != null:
					var vbs := RagdollMotor.body_linear_velocity(sb)
					vs = Vector2(vbs.x, vbs.z)
				extra += " v_thigh=%.2f v_shin=%.2f" % [Vector2(vt.x, vt.z).length(), vs.length()]
			# El clip que se esta reproduciendo y el estado del arbol.
			if ch2.animation_tree != null:
				var blend: float = ch2.animation_tree.get("parameters/walking/blend_amount")
				var esc: float = ch2.animation_tree.get("parameters/TimeScale/scale")
				var clip := "-"
				if ch2.animation_player != null:
					clip = str(ch2.animation_player.current_animation)
				extra += " | blend=%.2f esc=%.2f clip=%s" % [blend, esc, clip]
		print("[pg] t=%.1f pos=(%.2f,%.2f,%.2f) dXZ=%.2f up=%.2f omega=%.2f | inputs=%s%s" % [
			_t, pos.x, pos.y, pos.z, Vector2(dist.x, dist.z).length(),
			up, omega, _inputs(), extra])
	if info:
		info.text = "== PLAYGROUND RAGDOLL ==\nWASD mover | Mouse camara | Space saltar | T auto-walk\n\npos   = (%.2f, %.2f, %.2f)\ndXZ   = %.2f m\nup    = %.2f (1 = de pie)\nomega = %.2f rad/s\ninputs= %s" % [
			pos.x, pos.y, pos.z, Vector2(dist.x, dist.z).length(),
			up, omega, _inputs()]


## Las fases del test automatico.
func _maquetar_fases() -> void:
	match _fase:
		Fase.REPOSO:
			_errores()
			# Traza por frame: dice SI el hueso se voltea al caer o si
			# NACIO mal (el origen del problema).
			if Engine.get_physics_frames() % 6 == 0:
				print("[pg] t=%.2f pel_y=%.3f err pie=%5.1f err espinilla=%5.1f w_pie=%.2f" % [
					_t, _pos(_body).y,
					float(_err_por_hueso.get("foot.L", -1.0)),
					float(_err_por_hueso.get("shin.L", -1.0)),
					RagdollMotor.body_angular_velocity(_hueso("shin.L")).length()])
			if _fase_t > 1.5:
				print("[pg] --- errores en REPOSO ---")
				for n in ["spine", "spine.002", "spine.003", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L"]:
					if _err_por_hueso.has(n):
						print("      err %-12s = %5.1f grados" % [n, _err_por_hueso[n]])
				_debug_pie()
				_siguiente_fase(Fase.CAMINAR)
				_pos_caminar = _pos(_body)
				_pie_min = Vector3.ZERO
				_pie_max = Vector3.ZERO
				_vel_muestras.clear()
				_vel_pie_muestras.clear()
				_mano_y_sin = _altura_mano()
				print("[pg] FASE 1: caminando (3 s)")
				Input.action_press("move_forward")
		Fase.CAMINAR:
			_midiendo_caminata()
			if _fase_t > 3.0:
				_siguiente_fase(Fase.BRAZOS)
				Input.action_release("move_forward")
				_mano_y_sin = _altura_mano("hand.L")
				_mano_r_sin = _altura_mano("hand.R")
				print("[pg] FASE 2: brazos (clic)")
				Input.action_press("grab_left")
		Fase.BRAZOS:
			if _fase_t > 1.5:
				_mano_y_con = _altura_mano("hand.L")
				_mano_r_con = _altura_mano("hand.R")
				_ik_influencia = _influencia_ik()
				_siguiente_fase(Fase.FIN)
				Input.action_release("grab_left")
				_veredicto()
				get_tree().quit()


## DIAGNOSTICO: los ejes del pie (real vs objetivo) y su collider.
##
## El pie es el hueso mas traicionero: si su collider esta mal situado o
## mal orientado, el servo no puede llevar el hueso a su objetivo (el
## suelo lo frena) y el personaje se arrastra (medido: 96 grados de error
## en reposo, velocidad 0,5 m/s).
func _debug_pie() -> void:
	if not (character is RagdollCharacter):
		return
	var char := character as RagdollCharacter
	var skel: Skeleton3D = char.skeleton.physical_skel
	# DISTANCIA PADRE -> HIJO (real vs reposo): si el joint ancla en el
	# origen del padre (y no en su cola), la pierna se colapsa.
	for n in ["thigh.L", "shin.L", "foot.L", "thigh.R"]:
		var b := _hueso(n)
		if b == null:
			continue
		var id := b.get_bone_id()
		var pid := skel.get_bone_parent(id)
		if pid < 0:
			continue
		var hi := skel.get_bone_global_rest(id).origin
		var hp := skel.get_bone_global_rest(pid).origin
		var real_h := RagdollMotor.body_transform(b).origin
		var real_p := RagdollMotor.body_transform(_hueso(skel.get_bone_name(pid))).origin
		print("[pg] %-8s largo en reposo=%.3f | largo real=%.3f | padre %s" % [
			n, hi.distance_to(hp), real_h.distance_to(real_p), skel.get_bone_name(pid)])
	var objs := char._calcular_objetivos()
	for n in ["foot.L", "shin.L"]:
		var b := _hueso(n)
		if b == null:
			continue
		var id := b.get_bone_id()
		if id < 0 or not objs.has(id):
			continue
		var boff: Transform3D = b.get("body_offset")
		var actual := RagdollMotor.body_transform(b) * boff.affine_inverse()
		var obj: Transform3D = objs[id]
		var e := RagdollMotor.error_de_rotacion(obj.basis * actual.basis.inverse())
		print("[pg] %s: det_real=%.3f det_obj=%.3f | err=%.1f grados eje=%s | w=%s" % [
			n, actual.basis.determinant(), obj.basis.determinant(),
			rad_to_deg(e.length()),
			str(e.normalized().snapped(Vector3(0.01, 0.01, 0.01))),
			str(RagdollMotor.body_angular_velocity(b).snapped(Vector3(0.01, 0.01, 0.01)))])
		var cs := b.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var forma := "sin collider"
		if cs != null and cs.shape != null:
			forma = "%s off=%s" % [cs.shape.get_class(),
				str(cs.transform.origin.snapped(Vector3(0.01, 0.01, 0.01)))]
		print("[pg] %s: real Y=%s Z=%s | obj Y=%s Z=%s | w=%.2f | %s" % [
			n,
			str(actual.basis.y.snapped(Vector3(0.01, 0.01, 0.01))),
			str(actual.basis.z.snapped(Vector3(0.01, 0.01, 0.01))),
			str(obj.basis.y.snapped(Vector3(0.01, 0.01, 0.01))),
			str(obj.basis.z.snapped(Vector3(0.01, 0.01, 0.01))),
			RagdollMotor.body_angular_velocity(b).length(), forma])


func _siguiente_fase(f: int) -> void:
	_fase = f
	_fase_t = 0.0


## Mide lo que pasa al caminar: velocidad, zancada del pie y errores.
##
## La metrica que importa es el PATINAJE: la velocidad del PIE frente a la
## del cuerpo. Si el pie va mas rapido que el cuerpo, el pie se desliza
## (patina) y el personaje se arrastra; si van iguales, el pie se planta y
## el cuerpo pasa por encima (que es como camina la REFERENCIA).
func _midiendo_caminata() -> void:
	var v := RagdollMotor.body_linear_velocity(_body)
	_vel_muestras.append(Vector2(v.x, v.z).length())
	var pie := _hueso("shin.L")
	if pie == null:
		return
	var vp := RagdollMotor.body_linear_velocity(pie)
	_vel_pie_muestras.append(Vector2(vp.x, vp.z).length())
	var p := RagdollMotor.body_transform(pie).origin
	if _pie_min == Vector3.ZERO:
		_pie_min = p
		_pie_max = p
	_pie_min = _pie_min.min(p)
	_pie_max = _pie_max.max(p)
	_errores()


## El error de orientacion de cada hueso frente a su objetivo (el servo).
func _errores() -> void:
	if not (character is RagdollCharacter):
		return
	var char := character as RagdollCharacter
	var objs := char._calcular_objetivos()
	_err_por_hueso.clear()
	for b in char.skeleton.bones:
		var id := b.get_bone_id()
		if id < 0 or not objs.has(id):
			continue
		var boff: Transform3D = b.get("body_offset")
		var actual := RagdollMotor.body_transform(b) * boff.affine_inverse()
		var obj: Transform3D = objs[id]
		var e := rad_to_deg(RagdollMotor.error_de_rotacion(
			obj.basis * actual.basis.inverse()).length())
		_err_por_hueso[String(b.bone_name)] = e
		# OJO: el maximo GLOBAL mezcla el transitorio del estiron (el objetivo
		# del brazo salta 65 grados de golpe) con el error estacionario. Por
		# eso se guarda por FASE: en reposo y andando es donde el torso tiene
		# que estar recto.
		if String(b.bone_name) == "spine.003":
			_err_fase_pecho[_fase] = maxf(float(_err_fase_pecho.get(_fase, 0.0)), e)
		elif String(b.bone_name) == "upper_arm.L":
			_err_fase_brazo[_fase] = maxf(float(_err_fase_brazo.get(_fase, 0.0)), e)
		if e > _err_max:
			_err_max = e
			_err_hueso = String(b.bone_name)


func _hueso(nombre: String) -> PhysicalBone3D:
	if not (character is RagdollCharacter):
		return null
	var char := character as RagdollCharacter
	for b in char.skeleton.bones:
		if String(b.bone_name) == nombre:
			return b
	return null


## La altura de la mano (para ver si el IK la levanta).
func _altura_mano(nombre: String = "hand.R") -> float:
	var h := _hueso(nombre)
	if h == null:
		return 0.0
	var boff: Transform3D = h.get("body_offset")
	return (RagdollMotor.body_transform(h) * boff.affine_inverse()).origin.y


## Ya no hay componente de IK (`TwoBoneIK3D`): el estiron lo hace el servo.
## Esta cifra es 0 siempre; se deja la linea por compatibilidad del informe.
func _influencia_ik() -> float:
	return 0.0


func _inputs() -> String:
	var pressed := PackedStringArray()
	for a in DEBUG_ACTIONS:
		if Input.is_action_pressed(a):
			pressed.append(a)
	return ", ".join(pressed) if pressed.size() > 0 else "(ninguno)"


## Veredicto automatico: el personaje tiene que estar DE PIE al final.
func _veredicto() -> void:
	var up := _verticalidad()
	var pos := _pos(_body)
	var omega := RagdollMotor.body_angular_velocity(_body).length()
	print("===== VEREDICTO PLAYGROUND =====")
	print("  pel_y   = %.3f" % pos.y)
	print("  up_col  = %.3f  (peor en el recorrido: %.3f)" % [up, _peor_up])
	print("  omega   = %.2f rad/s (maximo: %.2f)" % [omega, _max_omega])
	var vel_media := 0.0
	# SUAVIDAD: la desviacion tipica de la velocidad por tick. Un avance en
	# diente de sierra (teleport) tiene sigma alta; un servo continuo, baja.
	var sigma := 0.0
	if _vel_muestras.size() > 0:
		var suma := 0.0
		for v in _vel_muestras:
			suma += v
		vel_media = suma / float(_vel_muestras.size())
		var varianza := 0.0
		for v in _vel_muestras:
			varianza += pow(v - vel_media, 2.0)
		sigma = sqrt(varianza / float(_vel_muestras.size()))
	var zancada := 0.0
	if _pie_max != Vector3.ZERO:
		zancada = (_pie_max - _pie_min).length()
	print("  vel media al andar = %.2f m/s  (sigma %.2f)   recorrido del pie = %.3f m" % [
		vel_media, sigma, zancada])
	var vel_pie := 0.0
	if _vel_pie_muestras.size() > 0:
		var suma := 0.0
		for v in _vel_pie_muestras:
			suma += v
		vel_pie = suma / float(_vel_pie_muestras.size())
	# PATINAJE: si el pie va mas rapido que el cuerpo, el pie se desliza
	# (por eso "los pies no se mueven" y el arrastra). Lo que se quiere es
	# pie ~= cuerpo.
	print("  vel media del PIE = %.2f m/s  (cuerpo %.2f) -> patinaje %+.2f m/s" % [
		vel_pie, vel_media, vel_pie - vel_media])
	print("  error max de orientacion = %.1f grados  (hueso: %s)" % [_err_max, _err_hueso])
	# Por FASE: el maximo global es el transitorio del estiron (el objetivo del
	# brazo salta 65 grados). Lo que se juzga es el error ESTACIONARIO.
	var nombres_fase := { Fase.REPOSO: "reposo", Fase.CAMINAR: "andando", Fase.BRAZOS: "brazos" }
	for f in [Fase.REPOSO, Fase.CAMINAR, Fase.BRAZOS]:
		if _err_fase_pecho.has(f) or _err_fase_brazo.has(f):
			print("    fase %-8s pecho=%5.1f  brazo=%5.1f" % [nombres_fase[f],
				float(_err_fase_pecho.get(f, 0.0)), float(_err_fase_brazo.get(f, 0.0))])
	for n in ["spine", "spine.002", "spine.003", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L"]:
		if _err_por_hueso.has(n):
			print("    err %-12s = %5.1f grados" % [n, _err_por_hueso[n]])
	print("  BRAZOS: el estiron lo hace el SERVO (no hay TwoBoneIK3D)")
	if character is RagdollCharacter:
		var ch := character as RagdollCharacter
		var hb := _hueso("hand.L")
		if hb != null:
			var boff: Transform3D = hb.get("body_offset")
			print("    mano izq FISICA = %s" % str(
				(RagdollMotor.body_transform(hb) * boff.affine_inverse()).origin.snapped(Vector3(0.01, 0.01, 0.01))))
			var fido := hb.get_bone_id()
			if fido >= 0:
				print("    mano izq OBJETIVO (servo) = %s" % str(
					ch._calcular_objetivos()[fido].origin.snapped(Vector3(0.01, 0.01, 0.01))))
			var eb := _hueso("forearm.L")
			if eb != null:
				var eoff: Transform3D = eb.get("body_offset")
				print("    antebrazo FISICO = %s | err=%.1f" % [
					str((RagdollMotor.body_transform(eb) * eoff.affine_inverse()).origin.snapped(Vector3(0.01, 0.01, 0.01))),
					float(_err_por_hueso.get("forearm.L", -1.0))])
	print("    mano IZQUIERDA (agarra): %.3f -> %.3f  (delta %+.3f)" % [
		_mano_y_sin, _mano_y_con, _mano_y_con - _mano_y_sin])
	print("    mano DERECHA (suelta) : %.3f -> %.3f  (delta %+.3f)" % [
		_mano_r_sin, _mano_r_con, _mano_r_con - _mano_r_sin])
	var ok := _peor_up > 0.7 and _max_omega < 20.0
	if altura_pelvis_esperada > 0.0:
		var d := absf(pos.y - altura_pelvis_esperada)
		print("  altura esperada %.2f -> desvio %.3f" % [altura_pelvis_esperada, d])
		ok = ok and d < 0.35
	if velocidad_esperada > 0.0:
		print("  velocidad esperada %.2f -> desvio %.3f" % [velocidad_esperada, absf(vel_media - velocidad_esperada)])
		ok = ok and absf(vel_media - velocidad_esperada) < 0.6
	print("  RESULTADO: %s" % ("OK" if ok else "FALLO"))
