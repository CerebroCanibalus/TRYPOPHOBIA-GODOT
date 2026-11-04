extends SceneTree

## FORGE DEL RIG del Shiba.
##
## Genera `src/ragdoll/rig/shiba_rig_config.tres` con la FISICA DEL RAGDOLL:
## que huesos tienen cuerpo, que collider lleva cada uno, que masa, que
## limites de articulacion y que reglas de colision.
##
## NUESTRO RIG, NO EL DE LA REFERENCIA
## -----------------------------------
## El proyecto de referencia (`tools/active_ragdoll_reference`) tiene 10
## cuerpos: pelvis + cabeza + 2 brazos x 2 + 2 piernas x 2, y su TORSO es
## un solo cuerpo rigido.
##
## El NUESTRO es mas complejo y mas expresivo (17 cuerpos): una COLUMNA de
## 7 huesos (spine..head), claviculas, brazos de 2, piernas de 2 y
## cabeza aparte. Eso permite que la ANIMACION deforme el modelo de verdad
## (el torso contra-rota, los hombros suben y bajan) en vez de mover un
## bloque rigido.
##
## El precio es que una cadena de 7 cuerpos articulados es un pendulo de 7
## eslabones: servirlos a una ORIENTACION ABSOLUTA uno por uno hace que
## cada uno pelee con su vecino (medido: la pelvis giraba a 344 grados por
## segundo y el personaje no ganaba terreno). El SERVO tiene que tratar la
## cadena como una cadena (el padre manda, el hijo se mueve RELATIVO a
## el padre): eso lo hace `RagdollMotor`.
##
## LA ANATOMIA (medida en el esqueleto del modelo; el informe completo lo
## da `tools/ragdoll/autorar_huesos.gd`):
##
##   neutral_bone
##   spine         (0.000, 0.829,-0.055)  raiz del tronco   ejeY arriba
##   +- spine.001  (0.000, 1.027, 0.008)   0,207
##      +- spine.002  (0.000, 1.189, 0.037)   0,165
##         +- spine.003  (0.000, 1.330, 0.016)   0,142   <- los hombros
##            |  +- shoulder.L  (0.018, 1.461, 0.068)   0,142
##            |  |  +- upper_arm.L (0.195, 1.420,-0.047)  0,215  ejeY al codo
##            |  |     +- forearm.L (0.481, 1.411,-0.052)  0,286
##            |  |        +- hand.L (0.784, 1.403,-0.049)  0,303 -> dedos
##            |  +- breast.L/R (0.118, 1.321, 0.174)   0,197
##            +- spine.004  (0.000, 1.494,-0.025)   0,169
##               +- spine.005  (0.000, 1.553,-0.025)   0,059
##                  +- head (0.000, 1.611,-0.025)   0,058  LA CABEZA
##   +- pelvis.L/R (0.000, 0.829,-0.055)  0,000  puente (sin cuerpo)
##   +- thigh.L   (0.176, 0.922,-0.012)  0,204  ejeY ABAJO (hacia la rodilla)
##      +- shin.L (0.197, 0.537,-0.001)  0,386
##         +- foot.L (0.232, 0.144,-0.067)  0,400   puente (sin cuerpo)
##            +- toe.L (0.232, 0.009, 0.038) / heel.02.L (0.194,0,-0.101)
##
## OJO con los PUENTES: `pelvis.L`, `shoulder.L`, `foot.L` y `hand.L` NO
## tienen cuerpo, pero eso NO rompe nada: Godot 4.7 busca el ancestro con
## cuerpo al crear el joint
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent` sube por la
## jerarquia). Verificado en el codigo de Godot 4.7.1.

const SRC := "res://src/player/shiba_player.tscn"
const DST := "res://src/ragdoll/rig/shiba_rig_config.tres"

## ZANCADA del ciclo de paso (m): lo que avanza el pie, de la punta atras
## a la punta delante.
##
## MEDIDA (2026-11-04, geometria): la pierna va de la cadera (y=0,922) a
## la rodilla (0,537) al tobillo (0,144): 0,786 m. Con el pie en el suelo
## el tobillo solo puede avanzar +-0,19 m (los 0,786 de pierna no dan
## para mas), asi que la zancada maxima con el pie plantado es de unos
## 0,38 m. Se usa 0,32 (con margen: el pie no llega al limite).
const ZANCADA := 0.32
## DURACION del ciclo de paso (s).
##
## Un ciclo son DOS pasos (una pierna y la otra) y en cada paso el cuerpo
## avanza UNA zancada (el pie va hacia atras mientras esta plantado y el
## cuerpo pasa por encima). Con la zancada de 0,32 m, un ciclo de 0,58 s
## da una velocidad NATURAL de 2*0,32/0,58 = 1,10 m/s: el ritmo de andar
## del Shiba (3,4 pasos por segundo).
##
## OJO con el factor 2 (medido): sin el, el clip va al doble de ritmo que
## el suelo y los pies patinan.
const CICLO := 0.58


func _init() -> void:
	var src := load(SRC) as PackedScene
	if src == null:
		print("ERROR: no carga ", SRC)
		quit(1)
		return
	var inst := src.instantiate()
	var skel := inst.get_node_or_null("Animated/metarig/Skeleton3D") as Skeleton3D
	if skel == null:
		print("ERROR: no hay esqueleto")
		quit(1)
		return

	var rig := RagdollRig.new()
	rig.model_path = "res://assets/players/shiba/shiba_V2.glb"
	rig.skeleton_path_in_model = "metarig/Skeleton3D"
	rig.body_bone_name = &"spine"
	rig.head_bone_name = &"head"
	rig.grab_bone_left_name = &"forearm.L"
	rig.grab_bone_right_name = &"forearm.R"
	# El "cast de suelo" cuelga del hueso que TIENE cuerpo (la espinilla) y
	# se coloca en la planta del pie (su hijo, el hueso "foot", que es un
	# puente sin cuerpo).
	rig.on_floor_left_bone_name = &"shin.L"
	rig.on_floor_right_bone_name = &"shin.R"
	rig.ik_arm_left = {"root": &"upper_arm.L", "mid": &"forearm.L", "end": &"hand.L"}
	rig.ik_arm_right = {"root": &"upper_arm.R", "mid": &"forearm.R", "end": &"hand.R"}
	rig.arm_name_token = "upper_arm"
	rig.leg_name_token = "thigh"
	rig.lean_body_suffix = "spine"
	rig.lean_head_suffix = "head"
	rig.clip_idle = &"IDLE"
	rig.clip_walk = &"walk_full"
	rig.clip_grab_lower = &"lean_back"
	rig.clip_grab_middle = &"IDLE"
	rig.clip_grab_upper = &"lean_forward"
	rig.walk_stride = ZANCADA
	rig.walk_cycle = CICLO
	rig.head_look_bones = PackedStringArray(["head"])
	rig.head_look_weights = PackedFloat32Array([1.0])

	# El ORDEN de la lista es el ORDEN DE LOS HUESOS EN EL ESQUELETO (no
	# el de la lista de la referencia): el autoring usa esa posicion para
	# el `index` del nodo dentro del esqueleto, y si no coincide el
	# editor reordena los huesos al guardar (medido: con el indice
	# inventado, los `PhysicalBone3D` acababan en un orden que no era el
	# del esqueleto y los joints se emparejaban con el hueso equivocado).
	var huesos: Array[RagdollBone] = []
	huesos.append(_columna("spine"))
	huesos.append(_columna("spine.001"))
	huesos.append(_columna("spine.002"))
	huesos.append(_columna("spine.003"))
	huesos.append(_columna("spine.004"))
	huesos.append(_columna("spine.005"))
	huesos.append(_cabeza())
	huesos.append(_clavicula("shoulder.L", "L"))
	huesos.append(_brazo("upper_arm.L", "L"))
	huesos.append(_antebrazo("forearm.L", "L"))
	huesos.append(_mano("hand.L", "L"))
	huesos.append(_clavicula("shoulder.R", "R"))
	huesos.append(_brazo("upper_arm.R", "R"))
	huesos.append(_antebrazo("forearm.R", "R"))
	huesos.append(_mano("hand.R", "R"))
	huesos.append(_muslo("thigh.L", "L"))
	huesos.append(_espinilla("shin.L", "L"))
	huesos.append(_muslo("thigh.R", "R"))
	huesos.append(_espinilla("shin.R", "R"))
	rig.physical_bones = huesos

	print("rig: %d cuerpos (nuestro rig: columna de 7 + hombros + 2x2 brazos + 2x2 piernas)" % \
		rig.physical_bones.size())
	var total := 0.0
	for b in rig.physical_bones:
		total += b.mass
		print("  %-14s %-10s masa=%5.2f  off=%5.3f  pd=%3.1f" % [
			b.bone_name, _forma(b), b.mass, b.offset, b.pd_gain])
	print("  peso total: %.1f kg" % total)
	print("  velocidad natural del clip: %.2f m/s (zancada %.2f / ciclo %.2f)" % [
		ZANCADA / CICLO, ZANCADA, CICLO])

	var err := ResourceSaver.save(rig, DST)
	print("SAVE ", DST, " err=", err)
	quit(0 if err == OK else 1)


## Un trozo de la COLUMNA (el tronco). El collider es una CAJA (el torso
## es volumen, no forma de hueso) y va hacia el HIJO (en este modelo el
## +Y local del hueso apunta al hijo).
##
## Las masas: el tronco de arriba es mas ligero que el de abajo (el que
## SOPORTA necesita inercia; el que se mueve, no) y las piernas pesan mas
## que el torso (son las que empujan contra el suelo).
func _columna(nombre_hueso: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = StringName(nombre_hueso)
	b.shape = RagdollBone.Shape.BOX
	match nombre_hueso:
		"spine":
			b.size = Vector3(0.30, 0.26, 0.28)
			b.offset = 0.15
			b.mass = 4.40
		"spine.001":
			b.size = Vector3(0.28, 0.24, 0.26)
			b.offset = 0.08239428
			b.mass = 3.85
		"spine.002":
			b.size = Vector3(0.26, 0.22, 0.24)
			b.offset = 0.0712118
			b.mass = 3.30
		"spine.003":
			b.size = Vector3(0.26, 0.22, 0.24)
			b.offset = 0.08458592
			b.mass = 3.30
		"spine.004":
			b.size = Vector3(0.14, 0.14, 0.12)
			b.offset = 0.029453397
			b.mass = 0.55
		"spine.005":
			b.size = Vector3(0.14, 0.12, 0.12)
			b.offset = 0.029055059
			b.mass = 0.50
	b.pd_gain = 2.0
	b.swing = 180.0
	b.twist = 180.0
	b.friction = 0.2
	b.group = "column"
	# Los huesos de la columna no colisionan entre si (son trozos del
	# mismo torso y se solapan).
	b.sin_colision_con = PackedStringArray(["spine*", "shoulder.*", "breast.*"])
	return b


## La CABEZA (esfera) es el ultimo de la columna.
func _cabeza() -> RagdollBone:
	var cabeza := RagdollBone.new()
	cabeza.bone_name = &"head"
	cabeza.shape = RagdollBone.Shape.SPHERE
	cabeza.radius = 0.11
	cabeza.offset = 0.03
	cabeza.mass = 0.825
	cabeza.pd_gain = 2.0
	cabeza.swing = 90.0
	cabeza.twist = 100.0
	cabeza.friction = 0.2
	cabeza.group = "column"
	cabeza.sin_colision_con = PackedStringArray(["spine*", "shoulder.*"])
	return cabeza


## La CLAVICULA: une el pecho (spine.003) con el hombro. Es un huesito
## corto (0,142 hasta el hombro) y su collider es una caja pequena.
##
## OJO: el brazo (upper_arm) se articula con el ANTEPASADO con cuerpo (el
## pecho), porque la clavicula esta en medio: Godot 4.7 sube por la
## jerarquia buscando el ancestro con cuerpo
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent`).
func _clavicula(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.BOX
	b.size = Vector3(0.14, 0.12, 0.12)
	b.height = 0.21489331
	b.offset = 0.107446656
	b.mass = 1.5
	b.pd_gain = 3.0
	b.swing = 180.0
	b.twist = 180.0
	b.friction = 0.2
	b.sin_colision_con = PackedStringArray(["spine*", "shoulder.*"])
	return b


## El BRAZO SUPERIOR (hombro -> codo): 0,286 m.
func _brazo(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.CAPSULE
	b.radius = 0.055
	b.height = 0.28615618
	b.offset = 0.14307809
	b.mass = 1.0
	b.pd_gain = 1.5
	b.swing = 180.0
	b.twist = 90.0
	b.friction = 0.2
	b.group = "arm"
	# El brazo NO choca con el pecho (a la altura del hombro lo rozaria
	# sin parar) pero SI con la cadera y las piernas.
	b.sin_colision_con = PackedStringArray(["spine.002", "spine.003", "spine.004",
		"spine.005", "head", "shoulder.L", "shoulder.R"])
	b.colision_con = PackedStringArray(["spine", "spine.001", "thigh." + lado,
		"thigh." + ("R" if lado == "L" else "L"),
		"shin." + lado, "shin." + ("R" if lado == "L" else "L")])
	return b


## El ANTEBRAZO (codo -> muneca): 0,303 m.
func _antebrazo(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.CAPSULE
	b.radius = 0.05
	b.height = 0.338
	b.offset = 0.169
	b.mass = 0.8
	b.pd_gain = 1.5
	b.swing = 180.0
	b.twist = 90.0
	b.friction = 0.2
	b.group = "arm"
	b.sin_colision_con = PackedStringArray(["spine.002", "spine.003", "spine.004",
		"spine.005", "head", "shoulder.L", "shoulder.R",
		"upper_arm.L", "upper_arm.R"])
	b.colision_con = PackedStringArray(["spine", "spine.001", "thigh." + lado,
		"thigh." + ("R" if lado == "L" else "L"),
		"shin." + lado, "shin." + ("R" if lado == "L" else "L")])
	return b


## La MANO: cuerpo pequeno en el hueso "hand.L/R" (la muneca). Los
## dedos son huesos SIN cuerpo (puente): los lleva el antebrazo.
##
## La referencia no tiene cuerpo de mano (cuelga el area de agarre del
## antebrazo), pero NUESTRO rig si: la mano es lo que agarra las cosas y
## sin cuerpo la mano no puede girar ni empujar contra nada.
func _mano(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.CAPSULE
	b.radius = 0.04
	b.height = 0.10
	b.offset = 0.04
	b.mass = 0.25
	b.pd_gain = 1.0
	b.swing = 180.0
	b.twist = 90.0
	b.friction = 0.4
	b.group = "arm"
	b.sin_colision_con = PackedStringArray(["spine*", "shoulder.*",
		"upper_arm.L", "upper_arm.R"])
	return b


## El MUSLO (cadera -> rodilla): 0,386 m. El eje +Y del hueso apunta hacia
## ABAJO (hacia la rodilla), asi que la capsula va en +Y (abajo).
func _muslo(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.CAPSULE
	b.radius = 0.084910455
	b.height = 0.38595662
	b.offset = 0.19297831
	b.mass = 3.52
	b.pd_gain = 3.0
	b.swing = 180.0
	b.twist = 90.0
	b.friction = 0.3
	b.group = "leg"
	b.sin_colision_con = PackedStringArray(["spine*", "thigh." + lado,
		"thigh." + ("R" if lado == "L" else "L")])
	return b


## La ESPINILLA (rodilla -> pie): el collider llega hasta el suelo, que es
## lo que hace de pie al personaje (el pie es un hueso SIN cuerpo, como en
## la referencia).
##
## La capsula va desde la rodilla (y=0,537) hasta el suelo: 0,537 de
## recorrido. Centro a 0,25 por debajo de la rodilla y 0,56 de alto: el
## fondo queda en 0,007 (el suelo).
func _espinilla(nombre: StringName, lado: String) -> RagdollBone:
	var b := RagdollBone.new()
	b.bone_name = nombre
	b.shape = RagdollBone.Shape.CAPSULE
	b.radius = 0.07
	b.height = 0.56
	b.offset = 0.25
	b.mass = 2.88
	b.pd_gain = 3.0
	b.swing = 180.0
	b.twist = 90.0
	# La planta agarra: es lo que empuja al cuerpo hacia delante.
	b.friction = 0.5
	b.group = "leg"
	b.sin_colision_con = PackedStringArray(["shin." + lado, "shin." + ("R" if lado == "L" else "L"),
		"thigh." + lado, "thigh." + ("R" if lado == "L" else "L")])
	return b


func _forma(b: RagdollBone) -> String:
	match b.shape:
		RagdollBone.Shape.BOX:
			return "caja"
		RagdollBone.Shape.CAPSULE:
			return "capsula"
		_:
			return "esfera"
