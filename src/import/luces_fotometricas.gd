@tool
extends EditorScenePostImport
## Deshace la conversion fotometrica del exportador glTF de Blender.
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

func _post_import(scene: Node) -> Object:
	var n := _convertir(scene, 0)
	print("[luces] %d luces devueltas a las unidades de Blender" % n)
	return scene

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
