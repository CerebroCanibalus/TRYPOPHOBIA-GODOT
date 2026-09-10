# Heren MCP v4 — Archive de handlers (2026-09-09).

Este directorio contiene handlers que fueron **removidos del toolset** porque
`scene_script` (§0.12 W4) los reemplazó completamente. Se mantienen aquí
como referencia y por si se necesita restaurar alguno en el futuro.

## ¿Por qué se archivaron?

El worker GDScript del agente habla directo con la API de Godot sin pasar por
un traductor (coder.rs + schemas.rs). Para mutaciones complejas (búsqueda en
árbol, ownership transaccional, AnimationTree params, esqueletos 2D/3D, etc.)
un worker es ~10 líneas vs cientos en el handler + schema + dispatcher.

## Estructura

- `animation_tree_handlers.gd` — tree_activate/travel/set_param/get_param/add_blend_node/connect_blend_nodes/set_anim_player + capture_pose + blend_pose + retarget (de animation_handlers.gd original).
- `skeleton_handlers.gd` — TODAS las actions skeleton/* (esqueleto 3D/2D completo).
- `tilemap_handlers.gd` — TODAS las actions tilemap/*.
- `ui_layout_theme_handlers.gd` — ui/layout + ui/theme (de ui_handlers.gd original).
- `shader_ops_handlers.gd` — shader/material + shader/uniform + shader/apply (de shader_handlers.gd original).
- `node_movement_handlers.gd` — node/reorder + node/move + node/set_owner (de node_handlers.gd original).
- `signal_set_script_handlers.gd` — signal/set_script (de signal_handlers.gd original).

## Cómo restaurar una tool

1. Mover el archivo de vuelta a `addons/heren/handlers/`.
2. Restaurar el `preload` + `_X_handlers = X.new() + add_child + register_handler` en `editor_plugin.gd`.
3. Restaurar la(s) entrada(s) en `_routes.gd`.
4. Restaurar el `#[tool]` fn en `server.rs` (desde `crates/heren-server/src/archived_tools.rs`).
5. Restaurar la(s) entrada(s) en `tests/tools_parity.rs::DISPATCH_ROUTES`.
6. Tests: `cargo test` (tools_parity) + `run_tests.gd` (gdscript).
