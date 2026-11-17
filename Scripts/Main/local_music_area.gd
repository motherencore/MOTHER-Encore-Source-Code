extends Area2D

export (String) var _music_intro: String
export (String) var _music_loop: String
export (bool) var _start_when_idle := false
export var max_distance: float

const IDLE_DURATION_BEFORE_PLAYING = 1
const MAIN_MUSIC_VOLUME_BASE = -20
const MAIN_MUSIC_VOLUME_REDUCTION = -5

var _audio_player_name: String
var _is_playing := false
var _time_idle := 0.0
var _tween: SceneTreeTween
var _previous_volume := 0.0

func _ready():
	$AudioStreamPlayer2D.stream = load("res://Audio/Music/" + _music_loop)
	$AudioStreamPlayer2D.max_distance = max_distance * 1.5
	set_process(false)
	$AudioStreamPlayer2D.volume_db = -80
	$AudioStreamPlayer2D.play()
	$CPUParticles2D.modulate.a = 0

func _on_body_entered(body):
	if body != global.get_player():
		return
	if _start_when_idle:
		set_process(true)
	else:
		_start_music()

func _on_body_exited(body):
	if body != global.get_player():
		return
	if _start_when_idle:
		set_process(false)
		_time_idle = 0.0
	if _is_playing:
		_stop_music()

func _process(delta):
	if global.get_player().has_substantial_movement():
		_time_idle = 0.0
		if _is_playing:
			_stop_music()
	else:
		if !_is_playing:
			_time_idle += delta
			if _time_idle > IDLE_DURATION_BEFORE_PLAYING and !_is_playing:
				_start_music()

func _start_music():
	var main_volume =  min(MAIN_MUSIC_VOLUME_BASE - MAIN_MUSIC_VOLUME_BASE * (global_position.distance_to(global.get_player().global_position) / max_distance), MAIN_MUSIC_VOLUME_REDUCTION)
	print("volume " + str(main_volume))
	print((global_position.distance_to(global.get_player().global_position) / max_distance))
	audioManager.fadeto_music_player_by_name(audioManager.CHANNELS.OVERWORLD, main_volume, 1.5)
	_previous_volume = audioManager.get_music_player_by_name(audioManager.CHANNELS.OVERWORLD).volume_db
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property($AudioStreamPlayer2D, "volume_db", 0, 1)
	_tween.tween_property($CPUParticles2D, "modulate:a", 1, 2)
	
	_is_playing = true

func _stop_music():
	audioManager.fadeto_music_player_by_name(audioManager.CHANNELS.OVERWORLD, _previous_volume)
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property($AudioStreamPlayer2D, "volume_db", -80, 1)
	_tween.tween_property($CPUParticles2D, "modulate:a", 0, 0.3)
	_is_playing = false
