extends Node
class_name PoseMirror
## COPIA las poses de los cuerpos fisicos al esqueleto VISIBLE (el que
## lleva la malla), para que lo que se ve sea la fisica y no la animacion.
##
## Hace dos cosas:
##
## 1. **Sigue a la pelvis.** Los esqueletos (fisico y animado) se
##    desplazan para que la pelvis (el cuerpo "cuerpo") quede en su sitio.
##    Sin esto los cuerpos caen al suelo pero los esqueletos se quedan en
##    la raiz de la escena: la malla se dibuja un metro mas abajo y el
##    personaje parece enterrado (medido: el pie estaba en y=0,07 y el
##    esqueleto lo ponia en y=-1,03).
##
## 2. **Vuelca las poses.** Los huesos CON cuerpo copian la transform del
##    cuerpo (leida del SERVIDOR de fisica: el nodo `PhysicalBone3D` no se
##    actualiza en este motor) y los huesos SIN cuerpo (dedos, falanges)
##    copian la pose de la ANIMACION apoyados en su padre: si no, los
##    dedos se quedan en la pose de reposo (T) con la mano animada.

## Posicion de la pelvis en el espacio del esqueleto (para el ajuste 1).
var pelvis_offset := Vector3.ZERO


## Captura el offset de la pelvis. Se hace UNA vez, con el esqueleto
## todavia en su sitio: si se capturase despues de moverlo, el offset
## saldria 0 y el ajuste se dispararia (medido: el esqueleto se iba a
## -1,4e7 en 5 frames).
func capture_offset(physical_skel: Skeleton3D, pelvis_body: PhysicalBone3D) -> void:
	if physical_skel == null or pelvis_body == null:
		return
	pelvis_offset = physical_skel.global_transform.affine_inverse() \
		* RagdollMotor.body_transform(pelvis_body).origin


## Espeja las poses. `animated_skel` puede ser null (entonces los huesos
## sin cuerpo se quedan en reposo).
func mirror(physical_skel: Skeleton3D, animated_skel: Skeleton3D,
		bones: Array[PhysicalBone3D], pelvis_body: PhysicalBone3D) -> void:
	if physical_skel == null:
		return
	follow_pelvis(physical_skel, animated_skel, pelvis_body)
	# `set_bone_global_pose()` espera un transform RELATIVO AL ESQUELETO
	# (es la misma convencion que `get_bone_global_pose`, ver
	# class_skeleton3d: "global pose below refers to the overall transform
	# of the bone with respect to skeleton"). El cuerpo viene en MUNDO
	# del servidor de fisica, asi que hay que convertirlo. Si se pasa en
	# mundo tal cual, el modelo visible queda ladeadado 180 grados (el
	# esqueleto fisico tiene un flip Y=180 frente al animado) y deformado.
	var inv := physical_skel.global_transform.affine_inverse()
	# Mapa id de hueso -> cuerpo fisico.
	var cuerpos := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			cuerpos[id] = b
	# Se recorren TODOS los huesos en orden (de la raiz a las puntas) para
	# que un hueso sin cuerpo pueda apoyarse en su padre ya espejado.
	#
	for i in physical_skel.get_bone_count():
		if cuerpos.has(i):
			var b: PhysicalBone3D = cuerpos[i]
			# OJO (medido) — el cuerpo NO esta en el origen del hueso: el
			# motor lo coloca en `esqueleto * pose * body_offset` (el
			# cuerpo va a MEDIA HUESO, ver `PhysicalBone3D::update_offset`).
			# Para volver a la pose hay que DESHACER ese offset, o la malla
			# se va media hueso por cada eslabon y sale deformada (medido:
			# la camara en 3a persona veia el interior del modelo).
			var boff: Transform3D = b.get("body_offset")
			physical_skel.set_bone_global_pose(i,
				inv * RagdollMotor.body_transform(b) * boff.affine_inverse())
		elif animated_skel != null:
			var ia := animated_skel.find_bone(physical_skel.get_bone_name(i))
			if ia < 0:
				continue
			var pose_mundo: Transform3D = animated_skel.global_transform \
				* animated_skel.get_bone_global_pose(ia)
			physical_skel.set_bone_global_pose(i, inv * pose_mundo)


## Mantiene los esqueletos ENCIMA del cuerpo de la pelvis.
func follow_pelvis(physical_skel: Skeleton3D, animated_skel: Skeleton3D,
		pelvis_body: PhysicalBone3D) -> void:
	if pelvis_body == null:
		return
	var pelvis := RagdollMotor.body_transform(pelvis_body).origin
	if physical_skel != null:
		var local := physical_skel.global_transform.affine_inverse() * pelvis
		# Mover el esqueleto en +D hace que la pelvis local baje en D, asi que
		# para dejar la pelvis en su sitio hay que moverlo en (local - offset).
		# (Con el signo al reves el ajuste se REFLEJA y diverge.)
		physical_skel.global_position += physical_skel.global_transform.basis \
			* (local - pelvis_offset)
	if animated_skel != null:
		var local2 := animated_skel.global_transform.affine_inverse() * pelvis
		animated_skel.global_position += animated_skel.global_transform.basis \
			* (local2 - pelvis_offset)
