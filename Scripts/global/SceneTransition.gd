extends Node
class_name SceneTransition

func goto_scene(path: String, player_pos := Vector2.ZERO, player_dir := Vector2(0, 0), params := []):
	call_deferred("_deferred_goto_scene", path, player_pos, player_dir, params)

func _deferred_goto_scene(path: String, player_pos: Vector2, player_dir: Vector2, params: Array):
	global.changing_scenes = true
	global.get_current_scene_player_node().remove_child(global.get_player())
	global.get_player().set_collisions(false)
	
	for node in global.get_persistent():
		if node and node.get_parent():
			node.get_parent().remove_child(node)
	
	var new_scene = ResourceLoader.load(path).instance()
	
	if global.currentScene is AreaRoom and new_scene is AreaRoom:
		global.currentScene.leave_for(new_scene)
	global.currentScene.free()
	global.currentScene = new_scene
	
	# Pass parameters between scenes
	if !params.empty() and global.currentScene.has_method("init_params"):
		global.currentScene.callv("init_params", params)
	
	get_tree().get_root().add_child(global.currentScene)
	
	global.get_current_scene_player_node().add_child(global.get_player())
	global.create_party_followers()
	global.set_party_position(player_pos, player_dir)
	
	for node in global.get_persistent():
		if is_instance_valid(node.get_parent()):
			node.get_parent().remove_child(node)
		global.get_current_scene_player_node().add_child(node)
	
	get_tree().set_current_scene(global.currentScene)
	uiManager.update_key_indicator()
	yield(get_tree(), "tree_changed")
	yield(get_tree(), "idle_frame")
	
	global.get_player().set_collisions(true)
	global.emit_signal("scene_changed")
	global.changing_scenes = false

func start_door_transition(door: Door, player: PartyMemberPlayer):
	var same_scene: bool = !door.targetScene or global.currentScene.get_name() == door.targetScene
	
	if !same_scene and door.fadeout_music_on_scene_change:
		audioManager.crossfadeout_overworld_music(door.fadeout_music_length)
		audioManager.fadeout_all_music_players(door.fadeout_music_length, false)
	
	if door.sound and door.sound != "None":
		door.audio_player.stream = load("res://Audio/Sound effects/" + door.sound)
		door.audio_player.play()
	
	var fade = uiManager.get_fade()
	fade.fade_in(door.transit_in_anim, door.transit_in_color, door.fade_in_speed)
	yield(fade, "fade_in_done")
	
	door.emit_signal("entered")
	
	if same_scene:
		door.goto_player()
	else:
		door.change_scene()
		yield(global, "scene_changed")
	
	if door.show_player_after_warp:
		player.camera.current = true
		player.visible = true
	fade.init_cut()
	
	if door.dir != Vector2.ZERO:
		player.set_direction_and_input(door.dir)
	
	yield(get_tree(), "idle_frame")
	_update_party_from_door(player)
	
	
	var out_anim := door.transit_out_anim
	if out_anim == "":
		out_anim = door.transit_in_anim
	fade.fade_out(out_anim, door.transit_out_color, door.fade_out_speed)
	yield(fade, "fade_out_mostly_done")
	
	if door.end_sound and door.end_sound != "None":
		door.audio_player.stream = load("res://Audio/Sound effects/" + door.end_sound)
		door.audio_player.play()
	
	if !uiManager.is_in_cutscene() and door.unpause_player:
		if door.dir != Vector2.ZERO:
			player.set_direction_and_input(door.dir)
		player.unpause()
	
	if !same_scene:
		global.remove_persistent(door)
		door.queue_free()
	
	if door.set_respawn:
		global.set_respawn()
	global.entering_door = false
	door.emit_signal("done")

func _update_party_from_door(player: PartyMemberPlayer):
	if global.partySpace.size() <= 1:
		return
	for i in global.partySpace.size():
		global.partySpace.push_front(player.position)
		global.partySpace.pop_back()
	for i in range(1, global.partyObjects.size()):
		global.partyObjects[i].position = player.position
		global.partyObjects[i].reinit()
		global.partyObjects[i].disappear()
