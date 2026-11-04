extends RefCounted
class_name RigForge
## FABRICA de rigs: construye un `RagdollRig` a partir de un modelo, sin
## que nadie tenga que medir huesos ni escribir tablas a mano.
##
## POR QUE EXISTE: poner un modelo nuevo en el sistema de ragdoll a mano
## es PROPENSO A FALLAR en tres sitios concretos, y los tres se han
##_{{\bf\*fallado de verdad en este repo}}:
##
## 1. **La cadena de cuerpos tiene que ser completa.** El joint de un
##    `PhysicalBone3D` se crea contra el cuerpo del PADRE del hueso: si el
##    padre no tiene cuerpo, el joint NO se crea y el hueso queda suelto.
##    En el Shiba faltaban 5 cuerpos (`spine.001/002/004`,
##    `shoulder.L/R`) y los brazos iban sueltos del pecho. El forge los
##    **encuentra solo** (huesos puente).
##
## 2. **Las masas.** El error de equilibrio del PD es
##    `τ_gravedad/(I·rigidez)` y `τ` es proporcional a la masa que CUELGA
##    del hueso: con 1 kg en todo, la pelvis no puede sostener el torso
##    (error de 54 grados). El forge reparte la masa entre los huesos
##    **proporcional a la carga que soportan**.
##
## 3. **Los colliders.** Deben ir del origen del hueso al de su hijo: el
##    forge mide la longitud de cada hueso y pone la capsula con el offset
##    correcto.
##
## Uso:
## {{{
##   var opts := ForgeOptions.new()
##   opts.model_path = "res://assets/players/shiba/shiba_V2.glb"
##   opts.body_bone = &"spine"
##   opts.head_bone = &"head"
##   opts.hands = [&"hand.L", &"hand.R"]
##   opts.feet = [&"foot.L", &"foot.R"]
##   var rig: RagdollRig = RigForge.forge(opts)
##   ResourceSaver.save(rig, "res://.../shiba_rig.tres")
## }}}


## Opciones del forge. Solo hay que declarar lo OBVIO (que hueso es el
## cuerpo, la cabeza, las manos y los pies); todo lo demas se deduce.
class Options extends RefCounted:
	## Ruta del modelo (.glb).
	var model_path := ""
	## Ruta del Skeleton3D dentro del modelo. Si se deja vacia se busca el
	## primer esqueleto del modelo.
	var skeleton_path := ""
	## Hueso que recibe la velocidad de caminar (la pelvis).
	var body_bone: StringName = &""
	## Hueso de la cabeza (ancla de la camara).
	var head_bone: StringName = &""
	## Huesos de las manos (el antebrazo si el rig lo tiene).
	var hands: Array[StringName] = []
	## Huesos de los pies.
	var feet: Array[StringName] = []
	## Huesos que ademas quieren cuerpo (columna, cuello, clavicula...).
	var extra: Array[StringName] = []
	## Meter los huesos "puente" que hagan falta para que la cadena este
	## completa (recomendado: es lo que evita el bug 1).
	var include_bridges := true
	## Masa total del personaje (kg).
	var mass_total := 50.0
	## Densidad lineal de referencia (kg por metro de hueso) antes de
	## normalizar.
	var linear_density := 8.0
	## Ganancia extra del PD para el hueso que mas carga soporta (la
	## pelvis). 1 = sin ganancia extra, 12 = la pelvis tiene 13 veces mas
	## rigidez que un dedo.
	var pd_gain_max := 12.0
	## Limite del joint en grados (180 = libre).
	var swing := 180.0
	var twist := 180.0
	## Clips (si se dejan vacios, el forge toma los que encuentre).
	var clip_idle: StringName = &""
	var clip_walk: StringName = &""
	var clip_grab_lower: StringName = &""
	var clip_grab_middle: StringName = &""
	var clip_grab_upper: StringName = &""
	## Biblioteca de animacion (.tres) de donde tomar los nombres de los
	## clips, si los clips NO estan en el modelo (el caso normal: los
	## clips se importan aparte).
	var clips_path := ""
	## Huesos de la cadena de la mirada (de la base a la punta) y su peso
	## (fraccion del giro). Es una decision de DISENO: el forge no la puede
	## deducir.
	var head_look_bones: PackedStringArray = PackedStringArray()
	var head_look_weights: PackedFloat32Array = PackedFloat32Array()
	## Cadenas IK de los brazos. Si se dejan vacias se deducen de las manos
	## (mano -> antebrazo -> brazo).
	var ik_arm_left := {}
	var ik_arm_right := {}
	## Token de nombre que marca los huesos de brazo y de pierna (para los
	## filtros del PD de los huesos que no declaran grupo).
	var arm_name_token := ""
	var leg_name_token := ""


## Resultado del forge: el rig + el informe de lo que se ha deducido.
class Result extends RefCounted:
	var rig: RagdollRig
	var bridges: Array[StringName] = []      ## Hunos-puente que se anadieron
	var warnings: PackedStringArray = []
	var clips_found: PackedStringArray = []


## Construye el rig. Devuelve null si el modelo no se puede leer.
static func forge(opts: Options) -> Result:
	var res := Result.new()
	if not ResourceLoader.exists(opts.model_path):
		res.warnings.append("el modelo no existe: " + opts.model_path)
		return res
	var packed: PackedScene = load(opts.model_path)
	if packed == null:
		res.warnings.append("no se pudo cargar el modelo: " + opts.model_path)
		return res
	var inst := packed.instantiate()
	var skel := _esqueleto_de(inst, opts.skeleton_path)
	if skel == null:
		res.warnings.append("el modelo no tiene Skeleton3D")
		inst.queue_free()
		return res

	var rig := RagdollRig.new()
	rig.model_path = opts.model_path
	rig.skeleton_path_in_model = _ruta_del_esqueleto(inst, skel)
	rig.body_bone_name = opts.body_bone
	rig.head_bone_name = opts.head_bone

	# --- 1) Que huesos lleva cuerpo ------------------------------------
	var con_cuerpo := {}
	var declarados: Array[StringName] = []
	declarados.append(opts.body_bone)
	declarados.append(opts.head_bone)
	declarados.append_array(opts.hands)
	declarados.append_array(opts.feet)
	declarados.append_array(opts.extra)
	for h in declarados:
		if h == &"":
			continue
		if skel.find_bone(h) < 0:
			res.warnings.append("el modelo no tiene el hueso '%s'" % h)
			continue
		con_cuerpo[h] = true

	# --- 2) Los HUESOS PUENTE: subir por los padres hasta el cuerpo ----
	# Esto es lo que evita que un hueso quede suelto por falta del padre.
	# Se añaden TODOS los intermedios, no solo el primero: si el pecho
	# (spine.003) tiene cuerpo pero entre el y la cabeza hay dos vertebras
	# sin, esas dos hacen falta o sus joints no se crean.
	if opts.include_bridges:
		for h in con_cuerpo.keys():
			var i := skel.find_bone(h)
			if i < 0:
				continue
			var p := skel.get_bone_parent(i)
			var guard := 0
			while p >= 0 and guard < 64:
				guard += 1
				var pn := StringName(skel.get_bone_name(p))
				if con_cuerpo.has(pn):
					break  # hemos llegado al cuerpo: la cadena esta
				con_cuerpo[pn] = true
				res.bridges.append(pn)
				p = skel.get_bone_parent(p)

	# --- 3) Tabla de huesos con sus colliders y masas -------------------
	# La COLUMNA: la cadena del cuerpo a la cabeza. El grupo "column" lo usa
	# el BalanceController para saber que hueso es el TORSO (el que hay que
	# enderezar). Si solo se marcara la pelvis, el balance no encontraria
	# torso y no haria NADA (medido: el personaje se quedaba tumbado con el
	# torso erguido).
	var columna := _cadena_entre(skel, opts.body_bone, opts.head_bone)

	# --- 3b) Masas y ganancia del PD -----------------------------------
	# La masa de un cuerpo es la de SU VOLUMEN: la suma de todas da el
	# peso real del personaje. La masa que un hueso SOPORTA NO va en la
	# masa (si no, el ragdoll pesa 4 veces lo que debe y la inercia
	# descoloca a los extremos): va en `pd_gain`, la ganancia del PD.
	#
	# La COLUMNA (para el BalanceController) se calcula antes.
	var volumenes := {}
	var vol_total := 0.0
	for h in con_cuerpo.keys():
		var largo := _longitud_hacia_hijo(skel, h)
		var v := 0.0
		if h == opts.body_bone:
			v = 0.36 * maxf(largo, 0.3) * 0.28
		else:
			var r := clampf(largo * 0.22, 0.05, 0.14)
			v = PI * r * r * maxf(largo, 0.05)
		volumenes[h] = v
		vol_total += v
	# La carga que soporta cada hueso (medida en unidades de volumen).
	var memo := {}
	for h in con_cuerpo.keys():
		_masa_recursiva(skel, h, con_cuerpo, memo, opts.linear_density)
	var carga_max := 0.0
	for h in con_cuerpo.keys():
		carga_max = maxf(carga_max, float(memo.get(h, 0.0)))
	for h in con_cuerpo.keys():
		var largo := _longitud_hacia_hijo(skel, h)
		var bone := RagdollBone.new()
		bone.bone_name = h
		# JOINT POR PIN (tipo 1), no cono (2): con un PD que manda sobre la
		# pose, los limites del cono solo estorban (medido: con cono, el
		# torso y la cabeza peleaban con el PD).
		bone.joint_type = 1
		var vol := float(volumenes.get(h, 0.0))
		bone.mass = maxf(0.05, opts.mass_total * vol / maxf(vol_total, 0.0001))
		# La ganancia del PD: proporcional a lo que este hueso SOPORTA.
		# Sin esto, el PD no puede sostener al torso contra la gravedad
		# (medido: 90 grados de error estatico en el pecho).
		bone.pd_gain = 1.0
		if carga_max > 0.0:
			bone.pd_gain = 1.0 + opts.pd_gain_max * (float(memo.get(h, 0.0)) / carga_max)
		bone.swing = opts.swing
		bone.twist = opts.twist
		bone.group = _grupo_de(h, opts, columna)
		if h == opts.body_bone:
			# La pelvis: caja (volumen) y sin limite extra.
			bone.shape = RagdollBone.Shape.BOX
			bone.size = Vector3(0.36, maxf(largo, 0.3), 0.28)
			bone.offset = bone.size.y * 0.5
			bone.radius = 0.18
		elif largo > 0.0:
			bone.shape = RagdollBone.Shape.CAPSULE
			bone.radius = clampf(largo * 0.22, 0.05, 0.14)
			bone.height = largo
			bone.offset = largo * 0.5
		else:
			bone.shape = RagdollBone.Shape.SPHERE
			bone.radius = 0.07
			bone.offset = 0.03
		rig.physical_bones.append(bone)

	# Ordenar por jerarquia (el padre antes que el hijo): el joint se crea
	# en orden y asi la cadena se monta bien.
	_ordenar_por_jerarquia(skel, rig.physical_bones)

	# --- 4) Nombres de los huesos que usan los filtros -----------------
	rig.arm_name_token = opts.arm_name_token if opts.arm_name_token != "" \
		else _token_de_lado(con_cuerpo, "arm")
	rig.leg_name_token = opts.leg_name_token if opts.leg_name_token != "" \
		else _token_de_lado(con_cuerpo, "leg")
	rig.grab_bone_left_name = _antebrazo(skel, opts.hands)
	rig.grab_bone_right_name = _antebrazo(skel, opts.hands, true)
	rig.on_floor_left_bone_name = opts.feet[0] if opts.feet.size() > 0 else &""
	rig.on_floor_right_bone_name = opts.feet[1] if opts.feet.size() > 1 else &""
	rig.lean_body_suffix = String(opts.body_bone)
	rig.lean_head_suffix = String(opts.head_bone)

	# --- 4b) Cadenas IK: de la mano hacia el hombro ---------------------
	if opts.ik_arm_left.is_empty() or opts.ik_arm_right.is_empty():
		var deducidas := _deducir_cadena_ik(skel, opts.hands)
		if opts.ik_arm_left.is_empty():
			rig.ik_arm_left = deducidas[0]
		else:
			rig.ik_arm_left = opts.ik_arm_left
		if opts.ik_arm_right.is_empty():
			rig.ik_arm_right = deducidas[1]
		else:
			rig.ik_arm_right = opts.ik_arm_right
	else:
		rig.ik_arm_left = opts.ik_arm_left
		rig.ik_arm_right = opts.ik_arm_right

	# --- 4c) Mirada de cabeza ------------------------------------------
	if opts.head_look_bones.size() > 0:
		rig.head_look_bones = opts.head_look_bones
		rig.head_look_weights = opts.head_look_weights
	else:
		# Por defecto: el ultimo hueso de la cadena (el de la cabeza).
		rig.head_look_bones = PackedStringArray([String(opts.head_bone)])
		rig.head_look_weights = PackedFloat32Array([1.0])

	# --- 5) Clips -------------------------------------------------------
	var clips := _clips_de(opts.clips_path)
	if clips.is_empty():
		clips = _clips_del_modelo(inst)
	res.clips_found = clips
	rig.clip_idle = opts.clip_idle if opts.clip_idle != &"" else _clip_simil(clips, "idle")
	rig.clip_walk = opts.clip_walk if opts.clip_walk != &"" else _clip_simil(clips, "walk")
	rig.clip_grab_lower = opts.clip_grab_lower if opts.clip_grab_lower != &"" else _clip_prefer(clips, ["lean_back", "grab_lower"])
	rig.clip_grab_middle = rig.clip_idle
	rig.clip_grab_upper = opts.clip_grab_upper if opts.clip_grab_upper != &"" else _clip_prefer(clips, ["lean_forward", "grab_upper"])
	for c in [rig.clip_idle, rig.clip_walk]:
		if c != &"" and not clips.has(String(c)):
			res.warnings.append("el clip '%s' no esta en el modelo (clips: %s)" % [c, ", ".join(clips)])

	inst.queue_free()
	res.rig = rig
	return res


# --- Utilidades -------------------------------------------------------------

static func _esqueleto_de(inst: Node, ruta: String) -> Skeleton3D:
	if ruta != "":
		return inst.find_child(ruta, true, false) as Skeleton3D
	for n in inst.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null


static func _ruta_del_esqueleto(inst: Node, skel: Skeleton3D) -> String:
	var partes: Array[String] = []
	var n: Node = skel
	while n != null and n != inst:
		partes.push_front(n.name)
		n = n.get_parent()
	return "/".join(partes)


## Padre del hueso que SI tiene cuerpo (sube por los intermedios).
static func _padre_con_cuerpo(skel: Skeleton3D, h: StringName, con_cuerpo: Dictionary) -> StringName:
	var i := skel.find_bone(h)
	if i < 0:
		return &""
	var p := skel.get_bone_parent(i)
	while p >= 0:
		var nombre := StringName(skel.get_bone_name(p))
		if con_cuerpo.has(nombre):
			return nombre
		p = skel.get_bone_parent(p)
	return &""


## Longitud del hueso: del origen de este al de su primer hijo.
static func _longitud_hacia_hijo(skel: Skeleton3D, h: StringName) -> float:
	var i := skel.find_bone(h)
	if i < 0:
		return 0.0
	for j in skel.get_bone_count():
		if skel.get_bone_parent(j) == i:
			var a := skel.get_bone_global_rest(i).origin
			var b := skel.get_bone_global_rest(j).origin
			return a.distance_to(b)
	return 0.0


## Masa que cuelga de cada hueso con cuerpo (sus descendientes con cuerpo).
static func _cargas(skel: Skeleton3D, con_cuerpo: Dictionary) -> Dictionary:
	var cargas := {}
	for h in con_cuerpo.keys():
		cargas[h] = 0.0
	for h in con_cuerpo.keys():
		var i := skel.find_bone(h)
		if i < 0:
			continue
		# Todos los huesos con cuerpo que son descendientes de h.
		for otro in con_cuerpo.keys():
			var j := skel.find_bone(otro)
			if j < 0 or j == i:
				continue
			if _es_descendiente(skel, j, i):
				cargas[h] = cargas.get(h, 0.0) + 1.0
	return cargas


static func _es_descendiente(skel: Skeleton3D, hijo: int, ancestro: int) -> bool:
	var p := skel.get_bone_parent(hijo)
	var guard := 0
	while p >= 0 and guard < 64:
		if p == ancestro:
			return true
		p = skel.get_bone_parent(p)
		guard += 1
	return false


## Token de nombre que identifica un grupo ("arm", "leg"...). Se busca el
## prefijo comun de los huesos del grupo.
static func _token_de_lado(con_cuerpo: Dictionary, grupo: String) -> String:
	var nombres := PackedStringArray()
	for h in con_cuerpo.keys():
		var n := String(h)
		if grupo == "arm" and (n.to_lower().contains("arm") or n.to_lower().contains("hand")):
			nombres.append(n)
		elif grupo == "leg" and (n.to_lower().contains("leg") or n.to_lower().contains("thigh") \
				or n.to_lower().contains("shin")):
			nombres.append(n)
	if nombres.is_empty():
		return ""
	var prefijo := ""
	for n in nombres:
		if prefijo == "":
			prefijo = n
			continue
		var i := 0
		while i < prefijo.length() and i < n.length() and prefijo[i] == n[i]:
			i += 1
		prefijo = prefijo.substr(0, i)
	return prefijo


## El antebrazo es el padre de la mano (el sitio donde va el area de agarre).
static func _antebrazo(skel: Skeleton3D, manos: Array[StringName], derecho := false) -> StringName:
	var mano: StringName = &""
	for h in manos:
		if derecho and String(h).to_lower().contains("r"):
			mano = h
			break
		if not derecho and String(h).to_lower().contains("l"):
			mano = h
			break
	if mano == &"" and manos.size() > 0:
		mano = manos[0]
	if mano == &"":
		return &""
	var i := skel.find_bone(mano)
	if i < 0:
		return &""
	var p := skel.get_bone_parent(i)
	if p < 0:
		return mano
	return StringName(skel.get_bone_name(p))


## Grupo del hueso: "column" (la cadena del cuerpo a la cabeza), "arm",
## "leg" o "" (neutro).
static func _grupo_de(h: StringName, opts: Options, columna: Dictionary) -> String:
	var n := String(h).to_lower()
	if columna.has(h):
		return "column"
	if n.contains("hand") or n.contains("arm") or n.contains("brazo"):
		return "arm"
	if n.contains("shin") or n.contains("thigh") or n.contains("leg") or n.contains("pierna"):
		return "leg"
	return ""


## Los huesos de la cadena que va del cuerpo a la cabeza (la columna).
## Se recorre desde la CABEZA hacia ARRIBA (por los padres) marcando todo
## hasta el cuerpo: la cadena se define por la jerarquia, no por un nombre.
static func _cadena_entre(skel: Skeleton3D, desde: StringName, hasta: StringName) -> Dictionary:
	var out := {}
	var i := skel.find_bone(hasta)
	var fin := skel.find_bone(desde)
	if i < 0:
		return out
	var guard := 0
	while i >= 0 and guard < 128:
		guard += 1
		out[StringName(skel.get_bone_name(i))] = true
		if i == fin:
			break
		i = skel.get_bone_parent(i)
	return out


## Clips que trae el modelo (los del AnimationPlayer o los de su
## AnimationLibrary).
static func _clips_del_modelo(inst: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		for lib in ap.get_animation_library_list():
			var l := ap.get_animation_library(lib)
			if l:
				for c in l.get_animation_list():
					if not out.has(String(c)):
						out.append(String(c))
	return out


## Clips de una biblioteca de animacion (.tres con AnimationLibrary).
static func _clips_de(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if path == "" or not ResourceLoader.exists(path):
		return out
	var lib := load(path)
	if lib == null:
		return out
	if lib is AnimationLibrary:
		for c in (lib as AnimationLibrary).get_animation_list():
			out.append(String(c))
	return out


## Deduce la cadena IK de un brazo: mano -> antebrazo -> brazo.
static func _deducir_cadena_ik(skel: Skeleton3D, manos: Array[StringName]) -> Array:
	var out: Array = [{}, {}]
	for lado in 2:
		var mano: StringName = &""
		for h in manos:
			var n := String(h).to_lower()
			if lado == 0 and n.contains("l"):
				mano = h
				break
			if lado == 1 and n.contains("r"):
				mano = h
				break
		if mano == &"" and manos.size() > lado:
			mano = manos[lado]
		if mano == &"":
			continue
		var i := skel.find_bone(mano)
		if i < 0:
			continue
		var medio := skel.get_bone_parent(i)
		if medio < 0:
			continue
		var raiz := skel.get_bone_parent(medio)
		if raiz < 0:
			continue
		out[lado] = {
			"root": StringName(skel.get_bone_name(raiz)),
			"mid": StringName(skel.get_bone_name(medio)),
			"end": StringName(skel.get_bone_name(i)),
		}
	return out


## Masa recursiva de un hueso: su volumen + la masa de lo que cuelga de el.
static func _masa_recursiva(skel: Skeleton3D, nombre: StringName,
		con_cuerpo: Dictionary, memo: Dictionary, densidad: float) -> float:
	if memo.has(nombre):
		return float(memo[nombre])
	memo[nombre] = 0.0
	var total := _longitud_hacia_hijo(skel, nombre) * densidad
	var i := skel.find_bone(nombre)
	if i >= 0:
		for j in skel.get_bone_count():
			if skel.get_bone_parent(j) != i:
				continue
			var hijo := StringName(skel.get_bone_name(j))
			if not con_cuerpo.has(hijo):
				continue
			total += _masa_recursiva(skel, hijo, con_cuerpo, memo, densidad)
	memo[nombre] = total
	return total


## Primer clip de la lista que exista (coincidencia exacta o parcial).
static func _clip_prefer(clips: PackedStringArray, candidatos: Array) -> StringName:
	for c in candidatos:
		var n := String(c)
		for clip in clips:
			if clip.to_lower() == n.to_lower():
				return StringName(clip)
	for c in candidatos:
		var n := String(c)
		for clip in clips:
			if clip.to_lower().contains(n.to_lower()):
				return StringName(clip)
	return &""


static func _clip_simil(clips: PackedStringArray, wanted: String) -> StringName:
	var w := wanted.to_lower()
	for c in clips:
		if c.to_lower() == w:
			return StringName(c)
	for c in clips:
		if c.to_lower().contains(w):
			return StringName(c)
	return &""


## Ordena la tabla por jerarquia (padre antes que hijo).
static func _ordenar_por_jerarquia(skel: Skeleton3D, huesos: Array[RagdollBone]) -> void:
	var profundidad := {}
	for b in huesos:
		profundidad[b.bone_name] = _profundidad(skel, b.bone_name)
	huesos.sort_custom(func(a: RagdollBone, b: RagdollBone):
		return profundidad.get(a.bone_name, 0) < profundidad.get(b.bone_name, 0))


static func _profundidad(skel: Skeleton3D, h: StringName) -> int:
	var i := skel.find_bone(h)
	var d := 0
	var p := skel.get_bone_parent(i)
	while p >= 0 and d < 64:
		d += 1
		p = skel.get_bone_parent(p)
	return d
