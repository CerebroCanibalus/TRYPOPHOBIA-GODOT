// ============================================================================
//  OCEANO ESTILIZADO — maps/misiones/petrolera_c1
//  Godot 4.7 · Forward Plus
// ----------------------------------------------------------------------------
//  Linea base: "Absorption based stylized water" (godotshaders.com, CC0)
//              + "screen space refraction shader" (godotshaders.com, CC0).
//  `src/shaders/agua1.gdshader` es el original descargado y lo usa NADIE:
//  se conserva como referencia. No conectarlo.
//
//  ESTE MAPA NO TIENE FONDO MARINO. Es una refineria en mar abierto: bajo el
//  agua no hay geometria, solo el background del depth buffer. Eso cambia TODO
//  el modelo, y es la razon de que la primera version saliera blanca plana:
//
//    v1 hacia  water_depth = scene_pos.y - water_pos.y, y con el background la
//    escena sale en el plano lejano MUY por debajo del agua -> water_depth
//    negativo gigante -> `shore` saturado a 1 en el 100% de los pixeles -> la
//    espuma cubria el oceano entero. Ni profundidad, ni transparencia, ni
//    espuma "alrededor de los objetos" (todo era espuma).
//
//  v2 separa las tres magnitudes y a cada una le da el dato que le sirve:
//
//    ESPUMA      -> grosor de la columna de agua (distancia de camara a la
//                   geometria menos distancia de camara al agua). Vale ~0
//                   justo en la linea de flotacion: ahi va la espuma, y en
//                   mar abierto da enorme -> no hay espuma. CORRECTO.
//    ABSORCION   -> distancia de la camara al fragmento de agua, saturada a
//                   max_view_depth. Es una ESTILIZACION, no fisica: el agua
//                   se aclara hacia los pies del jugador y se ennegrece hacia
//                   el horizonte. Da la sensacion de profundidad sin necesitar
//                   un fondo que medir.
//    REFRACCION  -> solo se aplica donde hay grosor de agua > 0, o sea donde
//                   hay algo detras que distortionar. Valida ademas que lo
//                   sampled no este DELANTE del agua (si no, el agua se mete
//                   dentro de los cascos).
//
//  NIEBLA Y SOL: no estan aqui a proposito. Los pone el WorldEnvironment de
//  la escena (Environment + DirectionalLight3D), no el material. Este shader
//  es LIT: escribe ALBEDO/ROUGHNESS/SPECULAR y deja que la luz de la escena
//  la ilumine. La unica excepcion es `reflect_color`, que NO es niebla sino
//  el color del cielo reflejado en el agua, y lo inyecta ocean.gd.
//
//  NO escribe ALPHA a proposito: en cuanto un shader escribe ALPHA pasa al
//  pipeline transparente, y los materiales transparentes NO aparecen en
//  hint_screen_texture ni en hint_depth_texture. Escribiendo ALPHA se
//  apagarian la refraccion y la espuma. La "transparencia" se hace
//  absorbiendo el color de fondo, que es como se hace en el mar real.
//
//  PRESUPUESTO: 1 depth + 1 screen (refraccion) + 2 normal + 2 espuma +
//  1 mascara de petroleo = 7 muestras/pixxel, un pase, sin render targets.
// ============================================================================

shader_type spatial;

// shadows_disabled: el agua recibe la niebla y la luz del sol de la ESCENA
// (render_mode normal), pero no proyecta sombra. Una ola con la normal muy
// inclinada proyectandose sobre si misma produce Shadow acne en todo el
// horizonte. Si se quiere que la refineria proyecte sombra sobre el agua,
// hay que activar esto DESPUES y ver si el acne aparece.
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// ---------------------------------------------------------------------------
//  GLOBALS — solo los que YA existen en project.godot [shader_globals].
//  Un `global uniform` inexistente hace que el shader no parsee, y el error
//  sale en un popup del editor, no en la consola. :v
// ---------------------------------------------------------------------------
global uniform float wind_intensity;
global uniform vec3  wind_direction;

// ---------------------------------------------------------------------------
//  Marea y radar de sonido — uniforms normales, los escribe ocean.gd
// ---------------------------------------------------------------------------
group_uniforms marea;
uniform float tide_level = 0.0;
uniform vec3  ripple_center = vec3(0.0);
uniform float ripple_time = 0.0;
uniform float ripple_strength = 0.0;

// ---------------------------------------------------------------------------
//  OLAS
// ---------------------------------------------------------------------------
group_uniforms olas;
// Rango de distancia en el que las olas se atenuan hasta ser planas. La malla
// mide 1800 m; bajo la niebla de este mapa a 500 m ya no se ve nada, asi que la
// geometria de lejos es geometria desperdiciada.
uniform float wave_lod_near : hint_range(0.0, 600.0, 1.0) = 90.0;
uniform float wave_lod_far  : hint_range(1.0, 1200.0, 1.0) = 320.0;

// Ola 0 — el swell. Lento, largo, el que da la silueta.
uniform float swell_length : hint_range(0.5, 200.0, 0.1) = 34.0;
uniform float swell_height : hint_range(0.0, 4.0, 0.01)   = 0.70;
uniform float swell_speed  : hint_range(0.0, 20.0, 0.01)   = 2.2;
uniform float swell_chop   : hint_range(0.0, 1.5, 0.01)    = 0.60;

// Ola 1 — rizo medio.
uniform float ripple_length : hint_range(0.5, 80.0, 0.1)  = 12.0;
uniform float ripple_height : hint_range(0.0, 2.0, 0.01)   = 0.22;
uniform float ripple_speed  : hint_range(0.0, 20.0, 0.01)   = 3.0;
uniform float ripple_chop   : hint_range(0.0, 1.5, 0.01)    = 0.40;

// Ola 2 — rizo fino, el que hace la costra cuando mira de cerca.
uniform float chop_length : hint_range(0.5, 40.0, 0.1) = 4.5;
uniform float chop_height : hint_range(0.0, 1.0, 0.01)  = 0.06;
uniform float chop_speed  : hint_range(0.0, 20.0, 0.01)  = 3.8;
uniform float chop_chop   : hint_range(0.0, 1.5, 0.01)   = 0.0;

uniform float wave_spread : hint_range(0.0, 1.5, 0.01) = 0.7;

// ---------------------------------------------------------------------------
//  AGUA
// ---------------------------------------------------------------------------
group_uniforms agua;
// Color de la luz que se dispersa dentro del agua (no la que se ve al fondo).
// En mar profundo esto es TODO lo que se ve, asi que es el color del oceano.
uniform vec3  scatter_color : source_color = vec3(0.26, 0.085, 0.060);
// Cuanto se apaga ese color por metro de agua recorrida. Mas alto = mas
// turbio. Ojo con la escala: a 0.32 el agua era opaca a los 15 m y no se veia
// NADA a traves, que es justo lo que hacia la v1. A 0.045 se ve el 50% a
// 15 m, el 10% a 50 m, y es opaca a partir de unos 120 m.
uniform float scatter_density : hint_range(0.0, 0.5, 0.001) = 0.045;
// A partir de esta distancia el agua se considera infinita. Es lo que corta
// el degradado antes de que el horizonte se vuelva negro puro.
uniform float max_view_depth : hint_range(1.0, 400.0, 1.0) = 120.0;

// Color del cielo reflejado. Lo inyecta ocean.gd desde el Environment. NO es
// niebla: es lo que se ve en la superficie cuando la vista es rasante.
uniform vec3 reflect_color : source_color = vec3(0.42, 0.055, 0.058);
uniform float reflect_amount : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float reflect_power  : hint_range(0.5, 8.0, 0.01)  = 5.0;

// Superficie mojada, pero NO un espejo. Con roughness 0.10 el agua reflejaba
// el cielo entero y el mar se leia como una lamina de leche: habia que bajar
// el brillo para que se viera el degradado de profundidad por debajo.
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.25;

// Refraccion en espacio de pantalla. La del shader de mujtaba-io, validada
// contra el depth buffer para no meter el agua dentro de los cascos.
uniform float refraction_strength : hint_range(0.0, 0.05, 0.0005) = 0.010;

// ---------------------------------------------------------------------------
//  ESPUMA
// ---------------------------------------------------------------------------
group_uniforms espuma;
// Grosor de agua (en metros) por debajo del cual se considera que estamos
// tocando algo. Este es EL numero que decide donde aparece la espuma.
// OJO con la escala: a 0.45 m la banda daba 2 pixeles a distancia de juego y
// no se veia NADA alrededor de los pilotes. La espuma tiene que "morder" lo
// suficiente para que se lea a 20-40 m.
uniform float contact_width : hint_range(0.05, 4.0, 0.05) = 1.30;
// Dureza del borde: cuanto mayor, mas nitido el contacto con el objeto.
uniform float contact_sharpness : hint_range(0.5, 8.0, 0.01) = 1.4;
// Espuma en la cresta de las olas grandes. crest_height es el umbral: solo
// espuman las puntas ALTAS del swell, no toda la ola, que es lo que separa
// "agua con crestas" de "agua con leche".
uniform float crest_amount : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float crest_height : hint_range(0.0, 2.0, 0.01) = 0.50;
// Escala de la mascara de espuma. OJO, esta es en INVERSOS DE METRO y es el
// bug que mas costlyaba encontrar: a 0.09 la textura se repite cada 11 m, o
// sea que a dos metros de un pilote estas viendo UNA celda estirada sobre toda
// la pantalla. Sin textura visible, la espuma se leia como un lavado liso y
// ademas DESAPARECIA al acercarse, segun el valor local de esa celda. A 0.32
// el tile mide 3 m y las celdas quedan en medio metro: hay grumos a cualquier
// distancia. La salpicadura usa esta misma escala x5.3 (~10 cm de grano).
uniform float foam_scale : hint_range(0.02, 3.0, 0.005) = 0.32;
uniform float foam_speed : hint_range(0.0, 2.0, 0.01) = 0.25;
// Blanco de espuma, casi puro. Contra el agua naranja que deja este
// environment, un gris claro se leia sucio.
uniform vec3  foam_color : source_color = vec3(0.97, 0.97, 0.98);
// 0 = negro. 1 = sin oscurecer. Cuanto MENOS, mas oscura es la banda mojada
// que rodea a la espuma. En 1.0 la espuma blanca se pierde: no tiene contra
// contra que destacar.
uniform float wet_darkening : hint_range(0.0, 1.0, 0.01) = 0.38;
// 0 = espuma poca y blanda. 1 = poca y marcada. Sube el corte de la mascara:
// a 1.0 solo sobreviven las celdas mas altas, y sale a trozos.
uniform float foam_contrast : hint_range(0.0, 1.0, 0.01) = 0.55;

// ---------------------------------------------------------------------------
//  PETROLEO — manchas AISLADAS, no una capa sobre todo el mar
// ---------------------------------------------------------------------------
group_uniforms petroleo;
// Centro de la mancha y radio. ocean.gd lo pone en la refineria, porque el
// aceite se sale de las tuberias, no flota Uniformemente por el oceano.
// 90 m era demasiado: cubria todo el campo de vision y parecia un filtro, no
// manchas. 35 m deja charcos sueltos alrededor de la plataforma.
uniform vec2  oil_center = vec2(0.0, 0.0);
uniform float oil_radius : hint_range(1.0, 500.0, 1.0) = 22.0;
uniform float oil_amount : hint_range(0.0, 1.0, 0.01) = 0.80;
// Corte de la mascara. Este numero ES la diferencia entre "manchas" y "capa":
// a 0.62 casi todas las celdas pasaban y el petroleo era continuo. Con 0.80
// solo sobreviven las celdas altas, o sea charcos sueltos con agua limpia
// entre ellos.
uniform float oil_threshold : hint_range(0.0, 1.0, 0.01) = 0.86;
uniform float oil_softness : hint_range(0.001, 0.5, 0.001) = 0.06;
uniform float oil_scale : hint_range(0.001, 0.2, 0.001) = 0.012;
uniform float oil_drift : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float oil_thickness : hint_range(0.0, 4.0, 0.01) = 1.4;
uniform float oil_spread : hint_range(0.0, 20.0, 0.1) = 4.0;

// ---------------------------------------------------------------------------
//  CAUSTICAS — solo en agua somera. El mapa no tiene fondo, asi que casi nunca
//  se ven: se dejan por si se anade suelo bajo la plataforma.
// ---------------------------------------------------------------------------
group_uniforms causticas;
uniform float caustics_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

// ---------------------------------------------------------------------------
//  TEXTURAS
// ---------------------------------------------------------------------------
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(0.001, 1.0, 0.001) = 0.16;
uniform float normal_strength : hint_range(0.0, 3.0, 0.01) = 0.85;
uniform float normal_speed : hint_range(0.0, 2.0, 0.01) = 0.30;
uniform float normal_lod_fade : hint_range(1.0, 900.0, 1.0) = 260.0;

uniform sampler2D screenshot : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex  : hint_depth_texture,  filter_linear_mipmap, repeat_disable;

// 0 = off, 1 = grosor de agua, 2 = mascara de espuma (ver donde hay contacto).
uniform int debug_view = 0;

varying vec3 world_pos;

// ===========================================================================
//  OLAS — Gerber analiticas, resueltas POR PIXEL
// ===========================================================================
void add_wave(inout vec3 nrm, inout float height, inout vec2 push,
        vec2 p, vec2 dir, float amp, float len, float spd, float chop) {
    float k = TAU / max(len, 0.01);
    float w = k * spd;
    float th = dot(p, dir) * k + TIME * w;
    float s = sin(th);
    float c = cos(th);

    height += amp * s;
    push += dir * (chop * amp * c);

    // Normal analitica (GPU Gems 1, cap. 1, eq. 12). Sin productos cruzados.
    nrm.x -= dir.x * w * amp * c;
    nrm.z -= dir.y * w * amp * c;
    nrm.x -= chop * w * amp * dir.x * dir.x * s;
    nrm.z -= chop * w * amp * dir.x * dir.y * s;
    nrm.y -= chop * w * amp * s;
}

void solve_waves(vec2 p, float detail, out float height, out vec2 push, out vec3 nrm) {
    height = 0.0;
    push = vec2(0.0);
    nrm = vec3(0.0, 1.0, 0.0);

    // Guarda anti-NaN: wind_direction llega (0,0,0) si nadie escribe el
    // global, y normalize(vec3(0)) = 0/0 = NaN, que se come el pixel entero.
    float wd_len = length(wind_direction.xz);
    vec2 wd = wd_len > 1e-4 ? normalize(wind_direction).xz : vec2(0.0, 1.0);
    vec2 wperp = vec2(-wd.y, wd.x);

    float calm = 1.0 - clamp(wind_intensity, 0.0, 1.0) * 0.55;
    float spread = wave_spread * (0.35 + 0.65 * clamp(wind_intensity, 0.0, 1.0));

    add_wave(nrm, height, push, p, wd,
            swell_height * detail * calm, swell_length, swell_speed, swell_chop);

    float ang1 = spread * 0.9;
    vec2 d1 = normalize(wd * cos(ang1) + wperp * sin(ang1));
    add_wave(nrm, height, push, p, d1,
            ripple_height * detail * calm, ripple_length, ripple_speed, ripple_chop);

    float ang2 = -spread * 1.4;
    vec2 d2 = normalize(wd * cos(ang2) + wperp * sin(ang2));
    add_wave(nrm, height, push, p, d2,
            chop_height * detail * calm, chop_length, chop_speed, chop_chop);

    // ---- RADAR DE SONIDO -------------------------------------------------
    // El anillo nace en el punto del ruido y se inyecta en la MISMA solucion
    // de olas: no cuesta un draw call ni una textura mas.
    if (ripple_strength > 0.001) {
        vec2 rp = p - ripple_center.xz;
        float rr = length(rp);
        float radius = ripple_time * 7.0;
        float ring = sin((rr - radius) * 1.6) * exp(-rr * 0.10) * exp(-ripple_time * 0.55);
        float ring_mask = ring * ripple_strength;
        vec2 rdir = normalize(rp + vec2(1e-5));
        height += ring_mask * 0.16;
        push += rdir * ring_mask * 0.35;
        nrm.xz -= rdir * ring_mask * 1.6;
    }
}

// ===========================================================================
//  UTILIDADES
// ===========================================================================
// GOTA: las matrices inversas se PASAN COMO ARGUMENTO. Dentro del cuerpo de
// una funcion el parser no resuelve INV_PROJECTION_MATRIX y aborta con
// "Unknown identifier"; en el cuerpo de vertex()/fragment() si funciona. Es lo
// que hacen outline.gdshader y agua1.gdshader, y no es casualidad. :v
vec3 world_from_depth(vec2 uv, float d, mat4 inv_proj, mat4 inv_view) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
    vec4 view_pos = inv_proj * ndc;
    view_pos.xyz /= view_pos.w;
    return (inv_view * view_pos).xyz;
}

float cam_distance(vec3 world_p, vec3 cam_pos) {
    return distance(world_p, cam_pos);
}

bool in_bounds(vec2 uv) {
    vec2 b = abs(floor(uv));
    return b.x + b.y < 0.1;
}

vec2 safe_wind_dir() {
    float l = length(wind_direction.xz);
    return l > 1e-4 ? normalize(wind_direction).xz : vec2(0.0, 1.0);
}

// ===========================================================================
//  VERTEX
// ===========================================================================
// Solo silueta. El detalle lo pone la solucion analitica del fragment, que no
// depende de la densidad de malla. El LOD apaga el desplazamiento lejos.
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
    float dist = cam_distance(world_pos, cam_pos);
    float lod = 1.0 - smoothstep(wave_lod_near, wave_lod_far, dist);

    float height; vec2 push; vec3 nrm;
    solve_waves(world_pos.xz, lod, height, push, nrm);

    VERTEX.x += push.x;
    VERTEX.z += push.y;
    VERTEX.y += height + tide_level;
    world_pos.y += height + tide_level;
}

// ===========================================================================
//  FRAGMENT
// ===========================================================================
void fragment() {
    vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
    float dist = cam_distance(world_pos, cam_pos);

    // ---- NORMAL -----------------------------------------------------------
    // El detalle se apaga con la distancia: a 260 m la niebla ya no deja ver
    // una normal map, y sin esto el oceano lejano hierve de ruido que se lee
    // como "mal renderizado".
    float detail = 1.0 - smoothstep(wave_lod_near, wave_lod_far, dist);
    float nrm_fade = 1.0 - smoothstep(normal_lod_fade * 0.4, normal_lod_fade, dist);

    float height; vec2 push; vec3 n_world;
    solve_waves(world_pos.xz, detail, height, push, n_world);
    n_world = normalize(n_world);

    // Normal map proyectada en el mundo. El agua es un plano horizontal, asi
    // que T = X y B = Z del mundo. Evita depender de TANGENT/BITANGENT (que en
    // Godot 4 llegan ya rotados) y es exacto sobre una superficie plana.
    vec2 flow = safe_wind_dir() * -normal_speed * TIME;
    vec2 uv1 = world_pos.xz * normal_scale + flow;
    vec2 uv2 = world_pos.xz * normal_scale * 0.43 - flow * 0.7 + vec2(0.37, 0.71);
    vec3 nm = mix(textureLod(normal_map, uv1, 0.0).xyz,
                  textureLod(normal_map, uv2, 0.0).xyz, 0.5) * 2.0 - 1.0;
    nm.xy *= normal_strength * nrm_fade;
    n_world = normalize(vec3(n_world.x + nm.x, n_world.y, n_world.z + nm.y));

    vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
    vec3 v_view = normalize(VIEW);   // de la camara al fragmento

    // ---- GROSOR DE LA COLUMNA DE AGUA --------------------------------------
    // Distancia de camara a la geometria que hay detras, menos distancia de
    // camara al agua. ~0 en la linea de flotacion de un pilote; en mar abierto
    // no hay nada detras y por eso se devuelve INFINITO.
    //
    // LA PUERTA `has_surface` es lo que hace que esto funcione. Sin ella, en
    // mar abierto el depth buffer vale 1.0 (plano lejano) y la reconstruccion
    // devuelve una distancia que OSCILA CON LA OLA: el valor entra y sale del
    // rango de contacto y aparecen bandas de espuma periodicas por todo el
    // horizonte. Con la puerta, "no hay nada detras" significa grosor
    // infinito, contacto 0, y la espuma solo puede aparecer donde hay un
    // pilote, un casco o la plataforma de verdad.
    float raw_d = texture(depth_tex, SCREEN_UV).x;
    bool has_surface = raw_d < 0.9999;
    float thickness = 1e6;
    // Separacion VERTICAL en metros entre la superficie del agua y la geometria
    // que hay detras. Es lo que decide la espuma de contacto, y se mide en Y a
    // proposito: restar dos distancias a la camara es restar dos numeros
    // grandes, y cuando te acercas al objeto la diferencia se come su propia
    // precision (y con el oleaje moviendo la superficie, la espuma parpadea y
    // acaba desapareciendo al acercarse). Comparar alturas no tiene ese
    // problema: el mismo pilote da la misma espuma a 2 m y a 40 m.
    float water_gap = 1e6;
    if (has_surface) {
        vec3 scene_pos = world_from_depth(SCREEN_UV, raw_d,
                INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
        thickness = max(cam_distance(scene_pos, cam_pos) - dist, 0.0);
        water_gap = world_pos.y - scene_pos.y;
    }

    // ---- REFRACCION --------------------------------------------------------
    // Solo donde hay geometria real detras. En mar abierto no hay nada que
    // refractar: la pantalla es solo cielo.
    vec2 refr_uv = SCREEN_UV + n_view.xy * refraction_strength * clamp(thickness, 0.0, 6.0);
    bool valid = has_surface && thickness > 0.02 && in_bounds(refr_uv);
    if (valid) {
        // Si lo sampled esta MAS CERCA que el agua, es geometria en primer
        // plano: refraccion invalida (el agua se meteria dentro del casco).
        vec3 other = world_from_depth(refr_uv, texture(depth_tex, refr_uv).x,
                INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
        vec3 water_vz = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
        vec3 other_vz = (VIEW_MATRIX * vec4(other, 1.0)).xyz;
        valid = other_vz.z <= water_vz.z + 0.05;
    }
    vec3 below = textureLod(screenshot, valid ? refr_uv : SCREEN_UV, 0.0).rgb;

    // ---- ABSORCION ---------------------------------------------------------
    // Camino optico = distancia a la camara, saturado. Estilizacion, no fisica:
    // a los pies del jugador el agua es clara, hacia el horizonte es un muro.
    // Asi se ve la profundidad sin necesitar un fondo que medir.
    float path = min(dist, max_view_depth);
    // Una pendiente muy inclinada atraviesa mas medio. Sin esto, las paredes de
    // las olas se ven tan claras como el fondo de un charco.
    path *= 1.0 + clamp(1.0 - n_world.y, 0.0, 0.5) * 3.0;

    float clarity = exp(-scatter_density * path);
    // Lo que se ve es el color de atras atenuado por lo que sobrevive al viaje
    // por el agua, mas la luz que el agua dispersa por su cuenta.
    vec3 water_col = mix(scatter_color, below, clarity);

    // ---- REFLEJO (Fresnel) -------------------------------------------------
    // Aqui NO hay SSR. El cielo de este mapa es un color plano
    // (background_mode = clear), y el SSR de agua1 son 100 iteraciones x 2
    // muestras para reflejar un color liso. Fresnel contra ese color da el
    // mismo resultado por 1/200 del coste. El reflejo solo importa en vista
    // rasante, que es donde el Fresnel pesa.
    float ndv = clamp(dot(n_view, v_view), 0.0, 1.0);
    float fres = pow(1.0 - ndv, reflect_power) * reflect_amount;
    water_col = mix(water_col, reflect_color, fres);

    // ---- ESPUMA ------------------------------------------------------------
    // Dos tramos, y la diferencia entre ellos es LA respuesta al "no veo la
    // espuma en absoluto":
    //
    //   CORE — el tramo pegado al objeto es BLANCO SOLIDO, sin textura. En una
    //   foto de rompiente el blanco que toca la roca es opaco; la textura solo
    //   talla el borde. Mi version anterior hacia `band * textura` en todo el
    //   ancho, asi que la espuma dependia de la celda que le tocara al objeto:
    //   si salia baja, la espuma no existia y el General no veia NUNCA nada.
    //
    //   EDGE — de ahi hacia fuera, la textura decide entre espuma y agua. Ahi
    //   es donde van los trozos y la salpicadura.
    float contact = 1.0 - smoothstep(0.0, contact_width, water_gap);
    contact = pow(clamp(contact, 0.0, 1.0), contact_sharpness);
    float crest = smoothstep(crest_height * 0.30, crest_height, height) * crest_amount;
    float core = 1.0 - smoothstep(contact_width * 0.35, contact_width * 0.55, water_gap);
    float edge = 1.0 - smoothstep(contact_width * 0.50, contact_width, water_gap);

    // 2) TROZOS — la mascara celular con umbral DURO convierte las bandas en
    //    masas irregulares de espuma CON AGUJEROS. Es lo que la separa de un
    //    lavado de pintura: un smoothstep ancho da gris plano, uno estrecho
    //    da trozos. foam_contrast sube el corte y se come espuma.
    // 3) SALPICADURA — segunda mascara, mas fina, que solo vive en el BORDE
    //    de la banda. Son los granitos que se despegan al romper. Sin ellos
    //    el borde queda cortado a navaja y se ve falso.
    vec2 fflow = safe_wind_dir() * -foam_speed * TIME;
    float coarse = textureLod(foam_noise, world_pos.xz * foam_scale + fflow, 0.0).r;
    float fine = textureLod(foam_noise, world_pos.xz * foam_scale * 5.3 - fflow * 1.7, 0.0).r;

    // El umbral lo marca SOLO la textura, y solo se aplica al tramo EDGE. El
    // CORE de arriba entra con peso 1 y la textura no lo toca.
    float cut = mix(0.52, 0.34, clamp(foam_contrast, 0.0, 1.0));
    float lump = smoothstep(cut, cut + 0.15, coarse);
    float spray = smoothstep(cut + 0.06, cut + 0.30, fine);
    float texture_gate = max(lump, spray * 0.75);

    // CORE solido + EDGE texturado + cresta de la ola.
    float foam = clamp(core + edge * texture_gate + crest, 0.0, 1.0) * nrm_fade;

    // BANDA MOJADA — el agua oscura que rodea a la espuma. Va FUERA de
    // contact_width, no solapada: si arranca antes (como en la v anterior, en
    // contact_width * 0.30) su pico caia donde contact ya habia llegado a 0,
    // y las dos rampas quedaban 90 grados desfasadas — la espuma en un lado,
    // el oscuro en el otro, y encima no se veia el blanco.
    float rim = smoothstep(contact_width, contact_width * 1.5, water_gap)
              * (1.0 - smoothstep(contact_width * 1.5, contact_width * 3.0, water_gap));
    water_col *= mix(1.0, wet_darkening, rim);

    // ---- PETROLEO — manchas aisladas ---------------------------------------
    // La v1 aplicaba la pelicula a TODO el mar y parecia un filtro. Aqui la
    // mascara tiene que superar un umbral para que exista petroleo, y ademas
    // se concentra alrededor de la refineria, que es de donde se sale.
    float oil_fall = 1.0 - smoothstep(oil_radius * 0.35, oil_radius,
            length(world_pos.xz - oil_center));
    // Muestreo a escala MUY baja: las celdas del mapa salen enormes, del orden
    // de las manchas, no del ruido de la espuma.
    vec2 ouv = world_pos.xz * oil_scale + safe_wind_dir() * -oil_drift * TIME;
    // INVERTIDO, y no es un capricho. En agua1.png (Voronoi) lo BRILLANTE son
    // las PAREDES de las celdas. Si se umbraliza lo brillante sale una red
    // conectada de lineas, y el petroleo parece una grieta de lava. Para charcos
    // AISLADOS hay que quedarse con los interiores de celda, que son los
    // oscuros: 1.0 - valor.
    float ocell = 1.0 - textureLod(foam_noise, ouv, 0.0).r;
    // Dos celdas a distinta escala: la grande reparte, la pequena rompe el
    // borde de la mancha para que no salga un circulo.
    float odetail = 1.0 - textureLod(foam_noise, ouv * 3.7 + vec2(0.19, 0.63), 0.0).r;
    float patch = ocell * 0.75 + odetail * 0.25;
    // EL CORTE: sin esto el petroleo es una capa continua, no manchas.
    float oil_mask = smoothstep(oil_threshold, oil_threshold + oil_softness, patch);
    oil_mask *= oil_fall;

    if (oil_mask > 0.001) {
        // Interferencia de capa fina por paleta coseno: el mismo truco del
        // arcoiris de Playa, 3 cosenos. Solo se nota donde el agua esta quieta
        // y la vista es rasante, que es donde el aceite de verdad se ve.
        // `oil_thickness` es el grosor de la pelicula en CICLOS de
        // interferencia: a 1.0 sale un solo arcoiris, a 3.0 salen tres y el
        // charco se ve mas chapoteo. Por eso multiplica la paleta en vez de
        // sumarse al final: subirlo NO satura el color, agrega franjas.
        float film = 0.5 + 0.5 * (sin(ouv.x * 9.0 + TIME * 0.19) * 0.5
                                + sin(ouv.y * 12.0 - TIME * 0.15) * 0.5);
        // Los tres canales van a 1.0 / 0.55 / 0.30, NO a 1.0 / 0.82 / 0.68.
        // Con factores comprimidos los tres cosenos van casi a la par y la
        // paleta sale OLIVA, no arcoiris. Separandolos se recorre el ciclo
        // entero y salen los azules, morados y dorados del aceite de verdad.
        vec3 sheen = 0.5 + 0.5 * cos(TAU * (film * oil_thickness * vec3(1.0, 0.55, 0.30))
                                + oil_spread * fres);
        // El radar de sonido revienta la pelicula: el anillo se invierte.
        sheen = mix(sheen, sheen.gbr, clamp(ripple_strength * exp(-ripple_time * 0.55), 0.0, 1.0));
        // El petroleo REAL es una pelicula OSCURA con iridiscencia sutil, no
        // una luz de neon. Por eso se MEZCLA sobre el agua en vez de
        // sustituirla, y por eso oil_amount esta por debajo de 1: a 0.80 el
        // charco se comia el color del agua y brillaba como magma.
        water_col = mix(water_col, mix(water_col, sheen, 0.65), oil_amount * oil_mask);
    }

    // ---- CAUSTICAS ---------------------------------------------------------
    if (caustics_strength > 0.001 && thickness > 0.05 && thickness < 6.0) {
        float f = 1.0 - smoothstep(0.0, 6.0, thickness);
        water_col += vec3(caustics_strength) * f * clarity;
    }

    // ---- ESPUMA (pintado) --------------------------------------------------
    // ULTIMO DE TODO, por encima del petroleo: el aceite es una pelicula sobre
    // el agua y la espuma flota encima. Al revés, el charco se comia el collar
    // blanco de los pilotes. REFLEJA luz, no la absorbe: sube el brillo, no
    // oscurece.
    water_col = mix(water_col, foam_color, foam);

    if (debug_view == 1) {
        ALBEDO = vec3(thickness / 4.0, contact, 0.0);
    } else if (debug_view == 2) {
        ALBEDO = vec3(foam);
    } else {
        ALBEDO = clamp(water_col, vec3(0.0), vec3(1.0));
    }

    // Superficie mojada: poca rugosidad y reflejo especular alto. El sol lo
    // pone la DirectionalLight3D de la escena, no este shader.
    ROUGHNESS = mix(roughness, 0.75, foam);
    SPECULAR = mix(specular, 0.15, foam);
}
