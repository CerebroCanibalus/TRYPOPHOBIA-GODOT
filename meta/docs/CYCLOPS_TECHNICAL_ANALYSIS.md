# Análisis Técnico — Limitaciones de Plugins Godot y Mejoras Posibles para Cyclops

**Estado:** Investigación completada | **Prioridad:** ALTA

---

## 1. LIMITACIONES TÉCNICAS DE EDITORPLUGIN (Godot 4.6)

### 1.1 Grid Nativo de Godot
**¿Podemos usarlo?** NO directamente.

**Problema:** El grid del viewport 3D de Godot NO tiene API pública para plugins. Es renderizado internamente por el engine y no expone:
- Configuración de tamaño de celda
- Visibilidad toggle desde plugin
- Eventos de snapping al grid

**Alternativas:**
- Dibujar grid propio encima del viewport (como propuse antes) — **POSIBLE pero innecesario**
- Usar `EditorNode3DGizmoPlugin` para dibujar líneas — **POSIBLE**
- Aprovechar que Godot ya muestra grid cuando seleccionas un nodo 3D — **YA FUNCIONA**

**Veredicto:** Dibujar nuestro propio grid es reinventar la rueda. Mejor solución: cuando Cyclops está activo, seleccionar automáticamente un nodo auxiliar invisible para que Godot muestre SU grid.

### 1.2 Sistema de Undo/Redo
**Problema:** Cyclops usa `EditorUndoRedoManager` pero con un sistema de comandos custom (`CyclopsCommand`). Esto causa:

```gdscript
# Cyclops hace esto:
undo_manager.create_action(command_name, UndoRedo.MERGE_DISABLE)
undo_manager.add_do_method(self, "do_it")
undo_manager.add_undo_method(self, "undo_it")
undo_manager.commit_action()
```

**Limitación:** Los métodos `do_it()` y `undo_it()` operan sobre los nodos `CyclopsBlock` directamente. Si el nodo se destruye o su path cambia entre undo y redo, falla silenciosamente.

**Por qué falla el undo en Cyclops:**
1. Los comandos guardan `NodePath` a los bloques
2. Si el bloque se mueve de padre o se renombra, el path cambia
3. El comando intenta operar sobre un nodo que ya no existe en ese path
4. Resultado: undo "no hace nada" o crashea

**¿Podemos arreglarlo?** Sí, pero requiere refactor grande:
- Guardar referencias directas (weak_ref) en vez de NodePath
- Invalidar comandos cuando se destruye un bloque
- Implementar sistema de "journal" para transacciones

**Esferzo estimado:** 8-12 horas.

### 1.3 Sistema de Transformación (Pivot Conflict)
**Problema:** Godot tiene su propio sistema de gizmos (flechas azul/roja/verde) para mover/rotar/escalar nodos. Cyclops tiene el SUYO propio.

**Conflicto:**
- Seleccionas un CyclopsBlock → Godot muestra sus gizmos nativos
- Activas herramienta Move de Cyclops → aparecen gizmos de Cyclops
- Ahora hay DOS sistemas de transformación superpuestos
- Si usas los de Godot, rompes la mesh de Cyclops
- Si usas los de Cyclops, el usuario se confunde

**¿Podemos desactivar los gizmos nativos de Godot?**
```gdscript
# En teoría sí, pero no hay API directa:
# No existe "EditorInterface.disable_native_gizmos()"
```

**Workaround posible:**
- Crear un `EditorNode3DGizmoPlugin` que deshabilite los gizmos para CyclopsBlock
- O: hacer que CyclopsBlock no sea un Node3D directamente (imposible, necesita transform)

**Veredicto:** El conflicto de pivot es inherentemente difícil de resolver sin cambios en Godot engine.

### 1.4 Unificación de Herramientas
**Problema:** Tienes 5 herramientas de creación (Block, Cylinder, Prism, Sphere, Stairs) + 3 de edición (Face, Edge, Vertex) + Move + Rotate + etc.

**¿Podemos unificarlas?**

**Opción A: Una sola herramienta con sub-menú**
- Crear `ToolCreate` que tenga un dropdown para elegir forma
- Internamente delegue a los comandos existentes
- **POSIBLE**, esfuerzo medio (4-6h)

**Opción B: Sistema de "Modos" estilo Blender**
- 1 tecla para cambiar entre modo Crear / Editar / Seleccionar
- En modo Crear: clic = crear bloque por defecto, Shift+clic = elegir forma
- **POSIBLE**, esfuerzo alto (8-12h)

**Opción C: Eliminar herramientas y hacer todo con el Inspector**
- Seleccionas "Crear bloque" en un menú del dock
- Configuras parámetros en el Inspector
- Clic en viewport = colocar con esos parámetros
- **POSIBLE**, cambia completamente el workflow

---

## 2. ANÁLISIS DE MEJORAS PROPUESTAS

### 2.1 "Grid nativo de Godot es suficiente"
**Estado:** Parcialmente cierto.

**Problema:** El grid de Godot solo aparece cuando:
1. Estás en el viewport 3D
2. Tienes seleccionado un nodo 3D
3. La vista no está en modo "perspectiva libre"

**Mejora propuesta:** En vez de dibujar grid propio, asegurar que Godot SIEMPRE muestre su grid cuando Cyclops está activo.

```gdscript
# En cyclops_level_builder.gd::update_activation()
# Hacer que el viewport muestre grid:
func ensure_grid_visible():
    var settings = EditorInterface.get_editor_settings()
    settings.set_setting("editors/3d/grid_visible", true)
    # NOTA: Esto afecta globalmente, no solo a Cyclops
```

**Limitación:** No hay API para "mostrar grid solo para este plugin". Es global.

**Veredicto:** Aceptar que el grid de Godot es el que hay. Documentar que el usuario debe tenerlo activado.

### 2.2 "Funciones de edición deberían estar centralizadas"
**Estado:** Cierto, pero requiere refactor grande.

**Arquitectura actual:**
```
CyclopsTool (base)
├── ToolBlock (crea bloques)
├── ToolCylinder (crea cilindros)
├── ToolEditFace (mueve caras)
├── ToolEditVertex (mueve vértices)
├── ToolMove (mueve bloques)
└── etc.
```

**Problema:** Cada herramienta es una clase separada con su propio estado, input handling, y lógica de undo.

**Arquitectura ideal:**
```
ToolUnified
├── Modo: CREAR
│   └── Forma: Block | Cylinder | Prism | etc.
├── Modo: EDITAR
│   └── Sub-modo: Face | Edge | Vertex | Block
└── Modo: TRANSFORMAR
    └── Sub-modo: Move | Rotate | Scale
```

**¿Es posible?** Sí, pero:
1. Requiere refactorizar 15+ archivos
2. Los comandos de undo existentes asumen herramientas separadas
3. El toolbar actual se genera dinámicamente desde la lista de herramientas

**Esferzo:** 12-16 horas.

---

## 3. PROBLEMAS CONCRETOS Y SOLUCIONES

### 3.1 Herramientas dispersas
**Problema:** Block, Cylinder, Prism, Sphere, Stairs son 5 botones separados.

**Solución rápida (2h):**
Crear una herramienta "Create" con menú desplegable:
```gdscript
class_name ToolCreate
extends CyclopsTool

enum ShapeType { BLOCK, CYLINDER, PRISM, SPHERE, STAIRS }
var current_shape:ShapeType = ShapeType.BLOCK

func _gui_input(viewport_camera, event):
    # Delegar al comando correspondiente según current_shape
    match current_shape:
        ShapeType.BLOCK: return create_block(viewport_camera, event)
        ShapeType.CYLINDER: return create_cylinder(viewport_camera, event)
        # etc.
```

**UI:** Un solo botón en el toolbar con dropdown/popup para elegir forma.

### 3.2 Conflictos de Pivot
**Problema:** Gizmos de Godot vs Gizmos de Cyclops.

**Solución (4h):**
Desactivar la selección nativa de Godot para CyclopsBlock y usar selección custom:

```gdscript
# En cyclops_level_builder.gd::_handles()
func _handles(object:Object):
    if object is CyclopsBlock:
        # Desactivar gizmos nativos temporalmente
        return true
    return object is CyclopsBlocks

# En tool_move.gd, implementar gizmo propio que reemplace al de Godot
```

**Limitación:** No podemos completamente desactivar los gizmos nativos, pero podemos hacer que Cyclops los ignore.

### 3.3 Undo roto
**Problema:** Undo no funciona bien con movimientos complejos.

**Solución (8h):**
Refactorizar `CyclopsCommand` para usar referencias en vez de NodePath:

```gdscript
class_name CyclopsCommandV2
extends RefCounted

# En vez de:
var path:NodePath

# Usar:
var block_ref:WeakRef  # weak_ref al nodo
var block_data:Dictionary  # backup de datos por si el nodo muere

func do_it():
    var block = block_ref.get_ref()
    if !block:
        # Recrear nodo si fue eliminado
        block = recreate_block_from_data()
    apply_changes(block)
```

---

## 4. RECOMENDACIONES ESTRATÉGICAS

### Opción A: Refactor menor (recomendada para corto plazo)
**Esferzo:** 8-12 horas | **Impacto:** Alto

1. **Unificar herramientas de creación** en una sola con dropdown
2. **Unificar herramientas de edición** (Face/Edge/Vertex) en modo "Edit" con toggles
3. **Fix selección de CyclopsBlocks** para mostrar herramientas
4. **Documentar** que se use el grid nativo de Godot
5. **Fix undo** para operaciones simples (mover bloque)

### Opción B: Refactor mayor (a largo plazo)
**Esferzo:** 30-40 horas | **Impacto:** Muy alto

1. Reescribir arquitectura de herramientas como sistema de modos
2. Implementar sistema de undo robusto con journaling
3. Crear gizmos propios que reemplacen completamente los de Godot
4. Implementar grid propio integrado con snapping

### Opción C: Alternativa — No usar Cyclops
**Opciones:**
- **TrenchBroom + importador:** Más estable, pero requiere export/import
- **GridMap nativo de Godot:** Simple pero limitado a voxels
- **CSG nativo de Godot:** Integrado pero menos potente que Cyclops
- **Blender + importación:** Gold standard, pero requiere salir de Godot

**Veredicto:** Para tu caso (fixed maps, estilo semi-Minecraft), Cyclops sigue siendo la mejor opción a pesar de los bugs. Con refactor menor (Opción A) se vuelve usable.

---

## 5. DECISIONES PENDIENTES

| Decisión | Opción A (Rápido) | Opción B (Completo) |
|----------|-------------------|---------------------|
| Grid | Usar nativo de Godot | Implementar propio |
| Herramientas | Dropdown unificado | Sistema de modos estilo Blender |
| Undo | Fix parcial | Refactor completo |
| Pivot | Convivir con Godot | Gizmos propios |
| Esferzo | 8-12h | 30-40h |

---

## 6. CONCLUSIÓN

**Sí se pueden mejorar todas las cosas que mencionaste**, pero con diferentes niveles de esfuerzo:

- **Grid:** No hace falta hacer uno propio, usar el de Godot ✅
- **Herramientas unificadas:** Posible con refactor moderado ✅
- **Undo:** Arreglable pero requiere cambios profundos ⚠️
- **Pivot:** Difícil de resolver completamente sin cambios en Godot engine ❌

**Recomendación:** Implementar Opción A (refactor menor) para hacer Cyclops usable ahora, y considerar Opción B solo si el equipo crece o el proyecto lo requiere.

---

*Documento v1.0 — Análisis técnico de limitaciones y mejoras*
