extends Node

const endValue = 1

var start_time
var length_ms
var start_value
var with_pitch : bool

func _ready():
	set_process(false)
	Engine.time_scale = 1

func start_slowmo(speed, length, pitch := true):
	start_time = Time.get_ticks_msec()
	length_ms = length * 1000
	start_value = speed
	with_pitch = pitch
	Engine.time_scale = start_value
	set_process(true)

func _process(delta):
	var current_time = Time.get_ticks_msec() - start_time
	var value = circl_ease_in(current_time, start_value, endValue, length_ms)
	if current_time >= length_ms:
		set_process(false)
		value = endValue
	Engine.time_scale = value
	if with_pitch: audioManager.set_sfx_audio_pitch(value)

func circl_ease_in(t, b, c, d):
	t /= d
	return -c * (sqrt(1 - t * t) - 1) + b
