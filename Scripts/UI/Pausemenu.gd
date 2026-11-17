extends CanvasLayer

enum CloseFlags {
	SILENT = 1,
	UNPAUSE = 2,
	HIDE_BARS = 4
}

onready var _arrow = $menu/Commands/Arrow
onready var _cash_box = $menu/Commands/Bottom/Cash
onready var _animation_player = $AnimationPlayer

var _active := false
var _visible := false

func open():
	_active = true
	_visible = true
	_cash_box.get_node("Amount").text = var2str(globaldata.cash)
	_animation_player.play("open")
	uiManager.info_plates_update()
	uiManager.info_plates_show()
	audioManager.play_sfx_by_name("menu_open2", "menu_open")
	uiManager.toggle_black_bars(true)
	audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 1)
	yield(_animation_player, "animation_finished")
	if _active:
		_arrow.on = true

func _input(event: InputEvent):
	if _active:
		if event.is_action_pressed("ui_select"):
			close(CloseFlags.UNPAUSE | CloseFlags.HIDE_BARS)

func _deactivate():
	_arrow.on = false
	audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 2)
	_active = false
	uiManager.close_key_indicator()

func _activate():
	_arrow.on = true
	audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 1)
	_active = true
	uiManager.info_plates_show()
	uiManager.update_key_indicator()

func _on_submenu_back():
	_activate()

func _on_Arrow_selected(cursor_index):
	Input.action_release("ui_accept")
	_deactivate()
	match cursor_index:
		0: #Goods
			$InventoryUI.open(global.get_party_in_natural_order()[0])
		1: #PSI
			$PSIMenuUI.open()
		2: #Equip
			uiManager.info_plates_hide()
			$EquipMenuUI.open(global.get_party_in_natural_order()[0])
		3: #Status
			uiManager.info_plates_hide()
			$StatsMenuUI.show_stats(global.get_party_in_natural_order()[0])
		4: #Map
			uiManager.open_current_map(false, funcref(self, "_on_submenu_back"))
		5: #Options
			_arrow.play_sfx("cursor2")
			uiManager.info_plates_hide()
			$OptionsUI.show_options()

func _on_Arrow_cancel():
	close(CloseFlags.UNPAUSE | CloseFlags.HIDE_BARS)

func _close_view(silent := false, hide_bars := true):
	if _visible:
		_visible = false
		_active = false
		_arrow.on = false
		if !silent: audioManager.play_sfx_by_name("menu_close2", "menu_close")
		if hide_bars:
			uiManager.toggle_black_bars(false)
		uiManager.info_plates_hide()
		_animation_player.play("Close")

func close(flags: int = 0, called_from_ui_manager := false):
	if _visible:
		_close_view(flags & CloseFlags.SILENT, flags & CloseFlags.HIDE_BARS)
		yield(_animation_player, "animation_finished")
		_arrow.set_cursor_from_index(0, false)
		audioManager.muffle_music_player_by_name(audioManager.CHANNELS.OVERWORLD, 0)
		if !called_from_ui_manager:
			uiManager.close_commands_menu(!(flags & CloseFlags.UNPAUSE), flags & CloseFlags.HIDE_BARS, flags & CloseFlags.SILENT, true)

func _on_close_to_title():
	if _visible:
		_close_view()
		_deactivate()

func _on_InventoryUI_exit_with_dialog(dialog_id: String):
	yield(close(), "completed")
	uiManager.open_dialogue_box_and_unpause(dialog_id)

func _on_InventoryUI_exit_with_item(item: Item):
	yield(close(CloseFlags.SILENT | CloseFlags.UNPAUSE), "completed")
	global.get_player().interact_item_with(item)
