extends Control

const BLINK_DURATION := 0.3
const DONT_CARE_CHOICES := 7
const SPRITES_GAP := 320
const KEYBOARD_ROWS := 5
const MAX_PINYIN_LENGTH := 6

var _scenario_id := "intro"
var _embed_mode := false

var _scenario: Array
var _check_duplicates_in: Array
var _allow_cancel := false
var _input_results := []
var _current_keyboard_panel := 0
var _blacklisted_names = tr("BLACKLISTED_NAMES").split(",")
var _current_step: int = 0
var _input_text := ""
var _current_settings_panel: Control = null
var _callback: FuncRef = funcref(self, "_default_callback")
var _tween: SceneTreeTween
var _highlight_tween: SceneTreeTween
var _pinyin_page = 0#标

onready var _prompt_label := $CanvasLayer/NameBox/Label
onready var _input_label := $CanvasLayer/NameBox/name/Label
onready var _keyboard_arrow := $CanvasLayer/NamingBox/arrow
onready var _settings_arrow := $CanvasLayer/Settings/SettingsArrow
onready var _text_speed_arrow := $CanvasLayer/TextSpeed/TextSpeedArrow
onready var _flavors_arrow := $CanvasLayer/Flavors/FlavorsArrow
onready var _button_prompts_arrow := $CanvasLayer/ButtonPrompts/ButtonPromptsArrow
onready var _confirm_arrow := $CanvasLayer/ConfirmationRight/Surely/ConfirmationArrow
onready var _keyboard_area := $CanvasLayer/NamingBox/Grid
onready var _keyboard_grid_1 := $CanvasLayer/NamingBox/Grid/GridContainer
onready var _keyboard_grid_2 := $CanvasLayer/NamingBox/Grid/GridContainer2
onready var _keyboard_grid_3 := $CanvasLayer/NamingBox/Grid/GridContainer3
onready var _keyboard_grid_dont_care := $CanvasLayer/NamingBox/CommandGrid/GridContainer4
onready var _keyboard_grid_ok_back := $CanvasLayer/NamingBox/CommandGrid/GridContainer5
onready var _panel_switch_button := $CanvasLayer/NamingBox/PressButton/Label
onready var _flavors_menu := $CanvasLayer/Flavors
onready var _text_speed_menu := $CanvasLayer/TextSpeed
onready var _button_prompts_menu := $CanvasLayer/ButtonPrompts
onready var _char_anims := $CharAnims
onready var _menu_anims := $MenuAnims
onready var _actors_container := $Objects/Actors/ActorsSequence
onready var _actors_collection := $Toolbox/Actors
onready var _confirm_collection := $Toolbox/Confirm
onready var _keyboard_dont_care := $"CanvasLayer/NamingBox/CommandGrid/GridContainer4/Don't care"
onready var _keyboard_ok := $CanvasLayer/NamingBox/CommandGrid/GridContainer5/OK
onready var _keyboard_backspace := $CanvasLayer/NamingBox/CommandGrid/GridContainer5/Backspace
onready var _pinyin := $CanvasLayer/Pinyin#标

func init(scenario_id: String, embed_mode := false, callback: FuncRef = funcref(self, "_default_callback")):
	_scenario_id = scenario_id
	_embed_mode = embed_mode
	_callback = callback

func _ready():
	var naming_sequence := globaldata.get_naming_sequence(_scenario_id)
	_scenario = naming_sequence.scenario
	_check_duplicates_in = naming_sequence.get("check_duplicates_in", [])
	_init_sprites()
	
	for step in _scenario:
		var target = step.get("target", "")
		if target in globaldata.characters.keys():
			var value = globaldata.characters.get(step.target)
			if not value is String:
				value = value.get_nickname()
			_input_results.append(value)
		else:
			_input_results.append("")
		
	_blacklisted_names.append("")
	
	_refresh_settings_menu()
	_current_settings_panel = _text_speed_menu
	global.get_player().pause()
	
	if !_embed_mode:
		uiManager.set_cutscene(true)
		global.get_player().hide()
	else:
		$Background.hide()
		$CanvasLayer/NameBox/Mask.hide()
	
	if naming_sequence.has("bgm"):
		if _embed_mode:
			audioManager.pause_all_music_players()
		
		audioManager.play_music(audioManager.CHANNELS.MENU, naming_sequence.bgm)
		audioManager.set_music_player_volume_by_name(audioManager.CHANNELS.MENU, 8)
	
	_refresh_keys()
	
	global.connect("locale_changed", self, "_update_locale")
	
	_char_anims.play("Start")
	_set_new_step()
	
	yield(get_tree().create_timer(0.5), "timeout")
	_allow_cancel = naming_sequence.get("allow_cancel", true)

func _update_locale():
	_toggle_keyboard_panel(0)
	_refresh_keys()

func _set_next_step():
	if _tween and _tween.is_running():
		return

	if _scenario[_current_step].type == "naming":
		if !_validate_current_name():
			return
		_accept_current_name()
	_current_step += 1

	_play_char_anims()
	_set_new_step()

func _validate_current_name() -> bool:
	var error_msg = _check_for_errors(_input_text)
	if error_msg:
		_show_name_error(error_msg)
		return false
	return true

func _accept_current_name():
	_input_results[_current_step] = _input_text
	$OkDesuka.play()
	_change_sprite(1)

func _show_name_error(error_msg: String):
	_prompt_label.text = error_msg
	$BlockName.play()
	if _highlight_tween and _highlight_tween.is_running():
		return
	_highlight_color()
	yield(_highlight_tween, "finished")
	_highlight_tween = create_tween()
	_highlight_tween.tween_property(_prompt_label, "modulate", Color.white, 0.2)
	_set_naming_prompt()

func _set_prev_step():
	if !_tween or !_tween.is_running():
		if _scenario[_current_step].type == "naming":
			_input_results[_current_step] = _input_text
		
		_current_step -= 1
		
		if _current_step < 0:
			if _allow_cancel:
				_keyboard_arrow.on = false
				_finish(false)
			else:
				_current_step = 0
		else:
			audioManager.play_sfx_by_name("menu_close", "swish")
			if _scenario[_current_step].type == "naming":
				_change_sprite(-1)
			
			_play_char_anims(-1)
			_set_new_step()

func _set_new_step():
	_keyboard_arrow.on = false
	_confirm_arrow.on = false
	_settings_arrow.on = false
	if _highlight_tween:
		_highlight_tween.kill()
		_prompt_label.modulate = Color.white
	if _current_step >= _scenario.size():
		_menu_anims.play("ConfirmationClose")
		_save_new_names()
		$OkDesuka.play()
		_finish(true)
	else:
		match (_scenario[_current_step].type):
			"naming":
				_keyboard_arrow.on = true
				_input_text = _input_results[_current_step]
				_reset_keyboard_cursor()
				_set_dots()
				_set_naming_prompt()
				_update_lr_prompts()
				_keyboard_dont_care.visible = _scenario[_current_step].has("dont_care")
			"settings":
				_settings_arrow.hide()
				_menu_anims.play("SettingsOpen")
				if _tween and _tween.is_running():
					yield(_tween, "finished")
					_settings_arrow.set_cursor_from_index(0, false)
					_settings_arrow.on = true
					_settings_arrow.show()
				_on_SettingsArrow_moved(0)
			"confirm":
				_confirm_arrow.hide()
				_refresh_confirmation_view()
				_menu_anims.play("ConfirmationOpen")
				_hide_all_setting_panels()
				yield(_menu_anims, "animation_finished")
				_confirm_arrow.set_cursor_from_index(0, false)
				_confirm_arrow.on = true
				_confirm_arrow.show()

func _input(event: InputEvent):
	if _current_step in range (0,_scenario.size()):
		if _scenario[_current_step].type == "naming":
			if event.is_action_pressed("ui_cancel"):
				_backspace()
			if event.is_action_pressed("ui_scope"):
				_toggle_keyboard_panel()
			if event.is_action_pressed("ui_select"):
				if _scenario[_current_step].has("dont_care"):
					_keyboard_arrow.change_parent(_keyboard_grid_dont_care)
				else:
					_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
					_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.get_last_available_idx())
			if event.is_action_pressed("ui_focus_next") and _can_do_next():
				_set_next_step()
				_pinyin.text = ""#标
			if event.is_action_pressed("ui_focus_prev") and _can_do_prev():
				_set_prev_step()
				_pinyin.text = ""#标
		elif _scenario[_current_step].type == "confirm":
			if event.is_action_pressed("ui_cancel"):
				_restart_sequence()
	
	if OS.is_debug_build() and event.is_action_pressed("ui_toggle"):
		for i in range(_scenario.size()):
			if _scenario[i].type == "naming" and _scenario[i].has("dont_care"):
					_input_results[i] = tr(_scenario[i].dont_care + "0")
		_save_new_names()
		_finish(true)

func _init_sprites():
	for i in _scenario.size():
		var _sprite_name = _scenario[i].get("sprite")
		if _sprite_name:
			var _sprite = _actors_collection.get_node_or_null(_sprite_name)
			var _new_sprite
			if _sprite:
				_new_sprite = _actors_collection.get_node(_sprite_name).duplicate()
			else:
				_new_sprite = load("res://Nodes/Reusables/npc.tscn").instance()
				_new_sprite.sprite = _sprite_name + "/main"
				_new_sprite.idle_animation = "Walk"
			_new_sprite.position.x = i * SPRITES_GAP
			_actors_container.add_child(_new_sprite)

func _highlight_color():
	_highlight_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	for i in range(2):
		_highlight_tween.tween_property(_prompt_label, "modulate", Color(TextTools.DIALOG_HINT_COLOR), BLINK_DURATION) \
				.set_ease(Tween.EASE_OUT)
		_highlight_tween.tween_property(_prompt_label, "modulate", Color.white, BLINK_DURATION) \
				.set_ease(Tween.EASE_OUT)
	_highlight_tween.tween_property(_prompt_label, "modulate", Color.white, 0.8)

func _reset_keyboard_cursor():
	_keyboard_arrow.change_parent(_keyboard_grid_1, false)
	_keyboard_arrow.cursor_index = 0
	_keyboard_arrow.set_cursor_from_index(0, true)

func _set_dots():
	_input_label.text = _input_text
	var max_characters = tr(_scenario[_current_step].longest_name).length()
	if len(_input_label.text) < max_characters:
		_input_label.text += tr("SYMBOL_BULLET_NAMING")
		for i in max_characters - len(_input_label.text):
			_input_label.text += tr("SYMBOL_DOT")

func _set_naming_prompt():
	if _scenario[_current_step].has("prompt"):
		_prompt_label.text = _scenario[_current_step].prompt

func _play_char_anims(direction: int = 1):
	if _current_step - direction in range(0, _scenario.size()):
		_play_char_anim(_scenario[_current_step - direction].char_anims_leave)
	if _current_step in range(0, _scenario.size()):
		_play_char_anim(_scenario[_current_step].char_anims_enter)

func _play_char_anim(sequences: Array):
	if sequences.empty():
		return
	_char_anims.play(sequences[0])
	for i in range(1,sequences.size()):
		yield(_char_anims, "animation_finished")
		_char_anims.play(sequences[i])

func _change_sprite(direction: int, reset = false):
	var final_val = _actors_container.position.x - (SPRITES_GAP * direction) if !reset else 0
	var duration = 1.0 if !reset else 1.5
	var trans_type = Tween.TRANS_QUART if !reset else Tween.TRANS_QUAD
	var ease_type = Tween.EASE_IN_OUT if !reset else Tween.EASE_OUT
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(_actors_container, "position:x", final_val, duration) \
			.set_trans(trans_type).set_ease(ease_type)

func _update_lr_prompts():
	$CanvasLayer/NameBox/Indicator.visible = _can_do_prev()
	$CanvasLayer/NameBox/Indicator2.visible = _can_do_next()

func _can_do_prev():
	return _scenario[_current_step].type == "naming" and _current_step > 0

func _can_do_next():
	return _scenario[_current_step].type == "naming" and _current_step < _scenario.size() - 1 and !_input_text.empty()

func _refresh_keys():
	var gridId = 0
	for parent in _keyboard_area.get_children():
		if parent is GridContainer && !parent in [_keyboard_grid_dont_care, _keyboard_grid_ok_back]:
			var letters = tr("KEYBOARD_PANEL%s_GRID%s" % [_current_keyboard_panel,gridId])
			# In case we need to set a different number of columns for different languages
			#parent.columns = len(letters) / KEYBOARD_ROWS
			for i in parent.get_child_count():
				var label = parent.get_child(i)
				var lower_label: Label
				if label.get_child_count() == 0:
					lower_label = label.duplicate()
					label.add_child(lower_label)
					label.percent_visible = 0
					lower_label.rect_position = Vector2.ZERO
				else:
					lower_label = label.get_child(0)
				var letter = letters[i] if i < len(letters) else ""
				letter = letter.replace("_", "")
				lower_label.text = letter
				label.text = "A" if !letter in ["", "⁦"]  else ""
			gridId += 1
	
	var next_current_keyboard_panel = fmod(_current_keyboard_panel + 1, _count_keyboard_panels())
	_panel_switch_button.text = "KEYBOARD_PANEL%s_NAME" % next_current_keyboard_panel

func _toggle_keyboard_panel(dir: int = 1):
	_current_keyboard_panel = int(fmod(_current_keyboard_panel + dir, _count_keyboard_panels()))
	_refresh_keys()
	_pinyin.text = ""
	if _keyboard_arrow.menu_parent.get_child(_keyboard_arrow.cursor_index).text == "":
		_reset_keyboard_cursor()
	if dir != 0:
		if _current_keyboard_panel == _count_keyboard_panels() - 1:
			audioManager.play_sfx_by_name("menu_close2", "casing")
		else:
			audioManager.play_sfx_by_name("menu_open2", "casing")

func _count_keyboard_panels():
	var i = 0
	while tr("KEYBOARD_PANEL%s_GRID1" % i) != "KEYBOARD_PANEL%s_GRID1" % i:
		i += 1
	return i

func _keyboard_char_addition(character):#标：记得csv与字库
	var lang = tr("LANGUAGE_CODE")
	if lang == "ko":
		var hangul_addition = KoreanHangul.compose_addition(_input_text, character)
		if hangul_addition:
			_input_text = hangul_addition
			return true
	
	if lang == "zh_Hans_CN" and _current_keyboard_panel == 0:
		var is_letter = ChinesePinyin.is_pinyin_char(character)   # 判断是否为有效拼音字母
		var is_page_key = character in "◂▸"
		
		if is_letter:
			_pinyin_page = 0
			if len(_pinyin.text) >= MAX_PINYIN_LENGTH:
				return false
			_pinyin.text += character.to_lower()
		elif is_page_key:
			var candidates = ChinesePinyin.get_candidates_for_input(_pinyin.text)
			_pinyin_page = ChinesePinyin.compare_page(_pinyin_page, character, candidates)
		else:
			_pinyin_page = 0
			_pinyin.text = ""
			_reset_keyboard_cursor()
		
		var candidates = ChinesePinyin.get_candidates_for_input(_pinyin.text)
		ChinesePinyin.show_candidates_on_grid(candidates, _pinyin_page, _keyboard_grid_1, _keyboard_grid_2, _keyboard_grid_3)
		
		if is_letter or is_page_key:
			return true

	if len(_input_text) < tr(_scenario[_current_step].longest_name).length():
		_input_text += character
		return true
	
	return false

func _keyboard_char_removal():#标
	var lang = tr("LANGUAGE_CODE")
	if lang == "ko":
		var hangul_removal = KoreanHangul.compose_removal(_input_text)
		if hangul_removal:
			_input_text = hangul_removal
			return
	if lang == "zh_Hans_CN" and _current_keyboard_panel == 0 and _pinyin.text != "":
		_pinyin_page = 0
		_pinyin.text = _pinyin.text.left(_pinyin.text.length() - 1)
		var candidates = ChinesePinyin.get_candidates_for_input(_pinyin.text)
		ChinesePinyin.show_candidates_on_grid(candidates, _pinyin_page, _keyboard_grid_1, _keyboard_grid_2, _keyboard_grid_3)
		if (_keyboard_arrow.menu_parent in [_keyboard_grid_2, _keyboard_grid_3] and _pinyin.text == "") \
				or _keyboard_arrow.menu_parent.get_child(_keyboard_arrow.cursor_index).text == "":
			_reset_keyboard_cursor()
		return
	if _input_text != "":
		_input_text = _input_text.left(_input_text.length() - 1)

func _backspace():
	if _input_text != "" or _pinyin.text != "":#标
		_keyboard_char_removal()
		_set_dots()
		_update_lr_prompts()
		_keyboard_arrow.play_sfx("back")
	else:
		_set_prev_step()

func _check_for_errors(name_to_check: String):
	var checkname = name_to_check.to_lower().strip_edges()
	# Checking for blacklisted names
	if checkname in _blacklisted_names:
		return "NAME_BLOCKED"
	# Checking for identical names from other steps
	for index in range(len(_input_results)):
		if index != _current_step and checkname == _input_results[index].to_lower().strip_edges():
			return "NAME_DUPLICATED"
	# Checking for identical names in previous naming scenarios
	for other_name_id in _check_duplicates_in:
		if other_name_id in globaldata.characters.keys():
			var other_name = globaldata.characters.get(other_name_id)
			if not other_name is String:
				other_name = other_name.get_nickname()
			if checkname == other_name.to_lower().strip_edges():
				return "NAME_DUPLICATED"

func _set_dont_care():
	var index = 0
	for i in DONT_CARE_CHOICES:
		if _input_text == tr(_scenario[_current_step].dont_care + str(i)):
			index = fmod(i + 1, DONT_CARE_CHOICES)
			break
	_input_text = tr(_scenario[_current_step].dont_care + str(index))
	_update_lr_prompts()
	_set_dots()

func _show_setting_panel(menu: Control):
	_hide_all_setting_panels()
	_current_settings_panel = menu
	if _tween and _tween.is_running():
		yield(_tween, "finished")
	if _current_settings_panel == menu:
		_tween = create_tween()
		_tween.tween_property(menu, "rect_position:x", 184, 0.2) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		if menu == _button_prompts_menu:
			_button_prompts_menu.refresh(false)

func _refresh_settings_menu():
	var speed_index = globaldata.TEXT_SPEEDS.find(globaldata.text_speed)
	$CanvasLayer/Settings/VBoxContainer2/Speed.text = "MENU_" + globaldata.TEXT_SPEEDS_NAMES[speed_index]
	$CanvasLayer/Settings/VBoxContainer2/Flavor.text = "FLAVOR_" + globaldata.menu_flavor.to_upper()
	$CanvasLayer/Settings/VBoxContainer2/Prompts.text = "MENU_" + globaldata.button_prompts.to_upper()

func _refresh_settings_selections(index: int):
	match index:
		0:
			_text_speed_arrow.set_cursor_from_index(globaldata.TEXT_SPEEDS.find(globaldata.text_speed), false)
		1:
			_flavors_arrow.set_cursor_from_index(globaldata.FLAVORS.find(globaldata.menu_flavor), false)
		2:
			_button_prompts_arrow.set_cursor_from_index(globaldata.BUTTON_PROMPTS.find(globaldata.button_prompts), false)
			_button_prompts_menu.refresh(false)

func _hide_all_setting_panels():
	_current_settings_panel = null
	if _tween: _tween.kill()
	_tween = create_tween()
	for i in [_text_speed_menu, _flavors_menu, _button_prompts_menu]:
		_tween.parallel().tween_property(i, "rect_position:x", 328, 0.2) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _refresh_confirmation_view():
	for i in _input_results.size():
		if _scenario[i].type == "naming":
			var res_node = find_node("Confirm%s" % i)
			res_node.get_node("Label").text = _input_results[i]
			var image_node = _confirm_collection.get_node(_scenario[i].sprite).duplicate()
			res_node.add_child(image_node)

func _restart_sequence():
	_change_sprite(0, true)
	_menu_anims.play("Naming Open")
	_current_step = 0

	_play_char_anims()
	_set_new_step()

func _save_new_names():
	for i in _scenario.size():
		if _scenario[i].has("target"):
			var target = _scenario[i].target
			if target in globaldata.characters.keys():
				globaldata.characters.get(target).set_nickname(_input_results[i])
			elif target in globaldata and globaldata.get(target) is String:
				globaldata.set(target, _input_results[i])

func _finish(completed: bool):
	if _embed_mode:
		audioManager.stop_music_player_by_name(audioManager.CHANNELS.MENU)
		audioManager.resume_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
		uiManager.remove_ui(self)
		queue_free()
	else:
		uiManager.set_cutscene(false)
	
	if _callback and _callback.is_valid():
		_callback.call_func(completed)
		_callback = null

func _default_callback(completed: bool):
	if completed:
		$Objects/DoorToIntro.enter()
	else:
		audioManager.stop_all_music_players()
		$Objects/DoorToTitle.enter()

func _on_arrow_selected(cursor_index: int):
	match _keyboard_arrow.get_current_item():
		_keyboard_dont_care:
			_set_dont_care()
			_keyboard_arrow.play_sfx("cursor2")
		_keyboard_backspace:
			_backspace()
		_keyboard_ok:
			if _input_text != "":
				_set_next_step()
				_pinyin.text = ""#标
		_:
			var character = ""
			if _keyboard_arrow.menu_parent.get_child(cursor_index).percent_visible == 1:
				character = tr(_keyboard_arrow.menu_parent.get_child(cursor_index).text)
			else:
				character = tr(_keyboard_arrow.menu_parent.get_child(cursor_index).get_child(0).text)
			var has_text_changed = _keyboard_char_addition(character)
			if has_text_changed:
				_set_dots()
				_update_lr_prompts()
				_keyboard_arrow.play_sfx("cursor2")

func _on_arrow_failed_move(dir: Vector2):
	var index = 0
	match _keyboard_arrow.menu_parent:
		_keyboard_grid_1:
			match dir:
				Vector2.LEFT:
					if _keyboard_arrow.change_parent(_keyboard_grid_3):
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index + _keyboard_grid_3.columns - 1)
					elif _keyboard_arrow.change_parent(_keyboard_grid_2):
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index + _keyboard_grid_2.columns - 1)
					else:
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index + _keyboard_grid_1.columns - 1, true, true)
				Vector2.RIGHT:
					if !_keyboard_arrow.change_parent(_keyboard_grid_2):
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index - _keyboard_grid_1.columns + 1, true, true)
				Vector2.UP:
					_keyboard_arrow.change_parent(_keyboard_grid_dont_care) \
					or _keyboard_arrow.set_cursor_from_index(_keyboard_grid_1.get_child_count() - _keyboard_grid_1.columns + (_keyboard_arrow.cursor_index % _keyboard_grid_1.columns), true, true)
				Vector2.DOWN:
					_keyboard_arrow.change_parent(_keyboard_grid_dont_care) or _keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index % _keyboard_grid_1.columns, true, true)
		_keyboard_grid_2:
			match dir:
				Vector2.LEFT:
					_keyboard_arrow.change_parent(_keyboard_grid_1)
				Vector2.RIGHT:
					if !_keyboard_arrow.change_parent(_keyboard_grid_3):
						_keyboard_arrow.change_parent(_keyboard_grid_1)
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index - _keyboard_grid_1.columns + 1)
				Vector2.UP:
					if _keyboard_arrow.cursor_index % _keyboard_grid_2.columns >= _keyboard_grid_2.columns/2:
						_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
						_keyboard_arrow.set_cursor_from_index(0)
					else:
						_keyboard_arrow.change_parent(_keyboard_grid_dont_care) \
						or _keyboard_arrow.set_cursor_from_index(_keyboard_grid_2.get_child_count() - _keyboard_grid_2.columns + (_keyboard_arrow.cursor_index % _keyboard_grid_2.columns), true, true)
				Vector2.DOWN:
					if _keyboard_arrow.cursor_index % _keyboard_grid_2.columns >= _keyboard_grid_2.columns/2:
						_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
					else:
						_keyboard_arrow.change_parent(_keyboard_grid_dont_care) \
						or _keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index % _keyboard_grid_2.columns, true, true)
		_keyboard_grid_3:
			match dir:
				Vector2.LEFT:
					if !_keyboard_arrow.change_parent(_keyboard_grid_2):
						_keyboard_arrow.change_parent(_keyboard_grid_1)
				Vector2.RIGHT:
					if _keyboard_arrow.change_parent(_keyboard_grid_1):
						_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index - _keyboard_grid_1.columns + 1)
				Vector2.UP:
					_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
				Vector2.DOWN:
					_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
		_keyboard_grid_dont_care:
			match dir:
				Vector2.LEFT:
					_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
					_keyboard_arrow.set_cursor_from_index(_keyboard_arrow.cursor_index + _keyboard_grid_ok_back.columns - 1)
				Vector2.RIGHT:
					_keyboard_arrow.change_parent(_keyboard_grid_ok_back)
				Vector2.UP:
					_keyboard_arrow.change_parent(_keyboard_grid_1)
				Vector2.DOWN:
					_keyboard_arrow.change_parent(_keyboard_grid_1)
					_keyboard_arrow.set_cursor_from_index(0)
		_keyboard_grid_ok_back:
			match dir:
				Vector2.LEFT:
					_keyboard_arrow.change_parent(_keyboard_grid_dont_care) or _keyboard_arrow.set_cursor_from_index(_keyboard_arrow.get_last_available_idx(), true, true)
				Vector2.RIGHT:
					_keyboard_arrow.change_parent(_keyboard_grid_dont_care) or _keyboard_arrow.set_cursor_from_index(_keyboard_arrow.get_first_available_idx(), true, true)
				Vector2.UP:
					_keyboard_arrow.change_parent(_keyboard_grid_3)
				Vector2.DOWN:
					_keyboard_arrow.change_parent(_keyboard_grid_3)
					if _keyboard_arrow.cursor_index == 0:
						_keyboard_arrow.set_cursor_from_index(0)
					else:
						_keyboard_arrow.set_cursor_from_index(_keyboard_grid_3.columns - 1)

func _on_SettingsArrow_moved(_dir):
	match _settings_arrow.cursor_index:
		0:
			_show_setting_panel(_text_speed_menu)
		1:
			_show_setting_panel(_flavors_menu)
		2:
			_show_setting_panel(_button_prompts_menu)
		3:
			_hide_all_setting_panels()

func _on_SettingsArrow_selected(_cursor_index):
	_settings_arrow.on = false
	if _tween and _tween.is_running(): yield(_tween, "finished")
	match _settings_arrow.cursor_index:
		0:
			_text_speed_arrow.on = true
			_text_speed_arrow.show()
		1:
			_flavors_arrow.on = true
			_flavors_arrow.show()
		2:
			_button_prompts_arrow.on = true
			_button_prompts_arrow.show()
			_button_prompts_menu.refresh(false)
		3:
			_set_next_step()
			_pinyin.text = ""#标
			return
	
	_refresh_settings_selections(_settings_arrow.cursor_index)

func _on_SettingsArrow_cancel():
	_hide_all_setting_panels()
	_settings_arrow.on = false
	_keyboard_arrow.on = true
	_keyboard_arrow.hide()
	_keyboard_arrow.set_cursor_from_index(0, false)
	_menu_anims.play("SettingsClose")
	if _tween and _tween.is_running():
		yield(_tween, "finished")
	_set_prev_step()

func _on_TextSpeedArrow_selected(cursor_index: int):
	_settings_arrow.on = true
	_text_speed_arrow.on = false
	_text_speed_arrow.hide()
	globaldata.text_speed = globaldata.TEXT_SPEEDS[cursor_index]
	_refresh_settings_menu()

func _on_TextSpeedArrow_cancel():
	_settings_arrow.on = true
	_text_speed_arrow.on = false
	_text_speed_arrow.hide()
	_text_speed_arrow.get_current_item().percent_visible = 1

func _on_FlavorsArrow_selected(cursor_index: int):
	_settings_arrow.on = true
	_flavors_arrow.on = false
	_flavors_arrow.hide()
	globaldata.menu_flavor = globaldata.FLAVORS[cursor_index]
	_refresh_settings_menu()

func _on_FlavorsArrow_cancel():
	uiManager.set_menu_flavors(globaldata.menu_flavor)
	_settings_arrow.on = true
	_flavors_arrow.on = false
	_flavors_arrow.hide()

func _on_ButtonPromptsArrow_selected(cursor_index: int):
	_settings_arrow.on = true
	_button_prompts_arrow.on = false
	_button_prompts_arrow.hide()
	globaldata.button_prompts = globaldata.BUTTON_PROMPTS[cursor_index]
	_refresh_settings_menu()

func _on_ButtonPromptsArrow_cancel():
	_settings_arrow.on = true
	_button_prompts_arrow.on = false
	_button_prompts_arrow.hide()
	_refresh_settings_selections(2)

func _on_ConfirmationArrow_selected(cursor_index: int):
	_confirm_arrow.on = false
	match cursor_index:
		0:
			_set_next_step()
			_pinyin.text = ""#标
		1:
			_restart_sequence()

func _on_ConfirmationArrow_cancel():
	_restart_sequence()
