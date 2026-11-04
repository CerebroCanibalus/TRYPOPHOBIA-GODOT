@tool
extends RefCounted
class_name ArmatureAnimationKeyService

## Servicio de creacion de pistas y claves de animacion para huesos modificados.
##
## QUE ES "HUESO MODIFICADO": aquel cuya pose actual (posicion/rotacion/escala)
## difiere de su pose de reposo (`rest`). Es sin estado: se recalcula en cada
## llamada, asi que no hay que "avisar" de los cambios ni limpiar nada.
##
## Editar el `rest` (modo Edit del gizmo) NO cuenta como modificado: el `rest`
## es la pose de ligadura y no se anima.
##
## RUTAS DE PISTA: `<ruta_relativa_del_skeleton>:<nombre_del_hueso>`, relativo
## al `root_node` del AnimationPlayer (p.ej. `metarig/Skeleton3D:spine`). Es el
## mismo formato que usa el editor nativo de Godot, de modo que las pistas
## creadas aqui son indistinguibles de las creadas por el boton nativo.
##
## CONVENCIO DE VALORES (copiado del editor nativo de Godot 4.7,
## `Skeleton3DEditor::_insert_keys`):
##   - posicion: `get_bone_pose_position() / get_motion_scale()`
##   - rotacion: `get_bone_pose_rotation()`
##   - escala:   `get_bone_pose_scale()`
##
## DESHACER/REHACER: se registra en el `EditorUndoRedoManager` del plugin, asi
## que Ctrl+Z funciona y la escena queda marcada como modificada. Las acciones
## de deshacer estan escritas de forma INDEPENDIENTE DEL ORDEN (ver notas en
## `insert_tracks` e `insert_keys`), para que funcionen igual aunque Godot las
## ejecute en orden inverso al registro.

const MASK_POSITION := 1
const MASK_ROTATION := 2
const MASK_SCALE := 4

## Tolerancia para comparar quaterniones (en radianes).
const ANGLE_EPSILON := 0.0001

var context: ArmatureSkeletonContext = null
var undo_redo: Object = null

## Mascara de tipos de pista seleccionada. Compartida por todos los paneles.
var track_mask: int = MASK_ROTATION

## Huesos que el gizmo acaba de transformar (informativo).
##
## La deteccion real de "hueso modificado" se recalcula comparando la pose
## contra el `rest` (ver `modified_bones`), que es mas fiable que depender de
## que el gizmo avise.
var _gizmo_modified: Array[int] = []


## Asigna las dependencias del servicio.
func set_dependencies(p_context: ArmatureSkeletonContext, p_undo_redo: Object) -> void:
	context = p_context
	undo_redo = p_undo_redo


## Registra los huesos que el gizmo acaba de transformar.
##
## @param bone_indices Indices de huesos modificados.
func note_bones_modified(bone_indices: Array) -> void:
	for value in bone_indices:
		var bone := int(value)
		if not _gizmo_modified.has(bone):
			_gizmo_modified.append(bone)


## Devuelve los ultimos huesos modificados por el gizmo.
##
## @return Indices de huesos modificados.
func gizmo_modified_bones() -> Array[int]:
	return _gizmo_modified.duplicate()


## Actualiza la mascara de tipos de pista.
##
## @param mask Combinacion de MASK_POSITION / MASK_ROTATION / MASK_SCALE.
func set_track_mask(mask: int) -> void:
	track_mask = mask


## Encuentra el AnimationPlayer del escenario abierto.
##
## Prioriza el que tiene una animacion asignada: es el que esta editando el
## panel Animation de abajo (el panel llama a `set_assigned_animation()`).
##
## @return AnimationPlayer encontrado o null.
func find_animation_player() -> AnimationPlayer:
	if context == null or context.editor_interface == null:
		return null
	var root := context.editor_interface.get_edited_scene_root()
	if root == null:
		return null
	var players := _collect_players(root)
	for player in players:
		if player.get_assigned_animation() != StringName():
			return player
	var named := root.get_node_or_null(NodePath("%AnimationPlayer")) as AnimationPlayer
	if named != null:
		return named
	for player in players:
		if String(player.name) == "AnimationPlayer":
			return player
	return players[0] if not players.is_empty() else null


## Devuelve la animacion que se esta editando ahora mismo en el panel Animation.
##
## El panel de Animation asigna la animacion seleccionada al AnimationPlayer,
## asi que `assigned_animation` es la fuente de verdad.
##
## @return Animation en edicion o null si no hay ninguna.
func current_animation(player: AnimationPlayer) -> Animation:
	if player == null:
		return null
	var anim_name := player.get_assigned_animation()
	if anim_name == StringName() or not player.has_animation(anim_name):
		return null
	return player.get_animation(anim_name)


## Devuelve el tiempo (playhead) actual del AnimationPlayer.
##
## El panel Animation sincroniza su cursor con
## `AnimationPlayer.get_current_animation_position()` (el editor nativo usa
## exactamente este valor), asi que es la misma cifra que ve el usuario.
##
## @param player AnimationPlayer del escenario.
## @return Tiempo en segundos.
func current_time(player: AnimationPlayer) -> float:
	if player == null:
		return 0.0
	# `get_current_animation_position()` AVISA por consola si no hay animacion
	# asignada, asi que solo se llama con una animacion valida.
	if player.get_assigned_animation() == StringName():
		return 0.0
	return player.get_current_animation_position()


## Devuelve la ruta del skeleton relativa al `root_node` del AnimationPlayer.
##
## @param player AnimationPlayer del escenario.
## @param skeleton Skeleton3D objetivo.
## @return Ruta relativa (p.ej. `metarig/Skeleton3D`).
func relative_skeleton_path(player: AnimationPlayer, skeleton: Skeleton3D) -> String:
	if player == null or skeleton == null:
		return ""
	var anim_root := player.get_node_or_null(player.get_root_node())
	if anim_root == null:
		anim_root = player
	return str(anim_root.get_path_to(skeleton))


## Devuelve la ruta del skeleton usando nombres unicos (`%Skeleton3D`).
##
## El editor nativo de Godot construye las rutas con
## `get_path_to(skeleton, true)`, que usa el nombre unico cuando el nodo lo
## tiene. Se usa como segunda opcion al buscar pistas ya existentes.
##
## @param player AnimationPlayer del escenario.
## @param skeleton Skeleton3D objetivo.
## @return Ruta relativa con nombres unicos.
func unique_skeleton_path(player: AnimationPlayer, skeleton: Skeleton3D) -> String:
	if player == null or skeleton == null:
		return ""
	var anim_root := player.get_node_or_null(player.get_root_node())
	if anim_root == null:
		anim_root = player
	return str(anim_root.get_path_to(skeleton, true))


## Lista los huesos cuya pose difiere de su pose de reposo.
##
## @param skeleton Skeleton3D a inspeccionar.
## @return Indices de huesos modificados, en orden.
func modified_bones(skeleton: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	if skeleton == null:
		return out
	for i in range(skeleton.get_bone_count()):
		if is_bone_modified(skeleton, i):
			out.append(i)
	return out


## Indica si un hueso tiene la pose modificada respecto a su `rest`.
##
## @param skeleton Skeleton3D a inspeccionar.
## @param bone Indice del hueso.
## @return true si la pose difiere del reposo.
func is_bone_modified(skeleton: Skeleton3D, bone: int) -> bool:
	if skeleton == null:
		return false
	if bone < 0 or bone >= skeleton.get_bone_count():
		return false
	var rest := skeleton.get_bone_rest(bone)
	var rest_rot := rest.basis.get_rotation_quaternion()
	var pose_rot := skeleton.get_bone_pose_rotation(bone)
	# `Quaternion.angle_to()` ya tiene en cuenta el signo (q y -q son la misma
	# rotacion), asi que no hay que normalizar antes de comparar.
	if absf(pose_rot.angle_to(rest_rot)) > ANGLE_EPSILON:
		return true
	if not skeleton.get_bone_pose_position(bone).is_equal_approx(rest.origin):
		return true
	if not skeleton.get_bone_pose_scale(bone).is_equal_approx(rest.basis.get_scale()):
		return true
	return false


## Crea las pistas que falten para los huesos indicados y pone una clave inicial.
##
## No toca las pistas que ya existen. La clave se inserta en el tiempo actual
## con el valor de pose actual del hueso.
##
## NOTA SOBRE EL DESHACER: todas las acciones de deshacer borran la pista en el
## MISMO indice (`base_index`, el numero de pistas que habia antes de empezar).
## Al borrar una pista, las siguientes se desplazan y vuelven a ocupar ese
## indice, asi que el resultado no depende del orden en que se ejecuten.
##
## @param skeleton Skeleton3D origen de los valores.
## @param anim Animacion destino.
## @param bones Indices de los huesos a keyar.
## @param time Tiempo donde insertar la clave.
## @param rel_path Ruta relativa del skeleton (p.ej. `metarig/Skeleton3D`).
## @param mask Mascara MASK_POSITION/MASK_ROTATION/MASK_SCALE.
## @return Numero de pistas creadas.
func insert_tracks(skeleton: Skeleton3D, anim: Animation, bones: Array[int], time: float, rel_path: String, mask: int) -> int:
	if skeleton == null or anim == null or rel_path.is_empty():
		return 0
	var types := _types_from_mask(mask)
	if types.is_empty():
		return 0
	var created := 0
	var base_index := anim.get_track_count()
	var next_index := base_index
	var old_length := anim.length
	var new_length := maxf(old_length, time)

	_begin_action("Insert Animation Tracks")
	for bone in bones:
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name.is_empty():
			continue
		for type in types:
			if _find_track(anim, rel_path, bone_name, type) != -1:
				continue
			var value := _value_for(skeleton, bone, type)
			if value == null:
				continue
			var path := _track_path(rel_path, bone_name)
			_add_do(anim, "add_track", [type])
			_add_do(anim, "track_set_path", [next_index, path])
			_add_do(anim, "track_insert_key", [next_index, time, value])
			_add_undo(anim, "remove_track", [base_index])
			next_index += 1
			created += 1

	if created > 0 and new_length > old_length:
		_add_do(anim, "set_length", [new_length])
		_add_undo(anim, "set_length", [old_length])

	_commit_action()
	if created > 0:
		anim.emit_changed()
	return created


## Inserta (o sobrescribe) claves en las pistas existentes de los huesos indicados.
##
## No crea pistas: si un hueso no tiene pista para ese tipo, se salta.
##
## NOTA SOBRE EL DESHACER: si ya habia una clave en ese tiempo, el deshacer
## vuelve a escribir su valor anterior (`track_insert_key` REEMPLAZA la clave
## que hay en ese tiempo). Si no habia ninguna, el deshacer la borra. Cada
## caso es una sola accion, asi que el orden no importa.
##
## @param skeleton Skeleton3D origen de los valores.
## @param anim Animacion destino.
## @param bones Indices de los huesos a keyar.
## @param time Tiempo donde insertar la clave.
## @param rel_path Ruta relativa del skeleton (p.ej. `metarig/Skeleton3D`).
## @param mask Mascara MASK_POSITION/MASK_ROTATION/MASK_SCALE.
## @return Numero de claves insertadas.
func insert_keys(skeleton: Skeleton3D, anim: Animation, bones: Array[int], time: float, rel_path: String, mask: int) -> int:
	if skeleton == null or anim == null or rel_path.is_empty():
		return 0
	var types := _types_from_mask(mask)
	if types.is_empty():
		return 0
	var inserted := 0
	var old_length := anim.length
	var new_length := maxf(old_length, time)

	_begin_action("Insert Animation Keys")
	for bone in bones:
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name.is_empty():
			continue
		for type in types:
			var track := _find_track(anim, rel_path, bone_name, type)
			if track == -1:
				continue
			var value := _value_for(skeleton, bone, type)
			if value == null:
				continue
			var existing := anim.track_find_key(track, time, Animation.FIND_MODE_APPROX)
			var old_value: Variant = null
			var old_transition := 1.0
			if existing != -1:
				old_value = anim.track_get_key_value(track, existing)
				old_transition = anim.track_get_key_transition(track, existing)
			_add_do(anim, "track_insert_key", [track, time, value])
			if existing != -1:
				# Sobrescribe la clave: para deshacer se vuelve a escribir el
				# valor anterior en ese mismo tiempo.
				_add_undo(anim, "track_insert_key", [track, time, old_value, old_transition])
			else:
				_add_undo(anim, "track_remove_key_at_time", [track, time])
			inserted += 1

	if inserted > 0 and new_length > old_length:
		_add_do(anim, "set_length", [new_length])
		_add_undo(anim, "set_length", [old_length])

	_commit_action()
	if inserted > 0:
		anim.emit_changed()
	return inserted


## Atajo de alto nivel: crea pistas para los huesos modificados de la escena.
##
## @param mask Mascara MASK_POSITION/MASK_ROTATION/MASK_SCALE.
## @param skeleton Skeleton3D a usar (por defecto, el seleccionado).
## @return Numero de pistas creadas.
func perform_insert_tracks(mask: int, skeleton: Skeleton3D = null) -> int:
	var parts := _resolve(skeleton)
	if parts.is_empty():
		return 0
	var bones := modified_bones(parts["skeleton"])
	if bones.is_empty():
		return 0
	return insert_tracks(parts["skeleton"], parts["anim"], bones, current_time(parts["player"]), parts["rel_path"], mask)


## Atajo de alto nivel: inserta claves en las pistas existentes de los huesos modificados.
##
## @param mask Mascara MASK_POSITION/MASK_ROTATION/MASK_SCALE.
## @param skeleton Skeleton3D a usar (por defecto, el seleccionado).
## @return Numero de claves insertadas.
func perform_insert_modified(mask: int, skeleton: Skeleton3D = null) -> int:
	var parts := _resolve(skeleton)
	if parts.is_empty():
		return 0
	var bones := modified_bones(parts["skeleton"])
	if bones.is_empty():
		return 0
	return insert_keys(parts["skeleton"], parts["anim"], bones, current_time(parts["player"]), parts["rel_path"], mask)


## Resuelve skeleton + animacion + player del escenario abierto.
##
## @param skeleton Skeleton3D a usar (por defecto, el seleccionado).
## @return Diccionario con `skeleton`, `anim`, `player` y `rel_path`.
func _resolve(skeleton: Skeleton3D = null) -> Dictionary:
	if context == null:
		return {}
	var skel := skeleton if skeleton != null else context.skeleton
	if skel == null:
		return {}
	var player := find_animation_player()
	if player == null:
		return {}
	var anim := current_animation(player)
	if anim == null:
		return {}
	var rel_path := relative_skeleton_path(player, skel)
	if rel_path.is_empty():
		return {}
	return {
		"skeleton": skel,
		"anim": anim,
		"player": player,
		"rel_path": rel_path,
	}


## Convierte la mascara en la lista de tipos de pista Animation.TYPE_*.
func _types_from_mask(mask: int) -> Array[int]:
	var types: Array[int] = []
	if mask & MASK_POSITION != 0:
		types.append(Animation.TYPE_POSITION_3D)
	if mask & MASK_ROTATION != 0:
		types.append(Animation.TYPE_ROTATION_3D)
	if mask & MASK_SCALE != 0:
		types.append(Animation.TYPE_SCALE_3D)
	return types


## Construye la ruta de pista de un hueso.
##
## @param rel_path Ruta relativa del skeleton.
## @param bone_name Nombre del hueso.
## @return NodePath de la pista.
func _track_path(rel_path: String, bone_name: String) -> NodePath:
	return NodePath(rel_path + ":" + bone_name)


## Busca la pista de un hueso, probando tambien la ruta con nombre unico.
##
## El editor nativo de Godot construye la ruta con `get_path_to(skeleton, true)`,
## que usa el nombre unico (`%Skeleton3D`) cuando el nodo lo tiene. Como las
## pistas pueden haber sido creadas por el editor nativo, se buscan las dos
## variantes para no crear duplicados.
##
## @param anim Animacion donde buscar.
## @param rel_path Ruta relativa del skeleton.
## @param bone_name Nombre del hueso.
## @param type Tipo de pista.
## @return Indice de la pista, o -1 si no existe.
func _find_track(anim: Animation, rel_path: String, bone_name: String, type: int) -> int:
	var track := anim.find_track(_track_path(rel_path, bone_name), type)
	if track != -1:
		return track
	var unique_rel := _unique_relative_path(rel_path)
	if unique_rel != rel_path:
		return anim.find_track(_track_path(unique_rel, bone_name), type)
	return -1


## Sustituye el ultimo tramo de la ruta por su nombre unico, si lo tiene.
##
## @param rel_path Ruta relativa del skeleton.
## @return Ruta relativa con nombre unico, o la misma si no se puede obtener.
func _unique_relative_path(rel_path: String) -> String:
	if context == null or context.skeleton == null:
		return rel_path
	var player := find_animation_player()
	if player == null:
		return rel_path
	var unique_rel := unique_skeleton_path(player, context.skeleton)
	if unique_rel.is_empty() or unique_rel == rel_path:
		return rel_path
	return unique_rel


## Valor de pista para un hueso y un tipo dados.
##
## @return Vector3 / Quaternion, o null si el tipo no aplica.
func _value_for(skeleton: Skeleton3D, bone: int, type: int) -> Variant:
	match type:
		Animation.TYPE_POSITION_3D:
			var motion_scale := skeleton.get_motion_scale()
			if motion_scale == 0.0:
				motion_scale = 1.0
			return skeleton.get_bone_pose_position(bone) / motion_scale
		Animation.TYPE_ROTATION_3D:
			return skeleton.get_bone_pose_rotation(bone).normalized()
		Animation.TYPE_SCALE_3D:
			return skeleton.get_bone_pose_scale(bone)
	return null


## Recoge los AnimationPlayer del arbol del escenario.
func _collect_players(node: Node, depth: int = 0) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	if depth > 8:
		return out
	if node is AnimationPlayer:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_players(child, depth + 1))
	return out


## Abre una accion de deshacer (silencioso si no hay gestor).
func _begin_action(action_name: String) -> void:
	if undo_redo == null:
		return
	undo_redo.call("create_action", action_name)


## Cierra la accion de deshacer.
func _commit_action() -> void:
	if undo_redo == null:
		return
	undo_redo.call("commit_action")


## Registra una operacion "hacer".
func _add_do(obj: Object, method: StringName, args: Array = []) -> void:
	if undo_redo == null:
		obj.callv(method, args)
		return
	var call_args: Array = [obj, method]
	call_args.append_array(args)
	undo_redo.callv("add_do_method", call_args)


## Registra una operacion "deshacer".
func _add_undo(obj: Object, method: StringName, args: Array = []) -> void:
	if undo_redo == null:
		return
	var call_args: Array = [obj, method]
	call_args.append_array(args)
	undo_redo.callv("add_undo_method", call_args)
