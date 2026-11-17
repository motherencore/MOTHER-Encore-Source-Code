extends DungeonAreaRoom

func _on_main_switch_hit():
	audioManager.fadeout_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
	global.get_player().pause()
	uiManager.set_cutscene(true)

func _on_wall_door_state_changed(state: bool, silent: bool):
	if state and !silent:
		yield(get_tree().create_timer(0.5), "timeout")
		uiManager.set_cutscene(false)
		global.get_player().unpause()
		$Music/MusicArea.play_music()
