@tool
extends EditorScenePostImport
## Arregla al importar las dos cosas que un glTF de Blender trae mal para Godot.
##
## SE LLAMABA `luces_fotometricas.gd` y hacia solo lo primero. Lo segundo entro al
## meter el sumergible, que es la primera pieza por la que se ANDA POR DENTRO.
##
## 1. Deshace la conversion fotometrica de las luces.
##
## Blender exporta las luces en unidades fisicas y Godot, sin physical light
## units, se las traga como multiplicador: el Sol de la isla llegaba con
## light_energy = 1775.8 en vez de 2.6, o sea 683 veces de mas. Resultado: 52,3 %
## del fotograma saturado, el terreno entero a blanco y el verde muerto ANTES de
## llegar al cuantizador — ninguna paleta podia arreglar eso.
##
## La conversion de Blender (PBR_WATTS_TO_LUMENS = 683):
##     SUN    lux = W/m2 * 683
##     POINT  cd  = W * 683 / (4*PI)        (y SPOT igual)
## Asi que aqui se invierte y se recupera EXACTAMENTE el valor que tiene la
## lampara en el .blend: 1775.8/683 = 2.6 y 1195.73*4*PI/683 = 22.0.
##
## El exportador de la Petrolera ya escribia `light_energy = sol.data.energy`
## a mano; esto es lo mismo para los mapas que viajan por glTF.

const LUMENES_POR_VATIO := 683.0
# si tras convertir una luz no cae aqui, es que la suposicion es falsa y hay que
# mirarlo en vez de dejar pasar un numero raro
const MIN_PLAUSIBLE := 0.01
const MAX_PLAUSIBLE := 1000.0

## 2. Enciende `backface_collision` en toda malla de colision.
##
##    POR QUE HACE FALTA, medido y no supuesto: en el casco del sumergible, de las
##    caras del piso OCHO miraban arriba y CINCO abajo, y de la virola interior 214
##    estaban del reves contra 169 bien. No es descuido del constructor —
##    `recalc_face_normals` no puede orientar una malla que mezcla un casco cerrado
##    con superficies de una sola cara (el piso, las pantallas de las lamparas, los
##    peldanos), asi que las orienta como puede.
##
##    Un `ConcavePolygonShape3D` trae `backface_collision` APAGADO por defecto: solo
##    choca por la cara de delante. Con mas de la mitad de la pared interior del
##    reves, eso es un submarino por cuyas paredes se sale andando y por cuyo suelo
##    se cae. Encendido, la orientacion deja de importar — que es justo lo que hace
##    falta en cualquier pieza HUECA que se recorra por dentro.
##
##    Reorientar las caras a mano seria arreglar el sintoma en una pieza; esto lo
##    arregla para todas, y ademas una pared de verdad choca por los dos lados.

func _post_import(scene: Node) -> Object:
	var n := _convertir(scene, 0)
	var c := _colisiones(scene, 0)
	print("[importar] %d luces a unidades de Blender · %d mallas de colision a dos caras" % [n, c])
	return scene


func _colisiones(nodo: Node, n: int) -> int:
	if nodo is CollisionShape3D:
		var f := nodo.shape as ConcavePolygonShape3D
		if f != null and not f.backface_collision:
			f.backface_collision = true
			n += 1
	for h in nodo.get_children():
		n = _colisiones(h, n)
	return n

func _convertir(nodo: Node, n: int) -> int:
	if nodo is DirectionalLight3D:
		n = _fijar(nodo, nodo.light_energy / LUMENES_POR_VATIO, n)
	elif nodo is OmniLight3D or nodo is SpotLight3D:
		n = _fijar(nodo, nodo.light_energy * 4.0 * PI / LUMENES_POR_VATIO, n)
	for h in nodo.get_children():
		n = _convertir(h, n)
	return n

func _fijar(luz: Light3D, vatios: float, n: int) -> int:
	assert(vatios >= MIN_PLAUSIBLE and vatios <= MAX_PLAUSIBLE,
		"%s: %f W fuera de rango tras convertir %f" % [luz.name, vatios, luz.light_energy])
	luz.light_energy = vatios
	return n + 1
