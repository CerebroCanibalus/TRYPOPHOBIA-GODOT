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
## La pelvis del CUERPO en el frame anterior: el esqueleto la sigue con
## este desplazamiento (ver `follow_pelvis`).
var _pelvis_anterior := Vector3.ZERO


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
			# TRAMPA (medida) — los huesos SIN cuerpo (dedos, falanges,
			# pezunas, la CAPA) NO pueden copiar la pose de la ANIMACION en
			# mundo: esa pose es la de la animacion, no la de la FISICA, y
			# la mano (que SI tiene cuerpo) va por otro lado -> los dedos
			# se quedan flotando, desconectados de la mano (medido: el
			# usuario veia las manos "sueltas" y estaticas).
			#
			# Lo correcto: la pose LOCAL del hueso (la que da la
			# animacion, relativa a su padre) compuesta sobre el PADRE YA
			# ESPEJADO (que esta en la pose fisica). Asi los dedos siguen
			# a la mano de verdad.
			#
			# Y OJO con la COMPOSICION (el bug que deformaba la malla):
			# la rotacion local del clip NO lleva el DESPLAZAMIENTO de
			# reposo del hueso (su origen respecto al padre). Si se compone
			# solo con la rotacion, el origen del hijo cae en el del padre
			# y la malla se APLASTA: la capa (una malla del modelo atada
			# a los huesos del torso) salia como una plancha roja
			# desplegada (medido en `tests/ragdoll/shots/`).
			#
			# La composicion correcta es:
			#   hijo = padre_fisico * (rotacion del clip, offset de REPOSO)
			var padre := physical_skel.get_bone_parent(i)
			if padre >= 0:
				# `get_bone_pose` devuelve la pose LOCAL (posicion +
				# rotacion) del hueso en la animacion.
				var local: Transform3D = animated_skel.get_bone_pose(ia)
				var pose_padre := physical_skel.get_bone_global_pose(padre)
				# El offset de reposo del hijo respecto al padre (el
				# `get_bone_rest` lo da en el marco del padre).
				var offset: Vector3 = physical_skel.get_bone_rest(i).origin
				physical_skel.set_bone_global_pose(i,
					pose_padre * Transform3D(local.basis, offset))
			else:
				var pose_mundo: Transform3D = animated_skel.global_transform \
					* animated_skel.get_bone_global_pose(ia)
				physical_skel.set_bone_global_pose(i, inv * pose_mundo)


## Mantiene los esqueletos ENCIMA del cuerpo de la pelvis.
##
## OJO (medido 2026-11-04) — POR QUE "SIGUE EL DESPLAZAMIENTO" Y NO
## "CORRIGE EL ERROR":
## Lo que se movia antes era un CORRECTOR (`pos += (local - pelvis_offset)`),
## o sea, el esqueleto se colocaba sobre la pelvis del cuerpo. Y como el
## objetivo del servo se calculaba con la posicion del esqueleto maestro,
## eso era un LAZO con un tick de retraso: el servo llevaba el cuerpo al
## objetivo, el corrector movia el maestro, el objetivo se movia... y el
## resultado era una OSCILACION DE PERIODO 2 (medido: la pelvis subia a
## 2,41 m y volvia a 0,30 m; el personaje "se movia horripilantemente").
##
## Ahora el esqueleto SIGUE al cuerpo (se le aplica el MISMO
## desplazamiento), no se coloca sobre el: no hay realimentacion y el
## objetivo del servo (que es la pose del clip en el mundo) se mantiene
## absoluto.
func follow_pelvis(physical_skel: Skeleton3D, animated_skel: Skeleton3D,
		pelvis_body: PhysicalBone3D) -> void:
	if pelvis_body == null:
		return
	var pelvis := RagdollMotor.body_transform(pelvis_body).origin
	if _pelvis_anterior == Vector3.ZERO:
		# El primer frame: solo se memoriza la posicion.
		_pelvis_anterior = pelvis
		return
	var d := pelvis - _pelvis_anterior
	_pelvis_anterior = pelvis
	if d.length_squared() < 1e-12:
		return
	if physical_skel != null:
		# OJO (medido 2026-11-05) — NO mover el esqueleto fisico.
		#
		# `physical_skel.global_position += d` movia el esqueleto cada tick,
		# y los `PhysicalBone3D` son sus HIJOS: el motor re-colocaba los
		# cuerpos en la pose del hueso, con lo que TODA velocidad lineal se
		# anulaba. Medido: se comandaba -5.99 m/s a la pelvis (impulso) y la
		# velocidad real seguia en +0.76; el personaje solo se movia por el
		# teleport o por los pies empujando el suelo.
		#
		# La malla NO lo necesita: `set_bone_global_pose()` recibe la pose
		# RELATIVA AL ESQUELETO y ya se le pasa el desplazamiento dentro
		# (`inv * mundo`), asi que la malla se dibuja donde esta el cuerpo
		# aunque el esqueleto se quede en el origen.
		pass
	# EL MAESTRO (el esqueleto ANIMADO, el del clip) NO se mueve.
	#
	# OJO (medido 2026-11-04): si el maestro sigue al cuerpo, el CICLO DE
	# PASO se va con el cuerpo y el pie barre "con" el: nunca se planta,
	# el cuerpo no avanza (medido: 0,5 m/s con un objetivo de 1,7) y es
	# exactamente el "arrastre" de los "pasitos horribles".
	#
	# En la REFERENCIA el esqueleto animado es un nodo FIJO de la escena:
	# el clip se reproduce en el sitio y el pie barre en el MUNDO, se
	# planta por el rozamiento y el cuerpo pasa por encima. El esqueleto
	# FISICO (el de la malla) si que sigue al cuerpo, para que la malla
	# quede pegada al personaje.
