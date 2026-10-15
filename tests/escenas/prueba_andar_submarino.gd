extends Node3D
## ¿Se ANDA dentro del SM-13?
##
## OJO AL MOTOR DE FISICA: con `3d/physics_engine="Box3D Physics"` esta prueba da
## 0,00 m en los dos tramos — con la velocidad correcta (4,98 m/s), el rumbo
## correcto y `is_on_floor()` en true. Ningun CharacterBody3D apoyado se mueve.
## Con DEFAULT, el mismo modelo y la misma escena dan 6,03 m y 6,89 m. Si esto
## falla de golpe sin que nadie haya tocado el submarino, mira el motor primero. A un jugador no se le pregunta si se cae: se le
## pregunta si se mueve. Esta prueba mete a Iza en la camara, le mantiene el paso
## adelante y mide cuanto avanza y cuanto baja.

const ESPERA := 40          # fotogramas para que asiente antes de medir
const PASOS := 240          # fotogramas andando
# Blender (x, y, z) -> Godot (x, z, -y). Camara en x 0..7,2 y piso en z=-1.16.
# SE ANDA A LO LARGO, no de traves. La primera version lo puso mirando al costado
# y avanzo 0,90 m exactos antes de parar: el paso libre es 1,125 del eje y el
# cuerpo mide 0,228 de radio, o sea 0,897 hasta el armario. Choco con el mueble y
# la prueba lo conto como "no anda". Medir el avance no basta: hay que andar POR
# DONDE SE ANDA.
const DENTRO := Vector3(0.9, -1.11, 0.0)
const MAMPARO_X := 7.2      # la puerta redonda entre camara y maquinas

var iza: CharacterBody3D


func _ready() -> void:
	iza = $Iza as CharacterBody3D
	iza.global_position = DENTRO
	# EL JUGADOR SE ENDEREZA SOLO. `iza_player.gd` guarda `_target_yaw` en SU
	# _ready() —que corre antes que el de la escena— y cada fotograma hace
	# lerp_angle de rotation.y hacia el. Girandole solo el cuerpo, se deshacia el
	# giro en tres fotogramas y seguia andando de traves: el avance de 0,90 m salia
	# identico y parecia que el problema era la colision.
	iza.rotation.y = -PI / 2.0          # el frente (-Z) pasa a ser +X, la eslora
	iza.set("_target_yaw", -PI / 2.0)
	_correr()


func _correr() -> void:
	# DOS TRAMOS, porque dentro de un submarino no se anda en linea recta. La
	# escala de la escotilla va en el EJE, bajo el brocal, que es donde va en un
	# barco; y la puerta del mamparo es un circulo centrado, asi que fuera del eje
	# su borde inferior queda a media altura y hace de galapago alto. El recorrido
	# real es: esquivar la escala por un lado y volver al centro para la puerta.
	var ok_largo := await _tramo("a lo largo, esquivando la escala",
		Vector3(0.9, -1.11, 0.62), 240, 4.0)
	var ok_puerta := await _tramo("cruzando el mamparo",
		Vector3(6.2, -1.11, 0.0), 160, 1.6, MAMPARO_X)
	var bien := ok_largo and ok_puerta
	print("[andar] %s" % ("SE ANDA DENTRO" if bien else "NO SE ANDA"))
	get_tree().quit(0 if bien else 1)


func _tramo(nombre: String, desde: Vector3, pasos: int, minimo: float,
		cruzar: float = INF) -> bool:
	iza.global_position = desde
	iza.velocity = Vector3.ZERO
	await _esperar(ESPERA)
	var p0: Vector3 = iza.global_position
	var y_min: float = p0.y
	Input.action_press("ui_up")
	for i in pasos:
		await get_tree().physics_frame
		y_min = min(y_min, iza.global_position.y)
	Input.action_release("ui_up")
	await _esperar(12)
	var p1: Vector3 = iza.global_position
	var avance := Vector2(p1.x - p0.x, p1.z - p0.z).length()
	var caida := p0.y - p1.y
	var paso := avance >= minimo and caida < 0.4 and iza.is_on_floor()
	if cruzar < INF:
		paso = paso and p1.x > cruzar
	print("[andar] %-34s %.2f m (pide %.1f) · caida %.2f · cota min %.2f · suelo %s%s  %s"
		% [nombre, avance, minimo, caida, y_min, iza.is_on_floor(),
		   ("" if cruzar == INF else " · x=%.2f (cruza en %.1f)" % [p1.x, cruzar]),
		   "ok" if paso else "FALLA"])
	return paso


func _esperar(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
