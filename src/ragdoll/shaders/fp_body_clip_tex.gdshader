shader_type spatial;


// Recorte de 1a persona que CONSERVA el material original del personaje.
//
// El shader original (fp_body_clip.gdshader) pinta de color plano y solo
// sirve para el rig viejo (una sola malla sin texturas). Este reproduce el
// StandardMaterial3D del GLB: color, rugosidad, metalic, textura de albedo,
// vertex colors, alpha y emision.
//
// OJO: los ShaderMaterial guardados sin sus shader_parameter/* salen NEGROS
// (el .tres no guarda esas claves), asi que este material se arma SIEMPRE
// en codigo (ragdoll_character.gd::_make_fp_clip_material).
uniform float clip_radius : hint_range(0.0, 2.0) = 0.0;
uniform float clip_forward_scale : hint_range(0.1, 4.0) = 2.0;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool alpha_enabled = false;
uniform bool alpha_scissor_enabled = false;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
uniform bool emission_enabled = false;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 1.0;

void fragment() {
	if (clip_radius > 0.0) {
		// En Godot 4, VERTEX dentro de fragment() esta en ESPACIO DE VISTA
		// (la camara en el origen mirando hacia -Z): la distancia a la camara
		// es su longitud. El eje Z se divide para estirar el recorte hacia
		// delante y tragarse el hocico sin comerse los brazos extendidos.
		vec3 v = VERTEX;
		float d = length(vec3(v.xy, v.z / clip_forward_scale));
		if (d < clip_radius) {
			discard;
		}
	}
	vec4 alb = albedo_color;
	if (use_albedo_texture) {
		alb *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		alb *= COLOR;
	}
	ALBEDO = alb.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (emission_enabled) {
		EMISSION = emission_color.rgb * emission_energy;
	}
	if (alpha_scissor_enabled) {
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	if (alpha_enabled) {
		ALPHA = alb.a;
	}
}
