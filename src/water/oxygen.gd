class_name Oxygen
extends Node
## Oxigeno y AHOGO. Cuelga de cualquier personaje con un WaterBody al lado y
## no sabe nada mas del juego: lee `cabeza_sumergida`, consume, y avisa. :v
##
## Decisiones (por ahora NO hay sistema de vida, y esto es deliberado):
##  * La cuenta es SOLO oxigeno. Con el tanque lleno no pasa nada, con el
##    tanque vacio empieza la gracia del ahogo (`gracia` segundos). :v
##  * Al agotarse llama a `apply_damage(dano * delta)` SI el cuerpo lo
##    entiende (mismo duck-typing que arma.gd -> vida.gd). Si nadie lo
##    entiende, no mata: solo emite `ahogado()` y el que quiera que reaccione.
##    Asi el sistema se enchufa hoy sin inventar la barra de vida. :v
##  * `morir()` si existe. Optional, siempre. :v
##
## Senales:
##   oxigeno_cambiado(restante, maximo)  — para la barra de HUD
##   sumergio_cambiada(sumergido)        — entro/salio el CAPO (no la cabeza)
##   sin_aire()                          — el tanque llego a 0
##   respirando_de_nuevo()               — recupero aire con el tanque vacio
##   ahogado()                           — se acabo la gracia :v
##
## API: `restante`, `maximo`, `porcentaje()` (0..1), `agotado` (bool).

signal oxigeno_cambiado(restante: float, maximo: float)
signal sumergio_cambiada(sumergido: bool)
signal sin_aire()
signal respirando_de_nuevo()
signal ahogado()

@export_group("Enlazado")
## Cuerpo dueño (para apply_damage / morir). Vacio = el padre. :v
@export var cuerpo: NodePath
## WaterBody del que lee la cabeza. Vacio = se busca en el arbol del dueño.
@export var agua: NodePath

@export_group("Apnea")
## Segundos de aire con el tanque lleno.
@export_range(5.0, 600.0, 1.0) var maximo := 60.0
## Cuanto se gasta por segundo bajo el agua. 6 = 10 s de apnea. :v
@export_range(0.5, 60.0, 0.5) var consumo := 6.0
## Cuanto se recupera por segundo fuera del agua. Tiene que ser MAYOR que el
## consumo o el bucle no cierra: nadie se recupera mas lento de lo que ahoga. :v
@export_range(0.5, 120.0, 0.5) var regeneracion := 25.0
## Segundos que aguantas con el tanque vacio antes de `ahogado()`. :v
@export_range(0.0, 60.0, 0.5) var gracia := 8.0
## Danio por segundo con el tanque vacio, si el cuerpo entiende apply_damage.
@export_range(0.0, 100.0, 0.5) var dano_ahogo := 12.0

var restante: float = 0.0
var agotado: bool = false
var sumergido: bool = false

var _cuerpo: Node
var _agua: WaterBody
var _segundos_vacio: float = 0.0
var _ahogado: bool = false


func _ready() -> void:
	restante = maximo
	_cuerpo = _resolver_cuerpo()
	_agua = _resolver_agua()
	if _agua == null:
		push_warning("[water] Oxygen (%s) sin WaterBody: no hay ahogo que hacer. :v" % name)


func _physics_process(delta: float) -> void:
	if _agua == null or not is_instance_valid(_agua):
		return

	var bajo := _agua.cabeza_sumergida
	if bajo != sumergido:
		sumergido = bajo
		sumergio_cambiada.emit(bajo)

	var antes := restante
	if bajo:
		restante = maxf(restante - consumo * delta, 0.0)
	else:
		restante = minf(restante + regeneracion * delta, maximo)
		if _segundos_vacio > 0.0:
			_segundos_vacio = 0.0
			if restante > 0.0:
				respirando_de_nuevo.emit()
	if not is_equal_approx(antes, restante):
		oxigeno_cambiado.emit(restante, maximo)

	var vacio := restante <= 0.0
	if vacio != agotado:
		agotado = vacio
		if vacio:
			sin_aire.emit()
		if not _ahogado:
			_segundos_vacio = 0.0

	if vacio:
		_segundos_vacio += delta
		if dano_ahogo > 0.0 and _cuerpo != null and _cuerpo.has_method("apply_damage"):
			_cuerpo.apply_damage(dano_ahogo * delta)
		if not _ahogado and _segundos_vacio >= gracia:
			_ahogado = true
			ahogado.emit()
			if _cuerpo != null and _cuerpo.has_method("morir"):
				_cuerpo.morir()


## Fraccion de aire restante, 0..1. Para barras que prefieren tanto por ciento. :v
func porcentaje() -> float:
	return restante / maxf(maximo, 0.001)


## Rellena el tanque (respawn, traje, burbuja de oxigeno del nivel). :v
func rellenar(cantidad: float = INF) -> void:
	restante = minf(restante + cantidad if is_finite(cantidad) else maximo, maximo)
	agotado = false
	oxigeno_cambiado.emit(restante, maximo)


func _resolver_cuerpo() -> Node:
	if not cuerpo.is_empty():
		return get_node_or_null(cuerpo)
	return get_parent()


## Busca el Oxygen dentro de un arbol (mismo convenio que WaterBody.buscar_en). :v
static func buscar_en(raiz: Node) -> Oxygen:
	if raiz == null:
		return null
	if raiz is Oxygen:
		return raiz as Oxygen
	for c in raiz.get_children():
		var hit := buscar_en(c)
		if hit != null:
			return hit
	return null


func _resolver_agua() -> WaterBody:
	if not agua.is_empty():
		return get_node_or_null(agua) as WaterBody
	return WaterBody.buscar_en(get_parent())
