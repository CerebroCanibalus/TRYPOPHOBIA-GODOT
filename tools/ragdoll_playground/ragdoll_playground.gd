## ragdoll_playground.gd
## Test aislado del sistema de active-ragdoll portado (PiCode9560).
##
## Controles:
##   WASD  -> mover (usa la direccion de la camara)
##   Mouse -> rotar camara (click izq captura, Escape libera)
##   Space -> saltar
##   T     -> toggle auto-walk (para ver el movimiento sin tocar nada)
##   R     -> NO hace nada (la accion 'ragdoll' fue vaciada a proposito)

extends Node3D

@export var auto_quit_seconds: float = 0.0
@export var auto_walk: bool = false
@export var capture_mouse_on_ready: bool = true
@export var diagnostic_direct_velocity: bool = false

@onready var character: Node3D = $RagdollCharacter
@onready var info: Label = $HUD/Info

var _t: float = 0.0
var _start_ms: int = 0
var _body: PhysicalBone3D = null
var _start_pos: Vector3 = Vector3.ZERO

const DEBUG_ACTIONS := [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "ragdoll", "grab_left", "grab_right",
]

func _ready() -> void:
	print("===== PLAYGROUND RAGDOLL =====")
	print("[playground] auto_quit=%.1fs auto_walk=%s diagnostic=%s" % [auto_quit_seconds, auto_walk, diagnostic_direct_velocity])
	_start_ms = Time.get_ticks_msec()
	_body = character.find_child("Physical Bone Body", true, false) as PhysicalBone3D
	if _body:
		_start_pos = _body.global_position
		print("[playground] body en %s" % _start_pos)
	else:
		push_error("[playground] NO se encontro Physical Bone Body")
	if capture_mouse_on_ready:
		get_window().grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("[playground] mouse capturado (Escape para liberar)")

func _process(_delta: float) -> void:
	if auto_quit_seconds > 0.0 and (Time.get_ticks_msec() - _start_ms) >= int(auto_quit_seconds * 1000.0):
		print("[playground] cerrando tras %.1fs" % auto_quit_seconds)
		get_tree().quit()

func _physics_process(delta: float) -> void:
	_t += delta

	# T = toggle auto-walk
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

	if _body:
		var dist := _body.global_position - _start_pos
		var pressed := PackedStringArray()
		for a in DEBUG_ACTIONS:
			if Input.is_action_pressed(a):
				pressed.append(a)
		var inputs := ", ".join(pressed) if pressed.size() > 0 else "(ninguno)"
		# HUD en pantalla
		if info:
			info.text = "== PLAYGROUND RAGDOLL ==\nWASD mover | Mouse camara (click izq) | Space saltar | T auto-walk (Y off)\n\npos   = (%.2f, %.2f, %.2f)\ndXZ   = %.2f m   (distancia recorrida)\nvel   = %.2f m/s\nangvel= %.2f rad/s\ninputs= %s\nauto_walk=%s" % [
				_body.global_position.x, _body.global_position.y, _body.global_position.z,
				Vector2(dist.x, dist.z).length(),
				_body.linear_velocity.length(), _body.angular_velocity.length(),
				inputs, auto_walk]
		# Log cada 0.5s
		if fmod(_t, 0.5) < delta:
			print("[pg] t=%.1f pos=(%.2f,%.2f,%.2f) dXZ=%.2f vel=%.2f angvel=%.2f | inputs=%s" % [
				_t, _body.global_position.x, _body.global_position.y, _body.global_position.z,
				Vector2(dist.x, dist.z).length(),
				_body.linear_velocity.length(), _body.angular_velocity.length(), inputs])
