# Heren MCP — Guía para agentes

Lee esto antes de tocar escenas. Las tool schemas son la fuente de verdad de args; esta guía es el workflow.

## Regla de oro: `scene_script` primero

Para CUALQUIER edición de escena más allá de ops atómicas simples (`node/add`, `set_prop`, `remove`), escribe un **worker GDScript** con `scene_script`:

- Contrato: `@tool` + `extends RefCounted` + `func run(ctx) -> void` (fail-fast si no se cumple).
- ctx: `get_scene_root` / `get_node_or_null` / `own` / `instance_scene` / `template` / `coords` / `find_nodes_by_name` / `ensure_unique_child_name` / `remove_node` / `clear_children` / `log` / `error` / `mark_modified` / `output`.
- Save transaccional: SOLO se guarda si llamas `ctx.mark_modified()`. Un worker que aborta a mitad no toca el disco.
- Modo `inspect`: read-only detached, nunca guarda.
- **Retry**: si el worker falla, parcha el MISMO `script_path` (con `resource/edit_script`) y re-run. No reenvíes todo el `code`.

## Reglas del worker (evitan fallos silenciosos)

1. **Verifica la API antes de usarla**: `node_query class_info` (o `has_method()`). Las APIs adivinadas abortan el worker SILENCIOSAMENTE a mitad de ejecución. Ejemplos reales: `Skeleton3D.add_bones()` NO existe en 4.7 (usar `add_bone`); `AnimationNodeBlendSpace3D` NO existe; `Light3D.light_enabled` NO existe.
2. **Nombres**: `ctx.ensure_unique_child_name(parent, nombre)` ANTES de `add_child` — un nombre duplicado se convierte en `@Class@ID`.
3. **NUNCA** hagas `own()` de un nodo dentro de una instancia PackedScene — se rechaza (aplanaría la instancia). Usa `ctx.instance_scene(parent, path, nombre)` o `ctx.template(nombre, params, parent)`.
4. **El grafo NO es el juego corriendo**: timers, `_process`, `get_tree()`, `get_path()`, `look_at()` fallan o se comportan distinto en detached. Orienta con `look_at_from_position()` o asigna `rotation`/`basis`.
5. **Tipado explícito**: `var x: float = ...` — la inferencia sobre Variant puede bloquear el parse-check.
6. **`ctx.coords(node, tier)`**: posición/bbox/dynamic state (animación, skeleton, luces, cámara) dentro del worker — verificación espacial sin llamadas extra.

## Percepción (jerarquía de costo)

- Toda mutación devuelve **coords proactivas** — no llames inspect tras cada edit.
- `visual/summary` = snapshot estructural con warnings; `visual/spatial` = overlaps/distance/neighbors/bounds.
- `node_query props_diff` = solo las props que difieren del default de la clase (tokens mínimos).

## Validación

- `resource/create_script` y `edit_script` devuelven `diagnostics` inline — corrige antes de continuar.
- `scene/validate` = QA estructural dual-engine. Los warnings `missing_material`/`missing_texture` son reales: revísalos.
- `scene_script` ya valida post-save automáticamente; no repitas la validación.

## Límites

- **Paths protegidos (W0)**: `addons/heren/**`, `project.godot`, `.git/**`, `.godot/**`, `export_presets.cfg` — no se pueden borrar/sobrescribir vía resource.
- **EFS en frío**: assets recién copiados al proyecto son invisibles hasta que el editor escanea — espera unos segundos tras el primer tool call o reintenta.
- Los workers son **editor-time**: el gameplay se verifica con `debug/run_scene` (los runtime probes llegan con W5).
- Los workers NO son sandbox: no toques filesystem/OS fuera de lo pedido.
- Guarda workers reutilizables en `res://.heren/scripts/` (ver listable con `scene_script list`) — memoria persistente del proyecto.

## Planning (opcional)

`scene/plan {plan_file}` → `scene/orchestrate` → `scene/validate` → `scene/commit`. Los steps `generic` pasan verbatim a cualquier tool. orchestrate exige que la escena del plan exista (usa `scene/create` primero para escenas nuevas).
