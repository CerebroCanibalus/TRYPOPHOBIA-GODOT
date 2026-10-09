# 💧 Sistema de agua — nodos reutilizables

Todo lo del agua vive en `src/water/` y está formalizado en **prefabs de
escena** que se arrastran desde el FileSystem a cualquier nivel. Ninguno
depende del demo: se buscan por clase (`WaterBody.buscar_en`, `Oxygen.buscar_en`),
nunca por nombre de nodo.

## Prefabs

| Prefab | Raíz | Para qué | Ajustar al colocarlo |
|---|---|---|---|
| `nodos/mar.tscn` | Node3D `Mar` | **Océano completo de una instancia**: `Ocean` (marea+viento) + `MarLejano` (malla 200×200 con `ocean_stylized_mat`) + `Superficie` + `Volumen` enlazados | Tamaño de malla/volumen (hijos con "editable children") |
| `nodos/superficie_agua.tscn` | Node3D | Réplica CPU de las olas + marea. **Dueña del reloj** (`wave_time` del shader) | Que mire la malla del mar (auto por grupo/material) |
| `nodos/volumen_agua.tscn` | Area3D | Dónde hay agua: XZ + fondo + densidad + corriente. El **tope lo pone la superficie**, no el shape | Escala de la `Forma` (BoxShape 200×80×200, tapa en y=+2) |
| `nodos/volumen_aire.tscn` | Area3D | **Zona seca sumergida** (sala, túnel, burbuja): el aire manda sobre el agua | Tamaño/posición (default 8×4×8 = sala del demo) |
| `nodos/cuerpo_agua.tscn` | Node | Componente de **empuje + arrastre multi-cuerpo**. Va dentro del personaje/objeto | `densidad_cuerpo` (700 persona · 500 madera · 2500 roca), `factor_empuje`, `arrastre` |
| `nodos/oxigeno.tscn` | Node | **Apnea, ahogo y señales** para HUD | `maximo`, `consumo`, `gracia` |
| `nodos/distorsion_submarina.tscn` | CanvasLayer | Post-proceso que traduce `WaterBody` a pantalla (tinte mojado · distorsión buceando) | Va en **capa 1**; el HUD va en **capa ≥ 10** |

## Añadir agua a un nivel (3 pasos)

1. **Arrastra `nodos/mar.tscn`** a la escena. Ya flota, ya hay marea, ya hay
   volumen físico. (Si el nivel ya tiene su malla de mar, en vez de eso arrastra
   `superficie_agua.tscn` + `volumen_agua.tscn` y apunta la superficie a la malla.)
2. Si hay **habitaciones sumergidas**, mete un `nodos/volumen_aire.tscn` dentro:
   quien esté dentro **no se ahoga y el agua no le cuenta** (la sala del demo es
   el ejemplo: 8×4×8 justo en la cara interior de los muros).
3. Nada más. Los personajes ya flotan solos si llevan sus componentes.

## Hacer un personaje (o cosa) acuático

Dentro del personaje: `cuerpo_agua.tscn` + `oxigeno.tscn` (+ `distorsion_submarina.tscn`).
Eso es lo que ya traen `ragdoll_character.tscn` e `IzaPlayer.tscn`.

API pública para sus scripts:

```gdscript
var agua := WaterBody.buscar_en(self)     # nunca por nombre
var oxigeno := Oxygen.buscar_en(self)

# ragdoll: el cuerpo real es el hueso Body (la raiz NO sigue al ragdoll)
agua.fijar_cuerpo(physical_bone_body)
agua.fijar_cuerpos_extra(physics_bones)   # los 10 huesos flotan, no solo 1
agua.fijar_cabeza(offset_local)           # punto de respiracion (Head +0,45)

# controles
agua.empuje_suprimido = corto_y_agachado  # Ctrl = hundirse de verdad
agua.impulso_vertical(8.0)                # salida del agua (a TODOS los cuerpos)
agua.apoyado = is_on_floor                # sin empuje apoyado en el suelo

# estado (para HUD/IA)
agua.sumergido, agua.cabeza_sumergida, agua.fraccion,
agua.profundidad, agua.nivel, agua.corriente, agua.aceleracion_empuje()
oxigeno.restante, oxigeno.porcentaje(), senales oxigeno_cambiada / ahogado()
```

## Convenciones

- **Capas 3d physics**: agua = bit 9 · aire = bit 7. Los volúmenes NO necesitan
  overlap: el test es analítico por punto (`WaterQuery.volumen_en(p)`), cero
  queries al physics server.
- **Prioridad**: aire > agua > nada. Por eso existen las zonas secas.
- **CanvasLayer**: distorsión capa 1 · HUD capa ≥ 10.
- El agua NO es server-authoritative todavía: en red hay que mandar volumen,
  superficie y oxígeno desde el servidor.

## Medir (la regla es medir, no mirar)

```powershell
# 17 comprobaciones: flota / cabeza fuera / ahogo / sala seca / Ctrl hunde / Espacio saca
$env:AGUA_TEST="1"; & "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "<proyecto>" --quit-after 40000 "res://src/water/demo/demo_agua.tscn"

# capturas
AGUA_SHOT=1                        # a los 5 s, cuerpos ya asentados
AGUA_SHOT=1 AGUA_SHOT_FLOTA=1      # ragdoll suelto en agua abierta
AGUA_SHOT=1 AGUA_SHOT_HONDA=1      # camara dentro del agua (se ve la distorsion)
```

## Compilar un GDScript sin abrir el editor

```powershell
& "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "<proyecto>" --check-only -s "res://ruta.gd"
```

## Gotchas del sistema (medidos)

- `Shape3D` **no tiene `get_aabb()`** en Godot 4.7 ni `AABB.transformed()` →
  están en `WaterShapeTest.aabb_de() / aabb_transformada()`.
- `CharacterBody3D` se llama **`velocity`**; `linear_velocity` es de
  RigidBody3D/PhysicalBone3D.
- `RenderingServer.global_shader_parameter_get()` es **editor-only** (ERROR por
  frame en runtime) → el viento sale de `Ocean.wind_intensity_actual()`.
- El muestreo del cuerpo es **por capas con la sección REAL** de la forma:
  muestrear las esquinas del AABB en una cápsula da puntos fuera de la cápsula
  y el personaje flota con la cabeza bajo el agua.
- Un solo hueso flotando no basta: con el ragdoll, empuje solo al `Body` =
  140 N contra 206 N de peso total ⇒ se hunde. Por eso `fijar_cuerpos_extra`.
