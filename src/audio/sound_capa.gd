@tool
class_name SoundCapa
extends Resource
## Una capa de un SoundScape: una o varias pistas .ogg que suenan a la vez :v
## con volumen, pitch y fades propios. Es la unidad mínima de modularidad:
## un soundscape se construye apilando capas (viento + motores + agua...).

## Nombre visible en el overlay de debug (F3) :v
@export var nombre: String = ""
## Pistas candidatas de la capa. Si hay varias se elige una al azar :v
## (AudioStreamRandomizer) al activarse cada reproducción :v
@export var streams: Array[AudioStream] = []
## Volumen base de la capa en dB (antes de peso de zona y duck) :v
@export var volumen_base: float = 0.0
## Variación aleatoria de pitch en semitonos por reproducción :v
@export var pitch_variation: float = 0.0
## Variación aleatoria de volumen en dB por reproducción :v
@export var variacion_db: float = 0.0
## Segundos hasta volumen pleno al entrar (fade in) :v
@export var fade_in: float = 2.0
## Segundos hasta silencio total al salir (fade out) :v
@export var fade_out: float = 3.0
## Nivel mínimo al que suena esta capa, 0..2. Es EL sistema de niveles, no un
## truco de la lluvia: mientras `AmbienteAudio.nivel` no llegue a `nivel_min`
## el objetivo de volumen de la capa vale 0 y su fade_out la diluye sola. Así
## la lluvia sube de "suave" (capa1) a "moderada" (+capa2) a "fuerte" (las
## tres) apilando capas, y el viento usará exactamente lo mismo sin escribir
## una línea nueva (:v
@export_range(0, 2, 1) var nivel_min: int = 0
## Nivel máximo opcional: con valor >= 0, la capa se apaga POR ENCIMA de él.
## -1 = sin techo. Sirve para capas que solo existen en un tramo, como una
## capa de granizo que no pinta en lluvia suave.
@export_range(-1, 2, 1) var nivel_max: int = -1


## ¿Debe sonar este nivel? Es la unica comprobación del sistema de niveles.
func suena_en(nivel: int) -> bool:
	if nivel < nivel_min:
		return false
	if nivel_max >= 0 and nivel > nivel_max:
		return false
	return true


## Construye el stream a reproducir. Con una sola pista y sin variación la :v
## devuelve tal cual; con pool o variación arma un AudioStreamRandomizer.
## NOTA: NO se usa ogg.loop=true — Godot 4.7 fuga los objetos OGG al salir
## con loop en runtime (bug medido: player estándar+loop → 4 Leaked
## instance; sin loop → limpio). El loop se hace con finished→play() :v
## en AmbienteAudio._activar() (ver replay_si_termino).
func construir_stream() -> AudioStream:
	var validos: Array[AudioStream] = []
	for s in streams:
		if s != null:
			validos.append(s)
	if validos.is_empty():
		return null
	if validos.size() == 1 and pitch_variation == 0.0 and variacion_db == 0.0:
		return validos[0]
	var rnd := AudioStreamRandomizer.new()
	for s in validos:
		rnd.add_stream(rnd.streams_count, s, 1.0)
	rnd.random_pitch_semitones = pitch_variation
	rnd.random_volume_offset_db = variacion_db
	rnd.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	return rnd
