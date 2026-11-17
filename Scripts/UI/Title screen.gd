 extends Control

const CREDITS_STEPS := 3

enum MenuOptions {
	LOOP_UP = -1,
	NEW_GAME,
	LOAD,
	SETTINGS,
	EXIT,
	LOOP_DOWN
}

const TITLE_SONG := "Mother Earth.mp3"

onready var _anim_player = $CanvasLayer/AnimationPlayer
onready var _label = $CanvasLayer/Aboveground/Base/IntroTexts/Label
onready var _press_button = $CanvasLayer/Title/PressButton
onready var _menu = $CanvasLayer/Title/Menu
var _is_active := false
var _can_skip := false
var _seq := ""

var option: int = MenuOptions.NEW_GAME

func _ready():
	global.get_player().pause(true)
	
	_label.text = "TITLE_INTRO_1"
	
	$CanvasLayer/Title/Earth.playing = true
	if !audioManager.is_song_playing_on_music_player_by_name(audioManager.CHANNELS.MENU, TITLE_SONG):
		audioManager.stop_all_music_players()
		audioManager.play_music(audioManager.CHANNELS.MENU, TITLE_SONG)
		_anim_player.play("intro1")
		_can_skip = true
	else:
		_anim_player.play("Instant Start")
		
	_update_text()
	global.connect("locale_changed", self, "_update_text")
	global.connect("inputs_changed", self, "_update_text")
	
	if (globaldata.device == globaldata.GAMEPAD)\
	and (OS.window_fullscreen):
		$CanvasLayer/Title/Control/VBoxContainer.visible = false

func _update_text() -> void:
	var pressText = "[center]%s[/center]" % TextTools.replace_text("MENU_PRESS")
	_press_button.bbcode_text = pressText

func _input(event: InputEvent):
	for action in InputMap.get_actions():
		if event.is_action_pressed(action):
			_seq += action.substr(3, 2)
			if !_is_active and !_can_skip and _seq.ends_with(globaldata.LANG_ALT):
				global.set_language("pr")
			break
	
	if event.is_action_pressed("ui_accept"):
		if _can_skip:
			if _anim_player.current_animation != "Fade" and \
					_anim_player.current_animation != "Skip Fade":
				_anim_player.play("Skip Fade")
		elif _press_button.modulate == Color.white:
			_show_menu()
			audioManager.play_sfx_by_name("cursor2", "cursor")
	
	if OS.is_debug_build():
		if _is_active:
			if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_toggle"):
				audioManager.fadeout_all_music_players(1)
				Input.action_release("ui_cancel")
				Input.action_release("ui_toggle")
				$Objects/DoorToDebug.enter()

func _physics_process(_delta):
	if _is_active:
		var input = controlsManager.get_controls_vector(true)
		
		if input.y > 0:
			option += 1
			_option_changed()
			audioManager.play_sfx_by_name("cursor1", "cursor")
		elif input.y < 0:
			option -= 1
			_option_changed()
			audioManager.play_sfx_by_name("cursor1", "cursor")
		
		if Input.is_action_just_pressed("ui_accept"):
			audioManager.play_sfx_by_name("cursor2", "cursor")
			_is_active = false
			match(option):
				MenuOptions.NEW_GAME:
					audioManager.fadeout_all_music_players(0.5)
					set_saveFile()
					global.load_new_game()
					$Objects/DoorToNewGame.enter()
				MenuOptions.LOAD:
					$Objects/DoorToSaveSelect.enter()
				MenuOptions.SETTINGS:
					$Objects/DoorToSettings.enter()
				MenuOptions.EXIT:
					global.save_settings()
					get_tree().quit()
		
		if OS.is_debug_build() and Input.is_action_just_pressed("ui_cancel"):
			$Objects/DoorToDebug.enter()

func set_saveFile() -> void:
	var saveGame = File.new()
	var newSave = 1
	for num in 10:
		if saveGame.file_exists("user://saveFile" + var2str(num) + ".save"):
			newSave += 1
	if newSave > 10:
		newSave = 10
	globaldata.save_file = newSave

func _option_changed() -> void:
	match(option):
		MenuOptions.LOOP_UP:
			option = MenuOptions.EXIT
		MenuOptions.LOOP_DOWN:
			option = MenuOptions.NEW_GAME
	
	for i in _menu.get_child_count():
		var flash = _menu.get_child(i).get_material()
		if i == option:
			flash.set_shader_param("flash_modifier", 0.35)
		else:
			flash.set_shader_param("flash_modifier", 0)

func _on_AnimationPlayer_animation_finished(anim_name: String) -> void:
	for i in range(1, CREDITS_STEPS):
		if anim_name == "intro%s" % i:
			_anim_player.play("intro%s" % (i + 1))
			_label.text = "TITLE_INTRO_%s" % (i + 1)
			var swap_array = tr("TITLE_INTRO_SWAP_LINES").split(",")
			if i < swap_array.size() and swap_array[i]:
				_swap_credit_layout()
	
	if anim_name == "intro%s" % CREDITS_STEPS:
		$CanvasLayer/Aboveground/Base.hide()
		_anim_player.play("Fade")

func _swap_credit_layout() -> void:
	var container = $CanvasLayer/Aboveground/Base/IntroTexts
	var node_to_move = container.get_child(1)
	container.move_child(node_to_move, 0)

func _show_menu() -> void:
	if globaldata.save_file != 0:
		option = MenuOptions.LOAD
	_option_changed()
	_menu.show()
	var tween = create_tween()
	tween.tween_property(_press_button, "modulate", Color.transparent, 0.2)
	tween.tween_property(_menu, "modulate", Color.white, 0.25).set_ease(Tween.EASE_IN_OUT)
	yield(tween, "finished")
	_press_button.hide()
	_is_active = true

func _show_button() -> void:
	yield(create_tween().tween_property($CanvasLayer/Aboveground/Base, "modulate", Color.transparent, 0.5), "finished")
	_press_button.show()
	create_tween().tween_property(_press_button, "modulate", Color.white, 0.5).from(Color.transparent)
	_can_skip = false
