@tool
class_name SoundScape
extends Resource
## Paisaje sonoro completo: conjunto de capas que suenan juntas :v
##
## Se comparte como .tres entre zonas y mapas (misma tormenta en isla y :v
## petrolera = editar un solo recurso). Cada SoundZona apunta a uno.

## Nombre para el overlay de debug y las señales :v
@export var nombre: String = ""
## Capas del paisaje; todas suenan a la vez, cada una con su volumen :v
@export var capas: Array[SoundCapa] = []
