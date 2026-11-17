extends CanvasLayer

signal back
signal close_to_title

enum {  
	OPTN_MENU_START = -1,
	OPTN_MAIN_FILE_SETTINGS, 
	OPTN_MAIN_GENERAL_SETTINGS, 
	OPTN_MAIN_TITLE_SCREEN, 
	OPTN_MAIN_QUIT,
	OPTN_FILE_TEXT_SPEED,
	OPTN_FILE_MENU_FLAVOR,
	OPTN_FILE_BUTTON_PROMPTS,
	OPTN_SETTINGS_AUDIO,
	OPTN_SETTINGS_VIDEO,
	OPTN_SETTINGS_CONTROLS,
	OPTN_SETTINGS_LANGUAGE,
	OPTN_SETTINGS_MASTER_VOLUME,
	OPTN_SETTINGS_MUSIC_VOLUME,
	OPTN_SETTINGS_SFX_VOLUME,
	OPTN_SETTINGS_RESOLUTION,
	OPTN_SETTINGS_FULLSCREEN,
	OPTN_SETTINGS_INT_SCALING,
	OPTN_SETTINGS_VSYNC,
	OPTN_SETTINGS_VIEWCREDITS,
	OPTN_SETTINGS_VIEWCREDITSACT1,
	OPTN_SETTINGS_VIEWCREDITSACT2,
	OPTN_SETTINGS_VIEWCREDITSFULL,
}
const NAV := {
	OPTN_MENU_START: [
		OPTN_MAIN_FILE_SETTINGS,
		OPTN_MAIN_GENERAL_SETTINGS,
		OPTN_MAIN_TITLE_SCREEN,
		OPTN_MAIN_QUIT
	],
	OPTN_MAIN_FILE_SETTINGS: [
		OPTN_FILE_TEXT_SPEED,
		OPTN_FILE_MENU_FLAVOR,
		OPTN_FILE_BUTTON_PROMPTS
	],
	OPTN_MAIN_GENERAL_SETTINGS: [
		OPTN_SETTINGS_AUDIO,
		OPTN_SETTINGS_VIDEO,
		OPTN_SETTINGS_CONTROLS,
		OPTN_SETTINGS_LANGUAGE,
		OPTN_SETTINGS_VIEWCREDITS
	],
	OPTN_SETTINGS_AUDIO: [
		OPTN_SETTINGS_MASTER_VOLUME,
		OPTN_SETTINGS_MUSIC_VOLUME,
		OPTN_SETTINGS_SFX_VOLUME
	],
	OPTN_SETTINGS_VIDEO: [
		OPTN_SETTINGS_RESOLUTION,
		OPTN_SETTINGS_FULLSCREEN,
		OPTN_SETTINGS_INT_SCALING,
		OPTN_SETTINGS_VSYNC
	],
	OPTN_SETTINGS_VIEWCREDITS: [
		OPTN_SETTINGS_VIEWCREDITSACT1,
		OPTN_SETTINGS_VIEWCREDITSACT2,
		OPTN_SETTINGS_VIEWCREDITSFULL
	]
}

const TITLES := {
	OPTN_MENU_START: "MENU_TITLE_OPTIONS",
	OPTN_MAIN_FILE_SETTINGS: "OPTIONS_FILESETTINGS",
	OPTN_MAIN_GENERAL_SETTINGS: "OPTIONS_SETTINGS",
	OPTN_SETTINGS_AUDIO: "OPTIONS_AUDIO",
	OPTN_SETTINGS_VIDEO: "OPTIONS_VIDEO",
	OPTN_SETTINGS_VIEWCREDITS: "OPTIONS_VIEWCREDITS"
}

const TITLE_SCREEN_ONLY := [
	OPTN_SETTINGS_VIEWCREDITS
]

const PATH_TITLE_SCREEN_SCENE := "Title screen"
const PATH_CREDITS_ACT1_SCENE := "Cutscenes/credits_act_1"
const PATH_CREDITS_ACT2_SCENE := "Cutscenes/credits_act_2"
const PATH_CREDITS_FULL_SCENE := "Cutscenes/credits_full"

const SAVE_ONLY := []

const VOLUME_GRADES := 11

export (NodePath) onready var _options_title = get_node(_options_title) as Label
export (NodePath) onready var _options_list = get_node(_options_list) as VBoxContainer
export (NodePath) onready var _cursor = get_node(_cursor) as Cursor

export (NodePath) onready var _confirm_dialog = get_node(_confirm_dialog) as PanelContainer

export (NodePath) onready var _panel_text_speed = get_node(_panel_text_speed) as NinePatchRect
export (NodePath) onready var _panel_text_speed_cursor = get_node(_panel_text_speed_cursor) as Cursor
export (NodePath) onready var _panel_flavors = get_node(_panel_flavors) as NinePatchRect
export (NodePath) onready var _panel_flavors_cursor = get_node(_panel_flavors_cursor) as Cursor
export (NodePath) onready var _panel_button_prompts = get_node(_panel_button_prompts) as NinePatchRect
export (NodePath) onready var _panel_button_prompts_cursor = get_node(_panel_button_prompts_cursor) as Cursor
export (NodePath) onready var _panel_controls = get_node(_panel_controls) as PanelContainer
export (NodePath) onready var _panel_generic = get_node(_panel_generic) as PanelContainer

onready var _transition_door = $OptionsMenu/Door

export var _from_save := true
export var _always_visible := false

var _first_level_menu := OPTN_MENU_START
var _nav_stack := [ ]
var _door_duplicate

var _volume_values: Array
var _language_values: Array
var _confirmation_type: String

func _ready():
	$OptionsMenu.hide()
	_language_values = global.get_supported_languages().duplicate()
	_language_values.sort_custom(self, "_sort_languages")
	
	if not _from_save:
		_first_level_menu = OPTN_MAIN_GENERAL_SETTINGS
	if _always_visible:
		show_options()
	global.connect("settings_changed", self, "_refresh_values")
	global.connect("locale_changed", self, "_refresh_values")
	_panel_controls.connect("exited", self, "_on_submenu_arrow_cancel")
	_volume_values = []
	for i in range(VOLUME_GRADES - 1, -1, -1):
		_volume_values.append(_volume_units_to_db(i))
	
	_door_duplicate = _transition_door.duplicate()

func show_options():
	$OptionsMenu.show()
	_nav_stack.push_front(_first_level_menu)
	_cursor.on = true
	_refresh_options_list()
	_refresh_values()
	if !is_instance_valid(_transition_door): # If the door was deleted because of returning to title screen, we make a new one
		var new_door = _door_duplicate.duplicate()
		$OptionsMenu.add_child(new_door)
		_transition_door = new_door

func _hide_options():
	global.save_settings()
	_cursor.on = false
	Input.action_release("ui_cancel")
	emit_signal("back")
	if _always_visible:
		_transition_door.enter()
	else:
		$OptionsMenu.hide()

func _refresh_options_list(back_from := -1):
	var cur_menu_content := []

	if !_nav_stack.empty():
		var cur_menu: int = _nav_stack.front()
		cur_menu_content = NAV.get(cur_menu, [])
		_options_title.text = TITLES.get(cur_menu, "MENU_TITLE_OPTIONS")
	
	for i in _options_list.get_child_count():
		_options_list.get_child(i).hide()
	
	if !cur_menu_content.empty():
		yield(_options_list, "resized")
		for id in cur_menu_content:
			if (_from_save and TITLE_SCREEN_ONLY.has(id))\
			or (!_from_save and SAVE_ONLY.has(id)):
				continue
			var label = _options_list.get_child(id)
			label.show()
			yield(label, "draw")
		var index_to_select = (back_from if back_from >= 0 else cur_menu_content[0])
		_cursor.set_cursor_from_index(index_to_select, false)
		_refresh_highlights()

func _refresh_values():
	var text_speed_idx := abs(globaldata.TEXT_SPEEDS.find(globaldata.text_speed)) # abs() sets it to 1 if -1
	
	var values := {
		OPTN_FILE_TEXT_SPEED: "MENU_" + globaldata.TEXT_SPEEDS_NAMES[text_speed_idx],
		OPTN_FILE_MENU_FLAVOR: "FLAVOR_" + globaldata.menu_flavor.to_upper(),
		OPTN_FILE_BUTTON_PROMPTS: "MENU_" + globaldata.button_prompts.to_upper(),
		OPTN_SETTINGS_LANGUAGE: _get_language_as_text(tr("LANGUAGE_CODE")),
		OPTN_SETTINGS_MASTER_VOLUME: _volume_db_to_units(globaldata.master_volume),
		OPTN_SETTINGS_MUSIC_VOLUME: _volume_db_to_units(globaldata.music_volume),
		OPTN_SETTINGS_SFX_VOLUME: _volume_db_to_units(globaldata.sfx_volume),
		OPTN_SETTINGS_RESOLUTION: _get_resolution_as_text(globaldata.win_size),
		OPTN_SETTINGS_FULLSCREEN: "OPTIONS_ON" if OS.window_fullscreen else "OPTIONS_OFF",
		OPTN_SETTINGS_INT_SCALING: "OPTIONS_ON" if IntegerResolutionHandler.is_active() else "OPTIONS_OFF",
		OPTN_SETTINGS_VSYNC: "OPTIONS_ON" if OS.vsync_enabled else "OPTIONS_OFF"
	}
	
	for menu_id in values:
		var node = _options_list.get_child(menu_id)
		if node is Label or node is OptionsSwitch:
			node.text = values[menu_id]
		else:
			node.value = values[menu_id]
	
	_panel_text_speed_cursor.set_cursor_from_index(text_speed_idx, false)
	_panel_flavors_cursor.set_cursor_from_index(globaldata.FLAVORS.find(globaldata.menu_flavor), false)
	_panel_button_prompts_cursor.set_cursor_from_index(globaldata.BUTTON_PROMPTS.find(globaldata.button_prompts), false)
	_refresh_highlights()

func _refresh_highlights():
	# Animate controls when the cursor is over them

	_options_list.get_child(OPTN_SETTINGS_MASTER_VOLUME).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_MASTER_VOLUME)
	_options_list.get_child(OPTN_SETTINGS_MUSIC_VOLUME).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_MUSIC_VOLUME)
	_options_list.get_child(OPTN_SETTINGS_SFX_VOLUME).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_SFX_VOLUME)
	_options_list.get_child(OPTN_SETTINGS_FULLSCREEN).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_FULLSCREEN)
	_options_list.get_child(OPTN_SETTINGS_INT_SCALING).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_INT_SCALING)
	_options_list.get_child(OPTN_SETTINGS_VSYNC).highlighted = (_cursor.cursor_index == OPTN_SETTINGS_VSYNC)

func _on_arrow_selected(cursor_index: int):
	_cursor.on = false

	if cursor_index in NAV:
		_nav_stack.push_front(cursor_index)
		_refresh_options_list()
		_cursor.on = true

	match cursor_index:
		OPTN_FILE_TEXT_SPEED: # Text Speed
			_panel_text_speed.show()
			_panel_text_speed_cursor.on = true
			_panel_text_speed._on_TextSpeedArrow_moved(null)
		OPTN_FILE_MENU_FLAVOR: # Menu Flavors
			_panel_flavors.show()
			_panel_flavors_cursor.on = true
		OPTN_FILE_BUTTON_PROMPTS: # Button Prompts
			_panel_button_prompts.show()
			_panel_button_prompts_cursor.on = true
			_panel_button_prompts.refresh(true)
		OPTN_SETTINGS_CONTROLS: # Controls
			_panel_controls.activate()
		OPTN_SETTINGS_LANGUAGE: # Language
			_panel_generic.open(_language_values, funcref(self, "_on_generic_option_back"), tr("LANGUAGE_CODE"), funcref(self,"_get_language_as_text"), funcref(self, "_is_language_enabled"))
		OPTN_SETTINGS_MUSIC_VOLUME: # Music Volume
			var volumeIdx = _volume_values.find(_discretize_volume(globaldata.music_volume))
			volumeIdx = max(volumeIdx - 1, 0)
			global.set_music_volume(_volume_values[volumeIdx])
			_cursor.on = true
		OPTN_SETTINGS_MASTER_VOLUME: # Master Volume
			var volumeIdx = _volume_values.find(_discretize_volume(globaldata.master_volume))
			volumeIdx = max(volumeIdx - 1, 0)
			global.set_master_volume(_volume_values[volumeIdx])
			_cursor.on = true
		OPTN_SETTINGS_SFX_VOLUME: # SFX Volume
			var volumeIdx = _volume_values.find(_discretize_volume(globaldata.sfx_volume))
			volumeIdx = max(volumeIdx - 1, 0)
			global.set_sfx_volume(_volume_values[volumeIdx])
			_cursor.on = true
		OPTN_SETTINGS_RESOLUTION: # Resolution
			var resolutions = _get_resolutions()
			_panel_generic.open(resolutions, funcref(self, "_on_generic_option_back"), resolutions[globaldata.win_size - 1])
		OPTN_SETTINGS_FULLSCREEN: # Full Screen
			global.toggle_fullscreen()
			_cursor.on = true
		OPTN_SETTINGS_INT_SCALING: # Integer Scaling
			IntegerResolutionHandler.toggle_active()
			_cursor.on = true
		OPTN_SETTINGS_VSYNC: # V-Sync
			OS.vsync_enabled = !OS.vsync_enabled
			_cursor.on = true
		OPTN_SETTINGS_VIEWCREDITSACT1:
			_enter_transition_door(PATH_CREDITS_ACT1_SCENE)
		OPTN_SETTINGS_VIEWCREDITSACT2:
			_enter_transition_door(PATH_CREDITS_ACT2_SCENE)
		OPTN_SETTINGS_VIEWCREDITSFULL:
			_enter_transition_door(PATH_CREDITS_FULL_SCENE)
		OPTN_MAIN_TITLE_SCREEN: # Title Screen
			_confirm_dialog.start_with_options("OPTIONS_TITLESCREEN_CONFIRM", funcref(self, "_on_close_to_title_confirm"))
		OPTN_MAIN_QUIT: # Close game
			_confirm_dialog.start_with_options("OPTIONS_QUIT_CONFIRM", funcref(self, "_on_quit_game_confirm"))
	
	_refresh_values()

func _input(event: InputEvent):
	if _cursor.is_active():
		match _cursor.cursor_index:
			OPTN_SETTINGS_RESOLUTION: # Resolution
				pass
			OPTN_SETTINGS_FULLSCREEN: # Full Screen
				if controlsManager.get_just_released_input_vector().x != 0: # Changed to key release to avoid "fullscreen loop of hell" on Mac
					global.toggle_fullscreen()
					_cursor.play_sfx("cursor2")
					_refresh_values()
			OPTN_SETTINGS_INT_SCALING: # Integer Scaling
				if controlsManager.get_just_pressed_input_vector().x != 0:
					IntegerResolutionHandler.toggle_active()
					_cursor.play_sfx("cursor2")
					_refresh_values()
			OPTN_SETTINGS_VSYNC: # V-Sync
				if controlsManager.get_just_pressed_input_vector().x != 0:
					OS.vsync_enabled = !OS.vsync_enabled
					_cursor.play_sfx("cursor2")
					_refresh_values()

func _on_arrow_failed_move(dir: Vector2):
	if _cursor.is_active():
		match _cursor.cursor_index:
			OPTN_SETTINGS_MASTER_VOLUME: # Master Volume
				var volume_idx := _volume_values.find(_discretize_volume(globaldata.master_volume))
				if dir.x < 0:
					volume_idx = int(min(volume_idx + 1, VOLUME_GRADES - 1))
					global.set_master_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()
				elif dir.x > 0:
					volume_idx = int(max(volume_idx - 1, 0))
					global.set_master_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()
			OPTN_SETTINGS_MUSIC_VOLUME: # Music Volume
				var volume_idx := _volume_values.find(_discretize_volume(globaldata.music_volume))
				if dir.x < 0:
					volume_idx = int(min(volume_idx + 1, VOLUME_GRADES - 1))
					global.set_music_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()
				elif dir.x > 0:
					volume_idx = int(max(volume_idx - 1, 0))
					global.set_music_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()
			OPTN_SETTINGS_SFX_VOLUME: # SFX Volume
				var volume_idx = _volume_values.find(_discretize_volume(globaldata.sfx_volume))
				if dir.x < 0:
					volume_idx = int(min(volume_idx + 1, VOLUME_GRADES - 1))
					global.set_sfx_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()
				elif dir.x > 0:
					volume_idx = int(max(volume_idx - 1, 0))
					global.set_sfx_volume(_volume_values[volume_idx])
					_cursor.play_sfx("cursor2")
					_refresh_values()

func _on_arrow_moved(dir: Vector2):
	_refresh_highlights()

func _on_arrow_cancel():
	if !global.entering_door:
		var from_menu: int = _nav_stack.pop_front()
		
		_cursor.play_sfx("back")
		if !_nav_stack.empty():
			_refresh_options_list(from_menu)
		else:
			_hide_options()

func _on_close_to_title_confirm(answer: bool):
	if answer:
		global.save_settings()
		_enter_transition_door("Title screen")
		$OptionsMenu.hide()
		global.stop_playtime()
		emit_signal("close_to_title")
	else:
		_cursor.on = true

func _on_quit_game_confirm(answer: bool):
	if answer:
		global.save_settings()
		get_tree().quit()
	else:
		_cursor.on = true

func _on_text_speed_arrow_selected(cursor_index):
	_cursor.on = true
	_panel_text_speed_cursor.on = false
	_panel_text_speed.hide()

	globaldata.text_speed = globaldata.TEXT_SPEEDS[cursor_index]
	_refresh_values()

func _on_flavors_arrow_selected(cursor_index):
	_cursor.on = true
	_panel_flavors_cursor.on = false
	_panel_flavors.hide()

	globaldata.menu_flavor = globaldata.FLAVORS[cursor_index]
	_refresh_values()

func _on_button_prompts_arrow_selected(cursor_index):
	_cursor.on = true
	_panel_button_prompts_cursor.on = false
	_panel_button_prompts.hide()

	globaldata.button_prompts = globaldata.BUTTON_PROMPTS[cursor_index]
	_refresh_values()

func _on_generic_option_back(did_confirm: bool, submenu_index: int, value: String):
	if did_confirm:
		match _cursor.cursor_index:
			OPTN_SETTINGS_LANGUAGE: # Language
				global.set_language(_language_values[submenu_index])
			OPTN_SETTINGS_RESOLUTION: # Resolution
				global.set_win_size(submenu_index + 1)
		_cursor.on = true
	else:
		_on_submenu_arrow_cancel()

func _on_submenu_arrow_cancel():
	uiManager.set_menu_flavors(globaldata.menu_flavor)
	_cursor.on = true
	_panel_text_speed_cursor.on = false
	_panel_flavors_cursor.on = false
	_panel_button_prompts_cursor.on = false
	_panel_text_speed.hide()
	_panel_flavors.hide()
	_panel_button_prompts.hide()
	_refresh_values()

func _enter_transition_door(scene):
	_nav_stack.clear()
	_transition_door.targetScene = scene
	_transition_door.enter()
	audioManager.fadeout_all_music_players(1)

func _on_door_done():
	uiManager.close_commands_menu(true)

func _get_language_as_text(code: String) -> String:
	return "OPTIONS_LANGUAGE_" + code.to_upper()

func _sort_languages(a, b):
	return tr(_get_language_as_text(a)) < tr(_get_language_as_text(b))

func _is_language_enabled(lang_code):
	return lang_code in global.get_supported_languages(false)

func _volume_units_to_db(volume: int) -> float:
	return 40 * log(float(volume + 1) / VOLUME_GRADES)

func _volume_db_to_units(volume_db: float) -> int:
	var ret = min(volume_db, 0)
	ret = VOLUME_GRADES * exp(float(volume_db) / 40) - 1
	return int(round(ret))

# Chooses the closest volume db value from the selectable range
func _discretize_volume(volume_db: float) -> float:
	return _volume_units_to_db(_volume_db_to_units(volume_db))

func _get_resolution_as_text(index: int) -> String:
	return "%s×%s" % [320 * index, 180 * index]

func _get_resolutions() -> Array:
	var resolutions := []
	var i := 1
	while Vector2(320 * i, 180 * i) < OS.get_screen_size():
		resolutions.append(_get_resolution_as_text(i))
		i += 1
	
	return resolutions
