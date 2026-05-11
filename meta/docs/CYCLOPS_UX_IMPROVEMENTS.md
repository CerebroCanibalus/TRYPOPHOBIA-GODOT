# Plan de Mejoras UX — Cyclops Level Builder para Trypophobia

**Estado:** Actualizado tras análisis técnico | **Prioridad:** ALTA | **Objetivo:** Hacer Cyclops usable para producción

---

## 1. DIAGNÓSTICO DE PROBLEMAS

### 1.1 Problema: Selección de CyclopsBlocks no muestra herramientas
**Causa raíz:**
- `cyclops_level_builder.gd::get_active_block()` solo devuelve `CyclopsBlock` (bloque individual)
- Cuando seleccionas `CyclopsBlocks` (el contenedor), devuelve `null`
- `editor_toolbar.gd::build_ui()` usa `_can_handle_object(active_block)` para filtrar herramientas
- Si `active_block` es `null`, NINGUNA herramienta se muestra

### 1.2 Problema: No hay grid visual
**Causa raíz:**
- Godot tiene grid nativo en viewport 3D, pero NO hay API pública para plugins
- Cyclops no tiene grid propio
- El grid de Godot solo aparece cuando seleccionas un nodo 3D normal

### 1.3 Problema: Herramientas dispersas
**Causa raíz:**
- 5 herramientas de creación separadas (Block, Cylinder, Prism, Sphere, Stairs)
- 3 herramientas de edición separadas (Face, Edge, Vertex)
- Cada una es una clase con su propio estado y UI

### 1.4 Problema: Conflictos de Pivot
**Causa raíz:**
- Godot muestra gizmos nativos (flechas) al seleccionar un nodo 3D
- Cyclops tiene SU propio sistema de transformación
- No hay API para desactivar gizmos nativos de Godot

### 1.5 Problema: Undo roto
**Causa raíz:**
- Los comandos de Cyclops guardan `NodePath` en vez de referencias directas
- Si un bloque se mueve/renombra entre undo y redo, el path cambia
- Resultado: undo "no hace nada" o crashea

---

## 2. SOLUCIONES PROPUESTAS (Post-Análisis Técnico)

### ✅ FASE 1: Grid Nativo de Godot (SIN crear grid propio)

**Decisión:** No crear nuestro propio grid. Usar el de Godot.

**Problema:** El grid de Godot solo aparece cuando seleccionas un nodo 3D normal.

**Solución:** Hacer que CyclopsBlocks se comporte como un nodo 3D seleccionable:
- No requiere cambios de código
- El grid aparece automáticamente cuando hay un nodo 3D seleccionado
- Documentar al usuario que debe tener activado el grid en Godot

**Para mejorar visibilidad:**
- Añadir un nodo auxiliar invisible dentro de CyclopsBlocks que fuerce la selección
- O: usar `EditorNode3DGizmoPlugin` para dibujar líneas de referencia

---

### ✅ FASE 2: Unificar Herramientas de Creación

**Problema:** 5 botones separados para crear formas.

**Solución rápida (4-6h):**
Crear `ToolCreate` con dropdown de formas:

```gdscript
# addons/cyclops_level_builder/tools/tool_create.gd
@tool
extends CyclopsTool
class_name ToolCreate

enum ShapeType { BLOCK, CYLINDER, PRISM, SPHERE, STAIRS }
var current_shape:ShapeType = ShapeType.BLOCK

func _get_tool_id() -> String:
    return "create"

func _get_tool_name() -> String:
    return "Create Shape"

func _get_tool_icon() -> Texture2D:
    return load("res://addons/cyclops_level_builder/art/icons/box_transform.svg")

func _can_handle_object(node:Node) -> bool:
    # Aceptar CyclopsBlocks (contenedor) y CyclopsBlock
    if node is CyclopsBlocks:
        return true
    return node is CyclopsBlock or node is CyclopsConvexBlock

func _gui_input(viewport_camera:Camera3D, event:InputEvent) -> bool:
    match current_shape:
        ShapeType.BLOCK:
            return _create_block(viewport_camera, event)
        ShapeType.CYLINDER:
            return _create_cylinder(viewport_camera, event)
        ShapeType.PRISM:
            return _create_prism(viewport_camera, event)
        ShapeType.SPHERE:
            return _create_sphere(viewport_camera, event)
        ShapeType.STAIRS:
            return _create_stairs(viewport_camera, event)
    return false

func _create_block(viewport_camera, event):
    # Delegar a la lógica existente de ToolBlock
    pass
```

**UI:** Un solo botón "Create Shape" con un dropdown/OptionButton al lado.

**Archivos a modificar:**
- `gui/menu/editor_toolbar.gd` — Mostrar solo ToolCreate en vez de 5 botones
- `tools/tool_create.gd` — Nueva herramienta unificada (NUEVO)
- `tools/tool_block.gd`, etc. — Marcar `_show_in_toolbar()` como `false`

---

### ✅ FASE 3: Unificar Herramientas de Edición

**Problema:** Face, Edge, Vertex son herramientas separadas.

**Solución rápida (4-6h):**
Crear `ToolEdit` con toggles para modo de edición:

```gdscript
# addons/cyclops_level_builder/tools/tool_edit.gd
@tool
extends ToolEditBase
class_name ToolEdit

enum EditMode { FACE, EDGE, VERTEX }
var edit_mode:EditMode = EditMode.FACE

func _get_tool_id() -> String:
    return "edit"

func _can_handle_object(node:Node) -> bool:
    return node is CyclopsBlock

func _gui_input(viewport_camera:Camera3D, event:InputEvent) -> bool:
    match edit_mode:
        EditMode.FACE:
            return _edit_face(viewport_camera, event)
        EditMode.EDGE:
            return _edit_edge(viewport_camera, event)
        EditMode.VERTEX:
            return _edit_vertex(viewport_camera, event)
    return false
```

**UI:** Un solo botón "Edit" con toggles o tabs: [Face] [Edge] [Vertex].

---

### ✅ FASE 4: Fix de Selección de CyclopsBlocks

**Problema:** Al seleccionar CyclopsBlocks (contenedor), no aparecen herramientas.

**Solución (1-2h):**
Modificar `_can_handle_object` en todas las herramientas de creación:

```gdscript
# En tools/tool_block.gd
func _can_handle_object(node:Node) -> bool:
    # Aceptar CyclopsBlocks para permitir crear bloques nuevos
    if node is CyclopsBlocks:
        return true
    return node is CyclopsBlock or node is CyclopsConvexBlock
```

**Archivos a modificar:**
- `tools/tool_create.gd` (nuevo) — `_can_handle_object`
- `tools/tool_move.gd` — `_can_handle_object` (solo aceptar CyclopsBlock, no CyclopsBlocks)

---

### ⚠️ FASE 5: Mitigar Conflictos de Pivot (NO se puede resolver completamente)

**Problema:** Gizmos de Godot vs Gizmos de Cyclops.

**Limitación técnica:** No hay API para desactivar gizmos nativos de Godot.

**Solución parcial (2-4h):**
1. Documentar al usuario que debe ignorar los gizmos nativos de Godot
2. Añadir overlay visual que indique "Use Cyclops tools, not Godot gizmos"
3. Hacer que los gizmos de Cyclops sean más prominentes (más grandes, más coloridos)

**Workaround:**
- Al seleccionar un CyclopsBlock, mostrar un mensaje en el toolbar: "⚠️ Use Cyclops Move tool, not Godot gizmos"

---

### ⚠️ FASE 6: Fix de Undo (Parcial)

**Problema:** Undo falla con movimientos complejos.

**Limitación técnica:** Requiere refactor grande del sistema de comandos.

**Solución parcial (4-6h):**
1. Fix inmediato: Guardar `WeakRef` en vez de `NodePath` en comandos nuevos
2. Añadir verificación `is_instance_valid()` antes de aplicar undo
3. Documentar que undo puede fallar si se renombran/mueven bloques

```gdscript
# En commands/cyclops_command.gd
class TrackedBlock extends RefCounted:
    var block_ref:WeakRef  # En vez de NodePath
    var path_parent:NodePath
    # ... resto de propiedades
    
    func _init(block:Node3D):
        block_ref = weakref(block)  # Guardar referencia débil
        path_parent = block.get_parent().get_path()
        # ...
```

**Veredicto:** No se puede hacer 100% robusto sin refactor mayor.

---

## 3. NUEVA ARQUITECTURA DE HERRAMIENTAS (Target)

```
Toolbar Cyclops (simplificado)
├── 🟦 Create Shape [dropdown: Block|Cylinder|Prism|Sphere|Stairs]
├── 🔧 Edit [tabs: Face|Edge|Vertex]
├── ✋ Move
├── 🔄 Rotate
├── ✂️ Clip
├── 📋 Duplicate
└── 🎨 Material Brush
```

**De 15+ botones a 7 botones.**

---

## 4. PRIORIDAD ACTUALIZADA

| Prioridad | Mejora | Esfuerzo | Impacto | Viabilidad |
|-----------|--------|----------|---------|------------|
| 🔴 P0 | Unificar herramientas de creación | 4-6h | CRÍTICO | ✅ Fácil |
| 🔴 P0 | Unificar herramientas de edición | 4-6h | CRÍTICO | ✅ Fácil |
| 🔴 P0 | Fix selección CyclopsBlocks | 1-2h | CRÍTICO | ✅ Fácil |
| 🟡 P1 | Grid nativo de Godot | 0h* | Alto | ✅ Ya funciona |
| 🟡 P1 | Fix undo parcial | 4-6h | Alto | ⚠️ Parcial |
| 🟢 P2 | Mitigar conflictos pivot | 2-4h | Medio | ⚠️ Limitado |
| 🔵 P3 | Atajos de teclado | 2h | Bajo | ✅ Fácil |

*Solo requiere documentación

---

## 5. IMPLEMENTACIÓN RECOMENDADA

### Paso 1 (30 min): Fix inmediato de selección
- Modificar `_can_handle_object` en tools de creación para aceptar `CyclopsBlocks`

### Paso 2 (4-6h): Unificar creación
- Crear `ToolCreate` con dropdown
- Ocultar tools individuales del toolbar

### Paso 3 (4-6h): Unificar edición
- Crear `ToolEdit` con modo Face/Edge/Vertex
- Ocultar tools individuales del toolbar

### Paso 4 (1h): Documentar grid
- Explicar al usuario que use el grid nativo de Godot
- Asegurar que CyclopsBlocks es un nodo 3D seleccionable

### Paso 5 (4-6h): Fix undo parcial
- Modificar `CyclopsCommand` para usar `WeakRef`
- Añadir validaciones

---

## 6. DECISIONES CLAVE

### ¿Grid propio o nativo?
**Decisión:** Nativo. No reinventar la rueda.

### ¿Unificar todas las herramientas en una?
**Decisión:** No. Separar en 3 grupos: Crear, Editar, Transformar. Cada grupo es una herramienta.

### ¿Sistema de modos estilo Blender?
**Decisión:** No para v1. Dropdown es suficiente y más simple.

### ¿Fix completo de undo?
**Decisión:** No. Fix parcial que cubra 80% de casos. El refactor completo es riesgoso.

---

*Documento v2.0 — Actualizado tras análisis técnico de limitaciones*
