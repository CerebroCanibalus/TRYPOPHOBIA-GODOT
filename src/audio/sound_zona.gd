@tool
class_name SoundZona
extends Resource
## Zona espacial por MATH puro (sin Area3D, decisión A1) :v
##
## Su forma + caída definen un peso 0..1 según dónde esté el oyente; :v
## con ese peso suena el SoundScape asociado. Varias zonas conviven y :v
## se crossfadean solas porque sus pesos se mueven en direcciones opuestas.

enum Forma { ESFERA, CAJA }

## Nombre visible en el overlay de debug (F3) :v
@export var nombre: String = ""
## Paisaje sonoro que suena dentro de esta zona :v
@export var soundscape: SoundScape
## Forma geométrica de la zona :v
@export var forma: Forma = Forma.ESFERA
## Centro de la forma en espacio LOCAL del nodo AmbienteAudio :v
@export var centro: Vector3 = Vector3.ZERO
## ESFERA: radio en metros :v
@export var radio: float = 10.0
## CAJA: semitamaño por eje en metros (x,y,z = ancho,alto,fondo/2) :v
@export var tamano: Vector3 = Vector3(10.0, 5.0, 10.0)
## Distancia de CAÍDA fuera de la forma hasta peso 0 (m). :v
## 0 = corte seco en el borde (sin crossfade espacial) :v
@export var caida: float = 6.0
## Curva de atenuación muestreada en 0..1 (0 = borde de la forma, :v
## 1 = final de la caída). Vacía = lineal descendente :v
@export var curva: Curve
## Apagar la zona sin quitarla de la lista :v
@export var activa: bool = true


## Distancia desde el punto hasta la superficie de la forma (0 = dentro) :v
func distancia_fuera(punto_local: Vector3) -> float:
	var d := punto_local - centro
	match forma:
		Forma.ESFERA:
			return maxf(d.length() - radio, 0.0)
		Forma.CAJA:
			var fuera := Vector3(
				maxf(absf(d.x) - tamano.x, 0.0),
				maxf(absf(d.y) - tamano.y, 0.0),
				maxf(absf(d.z) - tamano.z, 0.0))
			return fuera.length()
	return 0.0


## Peso 0..1 de la zona para un punto en espacio local del nodo :v
func peso_en(punto_local: Vector3) -> float:
	if not activa or soundscape == null:
		return 0.0
	var fuera := distancia_fuera(punto_local)
	if caida <= 0.0:
		return 1.0 if fuera <= 0.0 else 0.0
	var t := clampf(fuera / caida, 0.0, 1.0)
	if curva != null:
		return clampf(curva.sample_baked(t), 0.0, 1.0)
	return 1.0 - t
