extends Node

signal stat_state_updated(state)
signal music_player_labels_toggled

var stat_state = 4

# Check debug_key_list.txt in the root directory to find the list of debug keys

func _input(event):
	if !OS.is_debug_build():
		return
	
	# 2x Game Speed
	if event.is_action_pressed("ui_g"):
		Engine.time_scale = 2.0
	elif event.is_action_released("ui_g"):
		Engine.time_scale = 1.0
	
	# 10x Game Speed
	if event.is_action_pressed("ui_h"):
		Engine.time_scale = 10.0
	elif event.is_action_released("ui_h"):
		Engine.time_scale = 1.0
	
	# 0.2x Game Speed
	if event.is_action_pressed("ui_j"):
		Engine.time_scale = 0.2
	elif event.is_action_released("ui_j"):
		Engine.time_scale = 1.0
	
	if event.is_action_pressed("ui_show_audio"):
		emit_signal("music_player_labels_toggled")
	
	if uiManager.is_stack_empty() and !uiManager.is_in_battle():
		if !global.get_player().is_paused():
			# Toggle player invisibility
			if event.is_action_pressed("ui_w"):
				global.get_player().visible = !global.get_player().visible
			
			# Opens storage
			if event.is_action_pressed("ui_F6"):
				global.get_player().pause()
				uiManager.open_storage(false, funcref(global.get_player(), "unpause"))
			
			# Opens god storage for giving yourself any item
			if event.is_action_pressed("ui_F7"):
				global.get_player().pause()
				uiManager.open_storage(true, funcref(global.get_player(), "unpause"))
			
			if event.is_action_pressed("ui_F9"):
				global.get_player().pause()
				uiManager.open_save(SaveSelect.Type.LOAD, funcref(global.get_player(), "unpause"))
		
		# Reload most recent save file
		if event.is_action_pressed("ui_F10", true):
			audioManager.fadeout_all_music_players(0.5)
			global.load_game(globaldata.save_file)
		
		# Instantly new game
		if event.is_action_pressed("ui_F11", true):
			audioManager.fadeout_all_music_players(0.5)
			global.load_new_game(true, true)
		
		# Go to debug world
		if event.is_action_pressed("ui_F12", true):
			global.scene_transition.goto_scene("res://Maps/Testing/Debug world.tscn")
			global.get_player().position = Vector2.ZERO
			global.get_player().unpause()
	
	# Translation toggles
	if event.is_action_pressed("ui_translate"):
		global._toggle_language(global.LANGUAGES, 1 if event.is_echo() else -1)
		global.save_settings()
		$DebugIcons.show_language()
	
	for i in global.LANGUAGES.size():
		var input = "ui_lang%s" % i
		if input in InputMap.get_actions() and event.is_action_pressed(input):
			global.set_language(global.LANGUAGES[i])
			global.save_settings()
			$DebugIcons.show_language()
			return
	
	if !global.get_player().is_paused():
		# Toggle Collisions
		if event.is_action_pressed("ui_q"):
			global.party_call("set_collisions", false)
		if event.is_action_released("ui_q"):
			global.party_call("set_collisions", true)
		
		# Toggle player speed up
		if event.is_action_pressed("ui_e"):
			global.get_player().set_debug_speed(true)
		if event.is_action_released("ui_e"):
			global.get_player().set_debug_speed(false)
	
	# BATTLE DEBUG INPUTS
	if uiManager.is_in_battle():
		# Show enemy stats
		if event.is_action_pressed("ui_backtick"):
			stat_state += 1
			if stat_state > 4:
				stat_state = 0
			
			emit_signal("stat_state_updated", stat_state)
		
	# OUT OF BATTLE DEBUG INPUTS
	else:
		# Start debug battles
		if event.is_action_pressed("ui_F2") and !global.get_player().is_paused() and \
			global.get_player().get_state() == global.get_player().MOVE:
			uiManager.start_battle(BattleSystem.Advantage.NEUTRAL, true, [Enemy.new("TEST")])
		
		if event.is_action_pressed("ui_F3") and !global.get_player().is_paused() and \
			global.get_player().get_state() == global.get_player().MOVE:
			uiManager.start_battle(BattleSystem.Advantage.NEUTRAL, true, [Enemy.new("turnipman"), Enemy.new("danionel")])
		
		# Add debug UI
		if event.is_action_pressed("ui_backtick"):
			if uiManager.is_stack_empty():
				var debug_menu = load("res://Nodes/Ui/debug/debugUI.tscn")
				uiManager.add_ui(debug_menu.instance())
		
		# Add party members
		for character in globaldata.characters.size():
			if event.is_action_pressed("ui_%s" % (character+1), true):
				var party_member = globaldata.characters.values()[character]
				if party_member in global.party:
					if !party_member.is_incapacitated(): 
						party_member.add_status(Status.AILMENT_UNCONSCIOUS)
					elif global.party.size() <= 1: 
						party_member.remove_all_statuses()
					else:
						global.party.erase(party_member)
						if party_member.get_name() != PartyMember.NINTEN:
							party_member.remove_all_statuses()
				elif party_member in global.partyNpcs:
					if party_member.get_name() == PartyNPC.FLYING_MAN:
						globaldata.set_flag("flying_man_in_party", false)
					global.partyNpcs.erase(party_member)
					party_member.remove_all_statuses()
				
				else:
					if party_member.get_name() in global.POSSIBLE_PLAYABLE_MEMBERS:
						global.party.append(party_member)
					else:
						party_member.remove_all_statuses()
						global.partyNpcs.append(party_member)
						
						if party_member.get_name() == PartyNPC.FLYING_MAN:
							globaldata.set_flag("flying_man_in_party", true)
					
					if party_member.get_name() == PartyMember.NINTEN:
						party_member.remove_all_statuses()
				global.create_party_followers()
	
	# Mute music
	if event.is_action_pressed("ui_mute"):
		audioManager.stop_all_music_players()
