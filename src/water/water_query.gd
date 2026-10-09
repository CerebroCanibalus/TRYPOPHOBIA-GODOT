class_name WaterQuery
extends RefCounted
## Consultas de UN punto contra el mundo de agua. Esta es la fachada que usan
## WaterBody y Oxygen; nadie mas deberia tocar los registros. :v
##
## Prioridad de resolucion, que es la que hace posible "instalaciones secas
## bajo el agua":
##
##   1. Si el punto esta en un AirVolume -> NO hay agua (el aire manda). :v
##   2. Si esta en un WaterVolume y por debajo de su superficie -> hay agua. :v
##   3. En otro caso -> no hay agua. :v
##
## Coste: barrido del registro de aires + de volumenes con pre-filtro de forma.
## Con una decena de volumentes es ruido; si un mapa llegara a cientos, hay que
## añadir un broad-phase (AABB por volumen) — anotado, no hace falta aun. :v


## Bolsa de aire que contiene el punto, o null. :v
static func aire_en(p: Vector3) -> AirVolume:
	for a in AirVolume.registro():
		if a.contiene(p):
			return a
	return null


## Volumen de agua que contiene el punto, o null (aire, o fuera, o sobre la
## superficie). :v
static func volumen_en(p: Vector3) -> WaterVolume:
	for a in AirVolume.registro():
		if a.contiene(p):
			return null
	for v in WaterVolume.registro():
		if v.contiene(p):
			return v
	return null


## ¿Hay agua jugable en el punto? :v
static func en_agua(p: Vector3) -> bool:
	return volumen_en(p) != null


## ¿Se puede respirar en el punto? Fuera de agua o dentro de una bolsa de aire
## marcada como respirable. :v
static func se_puede_respirar(p: Vector3) -> bool:
	var a := aire_en(p)
	if a != null:
		return a.respirable
	return volumen_en(p) == null
