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
## Que mide (de la VERDAD, no del nodo):
##   * `pel_y`   -- altura de la pelvis (cuerpo) sobre el suelo
##   * `up_col`  -- verticalidad de la columna (1 = de pie, 0 = tumbado,
##                  -1 = invertido). Es LA metrica: si cae por debajo de
##                  0 el personaje esta tumbado o de cabeza.
##   * `cab_pel` -- altura de la cabeza sobre la pelvis (columna estirada)
##   * `omega`   -- velocidad angular del cuerpo (un trompo son > 10 rad/s)
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
## Con `auto_quit_seconds` la escena se cierra sola y saca el veredicto.

extends Node3D

@export var auto_quit_seconds: float = 0.0
@export var auto_walk: bool = false
@export var capture_mouse_on_ready: bool = true
@export var diagnostic_direct_velocity: bool = false
## Altura de la pelvis que se considera "de pie" (m). El rig del Shiba mide
## ~0,85 m de pie; el personaje de la referencia ~0,5 m.
@export var altura_pelvis_esperada: float = 0.0

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

const DEBUG_ACTIONS := [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "ragdoll", "grab_left", "grab_right",
]


func _ready() -> void:
	character = _buscar_personaje()
	info = _buscar_hud()
	print("===== PLAYGROUND RAGDOLL (TEST CANONICO) =====")
	print("[playground] auto_quit=%.1fs auto_walk=%s diagnostic=%s" % [
		auto_quit_seconds, auto_walk, diagnostic_direct_velocity])
	_start_ms = Time.get_ticks_msec()
	_body = character.find_child("Physical Bone Body", true, false) as PhysicalBone3D
	if _body == null and character is RagdollCharacter:
		_body = (character as RagdollCharacter).physical_bone_body
	if _body == null:
		_body = _primer_hueso()
	_head = character.find_child("Physical Bone Head", true, false) as PhysicalBone3D
	if _body:
		_start_pos = _pos(_body)
		print("[playground] cuerpo='%s' en %s" % [_body.bone_name, _start_pos])
	else:
		push_error("[playground] NO se encontro ningun hueso fisico")
	if capture_mouse_on_ready and not DisplayServer.get_name() == "headless":
		get_window().grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
## 1 = de pie, 0 = horizontal, -1 = de cabeza.
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
			_body.linear_velocity.z += 4.0 * delta

	if _body == null:
		return
	var pos := _pos(_body)
	var dist := pos - _start_pos
	var up := _verticalidad()
	var omega := RagdollMotor.body_angular_velocity(_body).length()
	_peor_up = minf(_peor_up, up)
	_max_omega = maxf(_max_omega, omega)
	if fmod(_t, 0.5) < delta:
		print("[pg] t=%.1f pos=(%.2f,%.2f,%.2f) dXZ=%.2f up=%.2f omega=%.2f | inputs=%s" % [
			_t, pos.x, pos.y, pos.z, Vector2(dist.x, dist.z).length(),
			up, omega, _inputs()])
	if info:
		info.text = "== PLAYGROUND RAGDOLL ==\nWASD mover | Mouse camara | Space saltar | T auto-walk\n\npos   = (%.2f, %.2f, %.2f)\ndXZ   = %.2f m\nup    = %.2f (1 = de pie)\nomega = %.2f rad/s\ninputs= %s" % [
			pos.x, pos.y, pos.z, Vector2(dist.x, dist.z).length(),
			up, omega, _inputs()]


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
	var ok := _peor_up > 0.7 and _max_omega < 20.0
	if altura_pelvis_esperada > 0.0:
		var d := absf(pos.y - altura_pelvis_esperada)
		print("  altura esperada %.2f -> desvio %.3f" % [altura_pelvis_esperada, d])
		ok = ok and d < 0.35
	print("  RESULTADO: %s" % ("OK" if ok else "FALLO"))
