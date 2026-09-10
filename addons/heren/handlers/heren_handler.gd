@tool
extends Node

# Heren MCP v4 - Contrato base para handlers (Fase C4).
# Todos los handlers extienden esta clase para garantizar el contrato mínimo:
#   set_editor_plugin(plugin)  — inyecta el EditorPlugin
#   _editor_interface()        — acceso a EditorInterface
#   _args_dict(args, key)      — lee un dict desde args (string JSON o dict)
# Los handlers pueden sobrescribir set_editor_plugin para guardar extras
# (ej. _undo_redo) llamando super.set_editor_plugin(plugin).

const HerenError := preload("heren_error.gd")

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


## Lee `key` de args como Dictionary. Acepta dict directo o string JSON.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


## Error canónico (shape estándar, Fase C6). Usar en handlers nuevos/migrados.
func _err(msg: String) -> Dictionary:
	return HerenError.err(msg)


# ---------------------------------------------------------------- W0: safety
# §0.12 W0: el agente NO puede destruir infraestructura crítica, y toda
# operación destructiva deja snapshot en .heren/backup/ antes de tocar disco.
# Statics: reutilizables desde cualquier handler sin duplicación.

## Prefijos protegidos (normalizados sin "res://", en minúsculas).
const PROTECTED_PREFIXES: Array[String] = [
	"addons/heren/",  # el propio plugin — el agente puede matarse a sí mismo
	"project.godot",  # config del proyecto
	".git/",  # repo del usuario
	".godot/",  # cache de Godot
	"export_presets.cfg",
]


## Devuelve "" si el path está permitido, o el motivo del bloqueo.
static func protected_reason(res_path: String) -> String:
	var p := res_path.replace("\\", "/").to_lower()
	if p.begins_with("res://"):
		p = p.substr(6)
	for prefix in PROTECTED_PREFIXES:
		if p.begins_with(prefix):
			return "protected_path: %s — '%s' es infraestructura protegida (W0)" % [res_path, prefix]
	return ""


## Crea el directorio padre de path (static, usable desde helpers estáticos).
static func ensure_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


## Snapshot-before-save (W0): copia el archivo a .heren/backup/ antes de una
## operación destructiva. Devuelve el path del snapshot, o "" si el archivo
## no existía (crear no necesita snapshot) o falló la copia.
static func snapshot_file(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		return ""
	var backup_dir := "res://.heren/backup/"
	ensure_dir(backup_dir + "snap.tmp")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dest := backup_dir + res_path.get_file() + "." + stamp + ".bak"
	var err := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(res_path),
		ProjectSettings.globalize_path(dest)
	)
	if err != OK:
		return ""
	return dest


## Restaura un snapshot sobre el archivo target (rollback transaccional).
## ei puede ser null (headless/tests) — solo salta el refresh del EFS.
static func restore_snapshot(ei: EditorInterface, snapshot_path: String, target_path: String) -> bool:
	if snapshot_path == "" or not FileAccess.file_exists(snapshot_path):
		return false
	var err := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(snapshot_path),
		ProjectSettings.globalize_path(target_path)
	)
	if err == OK and ei != null:
		var efs: EditorFileSystem = ei.get_resource_filesystem()
		if efs:
			efs.update_file(target_path)
	return err == OK


# ---------------------------------------------------------------- W4-c:
# §0.13 Diagnósticos inline (§0.12 W1 maduró): el validador YA NO devuelve
# `reload_err=43` con un "ver debug/output" — corre un static analyzer sobre
# el source ANTES de reload() y adjunta los hallazgos (línea/columna/mensaje)
# en `parse_hints`. Esto reduce el fix-loop de parse errors de 3 calls
# (validate → debug/output → fix) a 2 (validate con hints → fix).
#
# Cubre los errores más comunes de GDScript parse — los que NO requiere
# hookear stderr (Option B en §0.13). Confianza explícita por regla:
#   - high   = casi seguro que rompe el parse (brackets, indent mix, etc)
#   - medium = heurística razonable, puede haber false positives


## Tipos builtin cuyo shadowing casi siempre es bug.
const _SHADOW_BUILTINS: Array[String] = [
	"int", "float", "bool", "String", "StringName", "NodePath",
	"Array", "Dictionary", "Variant", "Object", "Node", "Resource",
	"Vector2", "Vector3", "Color", "Transform2D", "Transform3D",
	"PackedByteArray", "PackedFloat32Array", "PackedInt32Array",
	"PackedStringArray", "PackedVector2Array", "PackedVector3Array",
]


## Keys/control flow que SIEMPRE requieren ':' al final de su header.
const _COLON_KEYWORDS: Array[String] = ["if", "elif", "for", "while", "match", "class"]


## Quita de una línea: comentario trailing (#...) y strings ("..."/'...').
## Para análisis heurístico es suficiente — no necesitamos tokenización completa.
## 🚨 Importante: hay que trackear el estado string correctamente, sino
## `#` dentro de un string (ej. "color #ff0000") se trata como comentario
## y rompe la heurística downstream (unterminated_string falso positivo).
static func _strip_for_analysis(line: String) -> String:
	var s := ""
	var in_dq := false  # double-quote string
	var in_sq := false  # single-quote string
	var i := 0
	while i < line.length():
		var c := line.substr(i, 1)
		if in_dq:
			if c == "\\" and i + 1 < line.length():
				s += "  "  # escape: saltar siguiente char
				i += 2
				continue
			if c == "\"":
				in_dq = false
				s += " "
				i += 1
				continue
			s += " "  # contenido de string: ignorar para bracket counting
			i += 1
			continue
		if in_sq:
			if c == "\\" and i + 1 < line.length():
				s += "  "
				i += 2
				continue
			if c == "'":
				in_sq = false
				s += " "
				i += 1
				continue
			s += " "
			i += 1
			continue
		# Fuera de string:
		if c == "\"":
			in_dq = true
			s += " "
			i += 1
			continue
		if c == "'":
			in_sq = true
			s += " "
			i += 1
			continue
		if c == "#":
			break  # comentario hasta fin de línea
		s += c
		i += 1
	# Triple-string en una sola línea (raro): eliminar bloques.
	var tq := "\"\"\""
	while s.find(tq) >= 0:
		var a := s.find(tq)
		var b := s.find(tq, a + 3)
		if b < 0:
			break
		s = s.substr(0, a) + " " + s.substr(b + 3)
	return s


## Cuenta paréntesis abiertos/cerrados en una línea (sin strings/comments).
static func _count_brackets(s: String, open_c: String, close_c: String) -> int:
	var opens := 0
	var closes := 0
	for i in range(s.length()):
		var c := s.substr(i, 1)
		if c == open_c:
			opens += 1
		elif c == close_c:
			closes += 1
	return opens - closes  # +n = más abiertos, -n = más cerrados


## Hint helper: añade una entrada solo si no existe ya (deduplica por rule+line).
static func _add_hint(hints: Array[Dictionary], rule: String, line: int, col: int, message: String, confidence: String) -> void:
	for h in hints:
		if h.get("rule", "") == rule and int(h.get("line", -1)) == line:
			return  # dedupe
	hints.append({
		"rule": rule,
		"line": line,
		"col": col,
		"message": message,
		"confidence": confidence,
	})


## STATIC ANALYZER (W4-c): heurística pura sobre el source code.
## Devuelve `parse_hints` con line/col/message por hallazgo.
## NO toca el disco, NO ejecuta reload() — para integrar en cualquier flujo.
static func static_analyze_gdscript(source: String) -> Array[Dictionary]:
	var hints: Array[Dictionary] = []
	var lines := source.split("\n")

	# --- Regla 1: mix tabs/spaces en indent inicial (Godot exige uno) ---
	var seen_tab := false
	var seen_space := false
	var first_indent_line := -1
	for i in range(lines.size()):
		var ln: String = lines[i]
		if ln.length() == 0:
			continue
		var c0 := ln.substr(0, 1)
		if c0 == "\t":
			seen_tab = true
			if first_indent_line < 0:
				first_indent_line = i + 1
		elif c0 == " ":
			seen_space = true
			if first_indent_line < 0:
				first_indent_line = i + 1
	if seen_tab and seen_space:
		_add_hint(hints, "tabs_and_spaces_mixed", first_indent_line, 1,
			"Indent mixes tabs and spaces — Godot requires one style consistently",
			"high")

	# --- Reglas 2-4: brackets desbalanceados por línea ---
	for i in range(lines.size()):
		var raw: String = lines[i]
		var stripped := _strip_for_analysis(raw)
		var paren_diff := _count_brackets(stripped, "(", ")")
		var bracket_diff := _count_brackets(stripped, "[", "]")
		var brace_diff := _count_brackets(stripped, "{", "}")
		if paren_diff != 0:
			_add_hint(hints, "unbalanced_parens", i + 1, 1,
				"Unbalanced '(' on this line (diff=%d) — likely Parse Error" % paren_diff,
				"high")
		if bracket_diff != 0:
			_add_hint(hints, "unbalanced_brackets", i + 1, 1,
				"Unbalanced '[' on this line (diff=%d)" % bracket_diff,
				"high")
		if brace_diff != 0:
			_add_hint(hints, "unbalanced_braces", i + 1, 1,
				"Unbalanced '{' on this line (diff=%d)" % brace_diff,
				"high")

	# --- Regla 5: string sin cerrar (un solo `"` no escapado en una línea) ---
	# Tokenizar la línea trackeando estado de string ("/'/'""" no aplica aquí)
	# y comentario. `#` dentro de string NO debe cortar el análisis.
	# La métrica es: contar TODAS las `"` literales (apertura + cierre) fuera
	# de comentario y de escapes. Si impar → unterminated. Si termina con
	# `in_dq=true` (string abierto sin cerrar) → unterminated también.
	for i in range(lines.size()):
		var ln2: String = lines[i]
		var in_dq := false
		var in_sq := false
		var count := 0
		var first_unclosed_pos := -1
		var j := 0
		while j < ln2.length():
			var c := ln2.substr(j, 1)
			if in_dq:
				if c == "\\" and j + 1 < ln2.length():
					j += 2  # skip escape
					continue
				if c == "\"":
					in_dq = false
					count += 1  # cierre también cuenta para paridad
				j += 1
				continue
			if in_sq:
				if c == "\\" and j + 1 < ln2.length():
					j += 2
					continue
				if c == "'":
					in_sq = false
				j += 1
				continue
			# Fuera de string:
			if c == "#":
				break  # comentario: ignorar resto
			if c == "\"":
				count += 1
				if first_unclosed_pos < 0:
					first_unclosed_pos = j
				in_dq = true
				j += 1
				continue
			if c == "'":
				in_sq = true
				j += 1
				continue
			j += 1
		if in_dq or count % 2 == 1:
			var col := first_unclosed_pos + 1 if first_unclosed_pos >= 0 else 1
			_add_hint(hints, "unterminated_string", i + 1, col,
				"Unterminated string — odd quote count (%d) or unclosed \" on this line" % count,
				"high")

	# --- Regla 6: triple-string sin cerrar (""" impares en el archivo) ---
	# Buscamos `"""` que NO esté dentro de otra triple-string.
	# Para no anidar, basta con contar ocurrencias; impar = problema.
	var tq_count := 0
	var k := 0
	while k < source.length() - 2:
		if source.substr(k, 3) == "\"\"\"":
			tq_count += 1
			k += 3
		else:
			k += 1
	if tq_count % 2 == 1:
		_add_hint(hints, "unterminated_triple_string", 1, 1,
			"Triple-quoted string not closed (odd \"\"\" count=%d)" % tq_count,
			"high")

	# --- Regla 7: `func name(...)$` sin ':' al final (definición colgada) ---
	var re_func := RegEx.new()
	re_func.compile("^\\s*func\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\([^)]*\\)\\s*$")
	for i in range(lines.size()):
		if re_func.search(lines[i]) != null:
			_add_hint(hints, "missing_colon_after_func_def", i + 1, 1,
				"Function definition missing ':' at end",
				"medium")

	# --- Regla 8: if/elif/for/while/match/class sin ':' al final ---
	var re_kw := RegEx.new()
	re_kw.compile("^(\\s*)(" + "|".join(_COLON_KEYWORDS) + ")\\b.*[^:}\\s]\\s*$")
	for i in range(lines.size()):
		var m := re_kw.search(lines[i])
		if m == null:
			continue
		# Excluir líneas que sean sólo `class Foo:` (terminan en `:`)
		var trimmed := lines[i].strip_edges()
		if trimmed.ends_with(":"):
			continue
		# Excluir keywords seguidas de `:` (caso `match X:`)
		_add_hint(hints, "missing_colon_after_keyword", i + 1, 1,
			"Keyword line missing trailing ':' — likely Parse Error",
			"medium")

	# --- Regla 9: @export const (Godot lo rechaza) ---
	var re_export_const := RegEx.new()
	re_export_const.compile("^\\s*@export\\s+const\\b")
	for i in range(lines.size()):
		if re_export_const.search(lines[i]) != null:
			_add_hint(hints, "export_on_const", i + 1, 1,
				"@export const is not allowed in GDScript — use 'var'",
				"high")

	# --- Regla 10: await pegado a identificador (typo común) ---
	var re_await_stuck := RegEx.new()
	re_await_stuck.compile("\\bawait(func|var|for|if|return|class|while|elif|else|true|false|null)\\b")
	for i in range(lines.size()):
		if re_await_stuck.search(lines[i]) != null:
			_add_hint(hints, "await_stuck_to_identifier", i + 1, 1,
				"'await' stuck to identifier — missing space (likely typo)",
				"high")

	# --- Regla 11: var shadow builtin ---
	var re_shadow := RegEx.new()
	re_shadow.compile("^\\s*var\\s+(" + "|".join(_SHADOW_BUILTINS) + ")\\s*[=:]")
	for i in range(lines.size()):
		if re_shadow.search(lines[i]) != null:
			_add_hint(hints, "shadow_builtin_var", i + 1, 1,
				"Variable name shadows a built-in type — likely Parse Error or shadow bug",
				"high")

	# --- Regla 12: class_name duplicado en el mismo archivo ---
	var re_cn := RegEx.new()
	re_cn.compile("^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var seen_names: Dictionary = {}
	for i in range(lines.size()):
		var m2 := re_cn.search(lines[i])
		if m2 == null:
			continue
		var nm: String = m2.get_string(1)
		if seen_names.has(nm):
			var first_line: int = int(seen_names[nm])
			_add_hint(hints, "class_name_duplicate_in_file", i + 1, 1,
				"'class_name %s' already declared on line %d — Parse Error" % [nm, first_line],
				"high")
		else:
			seen_names[nm] = i + 1

	# --- Regla 13: await a nivel top-level (heurístico: indent 0 sin func antecesor) ---
	# Solo señalamos si la línea tiene await literal al inicio — la heurística
	# "indent 0" es ambigua con código indentado correctamente, así que la
	# omitimos en v1 para evitar false positives. Dejamos el slot por si
	# en el futuro tenemos el AST del parser.

	return hints


## SCRIPT DIAGNOSTICS (W1 maduró → W4-c): unifica load + refresh + analyze
## + reload. Devuelve el shape canónico con `parse_hints` para fix-loop de
## 2 calls (validate → fix) en vez de 3 (validate → debug/output → fix).
##
## Shape:
##   válido:    { valid:true,  reload_err:0, script_path, can_instance, warnings:[...] }
##   roto:      { valid:false, reload_err:43, script_path, parse_hints:[...], hint:str }
##   no_script: { valid:false, error:str }
##
## Reemplaza al antiguo _script_diagnostics() de resource_handlers.gd (DRY).
static func script_diagnostics(script_path: String) -> Dictionary:
	if script_path == "":
		return {"valid": false, "error": "script_path required"}
	if not FileAccess.file_exists(script_path):
		return {"valid": false, "error": "not_found: " + script_path}

	# 1) Leer source desde disco PRIMERO — funciona incluso cuando load()
	# falla (parse error evita que ResourceLoader cache el script).
	var fresh := FileAccess.get_file_as_string(script_path)
	if fresh == "":
		return {"valid": false, "error": "empty_or_unreadable: " + script_path}

	# 2) Static analyze sobre el source — hints disponibles ANTES de load().
	var hints := static_analyze_gdscript(fresh)

	# 3) Intentar load() — si falla (parse error muy temprano), devolvemos
	# hints en el mismo shape. Esto evita que el fix-loop vuelva a 3 calls
	# cuando load() revienta antes de llegar al reload().
	if not ResourceLoader.exists(script_path):
		return {"valid": false, "error": "not_found: " + script_path}
	var res: Resource = load(script_path)
	if res == null or not (res is Script):
		# 🚨 load() falla → casi siempre ERR_PARSE_ERROR. Devolver shape
		# unificado con hints para que el agente tenga algo accionable.
		return {
			"valid": false,
			"reload_err": ERR_PARSE_ERROR,
			"script_path": script_path,
			"error": "script_has_errors reload_err=%d (load failed)" % ERR_PARSE_ERROR,
			"parse_hints": hints,
			"hint": "los parse_hints apuntan a líneas problemáticas; corrige con resource/edit_script sobre el mismo script_path",
		}
	var gd: Script = res as Script

	# 4) Cache de recursos: load() devuelve el GDScript CACHED con source VIEJO.
	# Refrescar source desde disco antes de reload().
	if fresh != "":
		gd.source_code = fresh

	# 5) reload() — devuelve ERR_PARSE_ERROR (43) si hay errores sintácticos
	# que la heurística no detectó.
	var reload_err: int = gd.reload()
	if reload_err != OK:
		return {
			"valid": false,
			"reload_err": reload_err,
			"script_path": script_path,
			"error": "script_has_errors reload_err=%d" % reload_err,
			"parse_hints": hints,
			"hint": "los parse_hints apuntan a líneas problemáticas; corrige con resource/edit_script sobre el mismo script_path",
		}

	# Válido. Los hints pasan a `warnings` (no bloquean) si la heurística
	# señaló algo (ej. shadow_builtin_var — válido pero sospechoso).
	return {
		"valid": true,
		"reload_err": OK,
		"script_path": script_path,
		"can_instance": gd.can_instantiate(),
		"warnings": hints,
	}
