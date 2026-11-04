extends Node3D

## CAPTURA DE UNA SOLA FOTO del Shiba (diagnostico visual).
##
## NUNCA hace una rafaga: una foto por ejecucion. El nombre y la vista se
## pasan por entorno:
##   SHOT_NOMBRE=pasos1   -> tests/ragdoll/shots/pasos1.png
##   SHOT_VISTA=derecha   -> frente | derecha | atras | izquierda
##   SHOT_T=1.5           -> momento de la foto (s)
##   SHOT_ANDAR=1         -> camina hasta la foto
##
## Uso: Godot --path <proj> res://tests/ragdoll/shiba_shot.tscn
##      (sin --headless para que renderice de verdad)

@onready var shiba: Node3D = $Shiba

var _t := 0.0
var _cam: Camera3D = null
var _nombre := "shiba"
var _vista := "frente"
var _momento := 1.5
var _andar := false
var _hecha := false


func _ready() -> void:
	_nombre = OS.get_environment("SHOT_NOMBRE")
	if _nombre == "":
		_nombre = "shiba"
	_vista = OS.get_environment("SHOT_VISTA")
	if _vista == "":
		_vista = "frente"
	var t := OS.get_environment("SHOT_T")
	if t != "":
		_momento = float(t)
	_andar = OS.get_environment("SHOT_ANDAR") == "1"
	# El rig del Shiba tiene el pie en el suelo con el nodo en y=0.
	shiba.global_position = Vector3(0.0, 0.05, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_colocar_camara()
	if _andar:
		Input.action_press("move_forward")
	print("[shot] %s | vista=%s | t=%.2f | andar=%s" % [_nombre, _vista, _momento, str(_andar)])


func _process(delta: float) -> void:
	_t += delta
	if _andar:
		_colocar_camara()
	if not _hecha and _t >= _momento:
		_hecha = true
		_capturar()


func _colocar_camara() -> void:
	var p := shiba.global_position
	var off := Vector3.ZERO
	match _vista:
		"frente":
			off = Vector3(0.0, 0.55, -2.4)
		"derecha":
			off = Vector3(2.4, 0.55, 0.0)
		"atras":
			off = Vector3(0.0, 0.55, 2.4)
		"izquierda":
			off = Vector3(-2.4, 0.55, 0.0)
	_cam.global_position = p + off
	_cam.look_at(p + Vector3(0.0, 0.45, 0.0), Vector3.UP)


func _capturar() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := "res://tests/ragdoll/shots/%s.png" % _nombre
	DirAccess.make_dir_recursive_absolute("res://tests/ragdoll/shots")
	var err := img.save_png(ruta)
	print("[shot] ", ruta, " err=", err)
	if _andar:
		Input.action_release("move_forward")
	get_tree().quit()
