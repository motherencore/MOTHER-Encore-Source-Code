class_name SaveSelect

extends Control

enum Type { LOAD, SAVE }

var SaveFile = preload("res://Nodes/Ui/Saves/saveFile.tscn")

var _cursor_top := true
var _max_files := 100 if OS.is_debug_build() else 10
var _index = clamp(globaldata.save_file, 1, _max_files)
var _saves_offset := 21
var _save_file_height := 76
var _active := false
var _copying := false
var _type: int = Type.LOAD
var _is_embed := false
var _save_dict := {}
var _callback: FuncRef = null

onready var _saves_list = $CanvasLayer/Body/Saves/SaveList
onready var _saves_container = $CanvasLayer/Body/Saves
onready var _menus_cursor = $CanvasLayer/Body/Cursor
onready var _cursor_anim = $CanvasLayer/Body/Cursor/cursor_menu/AnimationPlayer
onready var _copy_cursor = $CanvasLayer/Body/Saves/CopyCursor

onready var _menu_save = $CanvasLayer/SaveConfirmation
onready var _menu_delete = $CanvasLayer/DeleteConfirmation
onready var _menu_text_speed = $CanvasLayer/TextSpeed
onready var _menu_flavors = $CanvasLayer/Flavors
onready var _menu_prompts = $CanvasLayer/ButtonPrompts

func init(type: int, index: int, embed = null, callback = null):
	_type = type
	_index = index
	_is_embed = embed if (embed != null) else (_type == Type.SAVE)
	_callback = callback

func _ready():
	_saves_offset = _saves_container.rect_position.y
	_cursor_anim.play("idle")
	for item in [_menu_save, _menu_delete, _menu_prompts, _menu_flavors, _menu_text_speed]:
		item.hide()
	
	for i in _max_files:
		var save_file = SaveFile.instance()
		save_file.init(_is_embed, i + 1)
		_saves_list.add_child(save_file)
		save_file.connect("deactivate", self, "activate")
		save_file.connect("show_copy", self, "set_copy_mode")
		save_file.connect("show_delete", self, "show_delete_confirm")
		save_file.connect("show_textSpeed", self, "show_textSpeed_setting")
		save_file.connect("show_menuFlavor", self, "show_menuFlavor_setting")
		save_file.connect("show_buttonPrompts", self, "show_buttonPrompts_setting")
	if _is_embed:
		$Background.hide()
		audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 1)
		$CanvasLayer/Body.margin_left = 32
		$CanvasLayer/Body.margin_right = -32
	_saves_container.rect_position.y = _saves_offset - (_index - 1) * 76
	_saves_offset = _saves_container.rect_position.y
	yield(get_tree().create_timer(0.5), "timeout")
	_menus_cursor.show()
	_active = true

func _input(event: InputEvent):
	if !_active: return
	if event.is_action_pressed("ui_accept"):
		var save_file = _saves_list.get_child(_index - 1)
		if _copying:
			_play_sfx("cursor2")
			if !save_file.has_data():
				overwrite_save(true)
				_copying = false
			else:
				show_save_confirm()
		else:
			match _type:
				Type.LOAD:
					if save_file.has_data():
						if _is_embed:
							yield(save_file.load_game(), "completed")
							_finish()
						else:
							_play_sfx("cursor2")
							deactivate()
							save_file.activate(true)
					else:
						_play_sfx("restricted")
				Type.SAVE:
					_play_sfx("cursor2")
					if !save_file.has_data():
						overwrite_save(false)
					else:
						show_save_confirm()
	
	if event.is_action_pressed("ui_cancel"):
		if _copying:
			_play_sfx("back")
			_copying = false
			_copy_cursor.hide()
		else:
			Input.action_release("ui_cancel")
			_finish()

func _process(_delta):
	if !_active: return
	var direction = controlsManager.get_controls_vector(true).y
	
	if direction < 0 and _index > 1:
		_play_sfx("cursor1")
		_index -= 1
		if !_cursor_top:
			_cursor_top = true
			_create_smooth_tween().tween_property(_menus_cursor, "rect_position:y", 0, 0.2)
		else:
			var new_saves_offset = _saves_offset + _save_file_height
			_create_smooth_tween().tween_property(_saves_container, "rect_position:y", new_saves_offset, 0.2)
			_saves_offset = new_saves_offset
			
	elif direction < 0 and _index == 1:
		_play_sfx("cursor1")
		_index = _max_files
		_cursor_top = false
		var new_saves_offset = _saves_offset - (_save_file_height * (_max_files - 2))
		var tween = _create_smooth_tween().set_parallel()
		tween.tween_property(_menus_cursor, "rect_position:y", _save_file_height, 0.2) 
		tween.tween_property(_saves_container, "rect_position:y", new_saves_offset, 0.2) 
		_saves_offset = new_saves_offset
		
	elif direction > 0 and _index < _max_files:
		_play_sfx("cursor1")
		_index += 1
		if _cursor_top:
			_cursor_top = false
			_create_smooth_tween().tween_property(_menus_cursor, "rect_position:y", _save_file_height, 0.2)
		else:
			var new_saves_offset = _saves_offset - _save_file_height
			_create_smooth_tween().tween_property(_saves_container, "rect_position:y", new_saves_offset, 0.2)
			_saves_offset = new_saves_offset
	
	elif direction > 0 and _index == _max_files:
		_play_sfx("cursor1")
		var new_saves_offset = _saves_offset + (_save_file_height * (_max_files - (1 if _cursor_top else 2)))
		var tween = _create_smooth_tween().set_parallel()
		tween.tween_property(_menus_cursor, "rect_position:y", 0, 0.2) 
		tween.tween_property(_saves_container, "rect_position:y", new_saves_offset, 0.2)
		_index = 1
		_cursor_top = true
		_saves_offset = new_saves_offset

func activate():
	_active = true
	_cursor_anim.play("idle")

func deactivate():
	_active = false
	_cursor_anim.play("select")

func _create_smooth_tween() -> SceneTreeTween:
	return create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _play_sfx(sfx_name: String):
	audioManager.play_sfx_by_name(sfx_name, "cursor")

func _load_save_dict(num: int):
	var dict = global.load_to_dict(num)
	if dict: _save_dict = dict

func _finish():
	if _is_embed:
		uiManager.remove_ui(self)
	else:
		_active = false
		$Objects/Door.enter()

func close():
	audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 0)
	if _callback and _callback.is_valid():
		_callback.call_func()
		_callback = null
	queue_free()

func overwrite_save(from_dict := false):
	var save_file = _saves_list.get_child(_index - 1)
	if from_dict:
		global.save_from_dict(_index, _save_dict)
	else:
		global.save_game(_index)
	save_file.load_data(_index)
	globaldata.save_file = _index
	_copying = false
	global.save_settings()
	_copy_cursor.hide()

func erase_save():
	global.erase_save(_index)
	var save_file = _saves_list.get_child(_index - 1)
	save_file.clear_data()

func show_save_confirm():
	yield(get_tree(), "idle_frame")
	_menu_save.get_node("saveArrow").on = true
	_menu_save.show()
	deactivate()

func show_delete_confirm():
	_menu_delete.show() # Put this way to prevent the cursor bugging during one frame when opening this menu
	yield(get_tree(), "idle_frame")
	_menu_delete.get_node("deleteArrow").on = true
	deactivate()

func show_textSpeed_type():
	yield(get_tree(), "idle_frame")
	_menu_delete.get_node("deleteArrow").on = true
	_menu_delete.show()
	deactivate()

func show_textSpeed_setting():
	yield(get_tree(), "idle_frame")
	_load_save_dict(_index)
	_menu_text_speed.get_node("TextSpeedArrow").on = true
	_menu_text_speed.show()
	deactivate()
	var text_speed_arrow = _menu_text_speed.get_node("TextSpeedArrow")
	var text_speed_index = globaldata.TEXT_SPEEDS.find(_save_dict["textspeed"])
	text_speed_arrow.set_cursor_from_index(text_speed_index, false)
	_menu_text_speed._on_TextSpeedArrow_moved(null)

func show_menuFlavor_setting():
	_load_save_dict(_index)
	_menu_flavors.get_node("FlavorsArrow").on = true
	_menu_flavors.show()
	deactivate()
	var flavors_arrow = _menu_flavors.get_node("FlavorsArrow")
	var flavor_index = globaldata.FLAVORS.find(_save_dict["menuflavor"])
	flavors_arrow.set_cursor_from_index(flavor_index, false)
	_menu_flavors._on_FlavorsArrow_moved(null)

func show_buttonPrompts_setting():
	_load_save_dict(_index)
	_menu_prompts.get_node("ButtonPromptsArrow").on = true
	_menu_prompts.show()
	deactivate()
	var button_prompts_arrow = _menu_prompts.get_node("ButtonPromptsArrow")
	var options := ["Both", "Objects", "NPCs", "None"]
	button_prompts_arrow.set_cursor_from_index(options.find(_save_dict["buttonprompts"]), false)
	_menu_prompts.refresh(true)

func set_copy_mode():
	_load_save_dict(_index)
	_copying = true
	activate()
	_copy_cursor.show()
	_copy_cursor.rect_global_position = _menus_cursor.rect_global_position

func _on_arrow_selected(cursor_index: int):
	if cursor_index == 0:
		overwrite_save(_copying)
		_play_sfx("cursor2")
	else:
		_play_sfx("back")
	activate()
	_menu_save.get_node("saveArrow").on = false
	_menu_save.hide()

func _on_deleteArrow_selected(cursor_index: int):
	match cursor_index:
		0:
			_play_sfx("cursor2")
			erase_save()
			activate()
		1:
			_play_sfx("back")
			var saveFile = _saves_list.get_child(_index - 1)
			saveFile.activate()
	_menu_delete.get_node("deleteArrow").on = false
	_menu_delete.hide()

func _on_TextSpeedArrow_selected(cursor_index: int):
	_save_dict["textspeed"] = globaldata.TEXT_SPEEDS[cursor_index]
	_close_submenu(_menu_text_speed, _menu_text_speed.get_node("TextSpeedArrow"))
	overwrite_save(true)

func _on_FlavorsArrow_selected(cursor_index: int):
	_save_dict["menuflavor"] = globaldata.FLAVORS[cursor_index]
	overwrite_save(true)
	_close_submenu(_menu_flavors, _menu_flavors.get_node("FlavorsArrow"))

func _on_ButtonPromptsArrow_selected(cursor_index: int):
	var options := ["Both", "Objects", "NPCs", "None"]
	_save_dict["buttonprompts"] = options[cursor_index]
	overwrite_save(true)
	_close_submenu(_menu_prompts, _menu_prompts.get_node("ButtonPromptsArrow"))

func _close_submenu(menu_node: Control, arrow_node: Node):
	var save_file = _saves_list.get_child(_index - 1)
	save_file.activate()
	arrow_node.on = false
	menu_node.hide()

func _on_arrow_cancel():
	activate()
	_menu_save.get_node("saveArrow").on = false
	_menu_save.hide()

func _on_deleteArrow_cancel():
	_close_submenu(_menu_delete, _menu_delete.get_node("deleteArrow"))

func _on_TextSpeedArrow_cancel():
	_close_submenu(_menu_text_speed, _menu_text_speed.get_node("TextSpeedArrow"))

func _on_FlavorsArrow_cancel():
	_close_submenu(_menu_flavors, _menu_flavors.get_node("FlavorsArrow"))

func _on_ButtonPromptsArrow_cancel():
	_close_submenu(_menu_prompts, _menu_prompts.get_node("ButtonPromptsArrow"))
