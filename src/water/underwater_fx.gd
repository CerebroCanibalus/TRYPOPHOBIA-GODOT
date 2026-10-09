class_name DistorsionAgua
extends CanvasLayer
## Distorsion de pantalla cuando el juego te considera bajo el agua. :v
##
## Es el ESPEJO visual de `WaterBody`: no decide nada, solo traduce el estado
## que ya calcula la fisica a un post-proceso para que el jugador SEPA que le
## estan contando como sumergido.
##
##   `sumergido`       -> tinte suave (estas mojado)
##   `cabeza_sumergida`-> distorsion fuerte (estas buceando, y de ahi sale
##                        el oxigeno y el ahogo)
##
## Se auto-monta el ColorRect y el ShaderMaterial en _ready: la escena solo
## necesita ESTE nodo. La capa por defecto (1) deja el HUD por encima, asi el
## texto no se distorsiona. :v

@export_group("Enlazado")
## WaterBody del personaje. Vacio = el del padre/arbrito. :v
@export var agua: NodePath
## Rapidez del fundido al entrar/salir (mayor = mas inmediato). :v
@export_range(1.0, 20.0, 0.5) var suavizado := 6.0

const SHADER := "res://src/shaders/underwater_distortion.gdshader"

var _agua: WaterBody
var _mat: ShaderMaterial
var _rect: ColorRect
var _fuerza := 0.0


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.name = "Distorsion"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Sin esto el rect come el raton y bloquea cualquier UI de encima. :v
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	_mat = ShaderMaterial.new()
	var sh := load(SHADER) as Shader
	if sh == null:
		push_warning("[water] no cargo %s: sin distorsion submarina. :v" % SHADER)
	else:
		_mat.shader = sh
		_rect.material = _mat
	add_child(_rect)

	_agua = _resolver_agua()
	if _agua == null:
		push_warning("[water] DistorsionAgua sin WaterBody: el efecto se queda quieto. :v")


func _process(delta: float) -> void:
	if _agua == null or not is_instance_valid(_agua):
		return
	# Objetivo: fuera = 0; mojado = 0.45 (tinte); buceando = 0.7 y mas hondo,
	# mas fuerte (hondo = mas columna de agua entre tu ojo y la superficie). :v
	var objetivo := 0.0
	if _agua.sumergido:
		objetivo = 0.45
		if _agua.cabeza_sumergida:
			objetivo = clampf(0.7 + _agua.profundidad / 20.0, 0.7, 1.0)
	# Exponencial: estable a cualquier FPS, sin depender de delta lineal. :v
	_fuerza = lerpf(_fuerza, objetivo, 1.0 - exp(-suavizado * delta))
	var encendida := _fuerza > 0.004
	if _rect.visible != encendida:
		_rect.visible = encendida
	if encendida and _mat != null:
		_mat.set_shader_parameter("fuerza", _fuerza)


## Fuerza actual del efecto, 0..1 (para HUD/debug). :v
func fuerza_actual() -> float:
	return _fuerza


func _resolver_agua() -> WaterBody:
	if not agua.is_empty():
		return get_node_or_null(agua) as WaterBody
	# El WaterBody del personaje al que cuelga este CanvasLayer. :v
	var n := get_parent()
	while n != null:
		var hit := WaterBody.buscar_en(n)
		if hit != null:
			return hit
		n = n.get_parent()
	return null
