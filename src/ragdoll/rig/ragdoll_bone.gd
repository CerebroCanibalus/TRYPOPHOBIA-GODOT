extends Resource
class_name RagdollBone
## Descripción de UN hueso físico del ragdoll (un `PhysicalBone3D` + su
## collider). Es la UNIDAD de datos de la librería: el `RagdollRig` tiene una
## lista de estos y de ahí salen tanto los nodos de la ESCENA como los
## cuerpos que crea el runtime.
##
## Antes esto era un `Dictionary` suelto dentro de `physical_bones` (sin
## tipar: `{"name": ..., "shape": ..., "args": ...}`). Un diccionario sin
## tipar es la forma mas facil de que un rig se rompa en silencio (una
## clave mal escrita = un collider nulo y un hueso sin masa). :v

## Forma del collider.
enum Shape {
	BOX,      ## Caja: para el torso y la pelvis (volumen, no forma de hueso).
	CAPSULE,  ## Cápsula: la forma natural de un hueso largo.
	SPHERE,   ## Esfera: para clavículas y manos.
}

## Nombre del hueso en el esqueleto (el `bone_name` del PhysicalBone3D).
@export var bone_name: StringName = &""

## Forma del collider.
@export var shape: Shape = Shape.CAPSULE

## Tamaño de la caja (solo `BOX`).
@export var size := Vector3(0.2, 0.4, 0.2)

## Radio de la cápsula o de la esfera.
@export var radius := 0.08

## Alto total de la cápsula (incluye las tapas).
@export var height := 0.4

## Desplazamiento del collider sobre el eje +Y del hueso (metros). El
## collider va del origen del hueso al de su hijo, asi que suele ser la
## mitad de la longitud del hueso.
@export var offset := 0.0

## Masa del cuerpo (kg). Es la MASA REAL de ese cuerpo (su volumen): la
## suma de todas da el peso del personaje.
##
## OJO: la masa que un hueso SOPORTA (la del torso que aguanta al
## personaje) NO va aqui: va en `pd_gain`. Meterla en la masa hace que el
## ragdoll pese 4 veces su peso y que la inercia descoloque a los
## extremos (medido: 216 kg de peso para un personaje de 50).
@export var mass := 1.0

## Ganancia del PD para este hueso (multiplica rigidez y amortiguamiento).
## Un hueso que SOPORTA mucho (la pelvis, el pecho) necesita un PD mas
## fuerte para que la gravedad no lo gane: sin esto el torso se queda
## tumbado (medido: 90 grados de error estatico).
@export var pd_gain := 1.0

## Limite del joint en GRADOS (tipo cono). 180/180 = articulacion libre:
## el cono no debe pelear con el PD.
@export var swing := 180.0
@export var twist := 180.0

## Tipo de joint de Godot. 2 = cono (el unico que soporta Box3D ademas de
## pin/hinge/slider). OJO: el 5 (Generic6DOF) NO lo soporta Box3D.
@export var joint_type := 2

## Capas de colision. La mascara por defecto (5) = mundo (1) + objetos
## agarrables (4), pero NO otros huesos (2): los colliders de huesos
## vecinos se solapan y se empujarian entre si.
## El hueso NO tiene collider (solo el cuerpo y el joint).
##
## Para el PIE es lo correcto (y es lo que hace el proyecto de referencia,
## que SI camina): el pie es un hueso SIN collider y la capsula de la
## ESPINILLA hace de pie (llega al tobillo). Con collider en el pie:
##   * el rozamiento de la planta frena al personaje (medido: 0,5 m/s en
##     vez de 3),
##   * al aterrizar el collider se clava en el suelo y el servo no puede
##     girar el hueso (medido: el pie se queda clavado a 114 grados de
##     error y gira en sentido contrario al del servo).
## El rozamiento del collider de este hueso.
##
## Para el PIE va a 0: el pie apoya (que se vea en el suelo) pero NO
## frena al personaje. Con friccion 0,9 el pie se agarraba al suelo y el
## Shiba se quedaba en 0,68 m/s (medido); con el pie SIN collider se
## llegaba a 1,43 m/s, pero el pie ya no apoyaba (medido).
@export var friction := 0.2
@export var sin_collider := false
## Los huesos con los que ESTE hueso NO colisiona. Patrones de nombre; un
## * final es comodin de prefijo ("spine*" = todos los que empiezan por
## spine).
##
## Es la regla que hace que los brazos choquen con las CADERAS y el torso
## bajo (que es lo que deben) y NO con el pecho. La regla automatica
## ("se solapan en reposo -> no colisionan") metia los brazos DENTRO del
## torso entero: el AABB del húmero en T cruza el pecho (medido).
@export var sin_colision_con := PackedStringArray()
## Los huesos con los que ESTE hueco SI colisiona, aunque se solapen en
## reposo. Tiene prioridad sobre la regla automatica.
@export var colision_con := PackedStringArray()
@export var collision_layer := 2
## El cuerpo va alineado con los EJES DEL MODELO en vez de los del hueso.
##
## Para el PIE es imprescindible: el hueso del pie esta inclinado 38
## grados (medido), asi que una capsula sobre su eje Y se clava en el
## suelo en diagonal: el pie patina, el servo no puede alinearlo (error
## de 65 grados) y el personaje se arrastra (medido).
@export var orientacion_modelo := false
## Desplazamiento del cuerpo en los ejes del MODELO (se usa con
## orientacion_modelo): lleva el collider al centro del pie.
@export var offset_modelo := Vector3.ZERO

## Mascara de colision. 5 = 1 (mundo) + 4 (interactuables). El bit 2 (los
## propios huesos) lo anade el runtime: los huesos colisionan entre si
## (para que los brazos no se metan en el cuerpo) EXCEPTO con su padre y
## su hijo, que se excluyen por excepcion del servidor.
@export var collision_mask := 5

## Grupo del hueso para los filtros del PD: "column" (torso), "arm",
## "leg" o "" (neutro). Es mas robusto que buscar por nombre.
@export var group := ""


## Crea el `Shape3D` de este hueso.
func make_shape() -> Shape3D:
	match shape:
		Shape.BOX:
			var box := BoxShape3D.new()
			box.size = size
			return box
		Shape.CAPSULE:
			var cap := CapsuleShape3D.new()
			cap.radius = radius
			cap.height = maxf(height, radius * 2.0 + 0.001)
			return cap
		Shape.SPHERE:
			var sph := SphereShape3D.new()
			sph.radius = radius
			return sph
	return null


## Nombre legible para los informes.
func describe() -> String:
	return "%s (%s, %.1f kg, swing %.0f/twist %.0f)" % [
		bone_name, Shape.keys()[shape], mass, swing, twist]
