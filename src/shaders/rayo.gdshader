shader_type spatial;
// CINTA DEL RAYO.
//
// El rayo no es una linea: es una cinta de triangulos que genera
// `src/weather/relampago.gd` con ImmediateMesh, ancha de lado a lado para que
// se pueda desvanecer hacia los bordes. Esto es lo que la pinta.
//
// UV.x recorre la cinta de un lado al otro (0 y 1 en los cantos, 0.5 en el
// eje). UV.y no es longitudinal: lleva el PESO de la rama, asi una rama
// secundaria sale mas tenue que el tronco principal sin hacer una malla (:v
//
// `blend_add` porque un rayo no tapa lo que hay detras, lo APORTA. Con eso la
// profundidad no se escribe (`depth_draw_never`) pero si se LEE, de modo que
// un rayo detras de un pilar queda oculto y no se dibuja por encima.

render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

group_uniforms rayo;

uniform vec3 color : source_color = vec3( 0.85, 0.92, 1.0 );
// Energia del pulso. La empuja `relampago.gd` cada frame con la envoltura de
// la tormenta: en 0 la cinta es invisible de verdad (no solo transparente).
uniform float intensidad : hint_range( 0.0, 4.0, 0.01 ) = 0.0;
// Anchura del nucleo blanco respecto al total de la cinta. Pequeno = filo
// fino y electrico; grande = barra blanca sin relieve.
uniform float nucleo : hint_range( 0.0, 1.0, 0.01 ) = 0.3;
// Cuanto se enciende el entorno INMEDIATO alrededor del trazo. Es lo que
// evita que el rayo parezca un sticker pegado sobre la escena.
uniform float halo : hint_range( 0.0, 4.0, 0.01 ) = 1.6;
group_uniforms;

void fragment()
{
	float lado = abs( UV.x * 2.0 - 1.0 );
	float peso = UV.y;

	// Nucleo duro centrado + halo suave alrededor. El `pow` del halo es lo
	// que da la caida tipica de una descarga: blanca en el eje y azulada en
	// los cantos.
	float nucleo_a = 1.0 - smoothstep( nucleo * 0.5, nucleo, lado );
	float halo_a = pow( max( 1.0 - lado, 0.0 ), 2.5 );

	float a = ( nucleo_a + halo_a * halo * 0.25 ) * intensidad * peso;

	ALBEDO = color * ( 1.0 + nucleo_a * 2.0 );
	ALPHA = clamp( a, 0.0, 1.0 );
}
