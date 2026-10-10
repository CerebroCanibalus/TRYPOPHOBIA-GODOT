extends Node3D
class_name Relampago
## RAYOS de la tormenta.
##
## Este nodo NO vive en ninguna escena: lo crea `atmosfera.gd` en runtime y
## SOLO si el preset trae `rayos_activos`. En el editor no existe absolutamente
## nada de esto — por eso el script no lleva `@tool`, que es la guarda mas
## barata y mas dificil de saltar que hay (:v
##
## El rayo NO es un efecto de pantalla. Son CUATRO FUENTES DE LUZ coordinadas
## por la misma envoltura de pulsos, y cada una tiene SU color, SU pico y SU
## velocidad de apagado:
##
##   | fuente               | pico     | apagado     | por que
##   |----------------------|----------|-------------|---------------------------
##   | Ambiente             | el mayor | medio (0.4) | el AIRE tarda en limpiarse
##   | Niebla volumetrica   | grande   | lento (0.9) | deja la estela visible
##   | Luz de impacto       | grande   | seco (0.1)  | el punto de golpe muere ya
##   | Luz de la nube       | medio    | corto (0.2) | el disco dentro de la masa
##   | Pantalla             | ---      | seco        | solo si el rayo esta cerca
##
## La ASIMETRIA es lo que importa: la luz SUBE en milisegundos (ataque) y BAJA
## con caida exponencial. Un salto a step se leeria como un bug de render.
##
## Tambien emite `relampago_producido` en el instante del destello y
## `trueno_escuchado` cuando el sonido LLEGARIA (distancia / 343). No reproduce
## nada: no hay ningun `.ogg` de trueno en el repo. Ver `AtmosferaPreset` (:v
##
## HIJOS CREADOS EN RUNTIME (nunca se guardan, no llevan `owner`):
##   `LuzImpacto`      OmniLight3D en el punto de golpe
##   `LuzNube`         OmniLight3D alta, dentro de la formacion
##   `Rayo`            MeshInstance3D con ImmediateMesh (cinta)
##   `FlashPantalla`   CanvasLayer capa 1 + ColorRect

## Senal en el INSTANTE del destello. `posicion` es el punto de golpe en el
## suelo (o la base de la nube si fue un destello sin golpe).
signal relampago_producido(posicion: Vector3, distancia: float)
## Senal cuando el trueno LLEGARIA al oyente. Sin `.ogg` no hace nada mas :v
signal trueno_escuchado(distancia: float, energia: float)

## Velocidad del sonido en el aire, en m/s. El retardo no es cosmético: es lo
## que hace que un rayo lejano se lea como lejano.
const VELOCIDAD_SONIDO := 343.0
## Pasos de subdivision al tender el rayo por desplazamiento de puntos medios.
## 5 = 32 tramos, que es el numero tipico de un rayo real.
const PASOS_RAYO := 5
## Que tanto se aparta el rayo de la recta en cada subdivision, en metros.
const AMPLITUD_RAYO := 34.0
## Ancho de la cinta por metro de distancia. La cinta se ancha con la
## distancia para que su ANGULO en pantalla sea constante: un rayo de 3 m a 4
## km seria un punto invisible.
##
## Con 0.0035 el rayo media ~0,2 grados, o sea CINCO pixeles — y el nucleo
## blanco solo uno o dos. Se leia "demasiado delgado" porque literalmente lo
## era. A 0.012 son ~17 pixeles (:v
const ANCHO_POR_METRO := 0.012
## Numero maximo de truenos pendientes a la vez. Un rayo cada segundo y medio
## con 3 s de retardo son 2 en vuelo; 8 es un techo holgado.
const MAX_TRUENOS := 8
## Los .ogg de trueno. Se elige uno AL AZAR por golpe: con una sola pista el
## jugador aprende a reconocer el sonido a los tres rayos y se rompe la
## ilusion (:v
const RUTAS_TRUENO := [
	"res://audio/sfx/clima/trueno1.ogg",
	"res://audio/sfx/clima/trueno2.ogg",
	"res://audio/sfx/clima/trueno3.ogg",
]
## Reproductores 3D para trueno.
##
## VAN EN PAREJAS: cada trueno ocupa DOS voces, una a `trueno_pitch` y otra un
## pelin mas grave. Es la receta clasica de ENGORDAR un sonido — una sola voz
## suena delgada porque tiene UNA sola curva espectral; dos desafinadas se
## solapan y dan cuerpo. Por eso aqui hay el DOBLE que golpes concurrentes.
##
## Antes eran 3 sueltos y se quedaban cortos: los .ogg duran varios segundos
## asi que se solapan tres o cuatro truenos a la vez y al llenarse el pool se
## CORTABA al que estaba sonando — que es "varios no se escuchan" (:v
const VOICES_POR_TRUENO := 2
const POOL_TRUENOS := 8

## Trueno pendiente de sonar.
##
## Vive en su propia clase y no en un Vector3 porque necesita CUATRO datos y
## el Vector3 solo tiene tres huecos: cuando suena, a que distancia, con que
## energia y DESDE DONDE — que es lo que hace que se oiga direccional (:v
class Trueno:
	var t: float = 0.0
	var distancia: float = 0.0
	var energia: float = 0.0
	var posicion: Vector3 = Vector3.ZERO

## Preset de tormenta. Lo asigna `atmosfera.gd` antes de `configurar()`.
var preset: AtmosferaPreset

var _material_cielo: ShaderMaterial
var _entorno: Environment

var _luz_impacto: OmniLight3D
var _luz_nube: OmniLight3D
var _rayo: MeshInstance3D
var _malla: ImmediateMesh
var _material_rayo: ShaderMaterial
## Trayectoria DEL RAYO guardada, no la cinta: la cinta se REHACE cada frame
## para que siempre encare a la camara, pero el Trazado solo se sortea una
## vez por golpe (si no, el rayo cambiaria de forma al girar la vista).
var _trayectoria: PackedVector3Array = PackedVector3Array()
var _ramas: Array[PackedVector3Array] = []
var _ancho_rayo := 1.0
var _flash: ColorRect
var _capa_flash: CanvasLayer

var _pool_truenos: Array[AudioStreamPlayer3D] = []
var _streams_trueno: Array[AudioStream] = []
## Ultima pista de trueno usada, para no repetir dos golpes seguidos.
var _ultimo_trueno := -1

var _rng := RandomNumberGenerator.new()

## Segundos hasta el proximo destello.
var _espera := 0.0
## Momentos en que empieza cada pulso, medidos desde el inicio del destello.
var _pulsos: PackedFloat32Array = PackedFloat32Array()
## Tiempo transcurrido desde el primer pulso. < 0 = no hay destello activo.
var _t_destello := -1.0
## Duracion total del destello (ultimo pulso + su cola).
var _duracion := 0.0

## Valores BASE de la Environment, capturados UNA vez tras aplicar el preset.
## Sin ellos, cada destello multiplicaria un valor ya multiplicado y en tres
## rayos el cielo se quedaria blanqueado para siempre.
var _ambiente_base := 1.0
var _ambiente_color_base := Color.WHITE
var _nievla_base := 1.0

## Cola de truenos pendientes: [tiempo_llegada, distancia, energia].
var _truenos: Array[Trueno] = []


func configurar(
		p: AtmosferaPreset,
		mat_cielo: ShaderMaterial,
		entorno: Environment
) -> void:
	preset = p
	_material_cielo = mat_cielo
	_entorno = entorno
	_capturar_base()
	_crear_nodos()
	if preset.rayos_semilla != 0:
		_rng.seed = preset.rayos_semilla
	else:
		_rng.randomize()
	_programar_siguiente()


## Fuerza un destello YA, sin esperar al temporizador. Sirve para capturas
## reproducibles y para las pruebas: con `rayos_semilla` fija, dos corridas
## disparan lo mismo (:v
func forzar_rayo(distancia: float = -1.0) -> void:
	_programar_siguiente()
	var d: float = distancia if distancia > 0.0 else _sortear_distancia()
	_disparar(d)


func _process(delta: float) -> void:
	if preset == null or not preset.rayos_activos:
		return

	# La cinta se rehace contra la camara ACTUAL mientras sea visible. Es lo
	# que evita que al girar el jugador el rayo quede DE CANTO y desaparezca (:v
	if _rayo != null and _rayo.visible:
		_actualizar_cinta()

	# --- Cola de truenos: suenan cuando el sonido HABRIA llegado -----------
	var i := 0
	while i < _truenos.size():
		var tr := _truenos[i]
		tr.t -= delta
		if tr.t <= 0.0:
			_truenos.remove_at(i)
			# La senal sale ANTES de reproducir: es el contrato por si alguien
			# quiere montar su propio audio encima sin usar nuestro pool (:v
			trueno_escuchado.emit(tr.distancia, tr.energia)
			_reproducir_trueno(tr)
		else:
			i += 1

	# --- Temporizador de proximo destello ----------------------------------
	if _t_destello < 0.0:
		_espera -= delta
		if _espera <= 0.0:
			_disparar(_sortear_distancia())
		return

	# --- Envoltura del destello en curso -----------------------------------
	_t_destello += delta
	if _t_destello > _duracion:
		_apagar()
		return

	_aplicar_fuentes(_t_destello)


# ---------------------------------------------------------------------------
#  Envoltura
#
#  Cada pulso (el inicial y cada repique) aporta: un ATAQUE lineal de
#  `rayos_tiempo_ataque` segundos y una CAIDA exponencial con su propio tau.
#  El conjunto es la suma — por eso los repiques no "reinician" la luz a cero,
#  se montan encima y el resultado es el temblequeo caracteristico.
# ---------------------------------------------------------------------------
func _envoltura(t: float, tau: float) -> float:
	var total := 0.0
	for inicio in _pulsos:
		var x: float = t - inicio
		if x <= 0.0:
			continue
		var ataque: float = minf(x / maxf(preset.rayos_tiempo_ataque, 1e-4), 1.0)
		total += ataque * exp(-x / maxf(tau, 1e-4))
	# Normalizo contra el pico teorico para que `rayos_*_pico` sea el valor
	# maximo REAL y no un multiplicador que dependa del numero de repiques.
	return minf(total, 1.0)


func _aplicar_fuentes(t: float) -> void:
	# ---- Ambiente ---------------------------------------------------------
	# El que mas sube y el que mas despacio se apaga. Su COLOR se mezcla hacia
	# el tinte, asi el mundo entero tiende al azul del rayo y no solo se
	# aclara.
	var e_amb: float = _envoltura(t, preset.rayos_ambiente_caida)
	_entorno.ambient_light_energy = _ambiente_base * lerpf(1.0, preset.rayos_ambiente_pico, e_amb)
	_entorno.ambient_light_color = _ambiente_color_base.lerp(preset.rayos_ambiente_tinte, e_amb)

	# ---- Niebla volumetrica ----------------------------------------------
	if _entorno.volumetric_fog_enabled:
		var e_nie: float = _envoltura(t, preset.rayos_niebla_caida)
		_entorno.volumetric_fog_emission_energy = _nievla_base * lerpf(1.0, preset.rayos_niebla_pico, e_nie)

	# ---- Luz de impacto ---------------------------------------------------
	var e_imp: float = _envoltura(t, preset.rayos_impacto_caida)
	_luz_impacto.light_energy = preset.rayos_impacto_energia * e_imp

	# ---- Luz de la nube ---------------------------------------------------
	var e_nub: float = _envoltura(t, preset.rayos_nube_caida)
	_luz_nube.light_energy = preset.rayos_nube_energia * e_nub

	# ---- Cinta del rayo: solo visible durante los pulsos ------------------
	# La cinta no lleva tau propia: lo que se apaga es la ENERGIA del shader.
	_material_rayo.set_shader_parameter("intensidad", minf(e_imp + e_nub, 1.0))

	# ---- Halo dentro de la nube, en el shader del cielo -------------------
	_c(_material_cielo, "rayos_intensidad", e_nub)
	_col(_material_cielo, "rayos_color", preset.rayos_nube_color)

	# ---- Flash de pantalla, solo para rayos cercanos ----------------------
	var e_pan: float = _envoltura(t, preset.rayos_impacto_caida)
	_flash.color.a = preset.rayos_pantalla_fuerza * e_pan


func _apagar() -> void:
	_t_destello = -1.0
	_luz_impacto.light_energy = 0.0
	_luz_nube.light_energy = 0.0
	_luz_impacto.visible = false
	_luz_nube.visible = false
	_rayo.visible = false
	_flash.color.a = 0.0
	if _material_cielo != null:
		_c(_material_cielo, "rayos_intensidad", 0.0)
	if _entorno != null:
		_entorno.ambient_light_energy = _ambiente_base
		_entorno.ambient_light_color = _ambiente_color_base
		if _entorno.volumetric_fog_enabled:
			_entorno.volumetric_fog_emission_energy = _nievla_base


## Tiempo hasta el proximo destello.
##
## ANTES era `media ± desvio` uniforme: un reparto LIMITADO alrededor de la
## media, que suena como un metronomo — al tercero el jugador ya se sabe
## cuando viene el siguiente. Ahora la media se reparte entre un SUELO fijo y
## una exponencial, que es la distribucion de los eventos independientes:
## da rachas de huecos cortos y de vez en cuando una PAUSA larga, y esa
## asimetria es lo que hace que no se pueda adivinar (:v
func _programar_siguiente() -> void:
	var base: float = maxf(preset.rayos_frecuencia_media, 0.1)
	var mezcla: float = clampf(preset.rayos_variacion, 0.0, 1.0)

	# SUELO = cuarta parte de la media. Sin el, la cola exponencial regala
	# huecos de cero y salen dos rayos pegados, que se lee como un glitch y no
	# como una tormenta. La media entera vive en el resto.
	var suelo: float = base * 0.25
	var resto: float = base - suelo

	# (0,1] y NO [0,1]: `log(0)` es menos infinito y el temporizador se
	# quedaria congelado para siempre.
	var u: float = _rng.randf_range(0.0001, 1.0)
	# Techo de la cola: sin el, un hueco suelto llega a 7-8 veces la media y
	# parecia que se habia apagado la tormenta. A 4.0 el hueco maximo es
	# ~3.25 veces la media, que ya se lee como una pausa y no como un corte.
	var exponencial: float = minf(-log(u), 4.0)
	# La uniforme es el extremo OPUESTO: todo pegado a la media, metronomo.
	# `rayos_variacion` decide cuanto hay de cada una — 0 = metronomo
	# estricto, 1 = exponencial pura con sus rachas (:v
	var uniforme: float = 2.0 * u
	_espera = suelo + lerpf(uniforme, exponencial, mezcla) * resto


func _sortear_distancia() -> float:
	var lo: float = minf(preset.rayos_distancia_min, preset.rayos_distancia_max)
	var hi: float = maxf(preset.rayos_distancia_min, preset.rayos_distancia_max)
	return _rng.randf_range(lo, hi)


# ---------------------------------------------------------------------------
#  Disparo
# ---------------------------------------------------------------------------
func _disparar(distancia: float) -> void:
	var golpea: bool = _rng.randf() > preset.rayos_prob_nube_sola
	var destino: Dictionary = _elegir_destino(distancia, golpea)
	var golpe: Vector3 = destino["golpe"]
	var base_nube: Vector3 = destino["nube"]

	# ---- Envoltura: el pulso inicial y los repiques ------------------------
	_pulsos = PackedFloat32Array([0.0])
	var x: float = 0.0
	for i in preset.rayos_restrikes - 1:
		# Cada repique llega mas tarde y con MAS amplitud relativa que el
		# anterior solo en el primer tercio; despues decae. El desfase se
		# sortea para que no suene a metronomo.
		x += preset.rayos_gap_restrike * _rng.randf_range(0.7, 1.6)
		_pulsos.append(x)
	_duracion = x + preset.rayos_ambiente_caida * 4.0
	_t_destello = 0.0

	# ---- Geometria del rayo ------------------------------------------------
	# La cinta se construye con vertices en coordenadas de MUNDO, asi que el
	# nodo tiene que salirse de la jerarquia de transformacion: Atmosfera
	# puede colgar de un mapa con escala 0.33 (lobbyV2 la tiene) y el rayo
	# saldria un tercio de gordo y girado. Identity global = el mundo es el
	# propio nodo (:v
	_rayo.global_transform = Transform3D.IDENTITY
	if golpea:
		_construir_rayo(base_nube, golpe, distancia)
	else:
		_ocultar_rayo()

	# ---- Luces -------------------------------------------------------------
	_luz_impacto.global_position = golpe
	_luz_impacto.light_color = preset.rayos_impacto_color
	_luz_impacto.omni_range = preset.rayos_impacto_rango
	_luz_impacto.visible = golpea

	# La luz de la nube va en la BASE de la formacion, no en la cresta: es
	# donde la masa es mas gruesa y el disco se lee mejor.
	_luz_nube.global_position = base_nube
	_luz_nube.light_color = Color(preset.rayos_nube_color)
	_luz_nube.omni_range = maxf(preset.rayos_nube_radio * distancia * 4.0, 200.0)
	_luz_nube.visible = true

	# ---- Flash de pantalla -------------------------------------------------
	_flash.visible = distancia <= preset.rayos_pantalla_umbral

	# ---- Halo en el shader del cielo ---------------------------------------
	if _material_cielo != null:
		var dir_hacia: Vector3 = (base_nube - _posicion_oyente()).normalized()
		_v3(_material_cielo, "rayos_direccion", dir_hacia)

	# ---- Senal inmediata + trueno diferido ---------------------------------
	relampago_producido.emit(golpe, distancia)
	if preset.rayos_senalar_sonido and _truenos.size() < MAX_TRUENOS:
		var pendiente := Trueno.new()
		# El retardo NO es cosmético: es lo que hace que un rayo a 2 km se
		# oiga LEJANO. Sin el, el trueno saltaria al instante y el jugador
		# lo viviria como si el rayo hubiera caido a sus pies (:v
		pendiente.t = distancia / VELOCIDAD_SONIDO
		pendiente.distancia = distancia
		pendiente.energia = preset.rayos_impacto_energia
		pendiente.posicion = golpe
		_truenos.append(pendiente)
	# No hay `_aplicar_fuentes(0.0)` aqui a proposito: con t=0 la envoltura
	# vale cero (el ataque aun no ha empezado) y la luz empieza sola en el
	# siguiente frame del `_process`, rampando durante `rayos_tiempo_ataque`.


func _elegir_destino(distancia: float, golpea: bool) -> Dictionary:
	var oyente: Vector3 = _posicion_oyente()
	# Azimut libre. La altura de la nube sale del preset para que el rayo
	# nazca EXACTAMENTE donde empieza la formacion que se ve en el cielo.
	var ang: float = _rng.randf_range(0.0, TAU)
	var plano: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * distancia
	var golpe: Vector3 = oyente + plano
	var altura: float = preset.nubes_altura if preset != null else 800.0
	return {
		"golpe": golpe,
		"nube": Vector3(golpe.x, oyente.y + altura, golpe.z),
	}


func _posicion_oyente() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	return global_position


func _ocultar_rayo() -> void:
	_malla.clear_surfaces()
	_rayo.visible = false
	# Sin trayectoria no hay nada que rehacer: asi el `_process` no se pone
	# a reconstruir una cinta que ya no se ve (:v
	_trayectoria = PackedVector3Array()
	_ramas.clear()


# ---------------------------------------------------------------------------
#  Cinta del rayo
#
#  Se construye UNA VEZ por golpe, nunca por frame. La anchura se decide en el
#  instante del disparo a partir de la distancia a la camara, de modo que un
#  rayo a 4 km ocupe mas o menos lo mismo en pantalla que uno a 500 m (:v
# ---------------------------------------------------------------------------
func _construir_rayo(desde: Vector3, hasta: Vector3, distancia: float) -> void:
	# El TAZADO se sortea UNA VEZ por golpe: si se repitiera cada frame el
	# rayo cambiaria de forma al girar la vista y pareceria que vibra.
	_trayectoria = _tender_rayo(desde, hasta, PASOS_RAYO, AMPLITUD_RAYO)
	_ancho_rayo = clampf(distancia * ANCHO_POR_METRO, 2.0, 120.0)

	_ramas.clear()
	var n_ramas: int = _rng.randi_range(1, 2)
	for r in n_ramas:
		if _trayectoria.size() < 8:
			break
		var idx: int = _rng.randi_range(2, _trayectoria.size() - 3)
		var origen: Vector3 = _trayectoria[idx]
		var fin: Vector3 = origen + (hasta - desde).normalized() * distancia * 0.22 \
				+ Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.1), _rng.randf_range(-1.0, 1.0)) \
				* distancia * 0.1
		# Rama mas corta y mas fina, como en un rayo real.
		_ramas.append(_tender_rayo(origen, fin, 3, AMPLITUD_RAYO * 0.5))

	_rayo.visible = true
	_actualizar_cinta()


## Reconstruye la cinta contra la posicion ACTUAL de la camara.
##
## Es LA solucion a "el rayo sale de lado o no se ve": la cinta se orienta con
## el producto vectorial entre el segmento y la direccion a la camara, y si se
## orientaba UNA sola vez en el instante del golpe, al girar el jugador la
## cinta quedaba DE CANTO — un plano de cero grosor, invisible. Se rehace
## mientras es visible; el coste es ~250 vertices durante un segundo, que es
## nada (:v
func _actualizar_cinta() -> void:
	if _trayectoria.is_empty() or _malla == null:
		return
	_malla.clear_surfaces()
	_malla.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_emitir_cinta(_trayectoria, _ancho_rayo, 1.0)
	for hilo in _ramas:
		_emitir_cinta(hilo, _ancho_rayo * 0.4, 0.65)
	_malla.surface_end()


func _emitir_cinta(puntos: PackedVector3Array, ancho: float, peso: float) -> void:
	if puntos.size() < 2:
		return
	var camara: Vector3 = _posicion_oyente()
	var mitad: float = ancho * 0.5
	var i := 0
	while i < puntos.size() - 1:
		var a: Vector3 = puntos[i]
		var b: Vector3 = puntos[i + 1]
		var la: Vector3 = _lateral(a, b, camara) * mitad
		var lb: Vector3 = _lateral(b, a, camara) * mitad
		# Cuatro vertices = dos triangulos. UV.x va de 0 a 1 a traves de la
		# cinta, que es lo que el shader usa para el desvanecido del borde.
		_par(a - la, Vector2(0.0, 0.0), peso)
		_par(a + la, Vector2(1.0, 0.0), peso)
		_par(b + lb, Vector2(1.0, 1.0), peso)
		_par(a - la, Vector2(0.0, 0.0), peso)
		_par(b + lb, Vector2(1.0, 1.0), peso)
		_par(b - lb, Vector2(0.0, 1.0), peso)
		i += 1


func _par(p: Vector3, uv: Vector2, peso: float) -> void:
	# UV.x = posicion a traves de la cinta (el 0.5 es el eje). UV.y = peso de
	# la rama, no la longitudinal. Los dos los lee `rayo.gdshader`, que es
	# donde esta el desvanecido de los cantos (:v
	_malla.surface_set_uv(Vector2(uv.x, peso))
	_malla.surface_add_vertex(p)


## Vector lateral, perpendicular al segmento y a la direccion de vision: asi la
## cinta ENCARA a la camara en vez de quedar de canto.
##
## OJO con el respaldo: el anterior era `dir.cross(Vector3.UP)`, que da EXACTO
## CERO cuando el segmento es VERTICAL — que es el caso normal de un rayo que
## cae. Salia un lateral inestable justo en el trazo principal. Ahora el eje de
## respaldo se elige en funcion de donde apunta el segmento (:v
func _lateral(a: Vector3, b: Vector3, camara: Vector3) -> Vector3:
	var dir: Vector3 = b - a
	if dir.length_squared() < 1e-8:
		return Vector3.RIGHT
	dir = dir.normalized()
	var vista: Vector3 = a - camara
	if vista.length_squared() < 1e-8:
		vista = Vector3.FORWARD
	var lat: Vector3 = dir.cross(vista.normalized())
	if lat.length_squared() < 1e-6:
		# Vista casi PARALELA al segmento: el producto vectorial se anula y
		# su direccion se vuelve inestable. Elijo un eje que NUNCA sea
		# paralelo al segmento, que es lo unico que hace falta aqui.
		var eje: Vector3 = Vector3.RIGHT if absf(dir.y) > 0.9 else Vector3.UP
		lat = dir.cross(eje)
	if lat.length_squared() < 1e-8:
		return Vector3.RIGHT
	return lat.normalized()


## Desplazamiento de puntos medios: se parte el segmento por la mitad, se
## aparta el medio de la recta y se repite. Es la forma classica de generar un
## rayo, y da el trazado irregular con quiebros bruscos que el ojo espera.
func _tender_rayo(desde: Vector3, hasta: Vector3, pasos: int, amplitud: float) -> PackedVector3Array:
	var puntos := PackedVector3Array([desde, hasta])
	var amp: float = amplitud
	for _p in pasos:
		var nuevos := PackedVector3Array()
		var j := 0
		while j < puntos.size() - 1:
			var a: Vector3 = puntos[j]
			var b: Vector3 = puntos[j + 1]
			nuevos.append(a)
			var medio: Vector3 = (a + b) * 0.5
			var dir: Vector3 = b - a
			if dir.length_squared() > 1e-8:
				dir = dir.normalized()
				var eje: Vector3 = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
				var p1: Vector3 = dir.cross(eje).normalized()
				var p2: Vector3 = dir.cross(p1).normalized()
				medio += (p1 * _rng.randf_range(-1.0, 1.0) + p2 * _rng.randf_range(-1.0, 1.0)) * amp
			nuevos.append(medio)
			j += 1
		nuevos.append(puntos[puntos.size() - 1])
		puntos = nuevos
		amp *= 0.55
	return puntos


# ---------------------------------------------------------------------------
#  Trueno
# ---------------------------------------------------------------------------
## Reproduce el trueno de un golpe cuyo retardo YA ha pasado.
##
## Suena DESDE el punto de impacto con un `AudioStreamPlayer3D`, no en 2D: la
## direccion es la mitad de la experiencia. Y se elige pista AL AZAR — con una
## sola el oido la aprende de memoria a los tres rayos y se rompe la ilusion.
##
## Va en DOS voces DESAFINADAS, que es la receta clasica para que suene GRUESO:
## una sola voz es delgada porque tiene UNA sola curva espectral, y dos con un
## pelin de diferencia de tono se solapan y dan cuerpo (:v
func _reproducir_trueno(tr: Trueno) -> void:
	if _pool_truenos.size() < VOICES_POR_TRUENO or _streams_trueno.is_empty():
		return

	# Busco una PAREJA libre. Arrancan juntas con el mismo stream, asi que se
	# liberan juntas. Si no hay ninguna me quedo con la primera y corto la que
	# este sonando: perderse un trueno nuevo seria peor que apagar el viejo (:v
	var libre := -1
	var i := 0
	while i + 1 < _pool_truenos.size():
		if not _pool_truenos[i].playing and not _pool_truenos[i + 1].playing:
			libre = i
			break
		i += VOICES_POR_TRUENO
	if libre < 0:
		libre = 0

	var idx := _rng.randi_range(0, _streams_trueno.size() - 1)
	# Evito repetir la MISMA pista dos golpes seguidos cuando hay mas de una.
	if _streams_trueno.size() > 1 and idx == _ultimo_trueno:
		idx = (idx + 1) % _streams_trueno.size()
	_ultimo_trueno = idx

	var st := _streams_trueno[idx]
	# Las dos voces EXACTAMENTE en el mismo punto: si no, se oirian como dos
	# truenos distintos y no como uno solo que suena gordo (:v
	_voz_trueno(_pool_truenos[libre], st, tr.posicion,
			preset.trueno_rango, preset.trueno_volumen_db, preset.trueno_pitch)
	_voz_trueno(_pool_truenos[libre + 1], st, tr.posicion,
			preset.trueno_rango, preset.trueno_volumen_db - 2.5,
			preset.trueno_pitch * 0.94)


## Pone una voz en su sitio y la lanza. En SIEMPRE se desactiva el cono de
## emision: con el cono apagado la fuente es OMNIDIRECCIONAL, o sea que el
## trueno suena IGUAL venga por delante o por detras y solo importa la
## distancia — que es lo que hace que "siempre mire al cliente" (:v
func _voz_trueno(
		p: AudioStreamPlayer3D,
		st: AudioStream,
		pos: Vector3,
		rango: float,
		vol: float,
		tono: float
) -> void:
	p.stream = st
	p.global_position = pos
	p.unit_size = rango
	p.volume_db = vol
	p.pitch_scale = tono
	p.emission_angle_enabled = false
	p.play()


# ---------------------------------------------------------------------------
#  Montaje de los hijos
# ---------------------------------------------------------------------------
func _crear_nodos() -> void:
	_luz_impacto = OmniLight3D.new()
	_luz_impacto.name = "LuzImpacto"
	# SOMBRAS APAGADAS por defecto: en Forward+ con niebla volumetrica, cada
	# luz con sombra multiplica el coste del pase de sombras y de la niebla.
	# Se enciende a mano si el mapa lo necesita (:v
	_luz_impacto.shadow_enabled = false
	add_child(_luz_impacto)

	_luz_nube = OmniLight3D.new()
	_luz_nube.name = "LuzNube"
	_luz_nube.shadow_enabled = false
	add_child(_luz_nube)

	_material_rayo = ShaderMaterial.new()
	_material_rayo.shader = load("res://src/shaders/rayo.gdshader")

	_malla = ImmediateMesh.new()
	_rayo = MeshInstance3D.new()
	_rayo.name = "Rayo"
	_rayo.mesh = _malla
	_rayo.material_override = _material_rayo
	_rayo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rayo.visible = false
	add_child(_rayo)

	# Capa 1 por convencion del proyecto: FX por debajo, HUD en capa >= 10.
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)

	_capa_flash = CanvasLayer.new()
	_capa_flash.name = "FlashPantalla"
	_capa_flash.layer = 1
	_capa_flash.add_child(_flash)
	add_child(_capa_flash)

	# ---- Pool de truenos 3D -------------------------------------------------
	# Se cargan los .ogg AQUI y no en cada golpe: cargar un OGG cuesta y
	# hacerlo justo cuando cae el rayo meteria un glich en el momento exacto
	# en que el jugador esta mirando. Si falta alguno (todavia sin importar)
	# se avisa una vez y el resto sigue funcionando (:v
	for ruta in RUTAS_TRUENO:
		var st := load(ruta) as AudioStream
		if st == null:
			push_warning("[relampago] no se pudo cargar " + ruta)
		else:
			_streams_trueno.append(st)

	for i in POOL_TRUENOS:
		var p := AudioStreamPlayer3D.new()
		# EN PAREJAS: voz 0-1 = trueno 1, voz 2-3 = trueno 2... La pareja se
		# busca en `_reproducir_trueno` saltando de 2 en 2 (:v
		p.name = "Trueno%d" % (i + 1)
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Sin cono de emision: fuente OMNIDIRECCIONAL, el trueno suena igual
		# venga por delante o por detras. Ver `_voz_trueno`.
		p.emission_angle_enabled = false
		# NUNCA se apaga por distancia: `unit_size` alto es lo que mantiene el
		# trueno lejano FUERTE y CLARO en vez de convertirlo en un moscardon.
		# La lejania se nota por el RETARDO, no por el volumen (:v
		p.unit_size = preset.trueno_rango if preset != null else 320.0
		p.volume_db = preset.trueno_volumen_db if preset != null else 6.0
		p.max_db = 6.0
		add_child(p)
		_pool_truenos.append(p)


func _capturar_base() -> void:
	if _entorno == null:
		return
	_ambiente_base = _entorno.ambient_light_energy
	_ambiente_color_base = _entorno.ambient_light_color
	_nievla_base = _entorno.volumetric_fog_emission_energy


# ---------------------------------------------------------------------------
#  Helpers de uniforms (mismo patron que `atmosfera.gd`)
# ---------------------------------------------------------------------------
func _c(m: ShaderMaterial, nombre: String, valor: float) -> void:
	if m != null and m.shader != null:
		m.set_shader_parameter(nombre, valor)


## Los `vec3 : source_color` del shader aceptan un `Color` sin mas: es el
## mismo patron que usa `atmosfera.gd` para los colores del cielo (:v
func _col(m: ShaderMaterial, nombre: String, valor: Color) -> void:
	if m != null and m.shader != null:
		m.set_shader_parameter(nombre, valor)


func _v3(m: ShaderMaterial, nombre: String, valor: Vector3) -> void:
	if m != null and m.shader != null:
		m.set_shader_parameter(nombre, valor)
