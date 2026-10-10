extends Resource
class_name AtmosferaPreset
## Preset de ATMOSFERA de UN nivel: cielo, soles, nubes, niebla, lluvia.
##
## Es el corazon del sistema canonico de clima: se preconfigura al cargar el
## nivel y NO cambia en runtime (no hay ciclo dia/noche ni transiciones). Lo
## unico que se anima es cosmético — las nubes derivan con `TIME`.
##
## Lo aplica `src/weather/atmosfera.gd` en `_ready()`. Un nivel = un `.tres`
## de este tipo. Ver `src/weather/atmosfera.tscn`, que es el nodo drag&drop,
## y dentro el suyo `WorldEnvironment`, que es donde corre todo el cielo (:v
##
## En runtime el cielo se dibuja con `src/shaders/sky_alien.gdshader`.

## ---------------------------------------------------------------------------
## Cielo — paleta. Seis colores porque el shader mezcla por altura y por
## condicion (dia / atardecer / noche), no por interpolacion lineal.
## ---------------------------------------------------------------------------
@export_group("Cielo")
## Cenit de dia.
@export var day_top_color := Color(0.02327777, 0.1227716, 0.19675368)
## Justo sobre el horizonte de dia. Es lo que mas se ve y lo que el agua
## refleja, por eso viene de `sky_horizon_color` del mapa original.
@export var day_bottom_color := Color(0.11191336, 0.41704106, 0.56165653)
## Cenit de atardecer.
@export var sunset_top_color := Color(0.55, 0.50, 0.68)
## Horizonte de atardecer — atado a la niebla volumetrica roja del mapa.
@export var sunset_bottom_color := Color(0.90, 0.42, 0.30)
## Cenit de noche. El planeta conserva su teal incluso de noche.
@export var night_top_color := Color(0.01, 0.02, 0.05)
## Horizonte de noche.
@export var night_bottom_color := Color(0.06, 0.10, 0.14)

## ---------------------------------------------------------------------------
## Horizonte — la franja POR DEBAJO de EYEDIR.y = 0.
## ---------------------------------------------------------------------------
@export_group("Horizonte")
## Color bajo el horizonte. En petrolera es el rojo de la Niebla Roja.
@export var horizon_color := Color(0.85511327, 0.0, 0.08077686)
## Anchura de la caida hacia el horizonte. Pequeno = linea dura.
@export_range(0.0, 1.0, 0.01) var horizon_blur := 0.05

## ---------------------------------------------------------------------------
## Sol A — el primario.
##
## LA DIRECCION NO SE FIIJ AQUI, salvo como RESPALDO. La fuente de verdad es
## la DirectionalLight3D que ya trae el mapa (en petrolera, `Sol`): `atmosfera.gd`
## lee `basis.z` de la primera que encuentre. Asi el disco que se dibuja en el
## cielo SIEMPRE esta donde sale la luz, y no hace falta que nadie sincronice
## dos cosas a mano. La luz es de la escena, el clima solo la pinta.
##
## Si el mapa no tiene ninguna luz direccional, se usa este valor.
## ---------------------------------------------------------------------------
@export_group("Sol A")
@export var sol_a_direccion := Vector3(0.679476, 0.497571, 0.539199)
## Color del DISCO en el cielo, en HDR (valores > 1, como la referencia).
## NO es el color de la luz: esa ilumina el mundo y vive en la DirectionalLight3D.
@export var sol_a_color := Color(5.5, 8.0, 7.5)
## Tinte del disco al caer al horizonte.
@export var sol_a_sunset_color := Color(9.0, 2.2, 1.0)
## Radio angular. La referencia usa 0.2 por defecto; la Tierra real, 0.0087.
@export_range(0.01, 1.0, 0.001) var sol_a_size := 0.16
@export_range(0.01, 20.0, 0.1) var sol_a_blur := 10.0
## Peso del primario en el atardecer y en el sombreado de las nubes.
@export_range(0.0, 4.0, 0.01) var sol_a_energy := 1.0

## ---------------------------------------------------------------------------
## Sol B — la estrella pequenna de la binaria.
##
## NO ILUMINA la escena: el mapa tiene UN SOLO DirectionalLight3D y es el suyo,
## el del mapa. SolB es puro dibujo — su luz en el mundo llega por el IBL,
## porque el disco entra en el radiance cubemap del sky shader.
##
## Su direccion SI va aqui, porque no existe ninguna luz de la que leerla:
## es una estrella que no ilumina, solo existe en el cielo (:v
## ---------------------------------------------------------------------------
@export_group("Sol B")
## Vector unitario que apunta HACIA la estrella. Cada nivel fija asi la
## separacion angular respecto al primario, y cada mapa congela una fase
## orbital distinta: eso es lo que da identidad propia a cada nivel.
@export var sol_b_direccion := Vector3(0.913683, 0.374632, 0.157589)
## Color frio — otra estrella, no un gemelo del A.
@export var sol_b_color := Color(6.5, 3.6, 1.4)
@export var sol_b_sunset_color := Color(6.5, 1.6, 0.8)
@export_range(0.001, 1.0, 0.001) var sol_b_size := 0.055
@export_range(0.01, 20.0, 0.1) var sol_b_blur := 8.0
@export_range(0.0, 4.0, 0.01) var sol_b_energy := 0.55
## 0 = sin binaria. Los presets de una sola estrella lo apagan y el shader
## trata la noche como si solo hubiera un sol.
@export_range(0.0, 1.0, 0.01) var sol_b_encendido := 1.0

## ---------------------------------------------------------------------------
## Luna
## ---------------------------------------------------------------------------
@export_group("Luna")
## Vector unitario que apunta HACIA la luna. Tampoco tiene luz propia.
@export var luna_direccion := Vector3(-0.769245, 0.564643, 0.299067)
@export var luna_color := Color(1.0, 0.95, 0.7)
@export_range(0.01, 1.0, 0.001) var luna_size := 0.06
@export_range(0.01, 10.0, 0.1) var luna_blur := 0.1
@export_range(0.0, 1.0, 0.01) var luna_encendida := 0.0

## ---------------------------------------------------------------------------
## Nubes — KELVIN-HELMHOLTZ, el UNICO sistema de nubes del juego.
##
## Antes convivian DOS formaciones en el mismo cielo: las nubes convencionales
## de la referencia (`nubes_escala`, `nubes_desenfoque`, ...) y la KH, ademas
## con nombres distintos para lo mismo (`kh_*` frente a `clouds_*`). Salian dos
## estilos superpuestos, y encima `nubes_direccion` no llegaba a la KH porque
## esta se regia por `kh_direccion`: tocabas una cosa y se movia otra.
## Ahora: UN grupo, UN nombre, UN estilo (:v
## ---------------------------------------------------------------------------
@export_group("Nubes")
## Colores de la cresta: masa de abajo, transicion, cima y contorno iluminado.
@export var nubes_borde := Color(0.8, 0.8, 0.98)
@export var nubes_cima := Color(1.0, 1.0, 1.0)
@export var nubes_media := Color(0.92, 0.92, 0.98)
@export var nubes_base := Color(0.83, 0.83, 0.94)
## Altura de la interfaz sobre el suelo, en metros. El rayo se intersecta con
## un plano a esta altura: por eso las nubes ocupan una BANDA y no todo el
## cielo.
@export_range(50.0, 4000.0, 10.0) var nubes_altura := 800.0
## Distancia entre crestas, en metros.
@export_range(50.0, 3000.0, 10.0) var nubes_periodo := 600.0
## Fuerza del vortice que enrolla el ruido alrededor de cada cresta. Es
## literalmente lo que separa "nubes con bultos" de "olas rompiendo": sin
## rollo, la cresta queda un borde limpio de galleta. En 0 no hay rizo.
@export_range(0.0, 3.0, 0.01) var nubes_rollo := 1.15
## Radio de influencia del vortice, en metros. Muy pequeno = rizos finos y
## artificiales; muy grande = se funde todo y no se lee la fila.
@export_range(20.0, 1500.0, 10.0) var nubes_radio := 260.0
## Grosor de la capa. Las KH reales son finas: un borde grueso se lee como
## niebla baja, no como inestabilidad.
@export_range(0.02, 1.0, 0.01) var nubes_grosor := 0.26
## Direccion del arrastre en el plano de la capa, en vueltas (0.0 = +X).
@export_range(0.0, 1.0, 0.001) var nubes_direccion := 0.13
## Deriva temporal de la capa entera: el campo viaja, las crestas no estan
## quietas. En 0 el cielo se queda congelado.
@export_range(0.0, 20.0, 0.01) var nubes_velocidad := 2.0
## Umbral de densidad del ruido. A mayor, mas aire entre crestas.
@export_range(0.0, 1.0, 0.01) var nubes_corte := 0.3
## Suavizado de ese umbral. A mayor, borde esponjoso.
@export_range(0.0, 2.0, 0.01) var nubes_difuminado := 0.5
## Mas peso = nubes mas oscuras: es el control de tormenta.
@export_range(0.0, 1.0, 0.01) var nubes_peso := 0.0
## 0 = cielo limpio. 1 = KH a full.
@export_range(0.0, 1.0, 0.01) var nubes_intensidad := 1.0

## Capas de la formacion. 1 = la KH sola (coste actual). 2 = una capa DETRAS,
## mas alta, mas laxa y con menos detalle: es lo que da sensacion de campo con
## profundidad en vez de un papel pintado. Cada capa extra cuesta ruido, por
## eso es opt-in y no el default.
@export_range(1, 2, 1) var nubes_capas := 2
## Altura de la capa trasera RELATIVA a la principal (1.35 = un 35% mas alta).
## Tambien baja su escala y su velocidad, que es lo que produce el parallax:
## al mirar al horizonte las dos capas se separan entre si.
@export_range(1.0, 3.0, 0.01) var nubes_capa2_altura := 1.35
## Ancho del tramo en que el rizo cambia de sentido. Antes eso lo hacia un
## `sign()`, que es un SALTO DE CARA: a traves del centro de cada cresta el
## angulo pasaba de +rollo a -rollo de golpe y se leia como un pliegue cortado
## a cuchillo. Con `tanh` el paso por cero es suave y el enrollado sigue
## leyendose. Se mide como fraccion de `nubes_radio`.
@export_range(0.001, 0.5, 0.001) var nubes_rizo_ancho := 0.06
## Distancia sobre el plano de la capa a partir de la cual las nubes empiezan
## a fundirse con la niebla del horizonte, en metros. ANTES el fundido era
## angular (`smoothstep(0.0, 0.09, EYEDIR.y)`) y cortaba en cinco grados secos;
## encima a esa altura el plano ya esta a casi 9 km y las UV se van a infinito.
## Fundiendo por DISTANCIA, el ultimo escalon se disuelve en el color del
## horizonte en vez de desaparecer de golpe.
@export_range(500.0, 40000.0, 100.0) var nubes_fundido_horizonte := 7000.0
## Sombreado interno: si HACIA EL SOL hay mas masa, esta nube esta a la sombra
## de la de delante. Beer-Powder en su forma mas barata — un solo muestreo
## extra del ruido, desplazado en la direccion del sol dentro del plano.
@export_range(0.0, 1.0, 0.01) var nubes_sombra := 0.55

## ---------------------------------------------------------------------------
## Estrellas. Sin `stars_texture` no salen: ver la nota en `atmosfera.gd`.
## ---------------------------------------------------------------------------
@export_group("Estrellas")
@export_range(0.0, 20.0, 0.01) var estrellas_velocidad := 1.0
@export_range(0.1, 3.0, 0.01) var estrellas_escala := 1.0
@export_range(0.0, 1.0, 0.01) var estrellas_opacidad := 1.0

## ---------------------------------------------------------------------------
## Entorno — niebla, ambiente y tonemap de la Environment.
##
## Van AQUI y no en la escena porque "preconfigura al nivel" incluye la
## atmosfera, no solo el cielo. `entorno_activo` permite a un mapa dejar su
## Environment tal cual: si esta en false, atmosfera.gd no lo toca.
## ---------------------------------------------------------------------------
@export_group("Entorno")
@export var entorno_activo := true

@export_subgroup("Fondo y ambiente")
## 1 = COLOR plano, 2 = SKY (el cielo del shader).
@export_range(0, 4, 1) var fondo_modo := 2
@export var fondo_color := Color(0.42, 0.055, 0.058, 1.0)
@export_range(0.0, 16.0, 0.01) var fondo_energia := 1.1
## 0 = BG, 1 = DISABLED, 2 = COLOR, 3 = SKY. En petrolera es COLOR (2).
@export_range(0, 3, 1) var ambiente_fuente := 2
@export var ambiente_color := Color(0.42, 0.055, 0.058, 1.0)
@export_range(0.0, 16.0, 0.01) var ambiente_energia := 1.1

@export_subgroup("Tonemap")
## 0 LINEAR, 1 REINHARDT, 2 FILMIC, 3 ACES, 4 AGX, 5 NEON.
@export_range(0, 5, 1) var tonemap_modo := 4
@export_range(0.0, 16.0, 0.01) var tonemap_exposicion := 0.9

@export_subgroup("Niebla")
@export var niebla_activa := false
## 0 EXPONENCIAL, 1 EXPONENCIAL_AL_CUADRADO.
@export_range(0, 1, 1) var niebla_modo := 1
@export var niebla_color := Color(0.42, 0.055, 0.058, 1.0)
@export_range(0.0, 16.0, 0.01) var niebla_energia := 0.9
@export_range(0.0, 1.0, 0.001) var niebla_densidad := 1.0
@export_range(0.0, 1.0, 0.01) var niebla_afecta_cielo := 0.0

@export_subgroup("Niebla volumetrica")
@export var niebla_vol_activa := true
@export_range(0.0, 1.0, 0.0001) var niebla_vol_densidad := 0.02
@export var niebla_vol_albedo := Color(0.31342387, 0.07480901, 0.011168127, 1.0)
@export var niebla_vol_emision := Color(0.3668608, 0.031290494, 0.022811353, 1.0)
@export_range(0.0, 16.0, 0.01) var niebla_vol_emision_energia := 1.05
@export_range(0.0, 4.0, 0.01) var niebla_vol_gi := 1.3
@export_range(-1.0, 1.0, 0.01) var niebla_vol_anisotropia := 0.12
@export_range(1.0, 4096.0, 0.1) var niebla_vol_longitud := 62.81
@export_range(0.0, 16.0, 0.01) var niebla_vol_detalle := 1.189207
@export_range(0.0, 1.0, 0.01) var niebla_vol_afecta_cielo := 0.77

## ---------------------------------------------------------------------------
## Precipitacion. El emisor vive en `clima.tscn`; aqui se decide si llueve.
## ---------------------------------------------------------------------------
@export_group("Precipitacion")
enum Precipitacion { NINGUNA, LLUVIA, NIEVE, GRANIZO }
@export var precipitacion := Precipitacion.NINGUNA
## Particulas vivas a la vez. El emisor usa `amount` en el editor; aqui es
## el multiplicador que aplica atmosfera.gd para que un preset lo suba o lo baje.
@export_range(0.0, 4.0, 0.05) var precipitacion_intensidad := 1.0
@export_range(0.0, 60.0, 0.1) var precipitacion_velocidad := 14.0
@export var precipitacion_color := Color(0.75, 0.82, 0.9, 1.0)
## Cuanto la inclina el viento, 0..1. 0 = cae a plomo, que es como se lee un
## grifo abierto y NO como un temporal. La inclinacion se aplica a la
## VELOCIDAD de la gota y no a una rotacion: con
## `TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY` la gota se alinea con su
## velocidad, asi que inclinar la velocidad inclina el churrete — que es
## exactamente lo que hace falta para que se lea temporal (:v
@export_range(0.0, 1.0, 0.01) var precipitacion_viento := 0.0

@export_subgroup("Nivel de la lluvia")
## Los TRES NIVELES de intensidad. No es un volumen: el nivel decide CUANTAS
## CAPAS DE AUDIO suenan, mirando `SoundCapa.nivel_min`.
##
##   SUAVE   -> solo `lluvia_capa1.ogg`
##   MODERADA-> capa1 + `lluvia_capa2.ogg`
##   FUERTE  -> las TRES a la vez, en loop
##
## Va en pareja con `precipitacion_intensidad`, que sigue mandando en las
## particulas: el nivel escala la cantidad y la intensidad es el ajuste fino.
## El VIENTE usara EXACTAMENTE este mismo sistema cuando lleguen sus .ogg (:v
enum NivelLluvia { SUAVE, MODERADA, FUERTE }
@export var precipitacion_nivel := NivelLluvia.FUERTE

@export_subgroup("Sonido del clima")
## Maestro de TODO el sonido de clima: lluvia Y viento. Para apagar el clima
## entero de un golpe sin tocar los dos niveles por separado.
@export var clima_sonido := true
## Volumen de la lluvia en dB.
@export_range(-60.0, 12.0, 0.5) var lluvia_volumen_db := -4.0

@export_subgroup("Viento")
## El viento usa EXACTAMENTE el mismo sistema que la lluvia: tres .ogg en
## loop (`viento1..3.ogg`) que se ANADEN al subir de nivel. Mismo constructor,
## mismos grados, cero codigo nuevo — solo cambian los ficheros (:v
@export var viento_activo := true
@export var viento_nivel := NivelLluvia.FUERTE
@export_range(-60.0, 12.0, 0.5) var viento_volumen_db := -8.0

@export_subgroup("Trueno")
## Volumen del trueno. Va ALTO a proposito: un trueno lejano se distingue por
## su RETARDO, no por salir flojo. Ver `Relampago`, que lo posiciona en 3D.
@export_range(-60.0, 24.0, 0.5) var trueno_volumen_db := 6.0
## Distancia (en metros) a la que el trueno aun suena a tope. Con la atenuacion
## inversa de Godot, `unit_size` es el RADIO a volumen pleno: por debajo no se
## atenúa y por encima cae como `rango / distancia`. A 90 un rayo a 1500 m
## salia 24 dB mas flojo — medido por el General, "varios no se escuchan".
@export_range(1.0, 1000.0, 1.0) var trueno_rango := 320.0
## Tono del trueno. Mas BAJO = mas gordo y pesado; 1.0 suena tal cual el .ogg.
## En realidad hay DOS voces: esta y otra un 6% mas grave, que es lo que le da
## el cuerpo (una sola voz suena delgada) — ver `Relampago._voz_trueno`.
@export_range(0.4, 1.5, 0.01) var trueno_pitch := 0.72

## ---------------------------------------------------------------------------
## Tormenta — RAYOS.
##
## El rayo NO es un efecto de pantalla: son cuatro fuentes de luz coordinadas
## por la MISMA envoltura de pulsos, cada una con su color, su pico y su
## velocidad de apagado. Esa asimetria es lo que hace que el conjunto se lea
## organico en vez de como un flash unico:
##
##   sube DE GOLPE (ataque de milisegundos) y baja RAPIDO pero SUAVE
##   (caida exponencial), y cada fuente tiene su propio tiempo de apagado.
##
## El nodo que lo monta todo es `src/weather/relampago.gd`, que `atmosfera.gd`
## crea en runtime SOLO si `rayos_activos`. En el editor no existe nada: no
## se anade ningun nodo a la escena (:v
## ---------------------------------------------------------------------------
@export_group("Tormenta")
@export_subgroup("Cuando")
## Apaga el sistema entero. Sin el, `atmosfera.gd` ni siquiera crea el nodo.
@export var rayos_activos := false
## Segundos medios entre destellos. La espera real se sortea alrededor de
## este valor con `rayos_variacion`.
@export_range(0.5, 120.0, 0.5) var rayos_frecuencia_media := 16.0
## Dispersion de esa espera, 0..1. En 0 los rayos salen como un metronomo.
@export_range(0.0, 1.0, 0.01) var rayos_variacion := 0.75
## Probabilidad de que el destello sea SOLO en la nube, sin golpear el suelo.
## Es el que da la sensacion de tormenta lejana.
@export_range(0.0, 1.0, 0.01) var rayos_prob_nube_sola := 0.3
## Semilla del temporizador. 0 = distinta en cada partida; con valor, los
## destellos salen SIEMPRE en el mismo orden, que es lo que hace reproducible
## una captura o una prueba.
@export var rayos_semilla := 0
@export_range(50.0, 4000.0, 50.0) var rayos_distancia_min := 500.0
## Nunca por detras de esta distancia: mas alla el rayo se ve un punto y no
## paga la luz de impacto.
@export_range(100.0, 20000.0, 100.0) var rayos_distancia_max := 4000.0

@export_subgroup("Envoltura")
## Segundos del ataque. Es el unico tramo donde la luz sube; a cero el rayo
## saltaria de la nada y se leeria como un bug de render, no como un rayo.
@export_range(0.001, 0.3, 0.001) var rayos_tiempo_ataque := 0.035
## Repiques: un rayo real no es un destello sino 2..5, con amplitud decreciente.
@export_range(1, 6, 1) var rayos_restrikes := 3
## Segundos entre repique y repique.
@export_range(0.01, 0.6, 0.005) var rayos_gap_restrike := 0.085

@export_subgroup("Ambiente")
## Multiplicador del `ambiente_energia` de la Environment en el pico. Es la
## fuente que mas SUBE y la que mas despacio se apaga: el aire tarda en
## limpiarse, el rayo no.
@export_range(0.0, 30.0, 0.1) var rayos_ambiente_pico := 4.5
## Tiempo de caida exponencial (tau, en segundos). Pequeno = chasquido seco.
@export_range(0.05, 4.0, 0.01) var rayos_ambiente_caida := 0.4
## Tinte del ambiente durante el destello. Es el color que tiñe TODO lo que no
## sea luz directa: el cielo, la niebla, las sombras suaves.
@export var rayos_ambiente_tinte := Color(0.72, 0.8, 1.0)

@export_subgroup("Niebla volumetrica")
## La niebla se ENCIENTE con el rayo. Es el golpe visual mas grande y mas
## barato del sistema, porque no anade geometria: solo emision.
@export_range(0.0, 30.0, 0.1) var rayos_niebla_pico := 5.0
## La niebla es la mas lenta en apagarse, y esa lentitud es lo que deja la
## estela tras el destello.
@export_range(0.05, 6.0, 0.01) var rayos_niebla_caida := 0.9

@export_subgroup("Luz de impacto")
@export var rayos_impacto_color := Color(0.82, 0.88, 1.0)
@export_range(0.0, 400.0, 1.0) var rayos_impacto_energia := 120.0
@export_range(10.0, 4000.0, 10.0) var rayos_impacto_rango := 900.0
## La mas rapida en apagarse: el punto de golpe se apaga casi al instante.
@export_range(0.02, 4.0, 0.01) var rayos_impacto_caida := 0.1

@export_subgroup("Luz de la nube")
## HDR: el disco que se enciende dentro de la formacion. En su color van los
## valores por encima de 1.
@export var rayos_nube_color := Color(2.2, 2.6, 3.8)
@export_range(0.0, 100.0, 0.5) var rayos_nube_energia := 30.0
@export_range(0.05, 4.0, 0.01) var rayos_nube_caida := 0.22
## Radio angular del halo dentro de la nube, en radianes.
@export_range(0.01, 2.0, 0.005) var rayos_nube_radio := 0.22

@export_subgroup("Pantalla")
## Solo para rayos CERCANOS: un rayo a 4 km no debe lavarte la pantalla.
@export var rayos_pantalla_color := Color(0.86, 0.91, 1.0)
@export_range(0.0, 1.0, 0.01) var rayos_pantalla_fuerza := 0.4
## Por debajo de esta distancia el flash de pantalla se activa.
@export_range(0.0, 10000.0, 50.0) var rayos_pantalla_umbral := 1200.0

@export_subgroup("Sonido")
## Emite `Relampago.trueno_escuchado(distancia, energia)` Y reproduce el trueno
## con un pool de AudioStreamPlayer3D posicionados en el punto de impacto,
## con retardo `distancia / 343` y pista al azar entre `trueno1..3.ogg`.
## En false, solo se emite la senal y no suena nada (:v
@export var rayos_senalar_sonido := true
