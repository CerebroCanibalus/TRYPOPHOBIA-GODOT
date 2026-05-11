# Editor de Niveles — Cyclops Level Builder (Modificado)

**Estado:** Instalado y listo para modificación | **Versión base:** 1.0.4 | **Prioridad:** ALTA

---

## 1. Decisión: Cyclops Level Builder

Tras investigar opciones existentes, **Cyclops Level Builder** es la herramienta seleccionada. Es el punto medio perfecto entre la complejidad de Hammer y la limitación de CSG nativo.

**Por qué Cyclops:**
- ✅ Edición directa en viewport de Godot (no sale del editor)
- ✅ Brushes con manipulación de caras, vértices, aristas (estilo Hammer modernizado)
- ✅ Snapping a grilla configurable
- ✅ Colisiones automáticas
- ✅ Materiales por cara con UVs triplanares
- ✅ Exporta a mesh estático optimizado
- ✅ Sistema de undo/redo completo
- ✅ Código abierto y modificable (MIT License)

**Ubicación en proyecto:** `addons/cyclops_level_builder/`

---

## 2. Análisis de la Arquitectura Base

### 2.1 Nodos Principales

| Nodo | Función |
|------|---------|
| `CyclopsBlocks` | Nodo raíz del nivel. Contiene todos los bloques |
| `CyclopsBlock` | Bloque individual (convexo). No es Node3D, vive dentro de CyclopsBlocks |
| `CyclopsBlockBody` | Mesh + CollisionShape generados automáticamente (no visible en outliner) |

### 2.2 Sistema de Comandos (Undo/Redo)

Todos los cambios se traducen en comandos:
- `cmd_add_block.gd` — Añadir bloque
- `cmd_delete_blocks.gd` — Eliminar bloques
- `cmd_move_faces.gd` — Mover caras
- `cmd_set_material.gd` — Asignar material
- `cmd_merge_blocks.gd` — Mergear bloques
- `cmd_subtract_block.gd` — Restar bloque (CSG booleano)

**Patrón:** Command pattern con `do_it()` y `undo_it()`

### 2.3 Herramientas Disponibles

| Herramienta | Función |
|-------------|---------|
| `tool_block.gd` | Crear bloques básicos |
| `tool_cylinder.gd` | Crear cilindros |
| `tool_prism.gd` | Crear prismas |
| `tool_stairs.gd` | Crear escaleras |
| `tool_edit_face.gd` | Editar caras (mover, escalar) |
| `tool_edit_edge.gd` | Editar aristas |
| `tool_edit_vertex.gd` | Editar vértices |
| `tool_material_brush.gd` | Pintar materiales |
| `tool_vertex_color_brush.gd` | Pintar colores de vértice |
| `tool_move.gd` | Mover selección |
| `tool_rotate.gd` | Rotar selección |
| `tool_clip.gd` | Cortar bloques |
| `tool_duplicate.gd` | Duplicar |

### 2.4 Docks y UI

- **Material Dock:** Gestión de materiales y asignación
- **Tool Settings Dock:** Configuración de herramienta activa
- **Face Properties Dock:** Propiedades de cara seleccionada

---

## 3. Modificaciones Planificadas para Trypophobia

### 3.1 FASE 1: Optimización para Estilo Semi-Minecraft

**Problema:** Cyclops genera UVs triplanares que no encajan con estilo tile/Minecraft.

**Modificación:**
```gdscript
# En: nodes/cyclops_block.gd o commands/cmd_set_face_uv_transform.gd
# Añadir modo de UV "Tile/Minecraft"
# En lugar de triplanar world-space, usar:
# - UVs basados en tamaño de celda (ej: 1m = 1 tile)
# - Snap de UVs a grid de textura
# - Soporte para atlas de texturas (spritesheet)
```

**Resultado:** Texturas se repiten perfectamente en bloques de 1x1x1m estilo Minecraft.

### 3.2 FASE 2: Exportación Optimizada a Mesh Estático

**Problema:** Cyclops mantiene bloques individuables en runtime (editables).

**Modificación:**
```gdscript
# Nueva acción: action_export_optimized.gd
# - Mergear todos los bloques estáticos en un solo MeshInstance3D
# - Generar un solo CollisionShape3D (convex hull o trimesh)
# - Preservar bloques "dinámicos" (puertas, plataformas) como nodos separados
# - Bake de NavigationMesh
```

**Resultado:** Nivel estático = 1 draw call. Objetos dinámicos = nodos separados.

### 3.3 FASE 3: Integración con Sistema de Entidades

**Modificación:**
```gdscript
# Nuevo dock: Entity Dock
# - Lista de entidades: info_player_start, info_enemy_spawn, trigger_zone, etc.
# - Colocar entidades como nodos hijos de CyclopsBlocks
# - Exportar como posiciones + propiedades al bakear nivel

# Nueva herramienta: tool_entity_placer.gd
# - Seleccionar tipo de entidad
# - Click en cara del bloque = colocar entidad
# - Visualización gizmo (icono 3D)
```

**Entidades soportadas:**
- `info_player_start` — Spawn de jugador
- `info_enemy_spawn` — Spawn de enemigo
- `trigger_zone` — Zona de trigger (misiones, eventos)
- `sound_ambient` — Sonido ambiente
- `prop_physics` — Objeto agarrable (rigid body)
- `light_point` — Luz puntual

### 3.4 FASE 4: Navegación Automática

**Modificación:**
```gdscript
# Al exportar/bakear nivel:
# - Generar NavigationRegion3D
# - Bake NavigationMesh desde geometría de CyclopsBlocks
# - Marcar áreas "no navegables" (void, agua, etc.)
# - Soporte para "navigation links" (saltos, escaleras)
```

### 3.5 FASE 5: Mejoras de Workflow

**Modificaciones menores:**
- **Randomize Tool:** Variación aleatoria de materiales similares (ruido visual)
- **Stamp Tool:** Guardar sección del nivel y reutilizar como prefab
- **Symmetry Tool:** Edición simétrica en X/Y/Z
- **Layer System:** Capas tipo Photoshop para organizar bloques (suelo, paredes, techos)
- **Quick Export:** Botón "Export to Scene" que bakea + guarda como .tscn

---

## 4. Pipeline de Trabajo Propuesto

```
FASE DE DISEÑO (En Godot Editor)
│
├── 1. Crear CyclopsBlocks node
│   └── Configurar grilla (ej: 1m para estilo Minecraft)
│
├── 2. Blockout con herramientas Cyclops
│   ├── tool_block → Paredes, suelos, techos
│   ├── tool_stairs → Escaleras
│   └── tool_cylinder → Columnas, tuberías
│
├── 3. Edición detallada
│   ├── tool_edit_face → Ajustar caras
│   ├── tool_material_brush → Pintar texturas
│   └── tool_vertex_color_brush → Variación de color
│
├── 4. Colocar entidades
│   └── tool_entity_placer → Spawns, triggers, luces
│
├── 5. Exportar/Bakear
│   ├── Mergear geometría estática
│   ├── Generar colisiones
│   ├── Bake NavigationMesh
│   └── Guardar como .tscn
│
└── 6. Post-proceso en Godot
    ├── Añadir iluminación
    ├── Colocar props físicos (RigidBody3D)
    └── Setup enemigos y testeo
```

---

## 5. Archivos Clave para Modificar

```
addons/cyclops_level_builder/
├── nodes/
│   ├── cyclops_block.gd              # UVs, material por cara
│   └── cyclops_blocks.gd             # Exportación, bakeo
├── commands/
│   └── mesh/
│       ├── cmd_add_block.gd          # Añadir bloque (ajustar snapping)
│       └── cmd_set_material.gd       # Asignar material (soporte atlas)
├── tools/
│   ├── tool_material_brush.gd        # Pintar materiales
│   └── [NUEVO] tool_entity_placer.gd # Colocar entidades
├── docks/
│   ├── dock_material.gd              # UI de materiales
│   └── [NUEVO] dock_entity.gd        # UI de entidades
└── actions/
    └── io/
        ├── action_export_as_godot_scene.gd  # Exportar a .tscn
        └── [NUEVO] action_export_optimized.gd # Exportar optimizado
```

---

## 6. Decisiones Técnicas Pendientes

| Decisión | Opción A | Opción B |
|----------|----------|----------|
| **UVs** | Triplanar world-space (original) | Tile-based 1m = 1 tile (modificado) |
| **Exportación** | Mantener bloques editables | Bakear a mesh único |
| **Entidades** | Nodos hijos de CyclopsBlocks | Archivo .json separado |
| **Colisiones** | Convex hull por bloque | Trimesh único del nivel |
| **Navegación** | Bake automático al exportar | Manual después de exportar |

---

## 7. Roadmap de Modificación

| Semana | Tarea | Archivos |
|--------|-------|----------|
| 1 | Instalar y testear Cyclops base | — |
| 2 | Modo UV Tile/Minecraft | `cyclops_block.gd`, `cmd_set_face_uv_transform.gd` |
| 3 | Exportación a mesh estático | `cyclops_blocks.gd`, nueva acción |
| 4 | Sistema de entidades (dock + tool) | `dock_entity.gd`, `tool_entity_placer.gd` |
| 5 | Navegación automática | `cyclops_blocks.gd` (bake navmesh) |
| 6 | Polish: stamp, symmetry, layers | Varios |

---

## 8. Ventajas de esta Aproximación

1. **No reinventamos la rueda:** Cyclops ya tiene el core de edición 3D
2. **Mantenible:** Solo modificamos lo que necesitamos
3. **Familiar:** Los level designers que conocen Hammer se adaptan rápido
4. **Escalable:** Desde blockout hasta producción final
5. **Nativo:** Todo dentro de Godot, sin exportar/importar

---

*Documento v2.0 — Cyclops seleccionado, modificaciones planificadas*
