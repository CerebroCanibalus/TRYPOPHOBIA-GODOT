extends SceneTree
## FORGE DE ANIMACIONES del Shiba (y de cualquier rig).
##
## MOTIVO: el GLB del Shiba NO tiene ninguna animacion (0 animaciones en el
## glTF) y los clips que habia en `shiba_anim.tres` eran la POSE DE REPOSO
## (T-pose con los brazos en cruz) con una sola clave por pista. Por eso:
##   * los brazos se caian de forma "rota" (el servo no puede sostener una
##     T-pose contra la gravedad),
##   * la caminata era un arrastre (las piernas nunca se movian).
##
## Este generador construye las poses y el ciclo de paso A PARTIR del
## esqueleto en reposo:
##   IDLE        = reposo con los brazos BAJADOS
##   walk_full   = ciclo de paso (cadera, rodilla, tobillo + columpio de
##                 brazos + balanceo de pelvis)
##   hands_front = los brazos al frente (el agarre)
##   lean_forward / lean_back = inclinaciones del torso
##
## CONVENCION (medida en Godot 4.7.1): el valor de una pista de rotacion es
## la rotacion LOCAL del hueso (relativa al padre), ABSOLUTA (no un delta):
## por eso una pista ausente deja el hueso en identidad (la "T" de la que
## habla el comentario del Blend2).
##
## EJES: la pierna bascula en el PLANO SAGITAL, asi que su eje es el X del
## modelo (izquierda-derecha). El signo (que bascula hacia delante y no
## hacia atras) se mide en el propio rig, no se supone.

const SRC := "res://src/player/shiba_player.tscn"
const DST := "res://src/player/shiba_anim.tres"

## Longitud del ciclo de paso (s).
##
## El clip se hace a la VELOCIDAD NATURAL del rig: `zancada / ciclo`. El
## `AnimationTree` lo escala despues con la velocidad que pida el
## personaje (el `TimeScale`), asi que el ritmo del clip y el del suelo
## coinciden siempre.
##
## Con la zancada de 0,32 m y un ciclo de 0,29 s la velocidad natural es
## 1,10 m/s (3,4 zancadas por segundo: un paso largo y tranquilo).
const CICLO := 0.58
## Muestras por ciclo (claves por pista).
##
## 32 muestras a 0,58 s son 18 ms por clave: a 60 fps se ve mas de una clave
## por frame (el pie se planta, no da saltos).
const MUESTRAS := 32
## ZANCADA del ciclo (metros): lo que avanza el pie, de la punta atras a la
## punta delante.
##
## MEDIDA (2026-11-04, geometria del autoring): la pierna va de la CADERA
## (hueso "thigh", y=0,922) a la RODILLA ("shin", y=0,537) al TOBILLO
## ("foot", y=0,144) y de ahi a la punta del pie (0,171 mas abajo, en el
## suelo). Los tramos con cuerpo son 0,386 y 0,400: la pierna mide 0,786 de
## la cadera al tobillo.
##
## Con el pie TOCANDO el suelo, el tobillo solo puede avanzar +-0,19 m (los
## 0,786 de pierna no dan para mas: medido, con una zancada de 0,42 el IK
## no llegaba y el error era de 0,21 m). La zancada de 0,32 m es la maxima
## con el pie plantado.
const ZANCADA := 0.32
## Altura a la que se levanta el pie en la fase de vuelo (m).
const ALTURA_VUELO := 0.12
## Altura del TOBILLO sobre el suelo (m). El collider de la espinilla llega
## al suelo, asi que el tobillo queda a 0,16 y la planta apoya.
const ALTURA_TOBILLO := 0.16
## Columpio de los brazos (grados). Va EN CONTRAFASE entre los dos brazos
## (como en la referencia: el brazo izquierdo va adelante cuando la
## pierna derecha va adelante).
const COLUMPIO_BRAZOS := 12.0
## Balanceo lateral del tronco (grados): el cuerpo se inclina hacia la
## pierna que adelanta. Es el unico movimiento del torso en el ciclo.
const BALANCEO_TRONCO := 3.0

var skel: Skeleton3D
var rest := {}       ## id -> Transform3D (reposo global, espacio del esqueleto)
var ids := {}        ## nombre -> id


func _init() -> void:
	var src := load(SRC) as PackedScene
	if src == null:
		print("ERROR: no carga ", SRC)
		quit(1)
		return
	var inst := src.instantiate()
	skel = inst.get_node_or_null("Animated/metarig/Skeleton3D")
	if skel == null:
		print("ERROR: no hay esqueleto animado")
		quit(1)
		return
	for i in skel.get_bone_count():
		rest[i] = skel.get_bone_global_rest(i)
		ids[skel.get_bone_name(i)] = i

	var lib := AnimationLibrary.new()
	lib.add_animation("IDLE", _clip([_pose_idle()], CICLO))
	lib.add_animation("walk_full", _clip(_muestras_paso(), CICLO))
	lib.add_animation("hands_front", _clip([_pose_brazos_adelante(_pose_idle())], CICLO))
	lib.add_animation("lean_forward", _clip([_pose_inclinada(8.0)], CICLO))
	lib.add_animation("lean_back", _clip([_pose_inclinada(-8.0)], CICLO))

	# --- VERIFICACION: el tobillo tiene que acabar en el objetivo --------
	var max_err := 0.0
	var peor := ""
	for n in MUESTRAS:
		var f := float(n) / float(MUESTRAS)
		var g := _pose_paso(f)
		for lado in ["L", "R"]:
			var fase := TAU * f if lado == "L" else TAU * f + PI
			var O := _objetivo_tobillo(lado, fase)
			var t: Vector3 = g[ids["foot." + lado]].origin
			var e := t.distance_to(O)
			if e > max_err:
				max_err = e
				peor = "  f=%.2f lado=%s objetivo=%s obtenido=%s" % [
					f, lado, str(O.snapped(Vector3(0.01, 0.01, 0.01))),
					str(t.snapped(Vector3(0.01, 0.01, 0.01)))]
	print("  VERIFICACION IK: error max del tobillo = %.4f m" % max_err)
	print(peor)
	# --- VERIFICACION DE LA POSE DE REPOSO (los brazos tienen que COLGAR) --
	var repose := _pose_idle()
	for lado in ["L", "R"]:
		var h: int = ids["shoulder." + lado]
		var m: int = ids["hand." + lado]
		print("  IDLE %s: hombro=%s mano=%s (dist=%.3f)" % [lado,
			str(repose[h].origin.snapped(Vector3(0.01, 0.01, 0.01))),
			str(repose[m].origin.snapped(Vector3(0.01, 0.01, 0.01))),
			(repose[m].origin - repose[h].origin).length()])
	print("  velocidad natural del clip = %.2f m/s (2 zancadas de %.2f por ciclo de %.2f)" % [
		2.0 * ZANCADA / CICLO, ZANCADA, CICLO])

	var err := ResourceSaver.save(lib, DST)
	print("SAVE ", DST, " err=", err)
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		print("  %-14s len=%.3f pistas=%d" % [n, a.length, a.get_track_count()])
	quit(0)


# --- GEOMETRIA DEL RIG -----------------------------------------------------

## El EJE de balanceo de la cadera: el X del modelo (la pierna bascula en
## el plano sagital, de delante atras).
func _eje_cadera() -> Vector3:
	return Vector3.RIGHT


## El EJE de flexion de la rodilla: el que separa al muslo de la espinilla.
## Se mide con los dos huesos (no se supone).
func _eje_rodilla() -> Vector3:
	var rodilla: int = ids["shin.L"]
	var dir: Vector3 = (rest[ids["foot.L"]].origin - rest[rodilla].origin).normalized()
	var dir_muslo: Vector3 = (rest[rodilla].origin - rest[ids["thigh.L"]].origin).normalized()
	var e: Vector3 = dir.cross(dir_muslo)
	if e.length() < 0.01:
		e = dir.cross(Vector3.UP)
	return e.normalized()


# --- POSES -----------------------------------------------------------------

## Reposo con los brazos BAJADOS (la T-pose no se puede sostener).
func _pose_idle() -> Dictionary:
	var g := rest.duplicate()
	for lado in ["L", "R"]:
		g = _bajar_brazo(g, lado, 0.0)
	return g


## Cycle de paso: una muestra por fase.
func _muestras_paso() -> Array:
	var out := []
	for n in MUESTRAS:
		var f := float(n) / float(MUESTRAS)
		out.append(_pose_paso(f))
	return out


## Una fase del ciclo de paso.
##
## LAS PIERNAS SE RESUELVEN POR IK DE DOS HUESOS (no con senos): se fija
## el PIE en el suelo y se resuelve la cadena cadera -> rodilla -> tobillo.
## Con senos la pierna se acortaba en la fase de vuelo y el personaje se
## hundia (medido: la pelvis caia de 0,66 a 0,30 y la velocidad era de
## 0,24 m/s).
func _pose_paso(f: float) -> Dictionary:
	var g := rest.duplicate()
	var a := TAU * f
	# --- Piernas (la derecha va media fase por delante) -------------------
	for lado in ["L", "R"]:
		var fase := a if lado == "L" else a + PI
		g = _pierna_ik(g, lado, fase)
	# --- Brazos: bajados y columpiandose EN CONTRAFASE --------------------
	#
	# El signo va espejado: los dos brazos con el MISMO signo se mueven
	# hacia el mismo lado (los dos adelante a la vez), que es un balanceo
	# de paraguas, no una marcha. Con el signo espejado, el brazo
	# izquierdo va adelante cuando la pierna DERECHA va adelante.
	for lado in ["L", "R"]:
		var fase := a if lado == "L" else a + PI
		var col := deg_to_rad(COLUMPIO_BRAZOS) * sin(fase)
		if lado == "R":
			col = -col
		g = _bajar_brazo(g, lado, col)
	# --- Tronco: se inclina hacia la pierna que adelanta -------------------
	g = _rotar(g, _cadena_columna(), rest[ids["spine"]].origin, Vector3.BACK,
			deg_to_rad(BALANCEO_TRONCO) * sin(a))
	return g


## El objetivo del tobillo en el espacio del esqueleto (el mismo que usa
## el IK): el pie va de atras a delante en la primera mitad del ciclo (en
## el aire) y de delante a atras en la segunda (plantado en el suelo).
func _objetivo_tobillo(lado: String, fase: float) -> Vector3:
	var A: Vector3 = rest[ids["thigh." + lado]].origin
	var B: Vector3 = rest[ids["shin." + lado]].origin
	var C: Vector3 = rest[ids["foot." + lado]].origin
	var L1 := (B - A).length()
	var L2 := (C - B).length()
	var dx := -ZANCADA * 0.5 * cos(fase)
	var h := ALTURA_VUELO * maxf(0.0, sin(fase))
	# El "adelante" del modelo es su +Z.
	var O := C + Vector3(0.0, ALTURA_TOBILLO - C.y + h, dx)
	# RECORTE: si el objetivo esta mas lejos de lo que la pierna puede
	# llegar, se recorta (si no, el IK no tiene solucion y el pie se
	# queda a medio camino: medido, error de 0,21 m).
	var dir := O - A
	var d := dir.length()
	var maxd := L1 + L2 - 0.002
	if d > maxd:
		O = A + dir / d * maxd
	return O


## El ciclo de paso de UNA pierna, por IK de DOS HUESOS.
##
##   A = cadera (hueso "thigh")   B = rodilla ("shin")   C = tobillo ("foot")
##   L1 = |A-B|   L2 = |B-C|   d = |A-objetivo|
##   ang = acos((L1^2 + d^2 - L2^2) / (2 L1 d))
##
## El tobillo recorre una ELIPSE: el pie se planta en la fase de apoyo y
## se levanta en la de vuelo. La cadena se resuelve en dos rotaciones:
## la de la cadera (que arrastra a la rodilla) y la de la rodilla.
func _pierna_ik(g: Dictionary, lado: String, fase: float) -> Dictionary:
	var cadera: int = ids["thigh." + lado]
	var rodilla: int = ids["shin." + lado]
	var tobillo: int = ids["foot." + lado]
	var A: Vector3 = rest[cadera].origin
	var B: Vector3 = rest[rodilla].origin
	var C: Vector3 = rest[tobillo].origin
	var L1 := (B - A).length()
	var L2 := (C - B).length()
	# --- El objetivo del tobillo -----------------------------------------
	# El pie va de atras a delante en la primera mitad del ciclo (en el
	# aire) y de delante a atras en la segunda (plantado en el suelo).
	var O := _objetivo_tobillo(lado, fase)
	var dir := O - A
	var d := dir.length()
	if d < 0.001:
		return g
	var u := dir / d
	var cos_a := (L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d)
	var ang_a := acos(clampf(cos_a, -1.0, 1.0))
	# El EJE de la articulacion: el perpendicular al plano de la pierna
	# (cadera-rodilla-tobillo). NO el X del modelo: la pierna no es
	# perfectamente plana (la punta del pie abre 5 cm hacia fuera) y con un
	# eje equivocado el IK no llega (medido: error de 0,32 m).
	var eje := (B - A).cross(C - B).normalized()
	# El LADO de la rodilla: en reposo la rodilla esta a un lado de la
	# linea cadera->tobillo, y al mover el pie se queda en ESE mismo lado
	# (una rodilla real dobla siempre hacia el mismo lado).
	var lado_rep := (C - A).cross(B - A).dot(eje)
	var b1 := A + u.rotated(eje, ang_a) * L1
	var b2 := A + u.rotated(eje, -ang_a) * L1
	var s1 := (O - A).cross(b1 - A).dot(eje)
	var s2 := (O - A).cross(b2 - A).dot(eje)
	var Bn := b1 if s1 * lado_rep >= 0.0 else b2
	# 1) La CADERA: llevar la rodilla de B a Bn (arrastra a todo lo de mas).
	var ang_cadera := _angulo(eje, B - A, Bn - A)
	g = _rotar(g, _cadena(cadera), A, eje, ang_cadera)
	# 2) La RODILLA: llevar el tobillo de C a O. OJO: el vector de la
	# rodilla al tobillo a partir de aqui es el de REPOSO ROTADO por la
	# rotacion de la cadera (si se usa el de reposo, el IK no llega:
	# medido, error de 0,25 m).
	var real := (C - B).rotated(eje, ang_cadera)
	g = _rotar(g, _cadena(rodilla), Bn, eje, _angulo(eje, real, O - Bn))
	return g


## El angle con signo para girar `v1` hasta `v2` alrededor de `eje`.
static func _angulo(eje: Vector3, v1: Vector3, v2: Vector3) -> float:
	var a := v1.normalized()
	var b := v2.normalized()
	if a.length_squared() < 0.5 or b.length_squared() < 0.5:
		return 0.0
	return atan2(a.cross(b).dot(eje), a.dot(b))


## Inclinacion del torso (para el lean).
func _pose_inclinada(grados: float) -> Dictionary:
	var g := _pose_idle()
	g = _rotar(g, _cadena_columna_cabeza(), rest[ids["spine"]].origin, Vector3.RIGHT,
			deg_to_rad(grados))
	return g


## Los brazos al frente (el agarre) sobre la pose de reposo.
func _pose_brazos_adelante(base: Dictionary) -> Dictionary:
	var g := base.duplicate()
	for lado in ["L", "R"]:
		var hombro: int = ids["upper_arm." + lado]
		var cadena := _cadena(hombro)
		var mano: int = ids["hand." + lado]
		# El hombro tiene que ir hacia DELANTE (+Z del modelo): se prueba
		# el signo y se corrige.
		var ang := deg_to_rad(85.0)
		var prueba := _rotar(g.duplicate(), cadena, rest[hombro].origin,
				Vector3.RIGHT, ang)
		if prueba[mano].origin.z < g[mano].origin.z:
			ang = -ang
		g = _rotar(g, cadena, rest[hombro].origin, Vector3.RIGHT, ang)
		# Y el codo se dobla un poco (la mano baja un poco).
		var codo: int = ids["forearm." + lado]
		var c := deg_to_rad(14.0)
		var p2 := _rotar(g.duplicate(), _cadena(codo), rest[codo].origin,
				Vector3.RIGHT, c)
		if p2[mano].origin.y > g[mano].origin.y:
			c = -c
		g = _rotar(g, _cadena(codo), rest[codo].origin, Vector3.RIGHT, c)
	return g


## Baja el brazo de un lado (y lo deja colgando). `columpio` lo gira un poco.
##
## OJO (medido 2026-11-04): la cadena empieza en el HUMERO (`upper_arm`),
## NO en la clavicula (`shoulder`). Rotando desde la clavicula, esta se
## enrolla 88 grados DENTRO del pecho y arrastra el brazo con ella: los
## brazos salen cruzados sobre el torso y las manos se meten dentro del
## cuerpo (medido en `tests/ragdoll/shots/shiba_caminando.png`).
func _bajar_brazo(g: Dictionary, lado: String, columpio: float) -> Dictionary:
	var hombro: int = ids["upper_arm." + lado]
	var cadena := _cadena(hombro)
	var mano: int = ids["hand." + lado]
	# El brazo tiene que BAJAR: se prueba el signo con el eje Z del modelo
	# (el brazo sale hacia el lado, hay que bajarlo en el plano frontal).
	var ang := deg_to_rad(88.0)
	var prueba := _rotar(rest.duplicate(), cadena, rest[hombro].origin,
			Vector3.BACK, ang)
	if prueba[mano].origin.y > rest[mano].origin.y:
		ang = -ang
	g = _rotar(g, cadena, rest[hombro].origin, Vector3.BACK, ang)
	# El codo se dobla un poco hacia delante (no un palo).
	var codo: int = ids["forearm." + lado]
	var c := deg_to_rad(12.0)
	var p2 := _rotar(g.duplicate(), _cadena(codo), rest[codo].origin,
			Vector3.RIGHT, c)
	if p2[mano].origin.z < g[mano].origin.z:
		c = -c
	g = _rotar(g, _cadena(codo), rest[codo].origin, Vector3.RIGHT, c)
	if columpio != 0.0:
		g = _rotar(g, cadena, rest[hombro].origin, Vector3.RIGHT, columpio)
	return g


## El signo con el que la RODILLA dobla (la espinilla va hacia atras).
func _signo_rodilla(lado: String) -> float:
	var rodilla: int = ids["shin." + lado]
	var tobillo: int = ids["foot." + lado]
	var p := _rotar(rest.duplicate(), _cadena(rodilla), rest[rodilla].origin,
			_eje_rodilla(), deg_to_rad(10.0))
	return 1.0 if p[tobillo].origin.z < rest[tobillo].origin.z else -1.0


## El signo con el que la CADERA lleva la pierna hacia DELANTE (+Z).
func _signo_cadera(lado: String) -> float:
	var cadera: int = ids["thigh." + lado]
	var rodilla: int = ids["shin." + lado]
	var p := _rotar(rest.duplicate(), _cadena(cadera), rest[cadera].origin,
			_eje_cadera(), deg_to_rad(10.0))
	return 1.0 if p[rodilla].origin.z > rest[rodilla].origin.z else -1.0


# --- UTILES ----------------------------------------------------------------

## Rota un conjunto de huesos alrededor de un eje que pasa por un pivote.
func _rotar(g: Dictionary, huesos: Array, pivote: Vector3, eje: Vector3,
		angulo: float) -> Dictionary:
	if angulo == 0.0:
		return g
	var b := Basis(Quaternion(eje.normalized(), angulo))
	var xf := Transform3D(b, pivote - b * pivote)
	for id in huesos:
		g[id] = xf * g[id]
	return g


## El hueso y todos sus descendientes.
func _cadena(id: int) -> Array:
	var out := [id]
	var pila := [id]
	while pila.size() > 0:
		var actual: int = pila.pop_back()
		for c in skel.get_bone_children(actual):
			out.append(c)
			pila.append(c)
	return out


## La columna (torso) SIN las piernas.
func _cadena_columna() -> Array:
	var out := []
	for i in skel.get_bone_count():
		var n := String(skel.get_bone_name(i))
		if n.begins_with("spine") or n.begins_with("breast") or n.begins_with("pelvis"):
			out.append(i)
	return out


## La columna sin la pelvis (para inclinar el torso).
func _cadena_columna_cabeza() -> Array:
	var out := []
	for i in skel.get_bone_count():
		var n := String(skel.get_bone_name(i))
		if n.begins_with("spine.0"):
			out.append(i)
	return out


## Convierte una lista de poses globales en un clip de animacion.
func _clip(poses: Array, duracion: float) -> Animation:
	var a := Animation.new()
	a.length = duracion
	a.loop_mode = Animation.LOOP_LINEAR
	var n_pistas := skel.get_bone_count()
	var index := {}
	for i in n_pistas:
		index[i] = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(index[i], NodePath("%s:%s" % [
			"Animated/metarig/Skeleton3D", skel.get_bone_name(i)]))
		a.track_set_interpolation_type(index[i], Animation.INTERPOLATION_LINEAR)
	# OJO: NO hay pista de POSICION en ningun clip. La pista de posicion
	# ("spine.001") que hubo antes era el "balanceo vertical" del torso, y
	# no servia para nada: el servo solo usa la ORIENTACION del objetivo y
	# la posicion de los huesos la pone la fisica. Ademas movia el
	# esqueleto maestro y hacia que el objetivo y el cuerpo se persiguieran
	# (el lazo de realimentacion).
	for n in poses.size():
		var t := duracion * float(n) / float(poses.size())
		var locales := _locales(poses[n])
		for i in n_pistas:
			a.track_insert_key(index[i], t, locales[i])
	return a


## Las rotaciones LOCALES (relativas al padre) de una pose global.
func _locales(g: Dictionary) -> Dictionary:
	var out := {}
	for i in skel.get_bone_count():
		var padre := skel.get_bone_parent(i)
		var gi: Transform3D = g[i]
		if padre < 0:
			out[i] = gi.basis.get_rotation_quaternion()
		else:
			var gp: Transform3D = g[padre]
			out[i] = (gp.basis.inverse() * gi.basis).get_rotation_quaternion()
	return out


## La posicion local del hueso (relativa al padre).
func _pos_local(id: int) -> Vector3:
	var padre := skel.get_bone_parent(id)
	if padre < 0:
		return rest[id].origin
	return rest[padre].basis.inverse() * (rest[id].origin - rest[padre].origin)
