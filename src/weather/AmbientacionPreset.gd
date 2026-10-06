extends Resource
class_name AmbientacionPreset
## Preset de AMBIENTACION de UN nivel: cielo, soles, nubes, niebla, lluvia.
##
## Es el corazon del sistema canonico de clima: se preconfigura al cargar el
## nivel y NO cambia en runtime (no hay ciclo dia/noche ni transiciones). Lo
## unico que se anima es cosmético — las nubes derivan con `TIME`.
##
## Lo aplica `src/weather/ambientacion.gd` en `_ready()`. Un nivel = un `.tres`
## de este tipo. Ver `src/weather/ambientacion.tscn`, que es el nodo drag&drop,
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
## la DirectionalLight3D que ya trae el mapa (en petrolera, `Sol`): `ambientacion.gd`
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

## ---------------------------------------------------------------------------
## Estrellas. Sin `stars_texture` no salen: ver la nota en `ambientacion.gd`.
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
## Environment tal cual: si esta en false, ambientacion.gd no lo toca.
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
## el multiplicador que aplica ambientacion.gd para que un preset lo suba o lo baje.
@export_range(0.0, 4.0, 0.05) var precipitacion_intensidad := 1.0
@export_range(0.0, 60.0, 0.1) var precipitacion_velocidad := 14.0
@export var precipitacion_color := Color(0.75, 0.82, 0.9, 1.0)
