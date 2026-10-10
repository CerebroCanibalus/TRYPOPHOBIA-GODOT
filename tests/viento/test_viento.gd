extends Node
## Test de la decision D-I2 — el viento es de Atmosfera, y el oceano LO LEE.
## (`meta/docs/Infeccion_Niebla_Roja.md`)
##
## Ninguna escena del proyecto tiene Atmosfera Y Ocean a la vez (medido:
## demo_agua no tiene Atmosfera; la petrolera no tiene controlador Ocean),
## asi que este test MONTA los dos juntos y comprueba el contrato ENTERO:
##
##   FASE 1 (con Atmosfera):
##     1. Atmosfera empuja su viento (0.9 fijo, sin racha).
##     2. Ocean adopta EL SUYO y no el suyo propio. El discriminador es a
##        proposito: si Ocean siguiera empujando lo suyo saldria 0.3; si lee
##        a Atmosfera (como debe) sale 0.9 (:v
##     3. Los getters de los dos coinciden — son los que lee WaterSurface.
##
##   FASE 2 (se LIBERA Atmosfera en vivo):
##     4. Ocean re-resuelve el grupo y cae a SU fallback (0.3) sin romperse.
##        Esto es "el oceano sigue afectando" en los dos sentidos: con
##        Atmosfera mandan los valores de ella; sin Atmosfera, los suyos (:v
##     5. La direccion de fallback es la de Ocean (rumbo 200 grados).
##
## El caso sin Atmosfera desde el arranque ya lo cubre el test del agua:
## `AGUA_TEST=1` -> 17 comprobaciones. (:v
##
## Correr (PowerShell):
##   & "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 1800 "res://tests/viento/test_viento.tscn"
##
## Salida esperada: `RESULTADO: TODO OK (5 comprobaciones)` y exit 0.
## El aviso `[atmosfera] sin preset` es ESPERADO: el test no necesita cielo,
## solo el viento, y el viento va en el nodo, no en el preset (:v

## Segundos de juego por fase. Sobran: a cientos de FPS headless se alcanza
## en un pispas, y `--quit-after 1800` es la red de seguridad (:v
const T_ESPERA := 1.0

## Intensidad de Atmosfera (la dueña). Con `viento_auto = false` sale EXACTA.
const VIENTO_ATM := 0.9
## Intensidad del propio Ocean (el fallback). Si Ocean la propaga en vez de
## la de Atmosfera, la fase 1 FALLA; y es exactamente el valor que debe
## recuperar en la fase 2 cuando Atmosfera desaparece (:v
const VIENTO_OCEANO := 0.3
## Rumbo del fallback de Ocean, en grados (fase 2).
const RUMBO_OCEANO := 200.0

var _t := 0.0
var _fase := 0
var _atm: Atmosfera
var _oce: Ocean
var _fallos := 0


func _ready() -> void:
	_atm = load("res://src/weather/atmosfera.tscn").instantiate() as Atmosfera
	if _atm == null:
		_comprobar("carga atmosfera.tscn", false, "instantiate devolvio null")
		_finalizar()
		return
	# Se fija ANTES de entrar al arbol: `_ready` de Atmosfera siembra sus
	# caches con estos valores y el primer `_process` los re-confirma (:v
	_atm.viento_intensidad = VIENTO_ATM
	_atm.viento_auto = false
	add_child(_atm)

	# `:=` no puede inferir sobre `load()` (Variant) — misma familia de
	# error que ya tiro este test la primera vez: castear ANTES (:v
	var mar := (load("res://src/water/nodos/mar.tscn") as PackedScene).instantiate()
	if mar == null:
		_comprobar("carga mar.tscn", false, "instantiate devolvio null")
		_finalizar()
		return
	_oce = mar.get_node_or_null(NodePath("Ocean")) as Ocean
	if _oce == null:
		_comprobar("mar.tscn tiene nodo Ocean", false, "no se encontro")
		_finalizar()
		return
	_oce.wind_intensity = VIENTO_OCEANO
	_oce.wind_heading_deg = RUMBO_OCEANO
	# SIN esto el fallback de Ocean corre con SUS rachas (`auto_wind=true`:
	# 0.3 x 1.0995 = 0.3298 y rumbo derivando +-12 grados) — medido en la
	# primera corrida, y el test fallaba por SU expectativa, no por el codigo.
	# Con racha apagada el fallback sale EXACTO y determinista (:v
	_oce.auto_wind = false
	add_child(mar)


func _process(delta: float) -> void:
	if _fase >= 2:
		return
	_t += delta
	if _t < T_ESPERA:
		return
	_t = 0.0
	if _fase == 0:
		_fase_uno()
	else:
		_fase_dos()


## Con Atmosfera viva: ella manda y Ocean la obedece (:v
func _fase_uno() -> void:
	if _atm == null or _oce == null:
		_finalizar()
		return
	var w_atm := _atm.wind_intensity_actual()
	var w_oce := _oce.wind_intensity_actual()
	_comprobar(
			"Atmosfera empuja su viento (%.1f)" % VIENTO_ATM,
			is_equal_approx(w_atm, VIENTO_ATM),
			"wind=%.4f (esperado %.1f)" % [w_atm, VIENTO_ATM]
	)
	# El corazon del contrato D-I2: Ocean NO debe propagar lo suyo (:v
	_comprobar(
			"Ocean adopta el de Atmosfera, no el suyo (%.1f)" % VIENTO_OCEANO,
			is_equal_approx(w_oce, VIENTO_ATM),
			"ocean wind=%.4f (si saliera %.1f, Ocean sigue empujando lo suyo)" % [
				w_oce, VIENTO_OCEANO
			]
	)
	var dir_atm := _atm.wind_direction_actual()
	var dir_oce := _oce.wind_direction_actual()
	_comprobar(
			"direcciones coinciden (lo que lee WaterSurface)",
			dir_atm.is_equal_approx(dir_oce),
			"atm=%s ocean=%s" % [dir_atm, dir_oce]
	)

	# Se libera Atmosfera EN VIVO: Ocean debe notar que el grupo queda vacio
	# y volver a su propia logica sin reiniciar nada (:v
	_atm.queue_free()
	_atm = null
	_fase = 1


## Sin Atmosfera: Ocean recupera su fallback (:v
func _fase_dos() -> void:
	if _oce != null:
		var w := _oce.wind_intensity_actual()
		_comprobar(
				"Ocean cae a SU fallback al liberar Atmosfera (%.1f)" % VIENTO_OCEANO,
				is_equal_approx(w, VIENTO_OCEANO),
				"ocean wind=%.4f (esperado %.1f)" % [w, VIENTO_OCEANO]
		)
		var rumbo := deg_to_rad(RUMBO_OCEANO)
		var esperada := Vector3(sin(rumbo), 0.0, cos(rumbo))
		var dir := _oce.wind_direction_actual()
		_comprobar(
				"rumbo de fallback = %d grados" % int(RUMBO_OCEANO),
				esperada.is_equal_approx(dir),
				"dir=%s esperada=%s" % [dir, esperada]
		)
	_finalizar()


func _finalizar() -> void:
	_fase = 2
	if _fallos == 0:
		print("[PRUEBA] RESULTADO: TODO OK (5 comprobaciones)")
	else:
		print("[PRUEBA] RESULTADO: FALLA — %d comprobacion(es)" % _fallos)
	get_tree().quit(1 if _fallos > 0 else 0)


func _comprobar(nombre: String, ok: bool, detalle: String) -> void:
	if ok:
		print("[PRUEBA] OK   " + nombre)
	else:
		_fallos += 1
		print("[PRUEBA] FALLA " + nombre + " — " + detalle)
