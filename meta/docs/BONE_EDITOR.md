# Editor de Huesos Procedural — Investigación y Decisión

**Estado:** Investigación completada | **Herramienta seleccionada:** ArmatureEditor | **Prioridad:** MEDIA

---

## 1. Requerimientos del Proyecto

Necesitamos una herramienta que permita:
- ✅ Modificar huesos del personaje directamente en Godot
- ✅ Añadir/eliminar huesos
- ✅ Weight painting (asignar pesos de influencia a vértices)
- ✅ Configurar IK (Inverse Kinematics) para animaciones procedurales
- ✅ Integración con el sistema de animación procedural
- ❌ NO necesitamos un editor de animaciones completo (usaremos animaciones procedurales)

**Contexto:** El personaje Iza ya tiene `Skeleton3D` con `PhysicalBoneSimulator3D`. Necesitamos retocar el rig, añadir huesos para IK, y configurar weight painting para prendas/aditamentos.

---

## 2. Opciones Evaluadas

### 2.1 ArmatureEditor (mishapsi) ⭐ RECOMENDADO

**GitHub:** `mishapsi/ArmatureEditor`

**Descripción:** Addon de Godot 4 para crear y editar jerarquías `Skeleton3D` directamente en el viewport 3D.

**Características:**
- ✅ **Bone authoring:** Crear, renombrar, eliminar huesos
- ✅ **Extrusión interactiva:** Arrastrar en viewport para definir longitud de hueso
- ✅ **Subdividir huesos:** Dividir un hueso en segmentos con redistribución de longitud
- ✅ **Copiar/Pegar:** Copiar huesos con reconstrucción completa del subtree
- ✅ **Multi-selección:** Seleccionar múltiples huesos
- ✅ **Undo/Redo:** Sistema de snapshots integrado
- ✅ **Spring bone chains:** Configurar cadenas de huesos con física (pelo, capas, colas)
- ✅ **Auto-weighting:** Calcular pesos automáticamente para mesh instances
- ✅ **Edit Mode / Pose Mode:** Modificar rest transforms vs pose transforms

**Ventajas:**
- Nativo de Godot, todo dentro del editor
- Diseñado específicamente para Skeleton3D
- Soporte para SpringBoneSimulator3D (Godot 4.5+)
- MIT License (código abierto, modificable)

**Desventajas:**
- Proyecto pequeño (4 estrellas, 1 fork)
- Poco mantenimiento visible (último commit hace tiempo)
- Puede tener bugs o incompatibilidades con Godot 4.6

**Ideal para:** Edición rápida de rigs, ajustes de huesos, weight painting básico

---

### 2.2 Godot 4.6 Nativo (SkeletonModifier3D)

**Descripción:** Godot 4.6 ya tiene IK nativo (FABRIK, TwoBoneIK, CCDIK, etc.) pero NO tiene editor de huesos visual.

**Características:**
- ✅ FABRIK3D, TwoBoneIK3D, LookAtIK3D, etc.
- ✅ SpringBoneSimulator3D
- ✅ Bone constraints
- ❌ **NO editor visual de huesos**
- ❌ **NO weight painting**
- ❌ **NO crear huesos en editor**

**Limitación crítica:** Todo por código. Puedes configurar IK, pero no puedes añadir huesos ni hacer weight painting visual.

**Ideal para:** Configurar IK una vez el rig está listo

---

### 2.3 Blender (Externo)

**Descripción:** Usar Blender para todo el rigging y exportar a Godot.

**Características:**
- ✅ Todo lo que necesitamos y más
- ✅ Editor de huesos profesional
- ✅ Weight painting avanzado
- ✅ Shape keys, constraints, drivers

**Desventajas:**
- ❌ Sale del editor Godot
- ❌ Pipeline más lento (editar en Blender → exportar → importar)
- ❌ Menos iterativo para ajustes rápidos

**Ideal para:** Rigging inicial, modelos nuevos, trabajo pesado

---

## 3. Comparativa

| Característica | ArmatureEditor | Godot Nativo | Blender |
|----------------|----------------|--------------|---------|
| Crear huesos | ✅ Visual | ❌ Código | ✅ Visual |
| Editar huesos | ✅ Visual | ❌ Código | ✅ Visual |
| Eliminar huesos | ✅ | ❌ | ✅ |
| Weight painting | ✅ Básico | ❌ | ✅ Avanzado |
| Spring bones | ✅ | ✅ | ✅ |
| IK setup | ⚠️ Parcial | ✅ Completo | ✅ Completo |
| Iteración rápida | ✅ | ⚠️ | ❌ |
| Dentro de Godot | ✅ | ✅ | ❌ |

---

## 4. Decisión: ArmatureEditor + Godot Nativo (Híbrido)

### Estrategia:

**Para edición de huesos y weight painting:**
- Usar **ArmatureEditor** para ajustes rápidos
- Crear/modificar/eliminar huesos
- Weight painting básico
- Setup de spring bones

**Para IK y animaciones procedurales:**
- Usar **Godot 4.6 nativo** (SkeletonModifier3D)
- FABRIK, TwoBoneIK, etc.
- Configurar en el editor de Godot

**Para rigging complejo desde cero:**
- Usar **Blender** como respaldo
- Exportar FBX/GLTF a Godot

---

## 5. Plan de Implementación

### FASE 1: Instalación y Test

```bash
# Clonar repositorio
git clone https://github.com/mishapsi/ArmatureEditor.git

# Copiar a addons/
cp -r ArmatureEditor/addons/ArmatureEditor addons/

# Activar en Godot: Project > Project Settings > Plugins > Enable Armature Editor
```

**Test inicial:**
- Abrir personaje Iza (`assets/players/iza_rig.tscn`)
- Seleccionar Skeleton3D
- Probar crear un hueso de prueba
- Verificar compatibilidad con Godot 4.6

### FASE 2: Ajustes del Rig Actual

**Tareas:**
1. **Añadir huesos IK:**
   - `IK_Hand_L` / `IK_Hand_R` (targets para manos)
   - `IK_Foot_L` / `IK_Foot_R` (targets para pies)
   - `IK_Head` (target para cabeza)

2. **Configurar cadenas IK:**
   - Brazo: `Shoulder → Arm → Hand` (FABRIK)
   - Pierna: `Hip → Leg → Foot` (TwoBoneIK)
   - Cabeza: `Neck → Head` (LookAtIK)

3. **Spring bones (opcional):**
   - Cabello, capas, colas de enemigos
   - Configurar via ArmatureEditor

### FASE 3: Weight Painting

**Para prendas y aditamentos:**
- Importar mesh de ropa/armadura
- Usar Auto-Weight de ArmatureEditor
- Ajustar manualmente vértices problemáticos
- Verificar deformación en pose mode

### FASE 4: Integración con Animaciones Procedurales

```gdscript
# Ejemplo de configuración post-rigging:
extends Skeleton3D

@onready var fabrik_left_arm = $FABRIK3D_LeftArm
@onready var fabrik_right_arm = $FABRIK3D_RightArm
@onready var two_bone_left_leg = $TwoBoneIK3D_LeftLeg
@onready var two_bone_right_leg = $TwoBoneIK3D_RightLeg

func _ready():
    # Configurar targets
    fabrik_left_arm.target_node = $IKTargets/LeftHand
    fabrik_right_arm.target_node = $IKTargets/RightHand
    two_bone_left_leg.target_node = $IKTargets/LeftFoot
    two_bone_right_leg.target_node = $IKTargets/RightFoot
```

---

## 6. Modificaciones Planificadas a ArmatureEditor

### Mejoras para nuestro proyecto:

1. **Integración con PhysicalBoneSimulator3D:**
   - Botón "Generate Physical Bones" (similar al de Godot nativo)
   - Configurar colliders automáticamente
   - Integrar con ragdoll system

2. **Preset de Humanoide:**
   - Template con estructura ósea estándar
   - Huesos pre-nombrados (hips, spine, chest, neck, head, arm, hand, leg, foot)
   - IK targets pre-configurados

3. **Mirror/Simetría:**
   - Editar hueso izquierdo → reflejar en derecho
   - Útil para rigs simétricos

4. **Visualización mejorada:**
   - Colores por cadena IK
   - Labels de huesos en viewport
   - Visualización de pesos en tiempo real

5. **Export/Import de poses:**
   - Guardar pose como recurso .tres
   - Compartir entre personajes

---

## 7. Roadmap

| Semana | Tarea |
|--------|-------|
| 1 | Instalar ArmatureEditor, testear compatibilidad |
| 2 | Ajustar rig de Iza (añadir huesos IK) |
| 3 | Configurar IK con Godot nativo (FABRIK, TwoBoneIK) |
| 4 | Weight painting para prendas |
| 5 | Integrar con sistema de animación procedural |
| 6 | Polish: presets, visualización, optimización |

---

## 8. Archivos Relacionados del Proyecto

```
assets/players/
├── iza_rig.tscn              # Personaje con Skeleton3D
├── iza_player.gd             # Script del jugador
├── boneinteraction.gd        # SkeletonIK3D (placeholder)
└── skeleton_3d.gd            # Physical bones

# Nuevos archivos (post-implementación):
src/animation/
├── procedural_gait.gd        # Sistema de paso
├── foot_ik_solver.gd         # Solver de pies
├── hand_ik_solver.gd         # Agarre de objetos
└── spine_controller.gd       # Control de columna

addons/armature_editor/
└── (modificado para nuestro pipeline)
```

---

## 9. Consideraciones Técnicas

### Compatibilidad Godot 4.6:
- ArmatureEditor fue diseñado para Godot 4.5+
- SkeletonModifier3D (Godot 4.3+) reemplaza SkeletonIK3D
- Probar y reportar/fixear incompatibilidades si surgen

### Performance:
- IK en Godot 4.6 es muy eficiente
- Spring bones pueden ser costosos si hay muchos
- Limitar a 4-6 cadenas IK por personaje

### Networking (sincronización):
- NO sincronizar huesos individualmente en red
- Sincronizar solo targets de IK (posición/rotación)
- Interpolar poses en cliente

---

*Documento v1.0 — ArmatureEditor seleccionado, plan de implementación definido*
