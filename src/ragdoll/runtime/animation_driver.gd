extends Node
class_name AnimationDriver
## El DRIVER DE ANIMACION: posee el `AnimationPlayer` y el `AnimationTree`,
## los deja en marcha y da acceso a la pose de cualquier hueso.
##
## Concentra las TRAMPAS del sistema de animacion, que son las que mas
## tiempo han costado:
##
## 1. **`AnimationTree.active` NO se serializa.** Es una propiedad de solo
##    runtime: al cargar la escena el arbol nace APAGADO y la animacion no
##    llega al esqueleto (medido: todos los huesos a 0 grados de su pose de
##    reposo, el personaje con los brazos en T y de espaldas). Hay que
##    activarlo a mano en `_ready()`.
##
## 2. **El `root_node` del AnimationMixer tiene que ser un ANCESTRO.**
##    `root_node = "Animated"` -> `invalid root_node path`. Con el arbol en
##    un subnodo, el `root_node` es la raiz de la escena ("../.." desde un
##    hijo) y las pistas llevan la ruta completa del esqueleto.
##
## 3. **Las pistas hay que reapuntarlas al esqueleto ANIMADO.** Los clips
##    importados traen la ruta del esqueleto de su propio modelo
##    ("metarig/Skeleton3D:spine"); hay que anteponer la ruta real del
##    esqueleto animado dentro de la escena. Este driver lo hace solo
##    (idempotente: reapuntar dos veces no rompe nada).
##
## 4. **El clip de reposo.** El BlendSpace de "direccion" mezcla poses
##    segun el pitch de la camara: en la coneja son poses de agarre y en
##    el Shiba poses de inclinacion. Si el nodo de reposo no esta en el
##    BlendSpace, el personaje se queda en la pose que toque.

## Rig con los nombres de los clips.
var rig: RagdollRig
## El `AnimationPlayer` con la biblioteca de clips.
var player: AnimationPlayer
## El `AnimationTree` (puede ser null si la escena no lo trae).
var tree: AnimationTree
## El esqueleto ANIMADO (el que escribe la animacion).
var animated_skel: Skeleton3D
## Ruta del esqueleto animado DESDE la raiz del personaje
## ("Animated/metag/Skeleton3D"): es la que llevan las pistas.
var skeleton_path := ""
## La raiz del personaje (a la que apuntan el root_node y las pistas).
var root_node: Node = null


## Monta el driver sobre la escena.
##
## `p_root` es el nodo raiz del personaje (el que lleva los esqueletos): el
## `root_node` del AnimationMixer y las rutas de las pistas se resuelven
## desde ahi. NO se usa `current_scene`: en headless es null y el arbol se
## queda sin resolver (medido: la animacion no llegaba al esqueleto).
func setup(p_rig: RagdollRig, p_player: AnimationPlayer, p_tree: AnimationTree,
		p_skel: Skeleton3D, p_skeleton_path: String, p_root: Node = null) -> void:
	rig = p_rig
	player = p_player
	tree = p_tree
	animated_skel = p_skel
	skeleton_path = p_skeleton_path
	root_node = p_root
	if player != null:
		_reapuntar_pistas()
		_configurar_clips()
	if tree != null:
		# TRAMPA 1: `active` no se serializa -> hay que activarlo aqui.
		tree.active = true
		if root_node != null and tree.is_inside_tree():
			var ruta := tree.get_path_to(root_node)
			if tree.root_node != ruta:
				tree.root_node = ruta
			if player != null and player.is_inside_tree():
				var ruta_p := player.get_path_to(root_node)
				if player.root_node != ruta_p:
					player.root_node = ruta_p
			print("[AnimationDriver] root_node: arbol=%s player=%s (esqueleto=%s)" % [
				str(tree.root_node), str(player.root_node if player else "-"), skeleton_path])


## ¿Ha escrito ya la animacion al esqueleto? (para alinear los cuerpos)
func animation_started() -> bool:
	if animated_skel == null:
		return false
	for i in animated_skel.get_bone_count():
		var pose := animated_skel.get_bone_pose_rotation(i)
		var rest := animated_skel.get_bone_rest(i).basis.get_rotation_quaternion()
		if not pose.is_equal_approx(rest):
			return true
	return false


## La pose global (en el espacio del esqueleto) de un hueso.
func pose_of(bone_id: int) -> Transform3D:
	if animated_skel == null:
		return Transform3D.IDENTITY
	return animated_skel.get_bone_global_pose(bone_id)


## La pose global de un hueso por nombre.
func pose_of_bone(bone_name: StringName) -> Transform3D:
	if animated_skel == null:
		return Transform3D.IDENTITY
	var i := animated_skel.find_bone(bone_name)
	if i < 0:
		return Transform3D.IDENTITY
	return animated_skel.get_bone_global_pose(i)


## Activa o desactiva el clip de paseo (mezcla con el de reposo).
func set_walking(caminando: bool) -> void:
	if tree == null:
		return
	tree.set("parameters/walking/blend_amount", 1.0 if caminando else 0.0)


## Posicion del BlendSpace de direccion (-1..1), normalmente el pitch.
func set_direction(valor: float) -> void:
	if tree == null:
		return
	tree.set("parameters/grab_dir/blend_position", valor)


## Reproduce un clip suelto (para efectos puntuales).
func play(clip: StringName) -> void:
	if player == null or clip == &"":
		return
	player.play(clip)


# --- Interno ---------------------------------------------------------------

## Reapunta las pistas de los clips al esqueleto animado. Idempotente.
func _reapuntar_pistas() -> void:
	if player == null or skeleton_path == "":
		return
	for lib_id in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_id)
		if lib == null:
			continue
		for clip_name in lib.get_animation_list():
			var anim := lib.get_animation(clip_name)
			if anim == null:
				continue
			for t in anim.get_track_count():
				var ruta := _reapuntar(anim.track_get_path(t))
				if ruta != anim.track_get_path(t):
					anim.track_set_path(t, ruta)


## "metarig/Skeleton3D:spine" -> "Shiba/Animated/metag/Skeleton3D:spine"
##
## La pista puede venir de tres sitios y todos tienen que acabar igual:
##   - con la ruta del MODELO ("metarig/Skeleton3D:spine"),
##   - con la ruta del modelo YA reapuntada ("Animated/metag/Skeleton3D:spine"),
##   - con cualquier otra ("spine" a pelo).
## La regla: si termina con la ruta del modelo, se sustituye por la ruta de
## la ESCENA (que ya lleva su propio nodo "Animated"); si no, se antepone.
func _reapuntar(path: NodePath) -> NodePath:
	var s := String(path)
	var sep := s.rfind(":")
	if sep < 0:
		return path
	var ruta := s.substr(0, sep)
	var hueso := s.substr(sep + 1)
	if ruta == skeleton_path:
		return path
	var ruta_modelo := ""
	if rig != null:
		ruta_modelo = rig.skeleton_path_in_model
	if ruta_modelo != "" and ruta.ends_with(ruta_modelo):
		return NodePath(skeleton_path + ":" + hueso)
	return NodePath(skeleton_path + "/" + ruta + ":" + hueso)


## Los clips de glTF vienen con loop_mode NONE: hay que forzarlo.
func _configurar_clips() -> void:
	if player == null or rig == null:
		return
	for clip_name in [rig.clip_idle, rig.clip_walk, rig.clip_grab_lower,
			rig.clip_grab_middle, rig.clip_grab_upper, rig.clip_grab_hold]:
		if clip_name == &"":
			continue
		if not player.has_animation(clip_name):
			continue
		var anim := player.get_animation(clip_name)
		if anim == null:
			continue
		if anim.length > 0.1 and anim.loop_mode == Animation.LOOP_NONE:
			anim.loop_mode = Animation.LOOP_LINEAR
