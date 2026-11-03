extends RefCounted
class_name RagdollSceneBuilder
## CONSTRUCTOR DE ESCENAS de ragdoll: monta el personaje completo a partir
## de un modelo y de un `RagdollRig`.
##
## Antes esto vivia en scripts de un solo uso (`.heren/tmp/build_*.gd`) que
## se perdian con el tiempo y obligaban a reescribirlo para cada rig. Con
## esto, poner un modelo nuevo en el juego es:
##
## {{{
##   var opts := RagdollSceneBuilder.Options.new()
##   opts.model_path = "res://assets/players/shiba/shiba_V2.glb"
##   opts.rig = load("res://.../shiba_rig.tres")
##   opts.output_path = "res://src/player/shiba_player.tscn"
##   RagdollSceneBuilder.build_and_save(opts)
## }}}
##
## TRAMPAS que esta escena respeta (todas medidas):
##
## - El GLB mira a su +Z local y el sistema usa "+Z = adelante" con la
##   camara mirando a -Z: sin el giro de 180 grados el personaje camina
##   HACIA la camara.
## - Las dos instancias del GLB (fisica y animacion) NO se marcan como
##   editables: al guardar, Godot INLINEA las mallas (el Shiba las tiene
##   como hijas del esqueleto) y el Skin deja de enlazar.
## - Los `PhysicalBone3D` NO van en la escena: el runtime los crea
##   dentro del simulador, en orden de jerarquia (padres antes que
##   hijos). Un PhysicalBone3D crea su joint en `_ready`: si entra al
##   arbol fuera del esqueleto (o antes que su padre), el joint NUNCA
##   se crea y el ragdoll es un saco de huesos sueltos (medido: la
##   cadena se abria 0,8 m).
## - El `AnimationTree` va en un subnodo `Anim/` con `root_node = "../.."`
##   (el Mixer exige un ancestro) y las pistas llevan la ruta completa.

const SCRIPT_CHARACTER := "res://src/ragdoll/character/ragdoll_character.gd"
const SCRIPT_CAMERA := "res://src/ragdoll/character/ragdoll_camera.gd"
const SCRIPT_POINTER := "res://src/ragdoll/character/ragdoll_pointer.gd"
const SCRIPT_RETICLE := "res://src/ragdoll/character/pointer_reticle.gd"
const PREFAB_AGUA := "res://src/water/nodos/cuerpo_agua.tscn"
const PREFAB_OXIGENO := "res://src/water/nodos/oxigeno.tscn"
const PREFAB_DISTORSION := "res://src/water/nodos/distorsion_submarina.tscn"


## Opciones de la construccion.
class Options extends RefCounted:
	## Ruta del modelo (.glb).
	var model_path := ""
	## El rig con los datos (obligatorio).
	var rig: RagdollRig = null
	## Nombre del nodo raiz.
	var root_name := "Character"
	## Ruta donde se guarda la escena ("" = no guardar).
	var output_path := ""
	## Biblioteca de animacion con los clips ("" = la del rig).
	var clips_path := ""
	## Anadir los componentes de agua (inertes si el mapa no tiene agua).
	var with_water := true
	## Montar el HUD y el puntero.
	var with_hud := true
	## Girar el modelo 180 grados (el GLB mira a su +Z local).
	var flip_model := true
	## Parametros de la camara.
	var camera_distance := 3.6
	var camera_side := 0.65
	var camera_height := 0.22
	var camera_pivot_height := 0.05
	var head_distance := 0.10
	var head_height := 0.13
	var third_person := true
	## Radio del recorte de 1a persona.
	var fp_clip_radius := 0.20
	## Ganancias del PD.
	var stiffness := 2500.0
	var damping := 100.0
	var max_angular_accel := 1500.0
	var max_angular_speed := 6.0


## Construye la escena y la guarda. Devuelve el error del guardado.
static func build_and_save(opts: Options) -> Error:
	var root := build(opts)
	if root == null:
		return ERR_CANT_CREATE
	if opts.output_path == "":
		return OK
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	return ResourceSaver.save(packed, opts.output_path)


## Construye la escena en memoria y devuelve el nodo raiz.
static func build(opts: Options) -> Node3D:
	if opts.rig == null:
		push_error("[RagdollSceneBuilder] falta el rig")
		return null
	var root := Node3D.new()
	root.name = opts.root_name
	root.set_script(load(SCRIPT_CHARACTER))
	root.set("rig_config", opts.rig)
	root.set("angular_spring_stiffness", opts.stiffness)
	root.set("angular_spring_damping", opts.damping)
	root.set("max_angular_accel", opts.max_angular_accel)
	root.set("max_angular_speed", opts.max_angular_speed)
	root.set("fp_clip_radius", opts.fp_clip_radius)
	root.set("body_follows_camera", false)
	root.set("head_look_enabled", true)
	root.set("head_yaw_max_degrees", 55.0)
	root.set("head_pitch_max_degrees", 30.0)
	root.set("body_turn_speed", 7.0)
	root.set("lean_max_degrees", 2.0)

	var giro := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) if opts.flip_model else Transform3D.IDENTITY

	# --- LAS DOS INSTANCIAS DEL MODELO ---------------------------------
	var physical := _instancia(opts.model_path, "Physical", root)
	physical.transform = giro
	var phys_skel := physical.find_child("Skeleton3D", true, false) as Skeleton3D
	if phys_skel == null:
		push_error("[RagdollSceneBuilder] el modelo no tiene Skeleton3D")
		return null

	var animated := _instancia(opts.model_path, "Animated", root)
	animated.transform = giro
	var anim_skel := animated.find_child("Skeleton3D", true, false) as Skeleton3D
	if anim_skel == null:
		push_error("[RagdollSceneBuilder] el modelo no tiene Skeleton3D")
		return null
	anim_skel.visible = false

	# --- ANIMACION ------------------------------------------------------
	_construir_animacion(opts, root)

	# --- CAMARA ---------------------------------------------------------
	_construir_camara(opts, root, phys_skel)

	# --- PUNTERO, HUD Y AGARRES -----------------------------------------
	_construir_misc(opts, root)

	# --- LOS HUESOS FISICOS -------------------------------------------------
	# NO se authoran en la escena: el runtime los crea dentro del
	# simulador (ver RagdollSkeleton). Un PhysicalBone3D crea su joint en
	# _ready: si entra al arbol fuera del esqueleto (o antes que su padre),
	# el joint NUNCA se crea y el ragdoll queda como un saco de huesos
	# sueltos (medido: la cadena se abrio 0,8 m).
	return root


# --- Piezas -----------------------------------------------------------------

static func _instancia(path: String, node_name: String, parent: Node) -> Node3D:
	var packed: PackedScene = load(path)
	var inst := packed.instantiate() as Node3D
	inst.name = node_name
	parent.add_child(inst)
	inst.owner = parent.get_owner() if parent.get_owner() != null else parent
	return inst


## AnimationPlayer + AnimationTree en un subnodo "Anim".
##
## El `root_node` es "../.." (la raiz de la escena): el AnimationMixer
## RECHAZA un root_node que no sea un ancestro ("invalid root_node path").
static func _construir_animacion(opts: Options, root: Node) -> void:
	var anim_node := Node.new()
	anim_node.name = "Anim"
	root.add_child(anim_node)
	anim_node.owner = root

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	var lib_path := opts.clips_path if opts.clips_path != "" else ""
	var lib: AnimationLibrary = null
	if lib_path != "" and ResourceLoader.exists(lib_path):
		lib = load(lib_path)
	if lib != null:
		ap.add_animation_library("", lib)
	ap.autoplay = ""
	# El root_node del Mixer tiene que ser un ANCESTRO y las pistas se
	# resuelven desde ahi. "../.." desde "Anim/AnimationPlayer" es el
	# PERSONAJE (el padre del nodo "Anim"), que es donde vive el esqueleto
	# animado: las pistas quedan "Animated/metag/Skeleton3D:<hueso>".
	ap.root_node = NodePath("../..")
	anim_node.add_child(ap)
	ap.owner = root

	var rig := opts.rig
	var bt := AnimationNodeBlendTree.new()
	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = rig.clip_walk
	# El BlendSpace de direccion: en el CENTRO va el clip de REPOSO (el idle)
	# y en los extremos las poses inclinadas. Si el centro no es el idle, el
	# personaje se queda en una pose de agarre en vez de en la de reposo
	# (medido: el clip de paseo no llegaba al esqueleto).
	var n_lo := AnimationNodeAnimation.new()
	n_lo.animation = rig.clip_grab_lower
	var n_mid := AnimationNodeAnimation.new()
	n_mid.animation = rig.clip_idle
	var n_hi := AnimationNodeAnimation.new()
	n_hi.animation = rig.clip_grab_upper
	var space := AnimationNodeBlendSpace1D.new()
	space.add_blend_point(n_lo, -1.0, -1, "lower")
	space.add_blend_point(n_mid, 0.0, -1, "middle")
	space.add_blend_point(n_hi, 1.0, -1, "upper")
	var blend := AnimationNodeBlend2.new()
	bt.add_node("walk", n_walk, Vector2(-460, 60))
	bt.add_node("lower", n_lo, Vector2(-460, 320))
	bt.add_node("middle", n_mid, Vector2(-460, 420))
	bt.add_node("upper", n_hi, Vector2(-460, 520))
	bt.add_node("grab_dir", space, Vector2(-220, 400))
	bt.add_node("walking", blend, Vector2(60, 200))
	# connect_node(receptor, indice_de_entrada, productor).
	bt.connect_node("walking", 0, "grab_dir")
	bt.connect_node("walking", 1, "walk")
	bt.connect_node("output", 0, "walking")

	var at := AnimationTree.new()
	at.name = "AnimationTree"
	at.anim_player = NodePath("../AnimationPlayer")
	at.root_node = NodePath("../..")
	at.tree_root = bt
	anim_node.add_child(at)
	at.owner = root

	# OJO: hay que cablear el AnimationPlayer y el AnimationTree al
	# personaje. Si no, el personaje los busca "por nombre" y encuentra el
	# AnimationPlayer que trae el propio GLB (con los clips importados), que
	# no es el que mueve la escena (medido: la animacion no llegaba al
	# esqueleto y el personaje se quedaba en T).
	#
	# Se pasan los NODOS, no un NodePath: estos @export son de tipo Node y
	# `set()` con un NodePath es un error de tipo (y Godot lo serializa
	# solo como NodePath al guardar).
	root.set("animation_player", ap)
	root.set("animation_tree", at)


static func _construir_camara(opts: Options, root: Node, phys_skel: Skeleton3D) -> void:
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.set_script(load(SCRIPT_CAMERA))
	root.add_child(pivot)
	pivot.owner = root
	pivot.set("physical_skel", phys_skel)
	pivot.set("head_distance", opts.head_distance)
	pivot.set("head_height", opts.head_height)
	pivot.set("position_smoothing", 0.03)
	pivot.set("mouse_sensitivity", 0.1)
	pivot.set("max_pitch_degrees", 85.0)
	pivot.set("third_person_enabled", opts.third_person)
	pivot.set("third_person_key", KEY_V)
	pivot.set("third_person_distance", opts.camera_distance)
	pivot.set("third_person_side", opts.camera_side)
	pivot.set("third_person_height", opts.camera_height)
	pivot.set("third_person_pivot_height", opts.camera_pivot_height)

	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 0.0
	arm.margin = 0.2
	pivot.add_child(arm)
	arm.owner = root

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	arm.add_child(cam)
	cam.owner = root

	var ray := RayCast3D.new()
	ray.name = "PointerRay"
	ray.set_script(load(SCRIPT_POINTER))
	ray.interact_range = 0.9
	cam.add_child(ray)
	ray.owner = root


static func _construir_misc(opts: Options, root: Node) -> void:
	var jt := Timer.new()
	jt.name = "JumpTimer"
	jt.one_shot = true
	root.add_child(jt)
	jt.owner = root

	for jn in ["GrabJointLeft", "GrabJointRight"]:
		var pj := PinJoint3D.new()
		pj.name = jn
		root.add_child(pj)
		pj.owner = root

	var pointer := Node3D.new()
	pointer.name = "Pointer"
	root.add_child(pointer)
	pointer.owner = root

	for n in ["HandTargetL", "HandTargetR"]:
		var h := Node3D.new()
		h.name = n
		root.add_child(h)
		h.owner = root

	if opts.with_hud:
		var hud := CanvasLayer.new()
		hud.name = "HUD"
		root.add_child(hud)
		hud.owner = root
		var reticle := Control.new()
		reticle.name = "Reticle"
		reticle.set_script(load(SCRIPT_RETICLE))
		reticle.set("anchors_preset", 0)
		hud.add_child(reticle)
		reticle.owner = root

	if opts.with_water:
		_prefab(PREFAB_AGUA, "Agua", root)
		_prefab(PREFAB_OXIGENO, "Oxigeno", root)
		_prefab(PREFAB_DISTORSION, "DistorsionAgua", root)


static func _prefab(path: String, node_name: String, root: Node) -> void:
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	var inst := packed.instantiate()
	inst.name = node_name
	root.add_child(inst)
	inst.owner = root
