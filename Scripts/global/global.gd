extends Node2D

signal cutscene_ended
signal flags_updated
signal locale_changed
signal inputs_changed
signal settings_changed
signal party_changed
signal scene_changed

const GAME_VERSION := "0.4.1.2"
const ACT := 2

const LANGUAGES := ["en", "fr", "it", "ja", "ko", "es", "es_ES", "pt_BR", "pl", "de", "ru", "uk", "zh_Hans_CN"]
const LANGUAGES_DISABLED := [] # disabled in release builds
const LANGUAGE_DEFAULT := "en"

const SAVE_NEW_GAME_PATH := "res://Data/save_new_game.yaml"
const SAVE_DEFAULT_PATH := "res://Data/save_default.yaml"


const POSSIBLE_PLAYABLE_MEMBERS := [PartyMember.NINTEN, PartyMember.ANA, PartyMember.LLOYD, PartyMember.TEDDY, PartyMember.PIPPI]

# Party
var party := []
var partyNpcs := []
var partySpace := []
var partyObjects := []

# Persistent elements
var _persist_array := []

# Scene and camera
var currentScene: Node = null
var currentCamera: GameCamera = null
var scene_transition := SceneTransition.new()

# Context
var item: Item = null
var talker: KinematicBody2D = null
var in_cutscene := false
var can_pause := true
var entering_door := false
var changing_scenes := false

var _phone_location := ""

func _ready():
	_set_localized_default_inputs()
	_load_settings()
	partySpace.resize(255)
	add_child(scene_transition)
	_init_player()
	_load_default_save()

func _init_player():
	var root := get_tree().get_root()
	currentScene = root.get_child(root.get_child_count() - 1)
	if partyObjects.size() > 0:
		return
	party.append(globaldata.characters.ninten)
	var player: PartyMemberPlayer = load("res://Nodes/Reusables/Player.tscn").instance()
	player.name = "player"
	player.position = Vector2.ZERO
	partyObjects = [player]
	var parent_node := get_current_scene_player_node()
	if parent_node:
		parent_node.add_child(player)
	else:
		currentScene.add_child(player)
		player.hide()
		player.connect("ready", player, "pause", [], CONNECT_ONESHOT)
	create_party_followers(false)
	set_respawn()

func _input(event: InputEvent):
	if uiManager.is_stack_empty():
		if !get_player().is_paused() and get_player().get_state() == get_player().MOVE and can_pause:
			if event.is_action_pressed("ui_select"):
				uiManager.open_commands_menu()
			elif event.is_action_pressed("ui_map") and _is_map_available():
				audioManager.play_sfx_by_name("menu_open", "map_menu")
				uiManager.open_current_map(false, funcref(self, "_on_map_closed"))
	
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		globaldata.device = globaldata.GAMEPAD
	elif event is InputEventKey:
		globaldata.device = globaldata.KEYBOARD
	
	if event is InputEventWithModifiers and !(event.alt or event.control or event.meta):
		if event.is_action_pressed("ui_fullscreen"):
			toggle_fullscreen()
			global.emit_signal("settings_changed")
			
		if event.is_action_pressed("ui_winsize"):
			_increase_win_size(-1 if event.shift else 1)

func start_slowmo(speed, length):
	$Slowmo.start_slowmo(speed, length)

func set_mouse_hider(value: bool):
	$MouseHider.set_active(value)

func get_persistent() -> Array:
	return _persist_array

func add_persistent(node_to_persist: Node):
	_persist_array.append(node_to_persist)

func remove_persistent(node_to_remove: Node):
	_persist_array.erase(node_to_remove)

func is_persistent(node_to_check: Node) -> bool:
	return node_to_check in _persist_array

func get_current_scene_player_node() -> Node:
	return currentScene.get_node_or_null("YSort" if currentScene.has_node("YSort") else "Objects")

func set_party_position(position: Vector2, direction: Vector2):
	get_player().position = position
	if partySpace.size() > 1:
		for i in partySpace.size():
			partySpace.push_front(position)
			partySpace.pop_back()
	if direction != Vector2.ZERO:
		for mem in partyObjects:
			mem.set_direction(direction)

func reset_party_positions():
	if partySpace.size() > 1:
		for i in partySpace.size():
			partySpace.push_front(get_player().position)
			partySpace.pop_back()

func create_party_followers(emit_signal:= true):
	var cur_party := party + partyNpcs
	if partyObjects.size() > 1:
		for i in range(1, partyObjects.size()):
			if is_instance_valid(partyObjects[i]):
				if is_persistent(partyObjects[i]):
					remove_persistent(partyObjects[i])
				partyObjects[i].queue_free()
	partyObjects.resize(1)
	for i in range(1, cur_party.size()):
		var Follower := load("res://Nodes/Reusables/PartyFollower.tscn")
		var follow: PartyFollower = Follower.instance()
		partyObjects.append(follow)
		get_player().get_parent().add_child(follow)
		follow.init_with_follower_idx(i)
	
	if emit_signal: 
		yield(get_tree(), "idle_frame")
		print("emitting party changed")
		emit_signal("party_changed")

func update_party_spritesheets():
	for party_obj in global.partyObjects:
		party_obj.update_party_member()
		party_obj.spritesheet()

func party_call(function, value = null):
	for i in partyObjects:
		if not is_instance_valid(i)		:	continue
		if not i is PartyObject			:	continue
		if not i.has_method(function)	:	continue
		if value == null:
			i.call(function)
		else:
			var value_as_array:Array = variant_to_array(value)
			i.callv(function,value_as_array)

func variant_to_array(value) -> Array:
	match typeof(value):
		TYPE_ARRAY:
			return value
		TYPE_DICTIONARY:
			var aux_array: Array = []
			for key in value.keys():aux_array.append([key, value[key]])
			return aux_array
		TYPE_STRING:
			return value.split("")
		_:
			return [value]

func swap_party_forward():
	party.push_back(global.party.pop_front())

func swap_party_backward():
	party.push_front(global.party.pop_back())

func set_party_leader(leader_name: String):
	while party[0].get_name() != leader_name:
		swap_party_forward()

func has_party_member(member_name: String, with_npcs := true):
	var all_party = get_party(with_npcs)
	
	for member in all_party.size():
		if all_party[member].get_name() == member_name:
			return true
	return false

func get_party_member_in_party(member_name: String, with_npcs := true) -> PartyMember:
	var all_party = get_party(with_npcs)
	
	for member in all_party.size():
		if all_party[member].get_name() == member_name:
			return all_party[member]
	return null

func get_player() -> PartyMemberPlayer:
	return partyObjects[0] as PartyMemberPlayer

func get_conscious_party() -> Array:
	var arr := []
	for mem in party:
		if !mem.is_incapacitated():
			arr.append(mem)
	return arr

func get_full_party() -> Array:
	return party + partyNpcs

func get_party(with_npcs := false) -> Array:
	var all_party = []
	all_party.append_array(party)
	
	if with_npcs: 
		all_party.append_array(partyNpcs)
	
	return all_party

func get_party_in_natural_order(include_party_npcs := false) -> Array:
	var ordered_party := []
	for character in globaldata.characters.values():
		if character in party or (include_party_npcs and character in partyNpcs):
			ordered_party.append(character)
	return ordered_party

func set_respawn():
	globaldata.respawn_point = get_player().position
	globaldata.respawn_scene = currentScene.get_filename()
	globaldata.respawn_run_sound = get_player().run_sound
	globaldata.respawn_shadow_effect = get_player().get_shadow()
	print("Respawn: %s %s" % [currentScene.name, globaldata.respawn_point])

func goto_respawn():
	scene_transition.goto_scene(globaldata.respawn_scene, globaldata.respawn_point)
	get_player().set_direction(Vector2(0, 1))
	get_player().run_sound = globaldata.respawn_run_sound
	get_player().set_shadow(globaldata.respawn_shadow_effect)
	uiManager.info_plates_show(true, true, true)

func set_phone_location(value: String):
	_phone_location = value

func start_joy_vibration(device_id: int, weak_magnitude: float, strong_magnitude: float, duration: float = 0):
	if globaldata.rumble:
		Input.start_joy_vibration(device_id, weak_magnitude, strong_magnitude, duration)

func detect_buttons_style() -> int:
	var joy_name := Input.get_joy_name(0)
	var NINTENDO_PATTERNS := ["nintendo", "switch", "joy-con", "snes", "famicom", "pro controller", "gamecube", "8bitdo"]
	var PLAYSTATION_PATTERNS := ["playstation", "sony", "ps5", "ps4", "ps3", "ps2", "dualsense", "dualshock"]
	for pattern in NINTENDO_PATTERNS:
		if pattern in joy_name.to_lower():
			return globaldata.BtnStyles.NINTENDO
	
	for pattern in PLAYSTATION_PATTERNS:
		if pattern in joy_name.to_lower():
			return globaldata.BtnStyles.PLAYSTATION
	
	return globaldata.BtnStyles.XBOX

# LOCALIZATION Code added: New method "set_win_size" to set window size to any value
# (especially from the options UI)
func _increase_win_size(amount: int):
	var new_size := globaldata.win_size + amount
	
	if new_size < 1:
		new_size = int(OS.get_screen_size().x / 320)
	
	if OS.get_screen_size() < Vector2(320 * new_size, 180 * new_size):
		new_size = 1
	
	set_win_size(new_size)

func toggle_fullscreen(value := !OS.window_fullscreen):
	set_win_size(globaldata.win_size, value)

func set_win_size(new_size_num: int, fullscreen := false):
	# Everything here needs to happen asynchronously: sometimes resizing the window hangs the system for a few milliseconds, causing issues
	yield(get_tree(), "idle_frame")
	
	if fullscreen != OS.window_fullscreen:
		OS.window_fullscreen = fullscreen
	
	if not fullscreen:
		var oldSize = OS.window_size
		var newSize = Vector2(320 * new_size_num, 180 * new_size_num)
		globaldata.win_size = new_size_num
		if newSize != oldSize:
			OS.window_borderless = false
			var new_pos = OS.window_position - (newSize - oldSize) / 2
			# We don’t want the title bar to be out of screen
			var topLeft = OS.get_screen_position() + Vector2(OS.get_screen_size().x * .1, 0)
			var bottomRight = OS.get_screen_position() + OS.get_screen_size() * .9
			new_pos.x = clamp(new_pos.x, topLeft.x - newSize.x, bottomRight.x)
			new_pos.y = clamp(new_pos.y, topLeft.y, bottomRight.y)
			OS.set_window_size(newSize)
			OS.set_window_position(new_pos)
	
	global.emit_signal("settings_changed")

func set_master_volume(volume: int):
	globaldata.master_volume = volume
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume)
	global.emit_signal("settings_changed")

func set_music_volume(volume: int):
	globaldata.music_volume = volume
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), volume)
	global.emit_signal("settings_changed")

func set_sfx_volume(volume: int):
	globaldata.sfx_volume = volume
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), volume)
	global.emit_signal("settings_changed")

func _toggle_language(ordered_languages: Array, direction := 1):
	direction = int(sign(direction))
	# Obtaining the language code the game falls back to (ex: "fr" if locale is "fr_BE")
	var lang = tr("LANGUAGE_CODE")
	var index = ordered_languages.find(lang)
	var newIndex = fposmod(index + direction, ordered_languages.size())
	set_language(ordered_languages[newIndex])

func set_language(lang_code):
	TranslationServer.set_locale(lang_code)
	global.emit_signal("locale_changed")

# Sets the default language based on the OS, in cases where the automatic selection fails
func _set_language_default():
	print("OS locale code: %s" % OS.get_locale())
	if OS.get_locale_language() == "es":
		if OS.get_locale() in ["es", "es_ES", "es_GQ", "es_IC"]:
			print("Switching to Spain Spanish")
			TranslationServer.set_locale("es_ES")
		else:
			print("Switching to American Spanish")
			TranslationServer.set_locale("es")
	else:
		var language_code := tr("LANGUAGE_CODE")
		if !language_code in get_supported_languages():
			language_code = LANGUAGE_DEFAULT
		TranslationServer.set_locale(language_code)

func get_supported_languages(include_disabled := OS.is_debug_build()) -> Array:
	if include_disabled:
		return LANGUAGES
	var ret := LANGUAGES.duplicate()
	for lang in LANGUAGES_DISABLED:
		ret.erase(lang)
	return ret

func _serialize_inputs() -> Dictionary:
	var controls := {}
	for action in InputMap.get_actions():
		controls[action] = []
		for event in InputMap.get_action_list(action):
			controls[action].append(var2str(event))
	return controls

func _deserialize_inputs(controls) -> void:
	if controls == null: return
	for action in controls:
		if !InputMap.has_action(action): continue
		InputMap.action_erase_events(action)
		for event in controls[action]:
			var event_to_add = str2var(event)
			event_to_add.device = 0
			InputMap.action_add_event(action, event_to_add)

# Default action keys adapted to various keyboard layouts
func _set_localized_default_inputs():
	var actions := ["ui_accept", "ui_cancel", "ui_select", "ui_focus_prev", "ui_focus_next"]
	var all_layouts := {
		"QWERTY": "ZXCAS", "AZERTY": "WXCQS", "BÉPO": "ZYXAU", "QWERTZ": "YXCAS",
		"QZERTY": "WXCAS", "DVORAK": ";QJAO", "COLEMAK": "ZXCAR", "NEO": "ZXCUI"
	}
	
	var user_layout_type := OS.get_latin_keyboard_variant()
	if user_layout_type in ["QWERTY", "ERROR"]:
		# workaround for BÉPO layout not recognized natively
		var os_layout_index := OS.keyboard_get_current_layout()
		var os_layout_name := OS.keyboard_get_layout_name(os_layout_index).to_upper()
		if ("BÉPO" in os_layout_name or "BEPO" in os_layout_name) \
			or (OS.keyboard_get_layout_language(os_layout_index) == "fr" and ("FRANCE" in os_layout_name) and not ("AZERTY" in os_layout_name)):
			user_layout_type = "BÉPO"
		else:
			user_layout_type = "QWERTY"
	
	for i in actions.size():
		var events := InputMap.get_action_list(actions[i])
		for event in events:
			if event is InputEventKey:
				event.scancode = ord(all_layouts[user_layout_type][i])

func start_playtime():
	$Playtimer.start()

func stop_playtime():
	$Playtimer.stop()

func _on_Playtimer_timeout():
	globaldata.playtime += 1

func save_settings():
	var save_dict := {
		"language": TranslationServer.get_locale(),
		"winsize": globaldata.win_size,
		"fullscreen": OS.window_fullscreen,
		"integerscaling": IntegerResolutionHandler.is_active(),
		"vsync": OS.vsync_enabled,
		"mastervolume": globaldata.master_volume,
		"musicvolume": globaldata.music_volume,
		"sfxvolume": globaldata.sfx_volume,
		"savefile": globaldata.save_file,
		"inputmap": _serialize_inputs(),
		"rumble": globaldata.rumble,
		"buttonsStyle": globaldata.buttons_style
	}
	
	var save_file := File.new()
	save_file.open_encrypted_with_pass("user://settings.save", File.WRITE,"ENCORE")
	save_file.store_line(to_json(save_dict))
	save_file.close()

func _load_settings():
	var save_file := File.new()
	if not save_file.file_exists("user://settings.save"):
		_set_language_default()
		return
	
	save_file.open_encrypted_with_pass("user://settings.save", File.READ,"ENCORE")
	
	var save_data = parse_json(save_file.get_line())
	save_file.close()
	
	var language = save_data.get("language", "en")
	var win_size = save_data.get("winsize", 3)
	var fullscreen = save_data.get("fullscreen", false)
	var master_volume = save_data.get("mastervolume", 0)
	var music_volume = save_data.get("musicvolume", 0)
	var sfx_volume = save_data.get("sfxvolume", 0)
	var int_scaling = save_data.get("integerscaling", false)
	_deserialize_inputs(save_data.get("inputmap", null))
	globaldata.rumble = save_data.get("rumble", true)
	globaldata.buttons_style = save_data.get("buttonsStyle", globaldata.BtnStyles.DETECT)
	globaldata.save_file = int(save_data.get("savefile", 0))
	OS.vsync_enabled = save_data.get("vsync", true)
	
	if language in get_supported_languages() and language in TranslationServer.get_loaded_locales():
		TranslationServer.set_locale(language)
	else:
		_set_language_default()
	
	set_win_size(win_size, fullscreen)
	IntegerResolutionHandler.set_active(int_scaling)
	set_master_volume(master_volume)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

func save_from_dict(num: int, dict: Dictionary):
	audioManager.play_sfx_by_name("save", "menu")
	var save_file := File.new()
	save_file.open_encrypted_with_pass("user://saveFile" + var2str(num) + ".save", File.WRITE,"ENCORE")
	save_file.store_line(to_json(dict))
	save_file.close()

func save_game(num: int):
	var location = _phone_location if _phone_location else currentScene.name
	
	var party_names := []
	for mem in party + partyNpcs:
		party_names.append(mem.get_name())
	
	var save_dict = {
		"scene": currentScene.get_filename(),
		"scenename": location,
		"posX": get_player().position.x,
		"posY": get_player().position.y,
		"playtime": globaldata.playtime,
		"flags": globaldata.flags,
		"object_flags": globaldata.object_flags,
		"seen_dialogue_flags": globaldata.seen_dialogue_flags,
		"keys": globaldata.keys,
		"textspeed": globaldata.text_speed,
		"menuflavor": globaldata.menu_flavor,
		"buttonprompts": globaldata.button_prompts,
		"earned_cash": globaldata.earned_cash,
		"description": globaldata.description,
		"cash": globaldata.cash,
		"bank": globaldata.bank,
		"ninten": globaldata.characters.ninten.to_dict(),
		"ana": globaldata.characters.ana.to_dict(),
		"lloyd": globaldata.characters.lloyd.to_dict(),
		"teddy": globaldata.characters.teddy.to_dict(),
		"pippi": globaldata.characters.pippi.to_dict(),
		"eve": globaldata.characters.eve.to_dict(),
		"flyingman": globaldata.characters.flyingman.to_dict(),
		"favoritefood": globaldata.favorite_food,
		"playername": globaldata.player_name,
		"runsound": get_player().run_sound,
		"shadoweffect": globaldata.respawn_shadow_effect,
		"dirX": get_player().get_direction().x,
		"dirY": get_player().get_direction().y,
		"party": party_names,
		"key_items": globaldata.key_items.to_array(),
		"storage": globaldata.storage.to_array(),
		"rareDrops": globaldata.rare_drops,
		"encountered": globaldata.encountered,
		"version": GAME_VERSION,
		"is_debug": OS.is_debug_build(),
		"date": Time.get_datetime_dict_from_system()
	}
	
	save_from_dict(num, save_dict)
	set_respawn()
	globaldata.flags["saved"] = true

func load_to_dict(num: int) -> Dictionary:
	var save_file := File.new()
	if !save_file.file_exists("user://saveFile%s.save" % num):
		return {}
	save_file.open_encrypted_with_pass("user://saveFile%s.save" % num, File.READ, "ENCORE")
	var save_dict = parse_json(save_file.get_line())
	save_file.close()
	if save_dict and !SaveManager.is_save_in_current_version(save_dict):
		SaveManager.upgrade_save(save_dict)
	return save_dict

func load_game(num: int, goto_game := true):
	var save_data := load_to_dict(num)
	if save_data:
		_load_dict_to_game(save_data, goto_game)

func _load_default_save():
	var save_data: Dictionary = globaldata.get_json_data(SAVE_DEFAULT_PATH)
	_load_dict_to_game(save_data, false)

func load_new_game(auto_name := false, goto_game := false):
	var save_data: Dictionary = globaldata.get_json_data(SAVE_NEW_GAME_PATH)
	if auto_name:
		for mem_name in globaldata.characters:
			save_data[mem_name].nickname = tr("NAME_%s0" % mem_name.to_upper())
		save_data["favoritefood"] = tr("FAVFOOD0")
		save_data["playername"] = "Tester"
	_load_dict_to_game(save_data, goto_game)

func _override_save_dict(save: Dictionary, overrides: Dictionary):
	for key in overrides.keys():
		if save.has(key) and save[key] is Dictionary and overrides[key] is Dictionary:
			_override_save_dict(save[key], overrides[key])
		elif save.has(key) and save[key] is Array and overrides[key] is Array:
			var fully_replace_array: bool = overrides[key].empty() or (save[key].size() > 0 and typeof(save[key][0]) in [TYPE_DICTIONARY, TYPE_ARRAY])
			if fully_replace_array:
				save[key] = overrides[key]
			else: # if it’s an array of primitive type, we’re merging them together (ex: learned skills)
				for item in overrides[key]:
					if !item in save[key]:
						save[key].append(item)
		else:
			save[key] = overrides[key]

func _load_dict_to_game(save_data: Dictionary, goto_game := true):
	_override_save_dict(save_data, globaldata.get_json_data("res://Data/save_overrides.yaml"))
	
	globaldata.respawn_point = Vector2(save_data.get("posX", 0), save_data.get("posY", 0))
	globaldata.respawn_scene = save_data.get("scene", globaldata.respawn_scene)
	globaldata.respawn_run_sound = save_data.get("runsound", globaldata.respawn_run_sound)
	globaldata.respawn_shadow_effect = save_data.get("shadoweffect", globaldata.respawn_shadow_effect)
	globaldata.playtime = save_data.get("playtime", 0)
	globaldata.favorite_food = save_data.get("favoritefood", globaldata.favorite_food)
	globaldata.player_name = save_data.get("playername", globaldata.player_name)
	globaldata.text_speed = save_data.get("textspeed", 0)
	globaldata.menu_flavor = save_data.get("menuflavor", globaldata.FLAVORS[0])
	globaldata.button_prompts = save_data.get("buttonprompts", globaldata.BUTTON_PROMPTS[0])
	globaldata.earned_cash = int(save_data.get("earned_cash", 0))
	globaldata.cash = int(save_data.get("cash", 0))
	globaldata.bank = int(save_data.get("bank", 0))
	globaldata.description = save_data.get("description", true)
	globaldata.keys = save_data.get("keys", {})
	globaldata.object_flags = save_data.get("object_flags", {})
	globaldata.seen_dialogue_flags = save_data.get("seen_dialogue_flags", {})
	globaldata.rare_drops = save_data.get("rareDrops", {})
	globaldata.encountered = save_data.get("encountered", {})
	globaldata.key_items.init_from_serialized(save_data.get("key_items", []))
	globaldata.storage.init_from_serialized(save_data.get("storage", []))
	# Load party data
	for char_id in globaldata.characters:
		globaldata.characters[char_id].init_from_dict(save_data.get(char_id, {}))
	#globaldata.reset_constant_data()
	#reappend party
	party.clear()
	partyNpcs.clear()
	for i in save_data["party"]:
		if i in POSSIBLE_PLAYABLE_MEMBERS:
			party.append(globaldata.characters.get(i))
		else:
			partyNpcs.append(globaldata.characters.get(i))
		
	uiManager.set_menu_flavors(globaldata.menu_flavor)
	
	for flag in globaldata.flags:
		globaldata.flags[flag] = save_data.get("flags", {}).get(flag, false)
		
	if goto_game:
		get_player().pause()
		scene_transition.goto_scene(save_data["scene"], globaldata.respawn_point, Vector2(save_data["dirX"], save_data["dirY"]))
		update_party_spritesheets()
		get_player().toggle_anim_tree(true)
		get_player().set_direction_and_input(Vector2(save_data["dirX"], save_data["dirY"]))
		get_player().eventRayCaster.rotation = get_player().get_direction().angle() - TAU/4
		get_player().set_idle()
		if save_data.has("runsound"):
			save_data["runsound"] = save_data["runsound"].replace(".wav", "")
			get_player().run_sound = save_data["runsound"]
		get_player().set_shadow(globaldata.respawn_shadow_effect)
		yield(get_tree(), "idle_frame")
		get_player().unpause()
		uiManager.info_plates_show(true, true)
		
		start_playtime()

func erase_save(num):
	audioManager.play_sfx(load("res://Audio/Sound effects/M3/Party_Member_Death.wav"), "menu")
	var save_game = Directory.new()
	save_game.remove("user://saveFile" + var2str(num) + ".save")

func party_give_exp(amount: int):
	var changed_stats := {}
	var learned_skills := {}
	var conscious_party := []
	var receiving_party := []
	for mem in party:
		if !mem.is_unconscious():
			conscious_party.append(mem)
			if mem.get_level() < PartyMember.LEVEL_CAP:
				receiving_party.append(mem)
	
	for party_mem in conscious_party:
		var received_exp := int(round(amount / receiving_party.size())) if receiving_party else 0
		changed_stats[party_mem.get_name()] = {}
		learned_skills[party_mem.get_name()] = []
		party_mem.give_exp(received_exp, changed_stats[party_mem.get_name()], learned_skills[party_mem.get_name()])
	
	_try_party_level_up(changed_stats, learned_skills)

func _try_party_level_up(changed_stats := {}, learned_skills := {}):
	var started_dialog_sequence := false
	var audio_players_names := []
	for member in changed_stats:
		if changed_stats[member] or learned_skills[member]:
			if !started_dialog_sequence:
				started_dialog_sequence = true
				get_player().pause()
				yield(get_tree().create_timer(.2), "timeout")
			if changed_stats[member]:
				if !audioManager.overworld_battle_music:
					audioManager.pause_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
				audio_players_names.append_array(_set_lvl_up_music(member))
			var battle_dialogue_box = yield(uiManager.open_battle_dialogue_box(), "completed")
			var dialog := _set_lvlup_or_new_skill_dialogue(battle_dialogue_box, member, changed_stats[member], learned_skills[member])
			yield(battle_dialogue_box.start_from_scripted_dialog(dialog), "completed")
	
	if !audio_players_names.empty():
		for player_name in audio_players_names:
			audioManager.stop_music_player_by_name(player_name)
		
		# Resume overworld music with a fade
		var overworld_music_player = audioManager.get_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
		if overworld_music_player and overworld_music_player.stream_paused:
			audioManager.fadein_music_player_by_name(audioManager.CHANNELS.OVERWORLD, overworld_music_player.volume_db, 1)
		audioManager.resume_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
	
	if started_dialog_sequence:
		get_player().unpause()

func _set_lvl_up_music(member_name: String) -> Array:
	if audioManager.overworld_battle_music:
		return []
	var audio_player_names := []
	var lvlup_music = "You Win/LVLUP.mp3"
	if !audioManager.is_song_playing_on_music_player_by_name(audioManager.CHANNELS.BATTLE, lvlup_music):
		audio_player_names.append(audioManager.CHANNELS.BATTLE)
	audioManager.play_music(audioManager.CHANNELS.BATTLE, lvlup_music)
	
	var member_audio_player_name = "Lvlup_" + member_name
	var audio_player = audioManager.get_music_player_by_name(member_audio_player_name)
	var mem_lvlup_music = "You Win/LVLUP_%s.mp3" % member_name
	
	if !audioManager.is_song_playing_on_music_player_by_name(member_audio_player_name, mem_lvlup_music):
		audio_player_names.append(member_audio_player_name)
	var start_time = audioManager.get_music_player_by_name(audioManager.CHANNELS.BATTLE).get_playback_position()
	audioManager.play_music(member_audio_player_name, mem_lvlup_music, start_time)
	return audio_player_names

func _set_lvlup_or_new_skill_dialogue(battle_dialogue_box, member_name: String, changed_stats := {}, learned_skills := []) -> Dictionary:
	var character = globaldata.characters[member_name]
	var json_dialog := {}
	var phrases := -1
	var context = battle_dialogue_box.FormatContext.new()
	if changed_stats:
		phrases += 1
		var level: int = character.get_level()
		json_dialog[String(phrases)] = {
			"text": battle_dialogue_box.format_battle_text("BATTLE_MSG_LEVEL_UP", context.set_actor(character).set_value(level)),
			"soundeffect": "M3/Cheering.mp3", "cleardialog": true
		}
		
		for stat in changed_stats:
			var gain: int = changed_stats[stat]
			var final_stat: String = stat
			phrases += 1
			json_dialog[String(phrases-1)]["goto"] = String(phrases)
			json_dialog[String(phrases)] = {
				"text": battle_dialogue_box.format_battle_text("BATTLE_MSG_LEVEL_UP_STAT", context.set_actor(character).set_value(gain).set_stat(final_stat))
			}
	
	# check skill table
	for new_skill in learned_skills:
		phrases += 1
		if phrases > 0:
			json_dialog[String(phrases-1)]["goto"] = String(phrases)
		json_dialog[String(phrases)] = {"text": battle_dialogue_box.format_battle_text("BATTLE_MSG_LEARNING", context.set_actor(character).set_item_or_skill(globaldata.get_battle_skill(new_skill))), \
		"soundeffect": "M3/Learned PSI.wav"}
	
	return json_dialog

func _is_map_available() -> bool:
	return global.currentScene.get_map_name(true) != ""

func _on_map_closed():
	audioManager.play_sfx_by_name("menu_close", "map_menu")
	global.get_player().unpause()
