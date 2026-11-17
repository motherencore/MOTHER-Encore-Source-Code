extends Area2D
class_name MusicChanger

export (String) var loop = "" # The song that the music changer should play. # TODO: change variable name to "song".
export var appear_flag = "" # If this flag is true, the music changer will only start playing music when entered.
export var disappear_flag = "" # If this flag is true, the music changer will no longer play music. Overrides appear_flag.
export (bool) var diegetic = false # Used to make other music changers play from the same playback position as the current one.
export (int) var volume_db = 0 # The volume in db. # TODO: Change to linear volume slider.
export var fadein_length = 1 # The length it takes for the song to fade in when crossfading in with another song.
export var fadeout_length = 1.5 # The length it takes for the song to fade out.
export var disabled = false # Whether the music changer should be disabled initially or not.

func _ready():
	get_child(0).disabled = disabled

func play_music():
	audioManager.add_music_changer(self)
	
func check_player_and_stop():
	stop_music()

func stop_music():
	audioManager.remove_music_changer(self)

func stop_music_immediately():
	audioManager.stop_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
	stop_music()

func set_disabled(value):
	get_child(0).disabled = value

func _check_flags():
	return globaldata.check_appear_disappear_flags(appear_flag, disappear_flag)

func _on_MusicArea_tree_exiting():
	stop_music()

func _on_MusicArea_area_entered(area):
	if area.owner == global.get_player() and !uiManager.is_in_cutscene() and !uiManager.is_in_battle() and _check_flags():
		play_music()

func _on_MusicArea_area_exited(area):
	if area.owner == global.get_player() and !uiManager.is_in_cutscene():
		check_player_and_stop()
