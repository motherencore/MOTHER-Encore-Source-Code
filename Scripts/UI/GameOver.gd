extends CanvasLayer

const GAME_OVER_DIALOG = "Reusable/GameOver"

var _fade: CanvasLayer
var _game_over_music: AudioStreamPlayer

signal fade_done
signal done

func _init():
	_fade = uiManager.get_fade()
	uiManager.clear_on_screen_enemies()

func _ready():
	audioManager.clear_previous_overworld_track_playback_positions()
	global.get_player().set_collisions(false)
	global.get_player().set_idle()
	globaldata.cash /= 2
	_fade.fade_in("Circle")
	yield(_fade, "fade_in_done")
	
	emit_signal("fade_done")
	$Timer.start()
	$GameOverLayer/ColorRect.modulate = Color.black
	yield($Timer, "timeout")
	$AnimationPlayer.play("nintenFall")
	audioManager.stop_all_music_players()
	_game_over_music = audioManager.play_music(audioManager.CHANNELS.MENU, "Game_Over.ogg")
	yield($AnimationPlayer, "animation_finished")
	
	var dialogueBox = uiManager.open_dialogue_box(GAME_OVER_DIALOG, funcref(self, "_end_dialogue"))

func _remove_fade_cut():
	_fade.set_cut(1, 0)

func _end_dialogue(try_again: int):
	if _game_over_music: audioManager.fadeout_music_player_by_name(audioManager.CHANNELS.MENU, 5)
	if try_again:
		$AnimationPlayer.play("nintenGetup")
		yield($AnimationPlayer, "animation_finished")
		$AnimationPlayer.play("transitionOut")
		_fade.fade_in("Fade", Color.white, 0.3)
		yield($AnimationPlayer, "animation_finished")
		revive_party()
		global.goto_respawn()
		global.update_party_spritesheets()
		global.party_call("set_anim_state", "Idle")
		$GameOverLayer.hide()
		_fade.fade_out("Fade", Color.white)
		yield(_fade, "fade_out_done")
		
		global.get_player().set_collisions(true)
		global.get_player().unpause()
	else:
		$AnimationPlayer.play("transitionOut")
		_fade.fade_in("Fade", Color.black, 0.2)
		yield($AnimationPlayer, "animation_finished")
		$GameOverLayer.hide()
		$Door.enter()
		yield($Door, "done")
	_game_over_music = null
	emit_signal("done")

func revive_party():
	global.set_party_leader(PartyMember.NINTEN)
	for i in global.party:
		i.remove_all_statuses()
		if i == global.party[0]:
			i.set_hp(i.get_stat(Character.MAXHP))
			i.set_pp(i.get_stat(Character.MAXPP))
		else:
			i.add_status(Status.AILMENT_UNCONSCIOUS)
			i.set_pp(i.get_stat(Character.MAXPP))
