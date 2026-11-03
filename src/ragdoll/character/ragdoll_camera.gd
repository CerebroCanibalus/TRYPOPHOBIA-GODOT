extends Node3D
## Camara del ragdoll.
##
## 1a PERSONA (default, el modo del juego): la camara NO cuelga del esqueleto.
##   - ROTACION: 100% raton. Apuntado 1:1, sin latencia y sin mareo.
##   - POSICION: frente del hueso de la cabeza, suavizada en TIEMPO.
##   Asi se hereda el PESO del ragdoll (bob, caidas, empujones) pero NO su
##   rotacion. Colgarla del hueso fisico seria peor: la cabeza es un rigidbody
##   con cone joint (+-45/180) y su rotacion la lleva un PD hacia el master, o
##   sea que el raton iria por delante y en un choque la camara giraria sola.
##
## 3a PERSONA: la camara se separa del cuerpo con el SpringArm3D y se
##   desplaza lateralmente para que el personaje NO tape el centro de la
##   pantalla. El pivote se queda EN la cabeza (sin avance): si el pivote
##   estuviera delante, el SpringArm llevaria la camara mas alla del
##   personaje y se veria desde el lado equivocado.
##
## OJO con el eje: la camara mira a su -Z local. Por eso el desplazamiento
## "hacia delante" en el espacio del pivote es -Z, no +Z.

## Hueso de la cabeza: fuente de la POSICION.
@export var target_node: Node3D
## Nodo que marca el "adelante" del personaje (su Y global da el yaw). Es el
## Skeleton3D del Animated, NO el pivote: el nodo Physical lleva 180 grados de
## mas, asi que usar el yaw del pivote pondria la camara detras del craneo.
@export var facing_node: Node3D
## DISTANCIA (m) desde el origen del hueso de la cabeza hacia ADELANTE donde vive
## la camara. Es LA perilla para sacarla del craneo: cuanto mas adelante, menos
## geometria propia tiene que borrar el shader de recorte. El origen del hueso
## esta en la base del craneo, asi que ~0.20-0.30 cae en la frente/cara.
@export var head_distance := 0.25
## Altura de la camara relativa al hueso (+ arriba).
@export var head_height := 0.08
## Desplazamiento lateral en el espacio de la camara (+ su derecha).
@export var head_side := 0.0
## Constante de tiempo del suavizado de POSICION (s). 0.0 = pegada al hueso
## (puede vibrar con la fisica); valores altos = mas flotante.
@export var position_smoothing := 0.03

@export var mouse_sensitivity = 0.1
## Limite de pitch en grados. En 3a persona +-45 alcanzaba; en 1a hay que poder
## mirar casi recto arriba y abajo.
@export var max_pitch_degrees := 85.0

@export var physical_skel: Skeleton3D

@export_group("Tercera persona")
## Habilita el modo 3a persona. Se alterna con `third_person_key`.
## En el juego puede quedar activado (el General lo pidio para poder VER al
## personaje); el recorte de 1a persona se desactiva solo en 3a.
@export var third_person_enabled := true
## Tecla que alterna 1a/3a persona.
@export var third_person_key: Key = KEY_V
## Distancia (m) de la camara al personaje en 3a persona.
@export var third_person_distance := 3.6
## Desplazamiento lateral (m) de la camara en 3a persona. El personaje queda
## a la IZQUIERDA del centro de la pantalla (la camara se va a su derecha).
@export var third_person_side := 0.65
## Altura (m) de la camara respecto al pivote en 3a persona.
@export var third_person_height := 0.22
## Altura (m) del pivote respecto al hueso de la cabeza en 3a persona.
@export var third_person_pivot_height := 0.05

@export_group("Debug")
## Habilita la tecla de conmutar 1a/3a persona. En el juego DEBE quedar false.
@export var debug_toggle_enabled := false
@export var debug_toggle_key: Key = KEY_F2
@export var debug_third_person_distance := 5.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var first_person := true
var mouse_lock = false # is mouse locked


func _ready() -> void:
	# Los NodePath exportados pueden quedar null si los bones fueron
	# reparentados bajo PhysicalBoneSimulator3D en runtime: busqueda recursiva.
	if target_node == null and physical_skel:
		target_node = physical_skel.find_child("Physical Bone Head", true, false) as Node3D
		if target_node == null:
			target_node = physical_skel.find_child("*Head*", true, false) as Node3D
	if facing_node == null:
		facing_node = _resolve_facing_node()
	# Una sola vez: ver _exclude_character_bodies().
	_exclude_character_bodies()
	_apply_third_person_layout()


## El "adelante" del personaje lo marca el Skeleton3D del Animated: es el que
## usa `ragdoll_character.gd` para caminar (`basis.z`).
func _resolve_facing_node() -> Node3D:
	var root := get_parent()
	if root == null:
		return null
	var animated := root.get_node_or_null("Animated")
	if animated:
		return animated.find_child("*Skeleton3D*", true, false) as Node3D
	return null


## Excluye los huesos del ragdoll del SpringArm (evita que la camara de debug
## en 3a se meta dentro del personaje). Se hace UNA sola vez: el bucle original
## lo repetia en cada frame de fisica y `add_excluded_object` NO deduplica, asi
## que la lista crecia sin limite (fuga de memoria + casts cada vez mas lentos).
func _exclude_character_bodies() -> void:
	if physical_skel == null:
		return
	# Recursivo: los bones pueden estar bajo PhysicalBoneSimulator3D.
	for child in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		spring_arm.add_excluded_object(child.get_rid())


## Coloca la camara en su sitio segun el modo actual (1a/3a).
func _apply_third_person_layout() -> void:
	if first_person:
		spring_arm.spring_length = 0.0
		if camera:
			camera.position = Vector3.ZERO
	else:
		spring_arm.spring_length = third_person_distance
		if camera:
			# Offset lateral/vertical DENTRO del SpringArm: la camara orbita
			# alrededor de la cabeza pero se desplaza a un lado, asi el
			# personaje no tapa el centro de la pantalla.
			camera.position = Vector3(third_person_side, third_person_height, 0.0)


## Cambia entre 1a y 3a persona. `third` = true para 3a persona.
## Devuelve true si ha cambiado.
func set_third_person(third: bool) -> bool:
	var nuevo_first_person := not third
	if nuevo_first_person == first_person:
		return false
	first_person = nuevo_first_person
	_apply_third_person_layout()
	return true


func toggle_third_person() -> void:
	# Si estamos en 1a persona, pasamos a 3a (y al reves).
	set_third_person(first_person)


func _physics_process(delta: float) -> void:
	# En 1a persona la camara vive en el pivote; el SpringArm solo se usa para
	# el modo debug en 3a.
	if first_person:
		spring_arm.spring_length = 0.0

	if target_node == null:
		return
	var goal := _target_position()
	if position_smoothing <= 0.0:
		global_position = goal
	else:
		# Suavizado exponencial INDEPENDIENTE del framerate (el viejo lerp a 0.5
		# por frame cambiaba de comportamiento con los FPS).
		var a := 1.0 - exp(-delta / position_smoothing)
		global_position = global_position.lerp(goal, a)


## Posicion del pivote = frente del hueso de la cabeza. El offset se aplica en
## el espacio de YAW de la CAMARA (no en el de la cabeza fisica, que gira sola
## y haria orbitar la camara, ni en el del cuerpo, que puede mirar a otro lado
## mientras la cabeza sigue al raton).
func _target_position() -> Vector3:
	var head := target_node.global_position
	if not first_person:
		# 3a persona: el pivote se queda EN la cabeza. El SpringArm lleva la
		# camara hacia atras; si el pivote estuviera delante del personaje, la
		# camara acabaria DETRAS de el y miraria de espaldas.
		return head + Vector3.UP * third_person_pivot_height
	# Base de YAW de la CAMARA: +X = su derecha, -Z = hacia donde mira.
	#
	# OJO: el yaw del pivote, NO el del `facing_node` (el cuerpo). Con el
	# modelo de cabeza independiente el cuerpo puede mirar a otro lado: si el
	# desplazamiento siguiera al cuerpo, la camara se separaria de la linea
	# de mira. Con body_follows_camera = true los dos yaws coinciden y el
	# resultado es identico al de antes.
	var b := Basis(Vector3.UP, global_rotation.y)
	# La camara mira a -Z, asi que "adelante" es -Z en este espacio.
	return head + b * Vector3(head_side, head_height, -head_distance)


## El toggle 1a/3a de DEBUG: en una exportacion de release nunca se
## habilita (aunque el export quede en true), asi el juego queda full FP.
func _debug_toggle_allowed() -> bool:
	return debug_toggle_enabled and OS.is_debug_build()


func _input(event: InputEvent) -> void:
	# Toggle 1a/3a de debug (F2). La tecla de JUEGO es `third_person_key`.
	if _debug_toggle_allowed() and event is InputEventKey and event.pressed and not event.echo and event.keycode == debug_toggle_key:
		toggle_third_person()
		mouse_lock = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Toggle 1a/3a de JUEGO.
	if third_person_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == third_person_key:
		toggle_third_person()
		mouse_lock = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# mouse lock
	if Input.is_action_just_pressed("exit_camera"):
		mouse_lock = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		mouse_lock = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	#rotate camera
	if event is InputEventMouseMotion and mouse_lock:
		rotation_degrees.y -= mouse_sensitivity * event.relative.x
		rotation_degrees.x -= mouse_sensitivity * event.relative.y
		rotation_degrees.x = clampf(rotation_degrees.x, -max_pitch_degrees, max_pitch_degrees)
