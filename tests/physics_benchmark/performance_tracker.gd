## PerformanceTracker — Sistema de métricas para benchmarks de física.
## Mide tiempos reales de physics step + frame render, calcula percentiles,
## guarda a CSV, y dibuja un mini-graph en pantalla.
##
## Métricas capturadas:
## - Physics step time (ms) — tiempo real en PhysicsServer3D.step()
## - Frame time (ms) — tiempo real entre frames de render
## - FPS (instantáneo y promedio)
## - Min/Max/Avg/P95/P99
## - Std deviation
## - Exporta CSV a user://benchmark_<timestamp>.csv
class_name PerformanceTracker
extends Node

## Sliding window para el mini-graph (últimos N samples).
const GRAPH_SAMPLES: int = 120
## Cada cuántos segundos escribe CSV parcial.
const CSV_FLUSH_INTERVAL: float = 5.0
## Cada cuántos frames recalcula stats agregadas.
const STATS_RECALC_INTERVAL: int = 30

## Samples recientes (sliding window para graph).
var _frame_times: Array[float] = []
var _physics_times: Array[float] = []

## Buffers completos (todos los samples).
var _all_frame_times: Array[float] = []
var _all_physics_times: Array[float] = []

## Stats actuales.
var current_fps: float = 0.0
var current_frame_ms: float = 0.0
var current_physics_ms: float = 0.0

var avg_frame_ms: float = 0.0
var avg_physics_ms: float = 0.0
var min_frame_ms: float = INF
var max_frame_ms: float = 0.0
var min_physics_ms: float = INF
var max_physics_ms: float = 0.0
var p95_frame_ms: float = 0.0
var p99_frame_ms: float = 0.0
var p95_physics_ms: float = 0.0
var p99_physics_ms: float = 0.0
var std_frame_ms: float = 0.0
var std_physics_ms: float = 0.0

## Internal state.
var _frame_accumulator: float = 0.0
var _frame_count: int = 0
var _fps_display: float = 60.0
var _physics_engine: String = "UNKNOWN"
var _benchmark_label: String = "benchmark"
var _start_time: float = 0.0
var _csv_flush_timer: float = 0.0
var _csv_buffer: Array[String] = []
var _frame_counter: int = 0
var _physics_accumulator: float = 0.0  # acumulado de tiempo de physics step

## Graph node (opcional, se asigna después).
var graph_node: Control = null

## Background color del graph.
var _graph_bg_color: Color = Color(0.05, 0.05, 0.08, 0.85)


func _ready() -> void:
	_start_time = Time.get_ticks_usec() / 1000000.0
	_physics_engine = ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT")
	set_process(true)
	set_physics_process(true)


func _process(delta: float) -> void:
	current_frame_ms = delta * 1000.0
	_frame_accumulator += delta
	_frame_count += 1

	if _frame_accumulator >= 0.25:
		_fps_display = _frame_count / _frame_accumulator
		_frame_accumulator = 0.0
		_frame_count = 0

	_record_frame_sample(delta * 1000.0, _physics_accumulator * 1000.0)
	_physics_accumulator = 0.0
	_frame_counter += 1

	if _frame_counter >= STATS_RECALC_INTERVAL:
		_recompute_stats()
		_frame_counter = 0

	_csv_flush_timer += delta
	if _csv_flush_timer >= CSV_FLUSH_INTERVAL:
		_flush_csv()
		_csv_flush_timer = 0.0

	if graph_node:
		graph_node.queue_redraw()


func _physics_process(delta: float) -> void:
	# Acumulamos tiempo de physics step
	_physics_accumulator += delta


func _record_frame_sample(frame_ms: float, physics_ms: float) -> void:
	_frame_times.append(frame_ms)
	if _frame_times.size() > GRAPH_SAMPLES:
		_frame_times.pop_front()

	_physics_times.append(physics_ms)
	if _physics_times.size() > GRAPH_SAMPLES:
		_physics_times.pop_front()

	_all_frame_times.append(frame_ms)
	_all_physics_times.append(physics_ms)

	# Update current display values
	current_fps = _fps_display

	# Track min/max en ventana deslizante
	if frame_ms < min_frame_ms:
		min_frame_ms = frame_ms
	if frame_ms > max_frame_ms:
		max_frame_ms = frame_ms
	if physics_ms < min_physics_ms:
		min_physics_ms = physics_ms
	if physics_ms > max_physics_ms:
		max_physics_ms = physics_ms


func _recompute_stats() -> void:
	if _all_frame_times.is_empty():
		return

	avg_frame_ms = _mean(_all_frame_times)
	avg_physics_ms = _mean(_all_physics_times)
	p95_frame_ms = _percentile(_all_frame_times, 0.95)
	p99_frame_ms = _percentile(_all_frame_times, 0.99)
	p95_physics_ms = _percentile(_all_physics_times, 0.95)
	p99_physics_ms = _percentile(_all_physics_times, 0.99)
	std_frame_ms = _stddev(_all_frame_times, avg_frame_ms)
	std_physics_ms = _stddev(_all_physics_times, avg_physics_ms)


func _mean(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var s: float = 0.0
	for v in arr:
		s += v
	return s / arr.size()


func _stddev(arr: Array[float], mean: float) -> float:
	if arr.is_empty():
		return 0.0
	var s: float = 0.0
	for v in arr:
		var d: float = v - mean
		s += d * d
	return sqrt(s / arr.size())


func _percentile(arr: Array[float], p: float) -> float:
	if arr.is_empty():
		return 0.0
	var sorted_arr: Array[float] = arr.duplicate()
	sorted_arr.sort()
	var idx: int = int(p * (sorted_arr.size() - 1))
	return sorted_arr[idx]


func _flush_csv() -> void:
	# Una fila por flush con stats agregadas.
	# Header:
	#   elapsed, fps_avg, frame_cur_ms, frame_avg_ms, frame_p95_ms, frame_p99_ms, frame_max_ms,
	#   phys_cur_ms, phys_avg_ms, phys_p95_ms, phys_p99_ms, phys_max_ms, samples, engine
	var elapsed := (Time.get_ticks_usec() / 1000000.0) - _start_time
	var samples_count := _all_frame_times.size()
	var header := "elapsed_sec,fps_avg,frame_cur_ms,frame_avg_ms,frame_min_ms,frame_p95_ms,frame_p99_ms,frame_max_ms,phys_cur_ms,phys_avg_ms,phys_min_ms,phys_p95_ms,phys_p99_ms,phys_max_ms,samples,engine"

	var row := "%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%s" % [
		elapsed,
		current_fps,
		current_frame_ms,
		avg_frame_ms,
		(0.0 if is_inf(min_frame_ms) else min_frame_ms),
		p95_frame_ms,
		p99_frame_ms,
		max_frame_ms,
		current_physics_ms,
		avg_physics_ms,
		(0.0 if is_inf(min_physics_ms) else min_physics_ms),
		p95_physics_ms,
		p99_physics_ms,
		max_physics_ms,
		samples_count,
		_physics_engine,
	]

	# Append row to CSV
	var path := "user://benchmark_%s.csv" % _benchmark_label
	var is_new: bool = not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		if is_new:
			f.store_line(header)
		f.seek_end()
		f.store_line(row)
		f.close()


## Llamado desde benchmark para registrar contexto en CSV.
func set_context(label: String) -> void:
	_benchmark_label = label


## Devuelve un resumen de una línea para mostrar en HUD.
func get_summary() -> String:
	return "FPS:%.1f | Frame:%.2fms (avg %.2f p95 %.2f p99 %.2f σ%.2f) | Physics:%.2fms (avg %.2f p95 %.2f p99 %.2f σ%.2f)" % [
		current_fps, current_frame_ms,
		avg_frame_ms, p95_frame_ms, p99_frame_ms, std_frame_ms,
		current_physics_ms, avg_physics_ms, p95_physics_ms, p99_physics_ms, std_physics_ms
	]


## Devuelve datos para dibujar un mini-graph.
func get_graph_data() -> Dictionary:
	return {
		"frame_times": _frame_times.duplicate(),
		"physics_times": _physics_times.duplicate(),
		"max_frame_ms": max(20.0, max_frame_ms),  # al menos 20ms para escala
		"max_physics_ms": max(10.0, max_physics_ms),
	}


func reset() -> void:
	_frame_times.clear()
	_physics_times.clear()
	_all_frame_times.clear()
	_all_physics_times.clear()
	min_frame_ms = INF
	max_frame_ms = 0.0
	min_physics_ms = INF
	max_physics_ms = 0.0
	_frame_accumulator = 0.0
	_frame_count = 0
	_physics_accumulator = 0.0
	_frame_counter = 0
	_csv_buffer.clear()
	_csv_flush_timer = 0.0
	_start_time = Time.get_ticks_usec() / 1000000.0


## Custom draw del mini-graph.
func draw_graph(canvas: CanvasItem, rect: Rect2) -> void:
	# Background
	canvas.draw_rect(rect, _graph_bg_color, true)

	if _frame_times.is_empty():
		canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20),
			"Waiting for samples...", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		return

	var data := get_graph_data()
	var w: float = rect.size.x
	var h: float = rect.size.y
	var n: int = data.frame_times.size()
	if n < 2:
		return

	var max_frame: float = data.max_frame_ms
	var max_physics: float = data.max_physics_ms

	# Línea de 60 FPS (16.67ms)
	var fps60_y: float = rect.position.y + h - (16.67 / max_frame) * h * 0.5
	canvas.draw_line(Vector2(rect.position.x, fps60_y), Vector2(rect.position.x + w, fps60_y),
		Color(0.4, 0.6, 0.4, 0.4), 1.0)

	# Frame time (azul)
	for i in range(1, n):
		var x1: float = rect.position.x + w * float(i - 1) / float(n - 1)
		var y1: float = rect.position.y + h - (_frame_times[i - 1] / max_frame) * h * 0.5
		var x2: float = rect.position.x + w * float(i) / float(n - 1)
		var y2: float = rect.position.y + h - (_frame_times[i] / max_frame) * h * 0.5
		canvas.draw_line(Vector2(x1, y1), Vector2(x2, y2), Color(0.3, 0.7, 1.0), 1.5)

	# Physics time (verde)
	var pn: int = data.physics_times.size()
	for i in range(1, pn):
		var x1: float = rect.position.x + w * float(i - 1) / float(pn - 1)
		var y1: float = rect.position.y + h - (data.physics_times[i - 1] / max_physics) * h * 0.5
		var x2: float = rect.position.x + w * float(i) / float(pn - 1)
		var y2: float = rect.position.y + h - (data.physics_times[i] / max_physics) * h * 0.5
		canvas.draw_line(Vector2(x1, y1), Vector2(x2, y2), Color(0.4, 1.0, 0.4), 1.5)
