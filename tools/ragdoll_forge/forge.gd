extends SceneTree
## FORGE: genera el `RagdollRig` (y opcionalmente la escena) de un modelo
## sin que nadie tenga que medir huesos ni escribir tablas a mano.
##
## USO (CLI):
## {{{
##   godot --headless --path <proyecto> -s res://tools/ragdoll_forge/forge.gd -- \
##     --model=res://assets/players/shiba/shiba_V2.glb \
##     --body=spine --head=head \
##     --hands=hand.L,hand.R --feet=foot.L,foot.R \
##     --extra=spine.003,spine.005 \
##     --clips=res://src/player/shiba_anim.tres \
##     --rig=res://src/ragdoll/rig/shiba_rig_config.tres \
##     --scene=res://src/player/shiba_player.tscn
## }}}
##
## PARAMETROS:
##   --model=   (obligatorio) ruta del .glb
##   --body=    (obligatorio) hueso de la pelvis (recibe la velocidad)
##   --head=    (obligatorio) hueso de la cabeza
##   --hands=   lista de manos (o antebrazos) separados por coma
##   --feet=    lista de pies separados por coma
##   --extra=   huesos extra con cuerpo (columna, cuello...) separados por coma
##   --clips=   biblioteca de animacion de donde tomar los nombres de los clips
##   --rig=     donde guardar el .tres del rig
##   --scene=   (opcional) donde guardar la escena del personaje
##   --name=    nombre del nodo raiz de la escena (por defecto "Character")
##   --mass=    masa total del personaje en kg (por defecto 50)
##   --look=    huesos de la mirada separados por coma (base -> punta)
##   --lookw=   pesos de la mirada separados por coma
##
## Lo que hace el forge:
##  - mide la jerarquia del esqueleto y la longitud de cada hueso,
##  - **encuentra los "huesos puente"** que faltan para que la cadena de
##    articulaciones este completa (el error que mas veces ha roto al
##    ragdoll: un joint que no se crea porque al padre no le falta cuerpo),
##  - pone el collider de cada hueso del origen al de su hijo,
##  - reparte la masa PROPORCIONAL a la carga que soporta cada hueso (la
##    vertebra pesa lo que aguanta: sin esto el PD no puede sostener al
##    personaje),
##  - deduce la cadena IK de los brazos desde las manos,
##  - y escribe un INFORME con lo que ha tenido que deducir.

const PREFIJO := "--"


func _init() -> void:
	var args := _args()
	var opts := RigForge.Options.new()
	opts.model_path = _valor(args, "model")
	if opts.model_path == "":
		_error("falta --model")
		return
	opts.body_bone = StringName(_valor(args, "body"))
	opts.head_bone = StringName(_valor(args, "head"))
	opts.hands = _lista(args, "hands")
	opts.feet = _lista(args, "feet")
	opts.extra = _lista(args, "extra")
	opts.clips_path = _valor(args, "clips")
	opts.mass_total = float(_valor(args, "mass")) if _valor(args, "mass") != "" else 50.0
	var look := _lista(args, "look")
	if look.size() > 0:
		opts.head_look_bones = PackedStringArray()
		for h in look:
			opts.head_look_bones.append(String(h))
		var pesos := _lista(args, "lookw")
		opts.head_look_weights = PackedFloat32Array()
		for p in pesos:
			opts.head_look_weights.append(float(p))
	if opts.body_bone == &"" or opts.head_bone == &"":
		_error("faltan --body y --head")
		return

	var res := RigForge.forge(opts)
	if res.rig == null:
		for w in res.warnings:
			printerr("[forge] " + w)
		_error("no se pudo generar el rig")
		return

	print("[forge] modelo: %s" % opts.model_path)
	print("[forge] huesos con cuerpo: %d" % res.rig.physical_bones.size())
	if res.bridges.size() > 0:
		print("[forge] HUESOS PUENTE anadidos (sin ellos los joints no se crean):")
		for b in res.bridges:
			print("        + %s" % b)
	for w in res.warnings:
		printerr("[forge] aviso: " + w)
	print("[forge] clips encontrados: %s" % ", ".join(res.clips_found))
	print("[forge] masa total: %.1f kg" % _masa_total(res.rig))

	# --- Informe de validacion -----------------------------------------
	var rep := RigReport.validate(res.rig)
	print(RigReport.to_text(rep))
	if rep.errors.size() > 0:
		printerr("[forge] el rig generado tiene %d error(es): no se guarda" % rep.errors.size())
		quit(1)
		return

	# --- Guardar el rig -------------------------------------------------
	var ruta_rig := _valor(args, "rig")
	if ruta_rig != "":
		var err := ResourceSaver.save(res.rig, ruta_rig)
		print("[forge] rig guardado en %s (err=%d)" % [ruta_rig, err])

	# --- Guardar la escena ----------------------------------------------
	var ruta_scene := _valor(args, "scene")
	if ruta_scene != "":
		var sopt := RagdollSceneBuilder.Options.new()
		sopt.model_path = opts.model_path
		sopt.rig = res.rig
		sopt.clips_path = opts.clips_path
		sopt.output_path = ruta_scene
		sopt.root_name = _valor(args, "name")
		if sopt.root_name == "":
			sopt.root_name = "Character"
		var err2 := RagdollSceneBuilder.build_and_save(sopt)
		print("[forge] escena guardada en %s (err=%d)" % [ruta_scene, err2])
	quit(0)


func _masa_total(rig: RagdollRig) -> float:
	var t := 0.0
	for b in rig.physical_bones:
		t += b.mass
	return t


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with(PREFIJO) and a.contains("="):
			var k := a.substr(PREFIJO.length(), a.find("=") - PREFIJO.length())
			var v := a.substr(a.find("=") + 1)
			out[k] = v
	return out


func _valor(args: Dictionary, clave: String) -> String:
	return String(args.get(clave, ""))


func _lista(args: Dictionary, clave: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var s := String(args.get(clave, ""))
	if s == "":
		return out
	for p in s.split(",", false):
		out.append(StringName(p.strip_edges()))
	return out


func _error(msg: String) -> void:
	printerr("[forge] ERROR: " + msg)
	quit(1)
