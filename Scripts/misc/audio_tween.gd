extends Node
class_name AudioTween

# This class is used to tween the volume_db of an audio player.
# dB scales logarithmically, meaning +6 dB doubles the volume, and +10 is perceived as twice as loud.
# This means that if you were to tween an audio player's db with a regular tween, 
# it won't scale in a way that feels natural to the human ear.
# To fix this, we tween a float value between 0 and 1 linearly, and then inside of _physics_process,
# we convert that float value to dB using linear2db() and assign it to the audio player's volume_db.

signal finished

var _audio_player: AudioStreamPlayer
var _tween: SceneTreeTween

var _linear_volume : float
var _end_time : float

func _init(a: AudioStreamPlayer, v: float, d: float):
	audioManager.add_child(self)
	_audio_player = a
	_linear_volume = db2linear(_audio_player.volume_db)
	_end_time = d
	_tween_volume(db2linear(v), d)

func _tween_volume(end_volume: float, duration: float):
	_tween = get_tree().create_tween()
	_tween.tween_property(self, "_linear_volume", end_volume, duration)
	_tween.connect("finished", self, "kill", [true])

func _physics_process(_delta):
	if is_instance_valid(_tween) and _tween.is_running():
		_update_audio_player_volume()

func _update_audio_player_volume():
	_audio_player.volume_db = linear2db(_linear_volume)

# Ends the tween. You can also choose whether the tween should immediately jump to the end position or not.
func kill(goto_end := false) -> void:
	if is_instance_valid(_tween):
		if goto_end:
			_tween.pause()
			_tween.custom_step(_end_time)
			_update_audio_player_volume()
		else:
			_tween.kill()
		emit_signal("finished")
		queue_free()

