# INFECCIÓN DE LA NIEBLA ROJA — Plan de diseño

> **Estado:** Fase 0 (plan, sin implementar) · **Fecha:** 2026-10-09
> **Objetivo:** representar la infección ambiental de la Niebla Roja como una
> **plasta blanquecina con rojo, agujeros, grumosa y humeante**, en "parches
> modulares" sobre el entorno, con **venas** que reaccionan al **viento de
> `Atmosfera`** y al **jugador** que les pisa encima.

---

## 1. Decisiones del General (cerradas)

| # | Decisión | Consecuencia arquitectónica |
|---|---|---|
| **D-I1** | **Visual reactiva, SIN spread** por ahora | Cero red. Los parches se siembran por zona (a mano o desde una semilla futura). Diseñado para que "sembrar desde la Colmena" sea añadir un llamador, no rehacer nada |
| **D-I2** | **`Atmosfera` es la DUEÑA del viento** | Refactor: la lógica de rachas/rumbo de `ocean.gd` pasa a `atmosfera.gd`; `Ocean` pasa a **leer**. Regla de un solo escritor de los shader globals |
| **D-I3** | **Solo entorno estático** | Parches por raycast sobre suelo/paredes/props estáticos. Personajes NO se tocan (el shader FP de clip ya es delicado) |

---

## 2. Verificación técnica hecha (medida, no supuesta)

| Pregunta | Respuesta | Fuente |
|---|---|---|
| ¿`Decal` de Godot acepta shader custom / se anima? | **NO.** Solo 4 ranuras de textura + `modulate`/`emission_energy`/`albedo_mix`. Sin vertex displacement, sin TIME, **sin afectar la transparencia del material de abajo** | docs 4.7 `class_decal` (leído hoy) |
| ¿`Decal` sirve? | Sí, como **capa de relleno estático** (clustered, barato, se adapta a cualquier geometría). NO como núcleo del efecto reactivo | ídem |
| ¿Exiten globals de viento? | **Sí**: `wind_intensity`, `wind_direction` en `project.godot [shader_globals]` (líneas 158-164) | grep hoy |
| ¿Quién los empuja hoy? | **Solo `Ocean._process`** (`ocean.gd` l.189-198). Mapa sin Ocean ⇒ viento = 0 para siempre | lectura |
| ¿`RenderingServer.global_shader_parameter_get()`? | **Editor-only**; en runtime emite ERROR por frame. Los getters se hacen cacheando lo que tú empujas (patrón `Ocean.wind_*_actual()`) | AGENTS + `ocean.gd` l.74-78 |
| ¿`Atmosfera` tiene dirección de viento? | **No**. El preset solo tiene viento de AUDIO (`viento_activo/nivel/volumen_db`) + lean de lluvia. Hace falta añadir rumbo/intensidad | `atmosfera.gd` |
| ¿Los mapas tienen `Atmosfera`? | Petrolera **sí** (instancia `atmosfera.tscn`); lobbyV2 tiene un nodo Atmosfera inline | grep de `maps/` |
| Render mode para huecos | `depth_prepass_alpha` **existe en 4.7** (docs spatial shaders leídas hoy) + `discard` a mano (GLSL puro, sin depender de nombres de built-ins) | docs 4.7 |
| ¿Trucos de agujeros trypofóbicos? | Estándar de producción: **Voronoi/Worley** con umbral → huecos agrupados de tamaños distintos + rim en el borde + interior oscuro rojo | búsqueda web hoy |

---

## 3. Arquitectura

### 3.1 Estructura de archivos (patrón `src/water/` ya validado)

```
src/infeccion/
├── infeccion_zona.gd        InfeccionZona (Node3D) — dueña de una zona de infección
├── parche.gd                Parche (MeshInstance3D) — UN parche de plasta
├── vena.gd                  Vena (MeshInstance3D) — cinta procedural que crece
├── infeccion_config.gd      Resource — look compartido (paleta, densidad, radios)
├── shaders/
│   ├── infeccion_parche.gdshader   el look de la plasta (núcleo del sistema)
│   └── infeccion_vena.gdshader     venas: crecimiento + viento + reacción
├── nodos/
│   ├── zona_infeccion.tscn   prefab arrastrable a cualquier mapa
│   └── parche.tscn
├── demo/
│   ├── demo_infeccion.tscn   harness jugable (patrón demo_agua)
│   └── demo_infeccion.gd     test automático por env (INFECT_TEST=1)
└── README.md
```

### 3.2 Árbol de nodos en runtime (por zona)

```
ZonaInfeccion (Node3D, InfeccionZona)          ← en la escena, a mano
├── Superficie (Node3D)
│   ├── Parche_01 (MeshInstance3D + parche.gd)  ← generados, SIN owner
│   ├── Parche_02 ...
│   └── ...
├── Venas (Node3D)
│   ├── Vena_01 (MeshInstance3D + vena.gd)
│   └── ...
├── Vapor (GPUParticles3D, opcional)           ← emisor único por zona
└── (material de zona: UN ShaderMaterial compartido por todos los hijos)
```

**Clave de diseño: UN `ShaderMaterial` por ZONA** (no por parche). Los uniforms
de reacción (`jugador_pos`, `jugador_actividad`) se escriben **una vez por
frame** sobre el material de la zona y todos sus parches/venas lo leen. 50
parches = 1 escritura de uniform, no 50.

---

## 4. Los tres subsistemas

### 4.1 `InfeccionZona` — la dueña

- `@export`: forma (caja/esfera), nº y radio de parches, densidad de venas,
  `InfeccionConfig`, si emite vapor.
- **Siembra en runtime** (al entrar en árbol): coloca parches con raycast al
  suelo/pared, orienta cada uno según la **normal del golpe** (una pared recibe
  un parche vertical sin special-casing: la milla la da la orientación).
- **Cola de siembra escalonada**: máx. K parches por frame (cada parche son
  ~N² raycasts; 50 parches × 25×25 = 31.250 raycasts de golpe = hitch medible).
- **Reactividad a 10 Hz**: escribe `jugador_pos` (jugador del grupo `"jugador"`
  más cercano — *hoy el grupo no existe, hay que registrarlo en el spawn del
  jugador*), `jugador_actividad` (velocidad) y lee viento en SU material.
- **Gizmos en editor** (círculo/caja de la zona), **sin `owner`** en hijos
  generados — gotcha ya vivida con `AmbienteAudio`/`Relampago`.
- Registro en grupo `"infeccion_zona"` para que una futura Colmena pueda
  sembrarlas (puerta D-I1 abierta).

### 4.2 `Parche` — la plasta (el look es TODO shader)

- **Malla**: `PlaneMesh` subdividida (16×16 → 512 tris; 25×25 → 1.250) generada
  en código, **conformada por raycast vértice a vértice** contra la superficie +
  offset 2-4 cm a lo largo de la normal (antiz-fighting; complementar con
  `render_priority` alto en el material).
- **Fallback**: si un raycast no da bola, ese vértice se queda en el plano; si
  falla el golpe central, el parche se descarta (no flotando).
- **UVs**: irrelevantes — el shader trabaja en **triplanar / espacio de mundo**
  (la malla es procedural, no tiene UV naturales útiles).

### 4.3 `Vena` — la porquería que crece y se mueve

- **Cinta procedural**: cadena de puntos muestreada desde el borde de un parche
  (zigzag por la superficie, paso 0.3-0.5 m, raycast en cada paso) → `ArrayMesh`
  de cinta (2 triángulos por segmento), ancho 5-15 cm con taper.
- **Crecimiento**: uniform `crecimiento` 0..1 → descarte en vertex/fragment por
  UV.x (barato, sin rebuild de malla).
- **Viento**: desplazamiento perpendicular × `global uniform wind_intensity`
  con `wind_direction` como eje, **amortiguado por la distancia a la raíz**
  (raíz anclada al parche ⇒ `amortiguación = pow(uv.x, 1.5)`).
- **Jugador**: uniform de zona → hinchazón + emisión roja + tensado (se pone
  tiesa cuando pasas cerca).

---

## 5. Look del shader de parche — capa a capa

| # | Capa | Técnica | Coste |
|---|---|---|---|
| 1 | Albedo blanquecino | triplanar 3 planos × fbm 2 octavas, tinte marfil enfermo `≈ (0.85, 0.82, 0.74)` | ~10 ALU |
| 2 | Rojo en hendiduras | máscara Worley: el **borde de célula** tiñe de rojo sangre; centro = blanco | ~12 ALU |
| 3 | Grumos (silueta) | vertex displacement con ruido baja frecuencia sobre la normal → borde irregular, no un quad | vertex |
| 4 | Grumos (luz) | normal derivada del ruido (analítica o `grumos_nrm.png`) | bajo |
| 5 | **Agujeros trypofóbicos** | Voronoi tileable → umbral → `discard` + **rim** claro en el borde + interior rojo oscuro con emisión débil; parallax de 2-3 pasos para profundidad falsa (POM NO) | medio |
| 6 | Mucosa / mojado | roughness bajo + fresnel de humedad + película que se desliza con `TIME` | bajo |
| 7 | Humo | 2 fuentes: (a) pluma de ruido scroll + fresnel sobre el agujero, (b) `GPUParticles3D` de la zona (sprite `vapor.png`) | medio |
| 8 | Latido | pulso `sin(TAU * t * frec)` sobre emisión/desplazamiento (la plasta respira) | casi 0 |
| 9 | **← Viento** | `global uniform float wind_intensity; global uniform vec3 wind_direction;` con **guard anti-NaN** (mismo patrón que `ocean_stylized.gdshader` l.261-265): inclina humo, arrastra la película, agita los bordes | casi 0 |
| 10 | **← Jugador** | uniform zona `jugador_pos`/`jugador_actividad`: los agujeros **se cierran** cerca de ti, el borde se hincha, la emisión sube (la plasta "reacciona" a que le pases encima) | bajo |

**Render modes**: `depth_prepass_alpha, cull_back` → los huecos escriben
profundidad y **proyectan sombra recortada** (sin prepass, sombra rectangular
feísima).

---

## 6. Refactor de viento (D-I2) — prerequisite de la Fase 3

**Antes (hoy):** `Ocean` escribe `wind_intensity`/`wind_direction` globales;
`Atmosfera` ni se entera; sin Ocean ⇒ viento 0.

**Después:**

1. `atmosfera.gd` gana `@export_group("Viento")`: `viento_intensidad`,
   `viento_rumbo_grados`, `viento_racha`, `viento_auto` (+ campos opcionales en
   `AtmosferaPreset` para que cada nivel defina su clima).
2. `Atmosfera` empuja los 2 globals en `_process` con la lógica de rachas
   **movida** de `ocean.gd::_push_globals` (dos senos incomensurables + deriva
   de rumbo ±12°, ya validada en el mar).
3. `Atmosfera` se registra en grupo `"atmosfera"` y expone
   `wind_intensity_actual()` / `wind_direction_actual()` (mismo contrato que
   hoy tiene `Ocean` — `global_shader_parameter_get` es editor-only).
4. `Ocean` deja de escribir: si encuentra un `Atmosfera` en la escena, **lee**
   sus getters cada frame y cachea en `_wind_actual/_wind_dir_actual` (los
   getters públicos se mantienen ⇒ `WaterSurface` **no cambia**). Si NO hay
   `Atmosfera`, mantiene su lógica de viento actual como fallback (mapas viejos).
5. `process_priority` de `Atmosfera` < el de `Ocean` para que el escritor corra
   primero (evita un frame de retraso en las olas).

**Los shaders de infección NO leen por GDScript**: declaran los `global
uniform` directamente ⇒ no les importa quién escribe, siempre que sea 1 solo.

---

## 7. Assets necesarios — ¿todo por shader?

**No hace falta NI UN modelo 3D externo.** Toda la geometría (parches, venas,
vapor) es procedural, generada por código. Lo que sí hace falta:

### Texturas (4-5)

| Fichero | Qué | Alternativa barata |
|---|---|---|
| `assets/env/textures/infeccion/huecos.png` | Worley/Voronoi tileable en grises 1024² — BASE de los agujeros | **Provisional: `agua1.png`** (ya es celular en grises; lo usa el océano, copia local) |
| `.../grumos_nrm.png` | Normal map tiling de grumos 1024² | Normales **analíticas** del ruido → 0 texturas |
| `.../mucosa.png` | Máscara de brillo/humedad para roughness | Reutilizar `huecos.png` |
| `.../vapor.png` | Sprite suave radial para las partículas | Dibujado a mano / generado |
| `.../vena_alpha.png` | Borde irregular de la cinta | Procedural en shader (recomendado) |

### Audio — `audio/sfx/infeccion/` (4 .ogg)

- `vapor_siseo.ogg` (loop) + `pulso_mucosa.ogg` (loop grave, latido) → van en
  un **`AmbienteAudio` con `grupo = "infeccion"` y zonas por `.tres`** — el
  sistema de audio por zonas YA existe y es exactamente para esto.
- `mucosa_pisada_01/02.ogg` (one-shots al pisar cerca).
- `vena_estirando.ogg` (aparece/crece vena).

### Escenas (por MCP, nunca a mano)

`zona_infeccion.tscn`, `parche.tscn`, `demo_infeccion.tscn` + materiales
`.tres` del shader + 2 `.tres` de `InfeccionConfig` (ej. `niebla_roja.tres`).

### Lo que NO hace falta

Modelos de venas · texturas de personaje · animaciones · authoring de decals
(si se usa la capa de relleno: 1 textura de mancha) · cambios de red.

---

## 8. Presupuesto de rendimiento y medición

- **Triángulos**: 100 parches × 512 tris = 51k + venas (40 × 60 tris) →
  despreciable. Añadir `visibility_aabb` generosa + distance fade.
- **Fragment** (lo caro): triplanar + Voronoi + parallax. Mitigar con distancia
  de corte del parallax (>25 m se apaga) y `discard` temprano.
- **Raycasts**: solo al crear, en cola (máx. K parches/frame).
- **Harness automático** al estilo del agua:
  `INFECT_TEST=1` → fases PASS/FAIL en consola; `INFECT_SHOT=1` → captura a
  los 5 s. Medir FPS con la captura, no a ojo.

---

## 9. Gotchas a respetar (medidas en este repo)

1. **`global uniform` inexistente rompe el shader SIN aviso en consola**
   (popup del editor). SOLO usar los 2 globales que ya existen:
   `wind_intensity`, `wind_direction`. Para nuevas variables de zona → uniforms
   normales del material.
2. **`ShaderMaterial` guardado sin `shader_parameter/*` sale NEGRO** —
   inyectar texturas/uniforms en `_ready` con defaults (patrón `_bind_material`
   de `ocean.gd`).
3. **`Array[X]` no acepta literales sin tipar** (`[zona]` queda `[]` en
   silencio) → declarar `var zonas_t: Array[SoundZona] = [zona]`.
4. **Nodos generados en runtime → SIN `owner`** (no se escriben en el `.tscn`).
5. **`heren.scene create` no persiste** la `.tscn` y `ctx.instance_scene()`
   falla en silencio → crear escenas con `load().instantiate()` + `owner` a
   mano o desde el editor.
6. **`validate reload_err=22` es falso positivo** (`ERR_ALREADY_IN_USE`, no
   parse); verdad = `Godot --headless --check-only -s res://ruta.gd` y el test
   de runtime.
7. **Alpha sin prepass = sombras rectangulares** → `depth_prepass_alpha`
   obligatorio.
8. **Z-fighting parche/superficie** → offset 2-4 cm + `render_priority`.
9. **`INV_PROJECTION_MATRIX` dentro de una función NO compila** (regla del
   océano) — si el parallax necesita la view vector, se calcula en el cuerpo de
   `fragment()`.
10. **`rendering/decals`** no importa aquí: los Decal de relleno son estáticos
    y los mete `InfeccionZona` como nodos, no el shader.

---

## 10. Fases

| Fase | Contenido | Entrega | Estado |
|---|---|---|---|
| **0** | Este plan | `meta/docs/Infeccion_Niebla_Roja.md` | ✅ hoy |
| **1** | **Refactor de viento**: `Atmosfera` dueña, `Ocean` lee (D-I2) | Océano con test `AGUA_TEST=1` verde + captura igual que antes | ☐ |
| **2** | Shader de parche + `InfeccionZona` con parches estáticos (sin reactividad) en `demo_infeccion.tscn` | `INFECT_TEST=1` PASS + captura "asquerosa" aprobada por el General | ☐ |
| **3** | Venas procedurales + reacción al viento | Captura con viento fuerte moviendo venas/humo | ☐ |
| **4** | Reactividad al jugador + vapor + audio (`AmbienteAudio` grupo "infeccion") | Demo jugable: pisas la plasta y reacciona | ☐ |
| **5** | Cablear en mapa real (petrolera: zonas de la Colmena) + gizmos + Decal de relleno opcional | Zonas en el mapa + README | ☐ |

---

## 11. Preguntas abiertas (para la Fase 5)

- ¿Dónde se estrena la primera zona? (petrolera: bajo el agua / sala de la
  Colmena / lobbyV2 como test corto)
- ¿La plasta bloquea visión (alpha scissor) o solo decora?
- ¿El vapor tiene gameplay (esconde al infectado) o es puro look?
- Red: hoy cero (D-I1). Si el spread entra en juego → patrón
  server-authoritative `apply_network_tide()` de `ocean.gd`.
