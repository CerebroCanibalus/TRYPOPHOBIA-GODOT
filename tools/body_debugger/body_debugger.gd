extends Node3D
## DEBUGGER DE CUERPO COMPLETO — agnostico al rig y multimodelo.
##
## POR QUE EXISTE: diagnosticar el ragdoll "a ojo" llevo a conclusiones FALSAS
## dos veces seguidas. Dos trampas que este tool resuelve de raiz:
##   1. `Skeleton3D.find_bone("Body")` devuelve 0, que NO es el hueso Body real.
##      El indice hay que sacarlo de `get_bone_name(i)`, no de find_bone().
##   2. Comparar el esqueleto fisico contra el animado en espacios distintos da
##      numeros basura (0.00 cuando en realidad hay 12 grados).
## Este tool muestra la VERDAD bone-por-bone: descubre TODOS los Skeleton3D bajo
## `target`, los compara POR NOMBRE de hueso y dibuja huesos + padres en 3D.
##
## Es multimodelo y agnostico: no hay un solo nombre de hueso hardcodeado, todo
## sale de `skeleton.get_bone_name(i)`. Funciona con cualquier rig (fursona,
## humanoid, lo que venga) y con cuantos esqueletos tenga el modelo.
##
## Uso: instanciar en cualquier escena y apuntar `target` al personaje (o dejar
## auto_find_target en true). Nada mas.

## Colores por esqueleto (A, B, C...). El primero suele ser el master/animado.
const SKELETON_COLORS := [
	Color(0.20, 0.90, 1.00),  # A - cian
	Color(1.00, 0.55, 0.15),  # B - naranja
	Color(0.45, 1.00, 0.35),  # C - verde
	Color(1.00, 0.35, 0.65),  # D - rosa
]

## Personaje a inspeccionar. Si queda null y auto_find_target esta activo, se
## busca el primer Skeleton3D del arbol de la escena.
@export var target: Node3D
@export var auto_find_target := true
## Dibujar huesos y lineas al padre en 3D.
@export var draw_enabled := true
## Refrescos por segundo (no hace falta mas de 10-15).
@export var update_hz := 10.0
## Indice del esqueleto B a comparar (-1 = no comparar). A siempre es el 0.
@export var compare_b := 1
## Resaltar en amarillo este hueso (por nombre). Vacio = ninguno.
@export var focus_bone := ""
## Marcar los huesos que existen en un esqueleto y no en el otro (asi se ve, por
## ejemplo, que un rig no tiene Neck fisico).
@export var show_missing := true
## Maximo de filas de la tabla (para que no se coma la pantalla).
@export var max_rows := 26
## Largo de la cruz que marca cada hueso (m).
@export var axis_length := 0.05
## Material del ImmediateMesh. Debe tener vertex_color_use_as_albedo y el depth
## test DESACTIVADO (para ver los huesos a traves de la malla).
@export var debug_material: Material

## Imprimir la tabla en consola: UNA vez al arrancar y OTRA a los
## `console_log_seconds`. La segunda es la que importa: muestra si la pose
## CONVERGE (arranque = reposo; a los 2 s = pose viva ya asentada).
@export var log_to_console := true
@export var console_log_seconds := 2.0

@onready var _mesh_instance: MeshInstance3D = $DebugMesh
@onready var _label: RichTextLabel = $HUD/Panel/Text

var _skeletons: Array[Skeleton3D] = []
var _accum := 0.0
var _interval := 0.1
var _logged_early := false
var _logged_late := false
var _t := 0.0
var _last_text := ""


func _ready() -> void:
	_interval = 1.0 / maxf(update_hz, 1.0)
	_ensure_target()
	_discover()
	_rebuild()


func _process(delta: float) -> void:
	_t += delta
	if log_to_console and not _logged_late and _t >= console_log_seconds:
		_logged_late = true
		_print_table(" (pose asentada @%.1fs)" % _t)
	_accum += delta
	if _accum < _interval:
		return
	_accum = 0.0
	if _skeletons.is_empty() or not is_instance_valid(target):
		_ensure_target()
		_discover()
	_rebuild()


func _print_table(tag: String = "") -> void:
	if _last_text.is_empty():
		return
	var plain := _last_text
	plain = plain.replace("[b]", "").replace("[/b]", "").replace("[table=5]", "")
	plain = plain.replace("[/table]", "").replace("[cell]", "| ").replace("[/cell]", " ")
	print("[body_debugger]%s\n%s" % [tag, plain])


## Resuelve `target` si no lo asignaron a mano: sube hasta la escena y busca el
## primer Skeleton3D. Devuelve el nodo duenio del esqueleto, no el esqueleto, para
## que find_children() despues encuentre TODOS los del personaje.
func _ensure_target() -> void:
	if target != null and is_instance_valid(target):
		return
	if not auto_find_target:
		return
	var root: Node = get_parent()
	if root == null and is_inside_tree():
		root = get_tree().current_scene
	if root == null:
		return
	# OJO: find_child() en esta version de Godot toma 3 argumentos (no acepta
	# `type`); find_children() si acepta los 4. Uso find_children y tomo el primero.
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var sk := found[0] as Skeleton3D
	if sk == null:
		return
	var owner_node: Node = sk.owner
	while owner_node != null and owner_node.get_parent() != null and owner_node.get_parent() != root:
		owner_node = owner_node.get_parent()
	target = (owner_node if owner_node is Node3D else sk.get_parent()) as Node3D


func _discover() -> void:
	_skeletons.clear()
	if target == null or not is_instance_valid(target):
		return
	for n in target.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		if sk != null:
			_skeletons.append(sk)


## Transform GLOBAL del hueso. Se compone a mano porque `get_bone_global_pose()`
## devuelve la pose en el espacio del esqueleto, no del mundo.
func _bone_world(sk: Skeleton3D, idx: int) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(idx)


## Inclinacion del eje Y del hueso respecto a la VERTICAL del mundo, en grados.
func _tilt_deg(sk: Skeleton3D, idx: int) -> float:
	return rad_to_deg(Vector3.UP.angle_to(_bone_world(sk, idx).basis.y.normalized()))


func _rebuild() -> void:
	if _label == null:
		return
	if _skeletons.is_empty():
		_label.text = "[b]BODY DEBUGGER[/b]\nNo encontre ningun Skeleton3D.\nAsigna `target` o activa auto_find_target."
		_draw()
		return
	var a: Skeleton3D = _skeletons[0]
	var b: Skeleton3D = null
	if compare_b >= 0 and _skeletons.size() > 1:
		b = _skeletons[clampi(compare_b, 0, _skeletons.size() - 1)]
		if b == a:
			b = null
	var text := _build_text(a, b)
	_label.text = text
	_last_text = text
	if log_to_console and not _logged_early:
		_logged_early = true
		_print_table(" (reposo @%.1fs)" % _t)
	_draw()


## Tabla bone-por-bone. Las columnas 2/3 son la inclinacion del hueso respecto a
## la vertical (dos esqueletos distintos por separado); la 4 es el DESACUERDO
## entre ambos para el MISMO nombre de hueso (fisico vs animado, etc).
func _build_text(a: Skeleton3D, b: Skeleton3D) -> String:
	var skel_names := PackedStringArray()
	for s in _skeletons:
		skel_names.append(s.name)
	var out := "[b]BODY DEBUGGER[/b]  target=%s\n" % [(target.name if target != null else "?")]
	out += "esqueletos (%d): %s\n" % [_skeletons.size(), ", ".join(skel_names)]
	out += "A=%s%s\n" % [a.name, ("   B=%s" % b.name) if b != null else "   (sin comparacion)"]
	out += "[table=5]"
	out += "[cell][b]hueso[/b][/cell][cell][b]%s[/b][/cell][cell][b]%s[/b][/cell][cell][b]delta[/b][/cell][cell][b]rest[/b][/cell]\n" % [
		a.name, b.name if b != null else "-"]

	var names_a: Array = []
	for i in a.get_bone_count():
		names_a.append(String(a.get_bone_name(i)))
	var union: Array = names_a.duplicate()
	if b != null:
		for i in b.get_bone_count():
			var n := String(b.get_bone_name(i))
			if not union.has(n):
				union.append(n)

	var rows := 0
	for n in union:
		if rows >= max_rows:
			out += "[cell]... (+%d)[/cell][cell][/cell][cell][/cell][cell][/cell]\n" % (union.size() - max_rows)
			break
		rows += 1
		var ia: int = a.find_bone(n)
		var ib: int = b.find_bone(n) if b != null else -1
		var col_a := "-"
		var col_b := "-"
		var col_d := "-"
		var col_r := "-"
		if ia >= 0:
			col_a = "%.1f" % _tilt_deg(a, ia)
		if b != null and ib >= 0:
			col_b = "%.1f" % _tilt_deg(b, ib)
		if ia >= 0 and ib >= 0:
			var wa := _bone_world(a, ia).basis.y.normalized()
			var wb := _bone_world(b, ib).basis.y.normalized()
			col_d = "%.2f" % rad_to_deg(wa.angle_to(wb))
			# Mismo calculo pero en REPOSO. Es la columna que CLASIFICA el bug:
			#   rest != 0  -> los dos rigs tienen los EJES distintos en reposo; el
			#                 PD pelea un offset constante (tuerce el hueso).
			#   rest ~ 0   -> los ejes coinciden y la pose viva diverge: el PD no
			#                 esta llegando al objetivo.
			var ra := a.get_bone_global_rest(ia).basis.y.normalized()
			var rb := b.get_bone_global_rest(ib).basis.y.normalized()
			col_r = "%.2f" % rad_to_deg(ra.angle_to(rb))
		elif show_missing:
			col_d = "SOLO %s (%d/%d)" % ["A" if ia >= 0 else "B", ia, ib]
		var mark := " *" if String(n) == focus_bone else ""
		out += "[cell]%d:%s%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]\n" % [
			ia, n, mark, col_a, col_b, col_d, col_r]
	out += "[/table]"
	out += "cols 2/3 = inclinacion del eje Y del hueso vs VERTICAL (grados)\n"
	out += "delta    = desacuerdo entre A y B para el MISMO hueso (grados)\n"
	out += "--------- = el hueso no existe en ese esqueleto\n"
	return out


## Dibuja cada hueso como una cruz de 3 ejes (orientacion REAL del hueso) y una
## linea hacia su padre (la cadena). Reutiliza el ImmediateMesh del .tscn: el
## script no crea recursos, solo los vacia y los rellena (regla de oro #1).
func _draw() -> void:
	if _mesh_instance == null or not (_mesh_instance.mesh is ImmediateMesh):
		return
	var im := _mesh_instance.mesh as ImmediateMesh
	im.clear_surfaces()
	if not draw_enabled or debug_material == null or _skeletons.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES, debug_material)
	for s in _skeletons.size():
		var sk: Skeleton3D = _skeletons[s]
		var col: Color = SKELETON_COLORS[s % SKELETON_COLORS.size()]
		for i in sk.get_bone_count():
			var w := _bone_world(sk, i)
			var o := w.origin
			var c := col
			if focus_bone != "" and String(sk.get_bone_name(i)) == focus_bone:
				c = Color(1.0, 1.0, 0.0)
			var axes := [w.basis.x.normalized(), w.basis.y.normalized(), w.basis.z.normalized()]
			for ax: Vector3 in axes:
				im.surface_set_color(c)
				im.surface_add_vertex(o)
				im.surface_set_color(c)
				im.surface_add_vertex(o + ax * axis_length)
			var p := sk.get_bone_parent(i)
			if p >= 0:
				im.surface_set_color(col * 0.55)
				im.surface_add_vertex(o)
				im.surface_set_color(col * 0.55)
				im.surface_add_vertex(_bone_world(sk, p).origin)
	im.surface_end()
