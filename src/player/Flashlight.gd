extends SpotLight3D


var horizontal = 0.0:
	set(value):
		horizontal = clamp(value, -1, 1)
		$AnimationTree.set("parameters/horizontal/blend_position", horizontal)
