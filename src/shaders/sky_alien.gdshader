shader_type sky;
render_mode use_quarter_res_pass;

// CIelo del planeta — sistema CANONICO de clima y cielo.
//
// Extraido de `maps/misiones/c1/c1.tscn` (estaba embebido como sub_resource
// `Shader_tdx3t`), que a su vez viene de:
//   https://godotshaders.com/shader/stylized-sky-with-procedural-sun-and-moon/
// La referencia original usa LIGHT0 = sol y LIGHT1 = luna. AQUI ESO NO APLICA:
// este shader recibe los soles por uniforms que empuja `ambientacion.gd`, porque el
// orden de LIGHT0..LIGHT3 NO esta garantizado (Godot los rellena recorriendo
// `p_render_data->lights` en orden de registro, sin contrato de orden por
// arbol — ver servers/rendering/renderer_rd/environment/sky.cpp).
//
// Ver `src/weather/ambientacion.gd` para quien empuja cada uniform (:v

group_uniforms sky;
	uniform vec3 day_top_color : source_color = vec3( 0.1, 0.6, 1.0 );
	uniform vec3 day_bottom_color : source_color = vec3( 0.4, 0.8, 1.0 );
	uniform vec3 sunset_top_color : source_color = vec3( 0.7, 0.75, 1.0 );
	uniform vec3 sunset_bottom_color : source_color = vec3( 1.0, 0.5, 0.7 );
	uniform vec3 night_top_color : source_color = vec3( 0.02, 0.0, 0.04 );
	uniform vec3 night_bottom_color : source_color = vec3( 0.1, 0.0, 0.2 );

group_uniforms horizon;
	uniform vec3 horizon_color : source_color = vec3( 0.0, 0.7, 0.8 );
	uniform float horizon_blur : hint_range( 0.0, 1.0, 0.01 ) = 0.05;

group_uniforms sun_a;
	// Sol primario — el que SI proyecta sombra en el escenario.
	// `ambientacion.gd` empuja estos 4 desde la DirectionalLight3D "SolA".
	uniform vec3 sun_a_direction = vec3( 0.0, 1.0, 0.0 );
	uniform vec3 sun_a_color : source_color = vec3( 10.0, 8.0, 1.0 );
	uniform vec3 sun_a_sunset_color : source_color = vec3( 10.0, 0.0, 0.0 );
	uniform float sun_a_size : hint_range( 0.01, 1.0 ) = 0.2;
	uniform float sun_a_blur : hint_range( 0.01, 20.0 ) = 10.0;
	uniform float sun_a_energy : hint_range( 0.0, 4.0, 0.01 ) = 1.0;

group_uniforms sun_b;
	// Sol secundario de la binaria — SIN sombra (decision del General).
	// Tamañoo y color distintos al primario: es otra estrella, no un gemelo.
	uniform vec3 sun_b_direction = vec3( 0.0, 1.0, 0.0 );
	uniform vec3 sun_b_color : source_color = vec3( 4.0, 5.0, 9.0 );
	uniform vec3 sun_b_sunset_color : source_color = vec3( 9.0, 2.0, 1.0 );
	uniform float sun_b_size : hint_range( 0.001, 1.0 ) = 0.06;
	uniform float sun_b_blur : hint_range( 0.01, 20.0 ) = 8.0;
	uniform float sun_b_energy : hint_range( 0.0, 4.0, 0.01 ) = 0.6;
	// 0 = oculto. Los presets sin binaria (luna sola, cielo cerrado) lo apagan.
	uniform float sun_b_enabled : hint_range( 0.0, 1.0, 0.01 ) = 1.0;

group_uniforms moon;
	uniform vec3 moon_direction = vec3( 0.0, -1.0, 0.0 );
	uniform vec3 moon_color : source_color = vec3( 1.0, 0.95, 0.7 );
	uniform float moon_size : hint_range( 0.01, 1.0 ) = 0.06;
	uniform float moon_blur : hint_range( 0.01, 10.0 ) = 0.1;
	uniform float moon_enabled : hint_range( 0.0, 1.0, 0.01 ) = 1.0;

group_uniforms nubes;
	// ---- KELVIN-HELMHOLTZ — sistema UNICO de nubes ------------------------
	// Es la identidad atmosferica del planeta. ANTES convivian aqui DOS
	// sistemas: estas crestas y las nubes convencionales de la referencia
	// (`clouds_*`), y salian DOS estilos en el mismo cielo — la KH pintaba
	// donde llegaba y las de referencia asomaban donde no cubria, sobre todo
	// cerca del horizonte. Ya no queda mas que esto (:v
	//
	// La KH es una INTERFAZ: una capa a cierta altura donde el viento de dos
	// capas arrastra en sentidos opuestos y levanta crestas que se rizan sobre
	// si mismas, como olas de mar rompiendo. Por eso aqui NO se rellena todo el
	// cielo: se intersecta el rayo con un plano a `nubes_altura` y solo se
	// pinta cerca de esa capa.
	uniform vec3 nubes_borde : source_color = vec3( 0.8, 0.8, 0.98 );
	uniform vec3 nubes_cima : source_color = vec3( 1.0, 1.0, 1.00 );
	uniform vec3 nubes_media : source_color = vec3( 0.92, 0.92, 0.98 );
	uniform vec3 nubes_base : source_color = vec3( 0.83, 0.83, 0.94 );
	// Altura de la interfaz sobre el suelo, en metros.
	uniform float nubes_altura : hint_range( 50.0, 4000.0, 10.0 ) = 800.0;
	// Periodo entre crestas, en metros sobre el plano. A mayor, mas separadas.
	uniform float nubes_periodo : hint_range( 50.0, 3000.0, 10.0 ) = 600.0;
	// Fuerza del vortice que enrolla el ruido alrededor de cada cresta. Es lo
	// que separa "nubes con bultos" de "olas rompiendo": sin rollo, la cresta
	// queda un borde limpio de galleta. En 0 desaparece el rizo y queda ruido.
	uniform float nubes_rollo : hint_range( 0.0, 3.0, 0.01 ) = 1.15;
	// Radio de influencia del vortice, en metros. Muy pequeno = rizos finos y
	// artificiales; muy grande = se funde todo y no se distingue la fila.
	uniform float nubes_radio : hint_range( 20.0, 1500.0, 10.0 ) = 260.0;
	// Grosor de la capa. Las KH reales son finas: un borde grueso se lee como
	// niebla baja, no como inestabilidad.
	uniform float nubes_grosor : hint_range( 0.02, 1.0, 0.01 ) = 0.26;
	// Direccion del arrastre en el plano de la capa, en vueltas (0.0 = +X).
	uniform float nubes_direccion : hint_range( 0.0, 1.0, 0.001 ) = 0.13;
	// Deriva temporal de la capa entera: el campo viaja, las crestas no estan
	// quietas. En 0 el cielo se queda congelado.
	uniform float nubes_velocidad : hint_range( 0.0, 20.0, 0.01 ) = 2.0;
	// Umbral de densidad del ruido. A mayor, mas aire entre crestas.
	uniform float nubes_corte : hint_range( 0.0, 1.0, 0.01 ) = 0.3;
	// Suavizado de ese umbral. A mayor, borde esponjoso.
	uniform float nubes_difuminado : hint_range( 0.0, 2.0, 0.01 ) = 0.5;
	// Mas peso = nubes mas oscuras: es el control de tormenta.
	uniform float nubes_peso : hint_range( 0.0, 1.0, 0.01 ) = 0.0;
	// 0 = cielo limpio. 1 = KH a full.
	uniform float nubes_intensidad : hint_range( 0.0, 1.0, 0.01 ) = 1.0;

group_uniforms stars;
	// Stars should be at black background
	uniform sampler2D stars_texture : filter_linear_mipmap, hint_default_black;
	uniform float stars_speed : hint_range( 0.0, 20.0, 0.01 ) = 1.0;
	uniform float stars_scale : hint_range( 0.1, 3.0, 0.01 ) = 1.0;
	uniform float stars_opacity : hint_range( 0.1, 1.0, 0.01 ) = 1.0;

group_uniforms settings;
	uniform float overwritten_time = 0.0;

////////////////////////////////////////////////////////////////////////////////////////////////////
	// Function for clouds noises. You can replace using "gen_fractal_ping_pong" with a simple texture reading.
	// I was frustrated with the repeating texture that's why I included the algorithm in the code.
	// Source: https://github.com/Auburn/FastNoiseLite/tree/master
	const int PRIME_X = 501125321;
	const int PRIME_Y = 1136930381;
	float lerp( float a, float b, float t )
	{
		return a + t * ( b - a );
	}
	float cubic_lerp( float a, float b, float c, float d, float t )
	{
		float p = d - c - ( a - b );
		return t * t * t * p + t * t * ( a - b - p ) + t * ( c - a ) + b;
	}
	float ping_pong( float t )
	{
		t -= trunc( t * 0.5 ) * 2.0;
		return t < 1.0 ? t : 2.0 - t;
	}
	int hash( int seed, int x_primed, int y_primed )
	{
		return ( seed ^ x_primed ^ y_primed ) * 0x27d4eb2d;
	}
	float val_coord( int seed, int x_primed, int y_primed )
	{
	    int hash = hash( seed, x_primed, y_primed );
	    hash *= hash;
	    hash ^= hash << 19;
	    return float( hash ) * ( 1.0 / 2147483648.0 );
	}
	float single_value_cubic( int seed, float x, float y )
	{
	    int x1 = int( floor( x ));
	    int y1 = int( floor( y ));

	    float xs = x - float( x1 );
	    float ys = y - float( y1 );

	    x1 *= PRIME_X;
	    y1 *= PRIME_Y;
	    int x0 = x1 - PRIME_X;
	    int y0 = y1 - PRIME_Y;
	    int x2 = x1 + PRIME_X;
	    int y2 = y1 + PRIME_Y;
	    int x3 = x1 + ( PRIME_X << 1 );
	    int y3 = y1 + ( PRIME_Y << 1 );

	    return cubic_lerp(
	        cubic_lerp( val_coord( seed, x0, y0 ), val_coord( seed, x1, y0 ), val_coord( seed, x2, y0 ), val_coord( seed, x3, y0 ), xs ),
	        cubic_lerp( val_coord( seed, x0, y1 ), val_coord( seed, x1, y1 ), val_coord( seed, x2, y1 ), val_coord( seed, x3, y1 ), xs ),
	        cubic_lerp( val_coord( seed, x0, y2 ), val_coord( seed, x1, y2 ), val_coord( seed, x2, y2 ), val_coord( seed, x3, y2 ), xs ),
	        cubic_lerp( val_coord( seed, x0, y3 ), val_coord( seed, x1, y3 ), val_coord( seed, x2, y3 ), val_coord( seed, x3, y3 ), xs ),
	    ys ) * ( 1.0 / ( 1.5 * 1.5 ));
	}
	// Params can be change in the same way as in noise settings in Godot
	const float FRACTAL_BOUNDING = 1.0 / 1.75;
	const int OCTAVES = 5;
	const float PING_PONG_STRENGTH = 2.0;
	const float WEIGHTED_STRENGTH = 0.0;
	const float GAIN = 0.5;
	const float LACUNARITY = 2.0;
	float gen_fractal_ping_pong( vec2 pos, int seed, float frequency )
	{
		float x = pos.x * frequency;
		float y = pos.y * frequency;
	    float sum = 0.0;
		float amp = FRACTAL_BOUNDING;
	    for( int i = 0; i < OCTAVES; i++ )
	    {
	        float noise = ping_pong(( single_value_cubic( seed++, x, y ) + 1.0 ) * PING_PONG_STRENGTH );
	        sum += ( noise - 0.5 ) * 2.0 * amp;
	        amp *= lerp( 1.0, noise, WEIGHTED_STRENGTH );
	        x *= LACUNARITY;
	        y *= LACUNARITY;
	        amp *= GAIN;
	    }
	    return sum * 0.5 + 0.5;
	}
////////////////////////////////////////////////////////////////////////////////////////////////////

// Function needed to calculate the phase of the moon
// Source: https://kelvinvanhoorn.com/2022/03/17/skybox-tutorial-part-1/
float sphere_intersect( vec3 view_dir, vec3 sphere_pos, float radius )
{
    float b = dot( -sphere_pos, view_dir );
    float c = dot( -sphere_pos, -sphere_pos ) - pow( radius, 2 );
    float h = pow( b, 2 ) - c;
    return h < 0.0 ? -1.0 : -b - sqrt( h );
}

vec2 rot2( vec2 p, float ang )
{
    float s = sin( ang );
    float c = cos( ang );
    return vec2( p.x * c - p.y * s, p.x * s + p.y * c );
}

// Interseccion del rayo con el plano de la capa KH, a `nubes_altura` sobre el
// suelo. Devuelve UV en metros. Devuelve vec2( 1e9 ) si el rayo no alcanza la
// capa (mira por debajo o muy rasante), que es la condicion normal del horizonte.
vec2 nubes_plano_uv( vec3 eyedir )
{
    if ( eyedir.y < 0.001 ) {
        return vec2( 1e9 );
    }
    float t = nubes_altura / eyedir.y;
    return eyedir.xz * t;
}

// El vortice de Kelvin-Helmholtz.
//
// La inestabilidad KH genera VORTICES PERIODICOS a lo largo de la interfaz, no
// una onda suave. Cada celda de `nubes_periodo` recibe un giroat cuyo centro es la
// cresta. Muestrear el ruido en esa coordenada enrollada es lo que produce el
// rizo de "ola rompiendo": el material de arriba se arrastra sobre el de abajo.
//
// El peso decae con `nubes_radio` y con la distancia a la altura de la interfaz,
// de modo que el enrollado solo existe EN la capa y el resto del cielo queda
// intacto. `desfase` desplaza el vortice celda a celda para que la fila no sea
// una repeticion mecanica perfecta.
vec2 nubes_rizo( vec2 uv, vec2 dir, vec2 perp, float desfase )
{
    float a = dot( uv, dir );
    float b = dot( uv, perp );

    float celda = floor( a / nubes_periodo + desfase );
    float centro_a = ( celda + 0.5 - desfase ) * nubes_periodo;
    vec2 centro = dir * centro_a;

    vec2 rel = uv - centro;
    float r2 = dot( rel, rel ) / max( nubes_radio * nubes_radio, 1.0 );
    float peso = exp( -r2 );

    // El giro apunta "hacia delante" en la interfaz: riza hacia arriba y por
    // encima, igual que una ola que rompe en la direccion del viento.
    float ang = nubes_rollo * peso * sign( dot( rel, perp ) + 0.0001 );
    return centro + rot2( rel, ang );
}

// Silueta de la capa: 1 en el centro de la interfaz, 0 fuera. Se le suma el
// ruido de rompimiento para que el borde se quiebre en filamentos en vez de
// quedar una linea cortada a navaja.
float nubes_capa( vec3 eyedir, vec2 uv, float ruido )
{
    float y = eyedir.y;
    float pico = 1.0 - nubes_grosor * 0.5;
    float banda = 1.0 - smoothstep( pico - nubes_grosor, pico + nubes_grosor * 0.4, abs( y - pico ) );
    return clamp( banda + ( ruido - 0.5 ) * 0.55, 0.0, 1.0 );
}

void sky()
{
	float time = overwritten_time != 0.0 ? overwritten_time : TIME;

	// Dos soles: direccion de cada uno. Normalizar porque el script empuja
	// la direccion de la DirectionalLight3D, que puede venir escalada.
	vec3 sun_a_dir = normalize( sun_a_direction );
	vec3 sun_b_dir = normalize( sun_b_direction );
	vec3 moon_dir = normalize( moon_direction );

	//////////////////// SKY ///////////////////////////////////////////////////////////////////////
	float _eyedir_y = abs( sin( EYEDIR.y * PI * 0.5 ));

	// The day color will be our base color
	vec3 _sky_color = mix( day_bottom_color, day_top_color, _eyedir_y );
	_sky_color = mix( _sky_color, vec3( 0.0 ), clamp(( 0.7 - nubes_corte ) * nubes_peso, 0.0, 1.0 ));

	// Atardecer: los dos soles ponen el tono por separado y se SUMAN, con el
	// primario pesando mas. Si solo usaramos el A, cuando B este en el
	// horizonte su atardecer no se veria — y ese es justo el interes visual
	// de una binaria: dos caidas de sol desfasadas.
	float _sunset_a = clamp( 0.5 - abs( sun_a_dir.y ), 0.0, 0.5 ) * 2.0 * sun_a_energy;
	float _sunset_b = clamp( 0.5 - abs( sun_b_dir.y ), 0.0, 0.5 ) * 2.0 * sun_b_enabled * sun_b_energy;
	float _sunset_amount = clamp( max( _sunset_a, _sunset_b ), 0.0, 1.0 );

	// The sky should be more red around the west, on the opposite side you don't see it as much
	float _sunset_distance = clamp( 1.0 - pow( distance( EYEDIR, sun_a_dir ), 2 ), 0.0, 1.0 );
	vec3 _sky_sunset_color = mix( sunset_bottom_color, sunset_top_color, _eyedir_y + 0.5 );
	_sky_sunset_color = mix( _sky_sunset_color, sunset_bottom_color, _sunset_amount * _sunset_distance );
	_sky_color = mix( _sky_color, _sky_sunset_color, _sunset_amount );

	// Noche = los DOS soles por debajo del horizonte. Con un solo sol, un
	// `max` bastaria; con la binaria, si uno sigue arriba no es de noche.
	float _bajo_a = clamp( -sun_a_dir.y + 0.7, 0.0, 1.0 );
	float _bajo_b = clamp( -sun_b_dir.y + 0.7, 0.0, 1.0 );
	float _bajo_b_encendido = mix( 1.0, _bajo_b, sun_b_enabled );
	float _night_amount = min( _bajo_a, _bajo_b_encendido );
	vec3 _sky_night_color = mix( night_bottom_color, night_top_color, _eyedir_y );
	_sky_color = mix( _sky_color, _sky_night_color, _night_amount );

	// Final sky color
	COLOR = _sky_color;

	//////////////////// HORIZON ///////////////////////////////////////////////////////////////////
	float _horizon_amount = 0.0;
	if( EYEDIR.y < 0.0 )
	{
		_horizon_amount = clamp( abs( EYEDIR.y ) / horizon_blur, 0.0, 1.0 );
		// Mixing with the color of the night sky to make the horizon darker
		vec3 _horizon_color = mix( horizon_color, _sky_color, _night_amount * 0.9 );
		// And if ther are many dark clouds, we also make the horizon darker
		_horizon_color = mix( _horizon_color, vec3( 0.0 ), ( 1.0 - nubes_corte ) * nubes_peso * 0.7 );
		COLOR = mix( COLOR, _horizon_color, _horizon_amount );
	}

	//////////////////// MOON //////////////////////////////////////////////////////////////////////
	float _moon_amount = 0.0;
	if( moon_enabled > 0.5 )
	{
		// Bigger moon near the horizon
		float _moon_size = moon_size + cos( moon_dir.y * PI ) * moon_size * 0.25;
		float _moon_distance = distance( EYEDIR, moon_dir ) / _moon_size;
		// Finding moon disc and edge blur
		_moon_amount = clamp(( 1.0 - _moon_distance ) / moon_blur, 0.0, 1.0 );
		if( _moon_amount > 0.0 )
		{
			// Moon illumination depending on the position of the sun
			float _moon_intersect = sphere_intersect( EYEDIR, moon_dir, _moon_size );
			vec3 _moon_normal = normalize( moon_dir - EYEDIR * _moon_intersect );
			// Power on the result gives a better effect
			float _moon_n_dot_l = pow( clamp( dot( _moon_normal, -sun_a_dir ), 0.05, 1.0 ), 2 );
			// Hiding the moon behind the horizon
			_moon_amount *= 1.0 - _horizon_amount;
			COLOR = mix( COLOR, moon_color, _moon_n_dot_l * _moon_amount );
		}
	}

	//////////////////// SUN B — la estrella pequenna de la binaria ///////////
	// Se pinta ANTES que el A para que el primario quede por encima si se
	// solapan: en un eclipse mutuo, el grande tapa al chico, no al reves.
	float _sunb_distance = 0.0;
	if( sun_b_enabled > 0.5 )
	{
		_sunb_distance = distance( EYEDIR, sun_b_dir );
		float _sunb_size = sun_b_size + cos( sun_b_dir.y * PI ) * sun_b_size * 0.25;
		float _sunb_amount = clamp(( 1.0 - _sunb_distance / _sunb_size ) / sun_b_blur, 0.0, 1.0 );
		if( _sunb_amount > 0.0 )
		{
			float _sunb_sunset = 1.0;
			if( sun_b_dir.y > 0.0 )
				_sunb_sunset = clamp( cos( sun_b_dir.y * PI ), 0.0, 1.0 );
			vec3 _sunb_color = mix( sun_b_color, sun_b_sunset_color, _sunb_sunset );
			_sunb_amount = clamp( _sunb_amount * ( 1.0 - _moon_amount ), 0.0, 1.0 );
			_sunb_amount *= 1.0 - _horizon_amount;
			if( _sunb_color.r > 1.0 || _sunb_color.g > 1.0 || _sunb_color.b > 1.0 )
				_sunb_color *= _sunb_amount;
			COLOR = mix( COLOR, _sunb_color, _sunb_amount );
		}
	}

	//////////////////// SUN A — el primario //////////////////////////////////
	float _sun_distance = 0.0;
	{
		_sun_distance = distance( EYEDIR, sun_a_dir );
		// Bigger sun near the horizon
		float _sun_size = sun_a_size + cos( sun_a_dir.y * PI ) * sun_a_size * 0.25;
		// Finding sun disc and edge blur
		float _sun_amount = clamp(( 1.0 - _sun_distance / _sun_size ) / sun_a_blur, 0.0, 1.0 );
		if( _sun_amount > 0.0 )
		{
			// Changing color of the sun during sunset
			float _sunset_local = 1.0;
			if( sun_a_dir.y > 0.0 )
				_sunset_local = clamp( cos( sun_a_dir.y * PI ), 0.0, 1.0 );
			vec3 _sun_color = mix( sun_a_color, sun_a_sunset_color, _sunset_local );
			// Hiding the sun behind the moon
			_sun_amount = clamp( _sun_amount * ( 1.0 - _moon_amount ), 0.0, 1.0 );
			// Hiding the sun behind the horizon
			_sun_amount *= 1.0 - _horizon_amount;
			// Leveling the "glow" in color
			if( _sun_color.r > 1.0 || _sun_color.g > 1.0 || _sun_color.b > 1.0 )
				_sun_color *= _sun_amount;
			COLOR = mix( COLOR, _sun_color, _sun_amount );
		}
	}

	//////////////////// STARS /////////////////////////////////////////////////////////////////
	vec2 _sky_uv = EYEDIR.xz / sqrt( max( EYEDIR.y, 0.0001 ));
	if( EYEDIR.y > -0.01 && sun_a_dir.y < 0.0 && _night_amount > 0.05 )
	{
		// Stars UV rotation
		float _stars_speed_cos = cos( stars_speed * time * 0.005 );
		float _stars_speed_sin = sin( stars_speed * time * 0.005 );
		vec2 _stars_uv = vec2(
			_sky_uv.x * _stars_speed_cos - _sky_uv.y * _stars_speed_sin,
			_sky_uv.x * _stars_speed_sin + _sky_uv.y * _stars_speed_cos
		) * stars_scale;
		// Stars texture
		vec3 _stars_color = texture( stars_texture, _stars_uv ).rgb * -sun_a_dir.y;
		// Hiding stars behind the moon
		_stars_color *= 1.0 - _moon_amount;
		COLOR += _stars_color * stars_opacity * _night_amount;
	}

	//////////////////// NUBES — KELVIN-HELMHOLTZ ////////////////////////////////////////////////
	if( EYEDIR.y > 0.0 )
	{
		// ---- Capa de Kelvin-Helmholtz: el UNICO sistema de nubes ----------
		// Antes de aqui habia un segundo bloque con las nubes convencionales
		// de la referencia, pintado encima y recortado con `1 - _cobertura`.
		// Salian DOS estilos en el mismo cielo, asi que ya no existe (:v
		vec3 _nubes_color = _sky_color;
		float _cobertura = 0.0;
		if( nubes_intensidad > 0.001 )
		{
			vec2 _nubes_uv = nubes_plano_uv( EYEDIR );
			if( _nubes_uv.x < 1e8 )
			{
				// Direccion de arrastre en el plano. El perp es lo que marca
				// "hacia arriba" en la interfaz: contra el signo de ese eje se
				// decide si el rizo va a favor o en contra del viento.
				float _ang = nubes_direccion * TAU;
				vec2 _dir = vec2( cos( _ang ), sin( _ang ));
				vec2 _perp = vec2( -_dir.y, _dir.x );

				// Deriva temporal de la capa entera: el campo viaja, las
				// crestas no estan quietas.
				vec2 _arrastre = _dir * time * nubes_velocidad * 6.0;
				vec2 _base = _nubes_uv - _arrastre;

				// Desfase por banda perpendicular a la direccion de viento:
				// sin esto, toda la fila de crestas seria identica a lo ancho
				// del cielo y se leyeria como papel pintado.
				float _banda = dot( _base, _perp );
				float _desfase = sin( _banda * 0.0032 ) * 0.42
							   + sin( _banda * 0.0009 + 1.7 ) * 0.27;

				vec2 _uvs = nubes_rizo( _base, _dir, _perp, _desfase );
				vec2 _uvc = _base;

				// Dos escalas de ruido: la enrollada aporta el rizo, la sin
				// enrollar la masa de fondo. Sin la segunda, la capa queda
				// demasiado limpia y parecen espirales dibujadas.
				float _n_hi = gen_fractal_ping_pong( _uvs * 0.0016, 7, 1.0 );
				float _n_lo = gen_fractal_ping_pong( _uvc * 0.0009, 3, 1.0 );
				float _n_mix = _n_hi * 0.68 + _n_lo * 0.32;

				// Rompimiento: warp sobre la cresta para que se quiebre en
				// filamentos. Muy leve — mas de 0.4 y la KH deja de leerse.
				vec2 _warp = vec2(
					gen_fractal_ping_pong( _uvc * 0.0042, 11, 1.0 ) - 0.5,
					gen_fractal_ping_pong( _uvc * 0.0042 + 31.0, 13, 1.0 ) - 0.5
				);
				_n_mix = clamp( _n_mix + ( _warp.x + _warp.y ) * 0.24, 0.0, 1.0 );

				float _capa = nubes_capa( EYEDIR, _nubes_uv, _n_mix );
				// Corte duro estilo referencia: mismos uniforms que las nubes
				// normales, asi un preset sirve para las dos formaciones.
				float _dens = smoothstep( nubes_corte, nubes_corte + nubes_difuminado, _n_mix );
				_cobertura = clamp( _capa * _dens, 0.0, 1.0 );
				_cobertura *= smoothstep( 0.0, 0.09, EYEDIR.y );
				_cobertura *= nubes_intensidad;

				// ---- Sombreado con DOS soles --------------------------------
				// Es la firma de la binaria y funciona con cualquier formacion:
				// dos terminadores por nube, con distinto tinte. La "normal" de
				// la capa apunta al zenith y se inclina con el gradiente del
				// ruido, que es lo que da volumen a la cresta.
				vec3 _n3 = normalize( vec3(
					( _n_hi - gen_fractal_ping_pong( _uvs * 0.0016 + 5.0, 7, 1.0 )) * 2.4,
					1.0,
					( _n_lo - gen_fractal_ping_pong( _uvs * 0.0016 + 9.0, 7, 1.0 )) * 2.4
				));
				float _dota = clamp( dot( _n3, sun_a_dir ), 0.0, 1.0 );
				float _dotb = clamp( dot( _n3, sun_b_dir ), 0.0, 1.0 ) * sun_b_enabled;

				vec3 _base_col = mix( nubes_base, nubes_cima, _n_mix );
				vec3 _lit = _base_col * ( 0.30 + _dota * sun_a_energy );
				_lit += _base_col * clamp( sun_b_color * 0.34, 0.0, 0.7 ) * _dotb * sun_b_energy;

				// Contorno: la cresta mas iluminada por el primario, que es
				// donde el ojo agarra la forma de la ola.
				float _borde = smoothstep( 0.74, 0.99, _n_mix ) * _dota;
				_lit = mix( _lit, nubes_borde, _borde * 0.5 );

				// Noche y tormenta bajan todo, igual que en las nubes normales.
				_lit = mix( _lit, _sky_color, clamp( _night_amount, 0.0, 0.98 ));
				_lit = mix( _lit, vec3( 0.0 ), nubes_peso * 0.9 );
				_lit = mix( _lit, sunset_bottom_color, _sunset_amount * 0.55 );

				_nubes_color = _lit;
				COLOR = mix( COLOR, _nubes_color, _cobertura );
			}
		}
	}
}
