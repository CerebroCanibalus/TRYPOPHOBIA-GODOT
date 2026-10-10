class_name Parche
extends MeshInstance3D
## UN parche de plasta — malla procedural conformada a la superficie.
##
## La zona (`InfeccionZona`) lo crea, lo orienta con la normal del golpe de
## rayo y le pide que se CONFORME: un grid en el plano local XZ cuyo cada
## vertice busca la superficie con su propio rayo. Asi el parche se pega a
## suelo, rampas, columnas y paredes sin que nadie modele nada (:v
##
## Todo lo VISUAL vive en el shader (`infeccion_parche.gdshader`): aqui solo
## hay geometria + UVs. El material se lo pone la zona (UN material por zona,
## asi los uniforms de reaccion son por zona y no por parche). (:v
##
## Offset: cada vertice se levanta OFFSET metros a lo largo de la normal del
## NODO (no de la superficie): sin eso la plasta z-fightea con el suelo. El
## shader no hace alpha-blend (usa `discard`), asi que el material va en el
## pipeline OPAQUE y las sombras salen recortadas con los agujeros. (:v

## Cuantas divisiones por lado del grid. 10 -> 121 vertices, 200 triangulos.
## Es el equilibrio medido: suficiente para que la plasta siga una pendiente
## suave, barato para los ~30 raycasts/vertice que vienen detras. (:v
const SUBDIVISIONES := 10
## Metros que el vertice se levanta sobre la superficie (antiz-fighting).
const OFFSET := 0.025
## Las NO proyectan sombra. Son una concha pegada al suelo: su sombra en si
## misma es la receta de shadow acne (mismo precedente que MarLejano en el
## oceano, ver AGENTS). Ademas la plasta no "flota": lo que tapa ya lo tapa
## la propia geometria con sus agujeros. :v
const PROYECTAR_SOMBRA := false
## Origen de cada rayo de conformado, en Y local (sobre el plano del nodo).
const DIST_ORIGEN := 0.75
## Longitud total del rayo de conformado: DIST_ORIGEN hacia arriba + 1.25
## hacia abajo. Cubre pendientes de ~45 grados dentro del parche; si un
## rayo no da bola (bajo el borde de un techo, por ejemplo) ese vertice se
## queda plano arriba en OFFSET, nunca POR DEBAJO de la superficie. (:v
const LONG_RAYO := 2.0

## Radio efectivo con el que se sembro (para ajustar escala de textura luego).
var radio := 1.0
## true si la malla se construyo con centro encontrado. Un parche sin centro
## NO existe: la zona lo libera en vez de dejar un quad flotando. (:v
var conforme := false


## Orienta el parche a la superficie y construye la malla conformada.
## Devuelve false si el rayo central no toco nada (no hay superficie aqui). :v
func sembrar(punto: Vector3, normal: Vector3, radio_: float, capas: int) -> bool:
	radio = radio_
	# La normal del golpe manda: local +Y = normal de la superficie, asi que
	# "hacia arriba" del grid es "saliendo de la pared" en cualquier
	# orientacion — el mismo parche sirve para suelo, techo y pared. (:v
	var q := Quaternion(Vector3.UP, normal.normalized())
	global_transform = Transform3D(Basis(q), punto)

	var espacio := get_world_3d().direct_space_state
	# Rayo CENTRAL primero: sin suelo debajo del centro no hay parche. :v
	var golpe_centro := _golpear(espacio, Vector3.ZERO, capas)
	if golpe_centro.is_empty():
		return false

	var n := SUBDIVISIONES
	var lado := radio_ * 2.0
	var paso := lado / float(n)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var alturas := PackedFloat32Array()  # Y local por vertice, para las normales

	for iz in n + 1:
		for ix in n + 1:
			var x := -radio_ + ix * paso
			var z := -radio_ + iz * paso
			var y := OFFSET
			var golpe := _golpear(espacio, Vector3(x, 0.0, z), capas)
			if not golpe.is_empty():
				# Origen en DIST_ORIGEN sobre el plano: si la superficie esta
				# a distancia d, su Y local es DIST_ORIGEN - d, y encima el
				# offset del parche entero. :v
				y = DIST_ORIGEN - float(golpe["distance"]) + OFFSET
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(float(ix) / float(n), float(iz) / float(n)))
			alturas.append(y)

	# Normales ANALITICAS del heightfield (derivadas finitas): dan +Y de
	# sentido correcto SIEMPRE, sin depender del winding de los indices —
	# que es justo lo que `cull_disabled` viene a tapar. (:v
	var normales := PackedVector3Array()
	var inv_2p := 1.0 / (2.0 * paso)
	for iz in n + 1:
		for ix in n + 1:
			var i0 := maxi(ix - 1, 0)
			var i1 := mini(ix + 1, n)
			var j0 := maxi(iz - 1, 0)
			var j1 := mini(iz + 1, n)
			var dydx := (alturas[iz * (n + 1) + i1] - alturas[iz * (n + 1) + i0]) * inv_2p
			var dydz := (alturas[j1 * (n + 1) + ix] - alturas[j0 * (n + 1) + ix]) * inv_2p
			normales.append(Vector3(-dydx, 1.0, -dydz).normalized())

	var indices := PackedInt32Array()
	for iz in n:
		for ix in n:
			var v00 := iz * (n + 1) + ix
			var v10 := v00 + 1
			var v01 := (iz + 1) * (n + 1) + ix
			var v11 := v01 + 1
			# Uno por uno y no `append_array([...])`: el literal es un Array
			# sin tipo y las conversiones silenciosas ya han dado problemas
			# en este repo (mismo criterio que Array[X] del sistema de agua). :v
			indices.append(v00)
			indices.append(v01)
			indices.append(v10)
			indices.append(v10)
			indices.append(v01)
			indices.append(v11)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
	conforme = true
	return true


## Un rayo desde `origen_local` a lo largo de -Y local (hacia la superficie).
## Devuelve el Dictionary de `intersect_ray` o vacio si no toco nada. :v
func _golpear(espacio: PhysicsDirectSpaceState3D, origen_local: Vector3, capas: int) -> Dictionary:
	var o := global_transform * (origen_local + Vector3(0.0, DIST_ORIGEN, 0.0))
	var d := global_transform.basis * Vector3.DOWN
	var f := o + d * LONG_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(o, f, capas)
	var golpe := espacio.intersect_ray(consulta)
	if golpe.is_empty():
		return golpe
	# OJO 4.7: `intersect_ray` YA NO devuelve la clave `distance` (era de
	# Godot 3). Sin esto, `golpe["distance"]` tumba `sembrar` entera —
	# medido: 19 errores identicos y 20 parches descartados de 20. (:v
	# El golpe siempre esta sobre la linea del rayo, asi que la distancia es
	# el euclideo desde el origen del propio rayo. :v
	golpe["distance"] = o.distance_to(golpe["position"] as Vector3)
	return golpe
