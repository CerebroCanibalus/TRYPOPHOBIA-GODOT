shader_type spatial;
// El material original del personaje usa cull_mode = DESACTIVADO (2): hay que
// reproducirlo o las caras internas del craneo/hocico se verian al meter la
// camara dentro de la cabeza.
render_mode cull_disabled, depth_draw_opaque;

// Radio (m) alrededor de la CAMARA dentro del cual el cuerpo se descarta.
// 0.0 = desactivado (3a persona / debug).
uniform float clip_radius : hint_range(0.0, 2.0) = 0.0;
// Elipsoide de recorte. 1.0 = esfera. >1.0 estira el radio a lo largo del eje
// de vision: se traga el hocico (que sobresale hacia delante) sin comerse los
// brazos cuando el jugador los estira hacia un objeto.
uniform float clip_forward_scale : hint_range(0.1, 4.0) = 2.0;

uniform vec4 albedo_color : source_color = vec4(0.906332, 0.906332, 0.906332, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	if (clip_radius > 0.0) {
		// En Godot 4, VERTEX dentro de fragment() ya esta en VIEW SPACE con la
		// camara en el origen mirando hacia -Z: la distancia a la camara es
		// simplemente su longitud.
		vec3 v = VERTEX;
		float d = length(vec3(v.xy, v.z / clip_forward_scale));
		if (d < clip_radius) {
			discard;
		}
	}
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness;
}
