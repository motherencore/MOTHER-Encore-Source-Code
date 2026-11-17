class_name BattleSystem
extends CanvasLayer

signal round_done
signal action_select_done
signal battle_paused
signal battle_unpaused
signal battle_to_ov
signal battle_ended(result)
signal party_changed(party)
signal enemy_party_changed(enemy_party)
signal encore_activated

enum Result { LOSE = -1, FLEE, WIN }
enum Advantage { ENEMY = -1, NEUTRAL, PLAYER }
enum ActionType {DAMAGE, HEALING, STAT, AILMENT, OTHER}
enum TargetType {ENEMY, ALLY, ALLY_EXCEPT_SELF, RANDOM_ENEMY, RANDOM_ALLY, SELF, ALL_ENEMIES, ALL_ALLIES, ANY, RANDOM_ENEMIES_2, RANDOM_ENEMIES_UNTIL_MISS}

const PARTY_MEMBERS_ORDER := [PartyMember.NINTEN, PartyMember.ANA, PartyMember.LLOYD, PartyMember.TEDDY, PartyMember.PIPPI, PartyNPC.CANARY_CHICK, PartyNPC.FLYING_MAN, PartyNPC.EVE]
const MAX_ENEMY_COUNT := 8

const FLEEING_MAX_ATTEMPTS := 3
const FLEEING_CHANCES_BASE := 40
const FLEEING_CHANCES_INCREASE := 10

const ADRENALINE_MULT := 1.5
const GUTS_MULT := 500.0
const SMASH_MULT := 4

const STAT_MOD_MINIMUM_AMOUNT := 3
const STAT_MOD_STEP := 1.0/32.0
const MAX_STAT_MODS := 4

const STAT_MOD_ANIMS = [Character.OFFENSE, Character.DEFENSE, Character.SPEED, Character.GUTS]

const PASSIVE_HEAL_PROB = 25
const HEAL_BY_HIT_PROB = 25
const TRANSMIT_PROB = 10
const SHAKE_FREQ := 0.04
const NPC_TAKING_HIT_THRESHOLD := { PartyNPC.FLYING_MAN: 200, PartyNPC.EVE: 400 }
const NPC_TAKING_HIT_CHANCE := { PartyNPC.FLYING_MAN: 60, PartyNPC.EVE: 90 }

const SPRITE_FRAMES = { 
	"crouch_up": Vector2(3, 3),
	"crouch_down": Vector2(3, 0),
	"crouch_left": Vector2(3, 1),
	"crouch_right": Vector2(3, 2),
	"jump_up": Vector2(3, 18),
	"jump_down": Vector2(0, 18),
	"jump_left": Vector2(1, 18),
	"jump_right": Vector2(2, 18),
	"scared": Vector2(5, 18)
}

const SP_TYPE := {
	BASIC = 6,
	ADRENALINE = 10,
	GUARD = 15,
	DAMAGED = 7,
	ENCORE = 40
}

const RisingNumTscn = preload("res://Nodes/Ui/Battle/RisingNumber.tscn")
const FlyingNumTscn = preload("res://Nodes/Ui/Battle/FlyingNumber.tscn")
const SmashAttackTscn = preload("res://Nodes/Ui/Battle/Smash.tscn")

const DroppedItemNode = preload("res://Nodes/Overworld/Objects/DroppedItem.tscn")

onready var _party_info := $PlayerInfo/PlayerInfoVbox/PartyInfo
onready var sp_meter := $PlayerInfo/PlayerInfoVbox/SpMeter as SPMeter
onready var _note_spawner := $NoteSpawner
onready var _enemies_manager := $Enemies
onready var _bg_darkinator := $BGDarkinator

# The inventory that the player has at the beginning of the battle is saved
# to be given back to the player if they die and choose to continue
var _saved_inventories := {}

# Everyone in battle!
var _party_BPs := []
var _npc_BPs := []
var _enemy_BPs := []

var _enemy_stash := []

# Dictionary <String, Array<BattleParticipant>>
var _enemies_per_name := {}
var _special_npc_BPs := {}
var _ongoing_npc_protection := {}

# UI Cursor/ Menus / Actions
var _menu_page_stack := []

var _doing_actions := false
var _current_action = null
var _current_action_index = 0
var _action_queue := []
var _curr_party_mem : int = -1

# For battle win stuff
var _exp_pool := 0
var _cash_pool := 0
# Dictionary <String, Array<Dictionary<String, int>>> (for each enemy name, an array of item/chances data)
var _item_pool := BattleItemPool.new()

# For prebattle transition
var _enemies_shaking := false
var _shake_time := 0.0

var _battle_bg
var _music := ""

# Listed in the strict order for battle (Ninten, Ana, Lloyd, Teddy, Pippi)
var _party_orig_objects := []
var _party_orig_positions := []
var _party_orig_dirs := []

# When the battle is inactive, we stop taking input except for encores
var _active := true
var _paused := false
var _lose_battle := false
var _tween: SceneTreeTween

# Pressing the scope/encore button, you can toggle an encore on and off during
# a battle participant's turn, and is handled upon that participant's turn's end.
var _can_encore := true
var _encore_activated := false
var _used_encore := false

var _fleeing_attempts := 0
var _stolen_item: Item = null
var _stolen_item_definitive := false

var _is_boss := false
var _can_run := true
var _advantage := 0
var _show_intro_outro := false
var _post_battle_cutscenes := {}
var _win_flag := ""
var _buffered_player_defeat := []
var _buffer_reorganize := false
var _new_enemies := []

# edge case for walkAway skill
var _received_exp_from_flee : bool = false

var _turns_count := 1

onready var _context = $Dialoguebox.FormatContext.new() # For ease of writing, we reuse the same object and just reset it every time it gets used

# sfx
var _sound_effects = {
	#cursors
	"cursor1": load("res://Audio/Sound effects/Cursor 1.mp3"),
	"cursor2": load("res://Audio/Sound effects/Cursor 2.mp3"),
	"back": load("res://Audio/Sound effects/M3/curshoriz.wav"),
	"error": load("res://Audio/Sound effects/M3/error.wav"),
	#menu sounds
	"attack1": load("res://Audio/Sound effects/Attack 1.mp3"),
	"attack2": load("res://Audio/Sound effects/Attack 2.mp3"),
	"yourpsi": load("res://Audio/Sound effects/your_psi.mp3"),
	"enemypsi": load("res://Audio/Sound effects/M3/enemy_psi.wav"),
	"statusafflicted": load("res://Audio/Sound effects/EB/ailment.wav"),
	"enemyturn": load("res://Audio/Sound effects/Enemy Turn.mp3"),
	"enemydefeated": load("res://Audio/Sound effects/Enemy Defeat.mp3"),
	"playerdefeated": load("res://Audio/Sound effects/EB/die.wav"), #buy2
	"psilearned": load("res://Audio/Sound effects/M3/Learned PSI.wav"),
	"mortaldamage": load("res://Audio/Sound effects/M3/Mortal_Blow.wav"),
	"partylose": load("res://Audio/Sound effects/PartyLose.mp3"),
	"smash": load("res://Audio/Sound effects/M3/SMAAAASH.wav"),
	"effectiveHit": load("res://Audio/Sound effects/M3/Confirm.wav"),
	"encoreactivate": load("res://Audio/Sound effects/M3/Confirm.wav"),
	"cheering": load("res://Audio/Sound effects/M3/Cheering.mp3"),
	#general sounds
	"hurt1": load("res://Audio/Sound effects/Hurt 1.mp3"),
	"hurt2": load("res://Audio/Sound effects/Hurt 2.mp3"),
	"statup": load("res://Audio/Sound effects/M3/Stat_increase.wav"),
	"statdown": load("res://Audio/Sound effects/M3/Stat_decrease.wav"),
	"dodge": load("res://Audio/Sound effects/EB/dodge.wav"),
	"miss": load("res://Audio/Sound effects/EB/miss.wav"),
	#attack sounds
	"swing": load("res://Audio/Sound effects/Ninten Bat.mp3"),
	"beam": load("res://Audio/Sound effects/Lloyd Beam.mp3"),
	"bash": load("res://Audio/Sound effects/bash.mp3"),
	#skills sounds
	"strike": load("res://Audio/Sound effects/strike.mp3"),
	"fire": load("res://Audio/Sound effects/EB/fire1.wav"),
	"curveball": load("res://Audio/Sound effects/Whistle.mp3"),
	"growl": load("res://Audio/Sound effects/M3/Growl.mp3"),
	"growl2": load("res://Audio/Sound effects/M3/Growl 2.mp3"),
	"siren": load("res://Audio/Sound effects/siren.mp3"),
	#item sounds
	"equip": load("res://Audio/Sound effects/M3/equip.wav"),
	"franklinbadge": load("res://Audio/Sound effects/M3/Franklin Badge.mp3"),
	"healHP": load("res://Audio/Sound effects/EB/heal 1.wav"),
	"healPP": load("res://Audio/Sound effects/EB/heal.wav"),
	"healstatus": load("res://Audio/Sound effects/EB/heal 2.wav"),
	# psi skill sounds
	"lifeup_a": load("res://Audio/Sound effects/EB/heal 1.wav"),
	"healing_a": load("res://Audio/Sound effects/EB/heal.wav"),
}
var _musical_effects = {
	"bossencounter": "Battle Encounter/Encounter Boss.mp3",
	"playeradv": "Battle Encounter/Encounter Player Advantage.mp3",
	"enemyadv": "Battle Encounter/Encounter Enemy Advantage.mp3",
	"encounter": "Battle Encounter/Encounter Enemy.mp3",
	"youwon": "You Win/YOUWON.mp3",
	"youwonboss": "You Win/YOUWONBOSS.mp3",
	"victory": "You Win/Victory.mp3",
	"lvlup": "You Win/LVLUP.mp3",
	"lvlup_ninten": "You Win/LVLUP_ninten.mp3",
	"lvlup_ana": "You Win/LVLUP_ana.mp3",
	"lvlup_lloyd": "You Win/LVLUP_lloyd.mp3",
	"lvlup_pippi": "You Win/LVLUP_pippi.mp3",
	"lvlup_teddy": "You Win/LVLUP_ninten.mp3"
}

# Classes
class Action extends Object:
	var user: BattleParticipant
	var priority := 0
	var target_type: int = TargetType.SELF
	var target_unconscious := false
	var target_incapacitated := false
	signal done
	
	func _init(user: BattleParticipant, priority: int = 0):
		self.user = user
		self.priority = priority
	
	# Overridden
	func get_dialog() -> String:
		return ""
	
	# Overridden
	func has_trait(trait: String) -> bool:
		return false

class SkillAction extends Action:
	var skill := {} setget _set_skill
	var targets := []
	var sp_at_action: int
	func _init(user: BattleParticipant, priority: int = 0).(user, priority):
		pass
	
	# Override
	func get_default_dialog() -> String:
		return "BATTLE_MSG_PSI" if skill.skill_type == "psi" else "BATTLE_MSG_SKILL"
	
	# Override
	func get_dialog() -> String:
		if has_trait("no_dialog"): return ""
		var dialog_field = skill.get("dialog") # null falls back to default, '' does not
		if targets.size() == 1 and user == targets[0]:
			dialog_field = skill.get("dialog_self", dialog_field)
		if dialog_field == null: 
			return get_default_dialog()
		if !(dialog_field is Array): 
			return dialog_field
		return dialog_field[randi() % dialog_field.size()]
	
	# Override
	func has_trait(trait: String) -> bool:
		return skill.get("traits", []).has(trait)
	
	func _set_skill(new_val: Dictionary):
		priority = new_val.get("priority", 0)
		target_type = new_val.get("target_type", TargetType.ENEMY)
		skill = new_val
		target_unconscious = has_trait("target_unconscious")
		target_incapacitated = has_trait("target_incapacitated") or target_unconscious
	

class ItemAction extends SkillAction:
	var item: Item setget _set_item
	var inv_idx := -1
	func _init(user: BattleParticipant, priority: int = 0).(user, priority):
		pass
	
	# Override
	func get_default_dialog() -> String:
		if targets.size() == 1 and user == targets[0]:
			return "BATTLE_MSG_ITEM_SELF"
		else: return "BATTLE_MSG_ITEM_OTHER"
		
	# Override
	func has_trait(trait: String) -> bool:
		var item_data = item.get_data()
		
		var traits = skill.get("traits", []) + item_data.get("traits", [])
		
		return traits.has(trait)
	
	func _set_item(new_val: Item):
		item = new_val
		var item_data = item.get_data()
		if item_data.get("battle_action", {}).get("skill"):
			_set_skill(globaldata.get_battle_skill(item_data.battle_action.skill))
		else:
			_set_skill({})
			if item.is_equippable():
				target_type = TargetType.SELF
			else:
				var item_battle_action := item_data.get("battle_action", item_data.actions[0]) as Dictionary
				if item_data.get("target_all", false): 
					target_type = item_battle_action.get("target_type", TargetType.ALL_ALLIES)
				else:
					target_type = item_battle_action.get("target_type", TargetType.ALLY)
				target_unconscious = has_trait("target_unconscious")
				target_incapacitated = true
		priority = item_data.get("priority", 0)

class FleeAction extends Action:
	func _init(_user: BattleParticipant).(_user):
		priority = 4
	
	func get_dialog() -> String:
		return "BATTLE_MSG_FLEE"

# 1. INITIALIZATION
# 2. PROCESS/INPUT
# 3. UI
# 4. ACTION SELECTION
# 5. BATTLE LOGIC
# 6. CALCULATIONS
# 7. BATTLE PARTICIPANTS MANAGEMENT
# 8. BATTLE END
# 9. VISUALS/SFX
# 10. GETTERS/MISC.


####################################################################
########################## INITIALIZATION ##########################
####################################################################

func _init():
	randomize()
	for party_member in global.get_party_in_natural_order():
		_add_party_member(party_member)
	for partyNpc in global.partyNpcs:
		_add_party_npc(partyNpc)
	
	_party_orig_objects = global.partyObjects.duplicate()
	_party_orig_objects.sort_custom(self, "_sort_party_objects")
	
	for party_obj in _party_orig_objects:
		_party_orig_dirs.append(party_obj.get_direction())

func init_battle_params(enemies_to_join: Array, advantage: int, can_run: bool = true, battle_bgs: Dictionary = {}, transition = null, post_battle_cutscenes := {}, win_flag := ""):
	for enemy in enemies_to_join:
		if !enemy is OnScreenEnemy:
			enemy = OnScreenEnemy.new(enemy, null)
		_add_enemy(enemy.enemy, enemy.overworld_object)
	
	var enemy_name: String = _enemy_BPs[0].get_id()
	if !globaldata.encountered.get(enemy_name, false):
		globaldata.encountered[enemy_name] = true
		globaldata.set_flag("%s_fought" % enemy_name, true, false)
		_show_intro_outro = _enemy_BPs[0].character.get_data().get("show_intro_outro", false)
	
	_music = _enemy_BPs[0].character.get_data().get("music", "")
	
	_advantage = advantage
	_can_run = can_run
	_post_battle_cutscenes = post_battle_cutscenes
	_win_flag = win_flag
	
	_item_pool.roll_item(_enemy_BPs)
	
	var bg = battle_bgs.get(_enemy_BPs[0].character.get_data().get("bg"), battle_bgs["lamp"])
	_battle_bg = CanvasLayer.new()
	_battle_bg.add_child(bg.instance())
	_battle_bg.layer = -1
	uiManager.add_ui(_battle_bg)
	if transition:
		transition.connect("done", _battle_bg, "set", ["layer", 1])

func _ready():
	var transitions_in_progress = _add_players_and_npc_transitions()
	_add_party_info_plates()
	for i in range(_enemy_BPs.size()):
		_enemy_BPs[i].add_battle_sprite($Enemies)
	_reorganize_enemies(false)
	$ActionMenuBox.connect("next", self, "_action_box_selected")
	# When we know who up first, we want to change the icons accordingly
	
	var _conscious_party := _get_conscious(_party_BPs, true)
	_add_actions_to_menu(_conscious_party[0] if _conscious_party else null)
	$TargetsBox.init(_party_BPs, _enemy_BPs)
	
	$AnimScene.play("transitionIn")
	$AnimScene.connect("animation_finished", self, "_battle_start", [], CONNECT_ONESHOT)
	
	$BossDefeatFlash.connect("animation_finished", self, "_win")
	$BossDefeatFlash.connect("defeat_enemies", self, "_kill_all_enemies")
	
	$EncoreTutorial.init(self, _conscious_party, _bg_darkinator)
	
	if _music and !audioManager.overworld_battle_music: audioManager.pause_all_music_players()
	for enemy in _enemy_BPs:
		if enemy.is_boss(): _is_boss = true
	
	var encounter_sound = _musical_effects[
		"bossencounter" if _is_boss else
		"playeradv" if _advantage == Advantage.PLAYER else
		"enemyadv" if _advantage == Advantage.ENEMY else
		"encounter"
	]
	
	if _is_boss: 
		audioManager.clear_previous_overworld_track_playback_positions()
	
	if _advantage == Advantage.ENEMY: $ActionMenuBox.hide()
	
	audioManager.play_music(audioManager.CHANNELS.MENU, encounter_sound)
	_save_inventories()
	_check_sp_meter()

func _battle_start(_anim := ""):
	for i in _npc_BPs.size():
		_npc_BPs[i].add_battle_sprite($NPCs, $NpcTransitions.get_child(i))
	
	# Enter "Actions" menu page
	if _music and !audioManager.overworld_battle_music:
		audioManager.play_music(audioManager.CHANNELS.BATTLE, "Battle Themes/" + _music)
	if _advantage == Advantage.ENEMY: _curr_party_mem = _party_BPs.size()
	
	# Activate statuses if there are any
	for bp in _party_BPs: bp.refresh_status_info()
	
	if _show_intro_outro:
		var dialog = _enemy_BPs[0].character.get("intro_message", "You encountered {n3}{name}!")
		yield($Dialoguebox.start_from_formatted(dialog, _context.set_actor(_enemy_BPs[0])), "completed")
		$AnimAction.play("transitionIn")
		yield($AnimAction, "animation_finished")
	
	_next_active_member()

func _add_party_info_plates():
	var party_size : int = _party_BPs.size()
	
	var plate_size := Vector2(66, 48) # Includes spacing
	var center_placement := Vector2(128,20)
	var even_placement := Vector2(94,20)
	
	var first_placement_x: int
	
	match party_size:
		2: first_placement_x = int(even_placement.x)
		3: first_placement_x = int(center_placement.x - plate_size.x)
		4: first_placement_x = int(even_placement.x - plate_size.x)
		5: first_placement_x = int(center_placement.x - (plate_size.x * 2))
		6: first_placement_x = int(even_placement.x - (plate_size.x * 2))
		_: first_placement_x = int(center_placement.x)
	
	for i in range(party_size):
		_party_BPs[i].add_info_plate(_party_info, first_placement_x + (plate_size.x * i), funcref(self, "_check_player_defeated"))

func _save_inventories():
	for bp in _party_BPs:
		var inv = bp.character.inv
		_saved_inventories[inv] = inv.to_array()

####################################################################
########################## PROCESS/INPUT ###########################
####################################################################

func _input(event: InputEvent):
	if !_active:
		return
	
	# Actions when the menu is shown
	if !_doing_actions:
		if OS.is_debug_build():
			_debug_inputs(event)
		
		if event.is_action_pressed("ui_cancel") and !_current_action:
			get_tree().set_input_as_handled()
			if _leave_menu():
				_play_sfx("back")
		
		if event.is_action_pressed("ui_toggle"):
			_set_fast_mode(true)
		elif event.is_action_released("ui_toggle"):
			_set_fast_mode(false)
	
	# Actions when in the middle of actions
	elif _can_encore and sp_meter.get_sp() >= SP_TYPE.ENCORE and _current_action and \
			_current_action.user.is_type(Character.Type.PARTY_MEMBER) and !(_current_action is SkillAction and _current_action.has_trait("guard")):
		if event.is_action_pressed("ui_cancel") and _encore_activated:
			_set_encore_active(false, true)
		if event.is_action_pressed("ui_select") and !_encore_activated:
			_set_encore_active(true, true)

func _debug_inputs(event: InputEvent):
	if $ActionMenuBox.cursor.on:
		# Debug win battle instantly
		if event.is_action_pressed("ui_end"):
			$ActionMenuBox.hide()
			var boss = false
			while !_enemy_BPs.empty():
				boss = _enemy_BPs[0].is_boss()
				_enemy_BPs[0].defeat()
				if boss:
					break
			if !boss:
				_win()
		
		# Die instantly
		if event.is_action_pressed("ui_home"):
			$ActionMenuBox.hide()
			_end_battle_to_game_over()
		
		# Halves enemy health
		if event.is_action_pressed("ui_q"):
			for enemy in _enemy_BPs:
				enemy = enemy as BattleParticipant
				enemy.set_target_hp(int(enemy.get_current_hp()/2.0))
		
		# Sets all enemy HP to 1
		if event.is_action_pressed("ui_w"):
			for enemy in _enemy_BPs:
				enemy = enemy as BattleParticipant
				enemy.set_target_hp(1)
		
		# Add SP
		if event.is_action_pressed("ui_e"):
			_add_sp(20)
		
		# Replenish all HP and PP
		if event.is_action_pressed("ui_r"):
			_add_sp(20)
			for party_member in _party_BPs:
				party_member = party_member as BattleParticipant
				party_member.set_target_hp(999)
				party_member.set_target_pp(999)
	
	
	for i in _party_BPs.size():
		if event.is_action_pressed("ui_%s" % str(i + 1)):
			_apply_damage(_party_BPs[i], 100)

func _physics_process(delta: float):
	if !_enemies_shaking:
		return
	_shake_time += delta
	if _shake_time <= SHAKE_FREQ:
		return
	_shake_time -= SHAKE_FREQ
	for ov_sprite in $EnemyTransitions.get_children():
		ov_sprite.offset.x = rand_range(-8.0,8.0) if _is_boss else rand_range(-4.0,4.0)
		ov_sprite.offset.y = rand_range(-8.0,8.0) if _is_boss else rand_range(-4.0,4.0)


####################################################################
############################### UI #################################
####################################################################

func _goto_menu(menu: BattleMenuBox, action: Action = null):
	if _menu_page_stack: _menu_page_stack.back().hide()
	menu.enter(true, action)
	_menu_page_stack.push_back(menu)

# Returns true if anything actually happens
func _leave_menu() -> bool:
	if _menu_page_stack.size() > 1:
		_menu_page_stack.pop_back().exit()
		_menu_page_stack.back().enter()
		return true
	elif _curr_party_mem < _party_BPs.size() and $ActionMenuBox.cursor.on:
		if _encore_activated:
			emit_signal("action_select_done")
			_reset_page_stack()
			_set_encore_active(false, true)
			_party_BPs[_curr_party_mem].get_sprite().hide_away()
		elif _is_first_active_member():
			_reset_page_stack()
			_goto_menu($ActionMenuBox)
		else: _prev_active_member()
		return true
	
	return false

func _reset_page_stack():
	for page in range(_menu_page_stack.size()):
		_menu_page_stack.pop_back().exit()

# When an action box is selected, we start an Action object that will be assembly-lined through menus
# When the last menu is completed, the Action object is then saved, and we move on to the next player
func _action_box_selected(action_name: String):
	for box in [$TargetsBox, $PSIBox, $SkillsBox, $ItemsBox]:
		for connection in box.get_signal_connection_list("next"):
			box.disconnect(connection.signal, connection.target, connection.method)
	
	for connection in $TargetsBox.get_signal_connection_list("fail"):
		$TargetsBox.disconnect(connection.signal, connection.target, connection.method)
	
	var bp: BattleParticipant = _party_BPs[_curr_party_mem]
	match(action_name):
		"Basic":
			var skill_action := SkillAction.new(bp)
			skill_action.skill = globaldata.get_battle_skill(bp.character.get_basic_skill())
			$TargetsBox.connect("next", self, "_action_selected", [skill_action])
			_goto_menu($TargetsBox, skill_action)
		"PSI":
			var skill_action := SkillAction.new(bp)
			$PSIBox.connect("next", self, "_goto_menu", [$TargetsBox, skill_action])
			$TargetsBox.connect("next", self, "_action_selected", [skill_action])
			_goto_menu($PSIBox, skill_action)
		"Skills":
			var skill_action := SkillAction.new(bp)
			$SkillsBox.connect("next", self, "_goto_menu", [$TargetsBox, skill_action])
			$TargetsBox.connect("next", self, "_action_selected", [skill_action])
			_goto_menu($SkillsBox, skill_action)
		"Items":
			var item_action := ItemAction.new(bp)
			$ItemsBox.connect("next", self, "_goto_menu", [$TargetsBox, item_action])
			$TargetsBox.connect("next", self, "_action_selected", [item_action])
			$TargetsBox.connect("fail", self, "_on_target_box_fail", [item_action])
			_goto_menu($ItemsBox, item_action)
		"Defend":
			var skill_action := SkillAction.new(bp)
			skill_action.skill = globaldata.get_battle_skill(globaldata.SKILL_GUARD)
			_action_selected(skill_action)
			_do_guard(skill_action)
		"Run":
			_action_selected(FleeAction.new(bp))

func _add_actions_to_menu(bp: BattleParticipant):
	var with_run := _is_first_active_member() and (_can_run or _post_battle_cutscenes.has(Result.FLEE))
	$ActionMenuBox.set_actions_for_user(bp, with_run)

func _on_target_box_fail(action: ItemAction): # suspend func
	_menu_page_stack.pop_back().exit()
	var error_text: String = action.targets[0].character.get_item_inability_message(action.item)
	if !error_text: error_text = "BATTLE_MSG_WRONG_ITEM"
	yield($Dialoguebox.start_from_formatted(error_text, _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.item.get_data())), "completed")
	_goto_menu($TargetsBox, action)

func _action_selected(action: Action):
	_set_action_prep_anim(action)
	_reset_page_stack()
	sp_meter.clear_preview_sp()
	
	
	if _encore_activated:
		_set_encore_active(false)
		_action_queue.insert(_current_action_index, action)
		_used_encore = true
		globaldata.set_flag("used_encore", true, false)
	else: 
		_cache_action(action)
		if action is FleeAction:
			_end_player_action_choices(false)
		else: 
			_next_active_member()
	if action is SkillAction:
		action.sp_at_action = sp_meter.get_sp()
		
		_apply_skill_sp_cost(action.skill)
		if action.has_trait("guard"):
			_add_sp(SP_TYPE.GUARD)
	emit_signal("action_select_done")

func _show_inability_text(bp: BattleParticipant, dialog:= ""): # suspend func
	if !dialog:
		yield(get_tree(), "idle_frame")
		return
	$ActionMenuBox.hide()
	yield($Dialoguebox.start_from_formatted(dialog, _context.set_actor(bp)), "completed")

func _check_sp_meter():
	var party_has_skills := false
	for bp in _party_BPs:
		if bp.character.get_usable_skills("skill"):
			party_has_skills = true
			break
	_set_sp_meter_visible(party_has_skills)

func _set_sp_meter_visible(enabled: bool):
	sp_meter.visible = enabled
	_can_encore = enabled
	$InfoBox.set_offset($PlayerInfo/PlayerInfoVbox.get_combined_minimum_size().y)

func _show_action_menu(is_battle_start := false):
	if !_show_intro_outro:
		$AnimAction.play("transitionIn")

####################################################################
######################## ACTION SELECTION ##########################
####################################################################

func _set_active_member(index: int): # suspend func
	# Set player turn
	_curr_party_mem = index
	var can_do_action = _party_BPs[_curr_party_mem].can_act() if _curr_party_mem < _party_BPs.size() else true
	# If party member is unconcious, cycle through party members until we reach next conscious party member
	while _curr_party_mem < _party_BPs.size() and !can_do_action:
		if !_party_BPs[_curr_party_mem].can_act() and !_party_BPs[_curr_party_mem].is_incapacitated():
			yield(_show_inability_text(_party_BPs[_curr_party_mem], _party_BPs[_curr_party_mem].get_combined_status_effect("turn_skip").get("message", "")), "completed")
		_curr_party_mem += 1
		can_do_action = _party_BPs[_curr_party_mem].can_act() if _curr_party_mem < _party_BPs.size() else true
		
	# When there is no party members left, start battle
	if _curr_party_mem >= _party_BPs.size():
		_end_player_action_choices()
	else:
		_party_BPs[_curr_party_mem].get_sprite().show_and_play("lookIntoYourSoul")
		_add_actions_to_menu(_party_BPs[_curr_party_mem])
		_goto_menu($ActionMenuBox)

func _next_active_member(): # suspend func
	_set_active_member(_curr_party_mem + 1) # Next player turn

func _prev_active_member(): # suspend func
	var prev_party_member = _curr_party_mem - 1
	while prev_party_member >= 0 and !_party_BPs[prev_party_member].can_act():
		if !_party_BPs[prev_party_member].is_incapacitated():
			yield(_show_inability_text(_party_BPs[prev_party_member], _party_BPs[prev_party_member].get_combined_status_effect("turn_skip").get("message", "")), "completed")
		prev_party_member -= 1
	if prev_party_member < 0: return
	_reset_page_stack()
	var action = _action_queue.pop_back() 
	if action is SkillAction:
		_set_sp(action.sp_at_action)
		if action.has_trait("guard"):
			action.user.defending = false
	
	_party_BPs[_curr_party_mem].get_sprite().hide_away()
	_curr_party_mem = prev_party_member
	_party_BPs[_curr_party_mem].get_sprite().play("lookIntoYourSoul", true)
	_add_actions_to_menu(_party_BPs[_curr_party_mem])
	_goto_menu($ActionMenuBox)

func _is_first_active_member() -> bool:
	var prev_party_member := _curr_party_mem - 1
	while prev_party_member >= 0 and !_party_BPs[prev_party_member].can_act():
		prev_party_member -= 1
	return prev_party_member < 0

func _end_player_action_choices(with_enemy_delay := true): # suspend func
	if _advantage != Advantage.PLAYER:
		_cache_enemy_and_npc_actions(true, _advantage == Advantage.NEUTRAL)
		if with_enemy_delay:
			yield(get_tree().create_timer(.3), "timeout")
	else:
		_cache_enemy_and_npc_actions(false, true)
	var in_progress = _do_actions()
	if in_progress: yield(in_progress, "completed")
	_new_round()

func _reset_actions():
	_current_action = null
	_current_action_index = 0
	_doing_actions = false

func _new_round(): # suspend func
	if !_active: return
	
	for enemy in _enemy_BPs:
		enemy.handle_battler_script()
	if _buffer_reorganize: _reorganize_enemies()
	_reset_actions()
	
	for bp in _party_BPs:
		bp.get_sprite().hide_away()
	
	# Check for win
	if !_get_conscious(_enemy_BPs):
		_win()
		return
	
	# Check for healed statuses and do passives
	for bp in (_get_conscious(_party_BPs + _enemy_BPs)):
		for sts in bp.character.get_status_ailments():
			var in_progress = _do_status_passive_heal(sts, bp)
			if in_progress: yield(in_progress, "completed")
		
		for passive in bp.get_passive_skills():
			var info: Dictionary = globaldata.get_passive_skill(passive)
			if info.get("one_turn", false):
				bp.try_remove_passive_skill(passive)
	
	_turns_count += 1
	emit_signal("round_done", _turns_count)
	yield(get_tree().create_timer(.4), "timeout")
	_advantage = Advantage.NEUTRAL
	if !_active: return
	# start new round!
	for action in _action_queue: action.free()
	_action_queue.clear()
	_curr_party_mem = -1
	_next_active_member()

func _cache_action(action:Action):
	_action_queue.append(action)

func _cache_enemy_and_npc_actions(do_enemies := true, do_npcs := true):
	var pool := []
	if do_enemies: pool += _enemy_BPs
	if do_npcs: pool += _npc_BPs
	for bp in pool:
		var action: SkillAction
		bp.emit_signal("action_choice")
		if bp.cur_scripted_skill:
			action = SkillAction.new(bp)
			action.skill = globaldata.get_battle_skill(bp.cur_scripted_skill)
			bp.cur_scripted_skill = ""
		else:
			action = _choose_random_action(bp)
		_cache_action(action)

func _choose_random_action(bp: BattleParticipant) -> SkillAction:
	var action: SkillAction
	match bp.get_type():
		# Currently unused for playables, this code was written for the confused status, but it was changed.
		# Anyways, I think it's better to preserve it
		Character.Type.PARTY_MEMBER:
			var actions = bp.get_selectable_action_types()
			var random_action = actions[randi() % actions.size()]
			match random_action:
				"basic":
					action = SkillAction.new(bp)
					action.skill = globaldata.get_battle_skill(bp.character.get_basic_skill())
				"skills", "psi":
					action = SkillAction.new(bp)
					var possible_skills: Array = bp.character.get_usable_skills(random_action)
					action.skill = globaldata.get_battle_skill(possible_skills[randi() % possible_skills.size()])
				"items":
					action = ItemAction.new(bp)
					action.item = bp.get_usable_items()[randi() % bp.get_usable_items().size()]
		_:
			var usable_skills := bp.get_usable_skills()
			var chosen_skill: EnemySkill
			var all_weights := 0.0
			for skill in usable_skills:
				all_weights += skill.weight
			var i = rand_range(0.0, all_weights)
			var current_weight := 0
			for skill in usable_skills:
				current_weight += skill.weight
				if i <= current_weight:
					chosen_skill = skill
					break
			action = SkillAction.new(bp)
			action.skill = globaldata.get_battle_skill(chosen_skill.skill_id)
			action.connect("done", chosen_skill, "try_start_cooldown")
			if !is_connected("round_done", chosen_skill, "try_tick_cooldown"):
				connect("round_done", chosen_skill, "try_tick_cooldown")
	return action

func _do_encore(user_index: int):
	print("Doing encore for " + _party_BPs[user_index].get_name())
	_doing_actions = false
	_current_action = null
	_darken_bg()
	_bg_darkinator.focus_spotlight_on_position(_party_BPs[user_index].get_battle_sprite_shown_position())
	_play_sfx("cheering", 2)
	_set_active_member(user_index)

func _end_encore():
	_doing_actions = true
	_undarken_bg()

func _set_encore_active(enabled: bool, update_encore := false):
	_encore_activated = enabled
	_note_spawner.set_notes_visible(enabled)
	if update_encore:
		if enabled: _remove_sp(SP_TYPE.ENCORE)
		else: _add_sp(SP_TYPE.ENCORE)
	if enabled: 
		_play_sfx("encoreactivate")
		emit_signal("encore_activated")
	print("Encore set to " + str(_encore_activated))

func _set_fast_mode(enabled: bool) -> void:
	for member in _party_BPs:
		member.get_plate().user_fast_mode = enabled

func _try_party_defeat():
	if _get_conscious(_party_BPs) or _lose_battle:
		return
	if _post_battle_cutscenes.has(Result.LOSE):
		_lose_battle = true
		_active = false
		_end_battle_to_overworld(Result.LOSE)
	else: _end_battle_to_game_over()


####################################################################
########################## BATTLE LOGIC ############################
####################################################################

func _do_actions(): # suspend func
	$ActionMenuBox.hide()
	_action_queue.sort_custom(self, "_sort_by_priority")
	
	var last_party_member_index := -1
	while (_current_action_index < _action_queue.size()):
		_set_fast_mode(false)
		_doing_actions = true
		_action_queue[_current_action_index].user.emit_signal("before_action", _action_queue[_current_action_index])
		var action = _action_queue[_current_action_index]
		call_deferred("_start_action", action)
		if action.user.is_type(Character.Type.PARTY_MEMBER):
			last_party_member_index = _party_BPs.find(action.user)
		yield(action, "done")
		
		if _paused:
			emit_signal("battle_paused")
			yield(self, "battle_unpaused")
		
		var status_in_progress = _check_status_effect(action.user)
		if action is SkillAction:
			if status_in_progress: yield(status_in_progress, "completed")
			if _buffer_reorganize: yield(_reorganize_enemies(), "completed")
			if action.skill.get("after_acting_wait"):
				yield(get_tree().create_timer(action.skill.get("after_acting_wait")), "timeout")
			action.user.emit_signal("acted", action)
		
		
		_current_action_index += 1
		
		# Handle Encore
		if !_get_conscious(_enemy_BPs):
			_set_encore_active(false)
		if _encore_activated and (_current_action_index >= _action_queue.size() or !_action_queue[_current_action_index].has_trait("not_interrupted_by_encore")):
			_do_encore(last_party_member_index)
			yield(self, "action_select_done")
			_end_encore()

func _start_action(action: Action): # suspend func
	if _lose_battle: return
	if _buffer_reorganize:
		yield(_reorganize_enemies(), "completed")
		if !_active: return
	_current_action = action
	
	# Hackiest code you've ever seen, at least it works
	for enemy in _enemy_BPs:
		if enemy.cur_dialog:
			if _current_action.user == enemy:
				var party_target_hp = []
				for bp in _party_BPs:
					party_target_hp.append(bp.get_target_hp())
					bp.get_plate().stop_scrolling()
				yield(get_tree().create_timer(1), "timeout")
				_darken_bg()
				yield(enemy.speech_from_dialog(enemy.cur_dialog), "completed")
				_undarken_bg()
				enemy.cur_dialog = {}
				for i in _party_BPs.size():
					_party_BPs[i].set_target_hp(party_target_hp[i])
	
	if action is SkillAction:
		if action.skill.get("special", "") and action.has_trait("special_before_dialogue"):
			var in_progress = _special_action(action.skill.special, action)
			if in_progress: yield(in_progress, "completed")

	# Check for win
	if !_get_conscious(_enemy_BPs):
		_win()
		return
	
	if action.user.is_incapacitated():
		action.emit_signal("done")
		return
	
	if _lose_battle: return
	
	var can_do_action = yield(_check_ableness_for_action(action.user, action), "completed")
	if !can_do_action:
		if action.user.get_type() == Character.Type.PARTY_MEMBER:
			action.user.get_sprite().hide_away("lookIntoYourSoul", true)
		action.emit_signal("done")
		return
	
	if action is SkillAction and !action is ItemAction and !action.has_trait("no_flash"):
		if action.user.is_type(Character.Type.ENEMY):
			if action.skill.skill_type == "psi":
				var color = action.skill.get("enemy_flash_color", Color.white)
				action.user.get_sprite().set_psi_flash_color(color)
				action.user.get_sprite().flash_psi()
			else:
				_play_sfx("enemyturn")
				action.user.get_sprite().flash()
		else:
			if action.skill.skill_type in ["basic", "skill"]:
				_play_sfx("attack1")
	
	yield(get_tree().create_timer(.05), "timeout")
	
	if !_active: return
	
	_apply_confusion(action)
	yield($Dialoguebox.start_from_appended(), "completed")
	if !_active: return
	
	_retarget_action(action)
	
	var dialog_key := action.get_dialog()
	
	# This category handles both skills and items because items just contain a skill
	if action is SkillAction and !action is ItemAction:
		var skill_cost_result := _try_apply_skill_costs(action.skill, action.user)
		
		if action.skill.skill_type == "psi":
			_play_sfx("enemypsi" if action.user.is_type(Character.Type.ENEMY) else "yourpsi")
		
		if action.targets:
			if dialog_key:
				$Dialoguebox.append_formatted(dialog_key, _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.skill))
				if !skill_cost_result:
					$Dialoguebox.append_formatted("BATTLE_MSG_NOTENOUGH_PP", _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.skill))
				yield($Dialoguebox.start_from_appended(), "completed")
			
			if skill_cost_result:
				_do_skill_with_screen_effect(action)
			else:
				action.emit_signal("done")
		else:
			action.emit_signal("done")
	
	elif action is ItemAction:
		var original_targets: Array = action.targets.duplicate()
		for target in original_targets:
			if !target.character.can_receive_item(action.item):
				action.targets.erase(target)
		
		_play_battle_sprite_anim(action.user, "item")
		
		if action.targets:
			if dialog_key:
				$Dialoguebox.append_formatted(dialog_key, _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.item.get_data()))
				yield($Dialoguebox.start_from_appended(), "completed")
			if action.item.is_battle_consumable():
				action.user.character.inv.reduce_or_drop_item(action.item)
			if action.skill:
				_do_skill_with_screen_effect(action)
			else:
				_do_item(action)
		else:
			for target in original_targets:
				dialog_key = target.character.get_item_inability_message(action.item)
				if !dialog_key: dialog_key = "BATTLE_MSG_WRONG_ITEM"
				$Dialoguebox.append_formatted(dialog_key, _context.set_actor(action.user).set_targets([target]).set_item_or_skill(action.item.get_data()))
				yield($Dialoguebox.start_from_appended(), "completed")
			action.emit_signal("done")
	
	elif action is FleeAction:
		if dialog_key:
			$Dialoguebox.append_formatted(dialog_key, _context.set_actor(action.user))
			yield($Dialoguebox.start_from_appended(), "completed")
		_try_flee(action)

func _do_skill(action: SkillAction): # suspend func
	print("Doing skill")
	if action.user.is_incapacitated():
		print("User is already incapacitated")
		action.emit_signal("done")
		return
	
	# General fail check (as opposed to per-target “miss”)
	if _chance_roll(action.skill.get("fail_chance", 0)):
		var dialog: String = action.skill.get("fail_dialog", "BATTLE_MSG_FAIL")
		if dialog:
			yield($Dialoguebox.start_from_formatted(dialog, _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.skill)), "completed")
		if action.skill.has("fail_action"):
			var fail_action := SkillAction.new(action.user)
			fail_action.skill = globaldata.get_battle_skill(action.skill.fail_action)
			#the target selection logic is weird. it should select targets based off of the FAIL action, not the normal action.
			#TODO: make it select targets based off the FAIL action
			fail_action.targets = action.targets
			call_deferred("_do_skill_with_screen_effect", fail_action)
			yield(fail_action, "done")
		action.emit_signal("done")
		return
	
	
	
	if action.skill.get("success_dialog", ""):
		yield($Dialoguebox.start_from_formatted(action.skill.success_dialog, _context.set_actor(action.user).set_targets(action.targets).set_item_or_skill(action.skill)), "completed")
	
	# Per-target “miss” check (in advance, so that protector NPCs know what to do)
	var no_miss_indexes := []
	var no_miss_targets := []
	for i in action.targets.size():
		if !_get_miss_chance(action):
			no_miss_indexes.append(i)
			if !no_miss_targets.has(action.targets[i]):
				no_miss_targets.append(action.targets[i])
	
	# Dictionary (ally → npc)
	var allies_protected_by_npcs := {}
	
	if !action.has_trait("guard"):
		match action.user.get_type():
			Character.Type.PARTY_MEMBER:
				if action.skill.skill_type:
					var anim_result := _play_battle_sprite_anim(action.user, action.skill.get("user_anim", ""))
					if anim_result and action.skill.skill_type == "basic":
						yield(action.user.get_sprite(), "apply_damage")
			
			Character.Type.ENEMY:
				if action.skill.action_type == ActionType.DAMAGE:
					var in_progress = _setup_npc_protection(action, no_miss_targets, allies_protected_by_npcs)
					if in_progress: yield(in_progress, "completed")
					
					if action.skill.skill_type in ["basic", "skill"]:
						action.user.get_sprite().attack()
						yield(action.user.get_sprite(), "apply_damage")
			
			Character.Type.PARTY_NPC:
				if action.skill.action_type == ActionType.DAMAGE:
					if action.user.get_sprite():
						yield(action.user.get_sprite().attack_target(action.targets[0]), "completed")
		
		var previous_target = null
		for i in action.targets.size():
			var skill := action.skill
			var user := action.user
			var target: BattleParticipant = action.targets[i]
			var intended_target := target
			var miss := !no_miss_indexes.has(i)
			
			print("Target is: %s" % target.character.get_name())
			if action.target_type == TargetType.RANDOM_ENEMIES_UNTIL_MISS:
				if i == 0:
					miss = false # The first hit never misses in this case
				elif action.targets.size() == 1: 
					miss = true
				if previous_target == target: # Must never hit the same enemy twice
					continue 
				
			if !target.is_targetable_for_action(action):
				continue
			
			var pre_hit_fx_in_progress = _do_pre_hit_effect(target, skill.get("pre_hit_effect", ""))
			
			if allies_protected_by_npcs.has(target.character.get_name()) and !miss:
				var npc_name = allies_protected_by_npcs[target.character.get_name()]
				if !_ongoing_npc_protection[npc_name]:
					_ongoing_npc_protection[npc_name] = _special_npc_BPs[npc_name].get_sprite().protect_ally(target)
				allies_protected_by_npcs.erase(target.character.get_name())
				target = _special_npc_BPs[npc_name]
			
			match skill.action_type:
				ActionType.DAMAGE:
					yield(pre_hit_fx_in_progress, "completed")
					if !miss:
						var passive_skill_data := target.get_passive_skill_for_attack(skill)
						var passive_multiplier: float = passive_skill_data.get("actions", {}).get("damage_multiplier", 1)
						
						var damage_value: int = yield(_do_attack_damage(action, target, intended_target), "completed")
						
						var in_progress = _use_passive_skill(passive_skill_data, skill, damage_value, user, target)
						if in_progress: yield(in_progress, "completed")
						
						if skill.get("stat_mods", {}) or skill.get("pp_drain", 0) > 0:
							yield(get_tree().create_timer(0.2), "timeout")
					
					else:
						_create_rising_num("Miss", target)
						
						target.get_sprite().dodge()
						$AudioStreamPlayer.stream = _sound_effects["miss" if target.is_type(Character.Type.ENEMY) else "dodge"]
						$AudioStreamPlayer.play()
				
				ActionType.HEALING:
					var val := _calculate_heal_value(action, target)
					_apply_restore_hp(target, val, action)
					print("%s is healed by %s!" % [target.get_name(), val])
					if val > 0:
						global.start_joy_vibration(0, 0.3, 0, 0.3)
						_create_rising_num(str(val), target, Color("00ee44"))
						_do_hit_effect(action.skill.get("hit_effect", ""), action.skill.get("hit_sound", ""), target)
					yield(pre_hit_fx_in_progress, "completed")
				ActionType.AILMENT:
					yield(pre_hit_fx_in_progress, "completed")
					var statuses := skill.get("status_effects", {}) as Dictionary
					if miss:
						_create_rising_num("Miss", target)
						
						target.get_sprite().dodge()
						$AudioStreamPlayer.stream = _sound_effects["miss" if target.is_type(Character.Type.ENEMY) else "dodge"]
						$AudioStreamPlayer.play()
					elif !miss and statuses:
						# Free space~!! dumbass lloyd shit go here for now
						var mult = target.get_affinity_multiplier(skill.get("class", ""))
						yield(_try_afflict_statuses(statuses, target, skill.action_type == ActionType.AILMENT, mult), "completed")
								
				# For non hp, non ailment stuff
				_:
					yield(pre_hit_fx_in_progress, "completed")
					var statuses := skill.get("status_effects", {}) as Dictionary
					if !miss and statuses:
						# Free space~!! dumbass lloyd shit go here for now
						var mult = target.get_affinity_multiplier(skill.get("class", ""))
						yield(_try_afflict_statuses(statuses, target, skill.action_type == ActionType.AILMENT, mult), "completed")
			
			if !_active: return
			
			# Additional effects
			if !miss:
				# Spying the enemy
				if action.skill.id == globaldata.SKILL_SPY:
					var in_progress = _spy_battler(action.user, target)
					if in_progress: yield(in_progress, "completed")
				
				# Summoning allies into battle
				if action.skill.get("allies", {}) and _enemy_BPs.size() < MAX_ENEMY_COUNT:
					_try_add_allies(action.user, action.skill.allies)
				
				# Draining PP
				if skill.get("pp_drain", 0) > 0:
					var pp_amount: int = skill.get("pp_drain")
					var pp_gained: bool = action.has_trait("pp_gained")
					_drain_pp(action.user, target, pp_amount, pp_gained)
				
				# Healing status ailments
				if skill.get("status_heals", []):
					var was_unconscious := target.is_unconscious()
					var heal_amount = skill.get("status_amount_healed", -1)
					if heal_amount > 0:
						for j in heal_amount:
							for status in target.character.get_status_ailments():
								if status.ailment in skill.status_heals:
									yield(_heal_status([status.ailment], target), "completed")
									break
					elif heal_amount == -1:
						yield(_heal_status(skill.status_heals, target), "completed")
					
					if was_unconscious and !target.is_unconscious():
						if action.has_trait("heal_on_revive"):
							var val := _calculate_heal_value(action, target)
							_apply_restore_hp(target, val, action)
							if val > 0:
								global.start_joy_vibration(0, 0.3, 0, 0.3)
								_create_rising_num(str(val), target, Color("00ee44"))
				
				# Giving passive skills
				if skill.has("give_passive_skill"):
					var p_skill_id: String = skill.give_passive_skill
					print(p_skill_id)
					var already_had := target.has_passive_skill(p_skill_id)
					target.add_passive_skill(p_skill_id)
					var p_skill_data: Dictionary = globaldata.get_passive_skill(p_skill_id)
					if p_skill_data.has("exclusive_to_one"):
						var bp = _get_bp_with_passive_skill(p_skill_id)
						if bp and bp != target:
							bp.remove_passive_skill(p_skill_id)
					var dialog := p_skill_data.get("dialogue_reapply" if already_had else "dialogue_apply", "") as String
					if dialog:
						yield($Dialoguebox.start_from_formatted(dialog, _context.set_actor(action.user).set_targets([target]).set_item_or_skill(action.skill)), "completed")
				
				# Affecting stats
				for stat in skill.get("stat_mods", {}):
					var in_progress = _mod_stat(stat, skill.stat_mods[stat], action.user, target, skill.action_type == ActionType.STAT)
					if in_progress: yield(in_progress, "completed")
					if !_active: return
				
				# Stealing items
				if action.has_trait("steal_item"):
					var in_progress = _do_steal_item(action.skill, action.user, target)
					if in_progress: yield(in_progress, "completed")
				
				var in_progress = _do_status_transmission(action.user, target, action)
				if in_progress: yield(in_progress, "completed")
				
				in_progress = _do_status_hit_heal(target, action)
				if in_progress: yield(in_progress, "completed")
			
			else:
				if action.skill.has("miss_dialog"):
					yield($Dialoguebox.start_from_formatted(action.skill.miss_dialog, _context.set_actor(action.user).set_targets([target]).set_item_or_skill(action.skill)), "completed")
			
			var action_repeats: int = action.skill.get("repeat", 0)
			if action_repeats > 0:
				var repeated_action := SkillAction.new(action.user)
				repeated_action.skill = action.skill.duplicate()
				repeated_action.targets = [target]
				repeated_action.skill.repeat = action_repeats - 1
				yield(get_tree().create_timer(.7), "timeout")
				_do_skill(repeated_action)
				yield(repeated_action, "done")
			
			var next_move: String = action.skill.get("next_move", "")
			if next_move:
				user.cur_scripted_skill = next_move
			
			yield(get_tree().create_timer(.08), "timeout")
			
			if miss and action.target_type == TargetType.RANDOM_ENEMIES_UNTIL_MISS:
				break
			
			if !target.is_unconscious():
				previous_target = target
			
			if !_active: return
	
	if action.has_trait("flee"):
		var did_run := false
		if action.targets[0].get_type() != action.user.get_type():
			match action.user.get_type():
				Character.Type.ENEMY:
					print(_enemy_BPs.size())
					_exp_pool -= action.user.character.get_exp()
					_exp_pool += action.skill.get("exp_from_flee", 0)
					action.user.enemy_flee()
					did_run = true
					if action.skill.get("exp_from_flee",0) > 0:
						# For displaying a special message if enemy uses walkAway and battle ends right after that
						_received_exp_from_flee = _enemy_BPs.size() < 1
				Character.Type.PARTY_MEMBER:
					if _can_run:
						_flee()
						did_run = true
		if !did_run:
			yield($Dialoguebox.start_from_string(tr("BATTLE_MSG_FLEE_FAIL")), "completed")
	
	if action.has_trait("kill_user"):
		action.user.defeat()
	
	if !_active: return
	# Check for status effect damage
	
	if action.get_dialog() != "":
		yield(get_tree().create_timer(.4), "timeout")
	
	if !_active: return
	
	if action.user.is_type(Character.Type.PARTY_MEMBER) and !action.user.defending:
		if action.skill.has("user_anim_return"):
			action.user.get_sprite().play(action.skill.user_anim_return, true)
		
		if _paused:
			emit_signal("battle_paused")
			yield(self, "battle_unpaused")
		
		action.user.get_sprite().hide_away()
	
	_check_buffered_player_defeat()
	
	action.emit_signal("done")

func _do_skill_with_screen_effect(action: SkillAction): # suspend func
	if action.skill.get("special", "") and !action.has_trait("special_before_dialogue"):
		var in_progress = _special_action(action.skill.special, action)
		if in_progress: yield(in_progress, "completed")
	
	var sound_name: String = action.skill.get("use_sound", "")
	if _sound_effects.has(sound_name):
		_play_sfx(sound_name)
	
	var started_effect := false
	
	var screen_effect_anim := "%sscreen_effect" % ("enemy_" if action.user.is_type(Character.Type.ENEMY) else "")
	screen_effect_anim = action.skill.get(screen_effect_anim, "")
	
	
	_check_buffered_player_defeat()
	
	if _lose_battle: return
	
	if $ScreenEffect/AnimationPlayer.has_animation(screen_effect_anim):
		$ScreenEffect/AnimationPlayer.play(screen_effect_anim)
		started_effect = true
	
	if started_effect:
		_darken_bg()
		yield($ScreenEffect/AnimationPlayer, "animation_finished")
	
	_do_skill(action)
	
	if started_effect:
		_undarken_bg()
	
	yield(action, "done")
	

func _do_item(action: ItemAction): # suspend func
	if action.user.is_incapacitated():
		action.emit_signal("done")
		return
	if !_get_conscious(_party_BPs): 
		action.emit_signal("done")
		return
	var item_data := action.item.get_data()
	if item_data.get("battle_action", {}).get("dialog"):
		var dialogue_path: String = "res://Data/Dialogue/%s.yaml" % item_data.battle_action.dialog
		if !File.new().file_exists(dialogue_path):
			dialogue_path = "Reusable/error"
		yield($Dialoguebox.start_from_scripted_dialog(YAMLParser.parse_file(dialogue_path), false), "completed")
	for target in action.targets:
		if target.is_targetable_for_action(action):
			if item_data.HPrecover > 0:
				_play_sfx("healHP", 1)
				_apply_restore_hp(target, item_data.HPrecover, action)
				_create_rising_num(str(item_data.HPrecover), target, Color("00ee44"))
			if item_data.PPrecover > 0:
				_play_sfx("healPP", 1)
				_apply_restore_pp(target, item_data.PPrecover, action)
				_create_rising_num(str(item_data.PPrecover), target, Color("d6b5ff"))
			if action.item.is_equippable():
				_play_sfx("equip", 1)
				target.character.inv.equip_item(action.item)
			if "status_heals" in item_data:
				var was_unconscious = target.is_unconscious()
				yield(_heal_status(item_data.status_heals, target), "completed")
				if was_unconscious and !target.is_unconscious():
					if action.has_trait("heal_on_revive"):
						var max_hp = target.get_stat(Character.MAXHP)
						_apply_restore_hp(target, max_hp, action)
						global.start_joy_vibration(0, 0.3, 0, 0.3)
						_create_rising_num(str(max_hp), target, Color("00ee44"))
				if !_active: return
			yield(get_tree().create_timer(.15), "timeout")
			if !_active: return
	if action.user.get_type() == Character.Type.PARTY_MEMBER:
		action.user.get_sprite().play("itemReturn", true)
		action.user.get_sprite().hide_away()
	yield(get_tree().create_timer(.3), "timeout")
	action.emit_signal("done")

func _do_guard(action: Action):
	action.user.defending = true
	if !is_connected("round_done", self, "_undo_all_guards"):
		connect("round_done", self, "_undo_all_guards", [], CONNECT_ONESHOT)

func _undo_all_guards(foo):
	for bp in _party_BPs + _enemy_BPs + _npc_BPs:
		if !bp.defending: continue
		bp.defending = false
		if bp.is_type(Character.Type.PARTY_MEMBER):
			bp.get_sprite().hide_away()

func _special_action(special_id: String, action: Action):
	var user = action.user
	match special_id:
		"ratKingUncloak":
			yield(user.get_sprite().uncloak(), "completed")
			var rats = user.get_sprite().get_stronger_rats_sprites()
			if _enemy_stash:
				for i in range(_enemy_stash.size()):
					var enemy_bp = _enemy_stash[i]
					enemy_bp.reassign_sprite(rats[i], $Enemies)
					_enemy_BPs.append(enemy_bp)
					enemy_bp.character.remove_status(Status.AILMENT_UNCONSCIOUS)
				_enemy_stash.clear()
			else:
				for i in range(2):
					var enemy_bp := _add_enemy(Enemy.new("strongerrat"))
					enemy_bp.add_battle_sprite($Enemies, null, rats[i])
					enemy_bp.get_sprite().show()
			_buffer_reorganize = true
		
		"ratKingRecloak":
			yield(user.get_sprite().recloak(), "completed")
			for bp in _get_conscious(_enemy_BPs):
				if bp.character.get_id() == "strongerrat":
					_stash_enemy(bp)
					bp.character.add_status(Status.AILMENT_UNCONSCIOUS)
		
		"rocketLauncherCountdown":
			var in_progress = user.advance_counter()
			if in_progress: yield(in_progress, "completed")
		
		"rocketLaunch":
			user.launch()
			add_action(user, "advance_counter", false)
		
		"callRocketLaunchers":
			var rocket_launcher_enemy = load("res://Scripts/UI/Battle/RocketLauncherEnemy.gd")
			for i in range(2):
				_enemy_BPs.append(rocket_launcher_enemy.new(self, i == 1))
			emit_signal("enemy_party_changed", _get_conscious(_enemy_BPs))
		
		"focusDistorto":
			var conscious_party = _get_conscious(_party_BPs)
			if conscious_party.size() > 0:
				var min_hp = INF
				for bp in conscious_party:
					if bp.get_target_hp() < min_hp:
						min_hp = bp.get_target_hp()
						action.targets = [bp]
			var enemies = []
			for bp in _get_conscious(_enemy_BPs):
				if !bp.character.get_id() in ["drdistorto", "rocketlauncher"]:
					enemies.append(bp)
			pause_battle()
			$PreHitEffect/AnimationPlayer.connect("animation_finished", self, "unpause_battle", [], CONNECT_ONESHOT)
			for bp in enemies:
				add_action(bp, "robotBash")
				$PreHitEffect.connect("apply_damage", bp, "speech_from_string", ["BATTLE_DRDISTORTO_ROBOTS_0", true], CONNECT_ONESHOT)
				connect("battle_unpaused", bp.get_speech_bubble(), "manual_end_dialogue", [], CONNECT_ONESHOT)
		
		"robotBash":
			var bp = _get_bp_with_passive_skill("focus")
			if bp:
				action.targets[0] = bp
			else:
				var rocket_launchers = []
				for e_bp in _get_conscious(_enemy_BPs):
					if e_bp.character.get_id() == "rocketlauncher" and e_bp.toggled:
						rocket_launchers.append(e_bp)
				if rocket_launchers and _chance_roll(40):
					action.targets[0] = rocket_launchers[randi() % rocket_launchers.size()]

func _check_ableness_for_action(bp: BattleParticipant, action: Action = null) -> bool: # suspend func
	var turn_skip = _current_action.user.get_combined_status_effect("turn_skip")
	if turn_skip.get("enable", false):
		yield(_show_inability_text(_current_action.user, turn_skip.get("message", "")), "completed")
		return false
	
	var action_types = bp.get_combined_status_effect("cant_do")
	var can_do = true
	for type in action_types:
		if "action" in type.keys():
			can_do = !_compare_action_types(action, type.action)
		if !can_do:
			yield(_show_inability_text(bp, type.get("message", "")), "completed")
			return false
	yield(get_tree(), "idle_frame")
	return true

func add_action(bp: BattleParticipant, skill_name: String, overwrite_skill := true):
	var action = SkillAction.new(bp)
	action.skill = globaldata.get_battle_skill(skill_name)
	
	if overwrite_skill:
		for i in range(_action_queue.size()):
			if _action_queue[i].user == bp and !_was_action_done(_action_queue[i]):
				_action_queue.remove(i)
				_action_queue.insert(i, action)
				return
	
	if !_doing_actions:
		_cache_action(action)
		_action_queue.sort_custom(self, "_sort_by_priority")
	else:
		for i in range(_current_action_index + 1, _action_queue.size()):
			if _sort_by_priority(action, _action_queue[i]):
				_action_queue.insert(i, action)
				return
		_action_queue.append(action)

func _retarget_action(action: Action):
	# ANYWAY if there are no targets (or they are unconscious), try again
	if !action is SkillAction: return
	var target_ok = (!action.target_type in [TargetType.ALL_ALLIES, TargetType.ALL_ENEMIES]) and action.targets
	for target in action.targets:
		if !target.is_targetable_for_action(action):
			# Redo targets, heck
			target_ok = false
	action.targets = _retargeting(action, target_ok)

func _retargeting(action: Action, maintain := true):
	var targets := []
	
	var party_side := _get_targetables_for_action(_party_BPs + _npc_BPs, action)
	var enemy_side := _get_targetables_for_action(_enemy_BPs, action)
	
	var actor_side := enemy_side if action.user.is_type(Character.Type.ENEMY) else party_side
	var opposite_side := party_side if action.user.is_type(Character.Type.ENEMY) else enemy_side
	
	match action.target_type:
		TargetType.ALL_ENEMIES:
			targets = opposite_side
		TargetType.ALL_ALLIES:
			targets = actor_side
		TargetType.RANDOM_ENEMY:
			targets = [opposite_side[randi() % opposite_side.size()]]
		TargetType.RANDOM_ENEMIES_2:
			targets = [opposite_side[randi() % opposite_side.size()]]
			targets += [opposite_side[randi() % opposite_side.size()]]
		TargetType.RANDOM_ENEMIES_UNTIL_MISS:
			targets = []
				
			if opposite_side.size() > 1:
				var previous_target = null
				for i in 100: # Always try to pick a random enemy other than the previously targeted one
					var new_target = opposite_side[randi() % opposite_side.size()]
					while new_target == previous_target:
						new_target = opposite_side[randi() % opposite_side.size()]
					targets.append(new_target)
					previous_target = new_target
			else:
				targets.append(opposite_side[0])
		TargetType.RANDOM_ALLY:
			targets = [actor_side[randi() % actor_side.size()]]
		TargetType.ANY:
			# Decide random!
			var all = actor_side + opposite_side
			var random = all[randi() % all.size()]
			targets.append(random)
		TargetType.ENEMY:
			if !maintain: 
				targets = [opposite_side[randi() % opposite_side.size()]]
			else: targets = action.targets
		TargetType.ALLY:
			if !maintain:
				targets = [actor_side[randi() % actor_side.size()]]
				if action is ItemAction:
					continue
			else: targets = action.targets
		TargetType.ALLY_EXCEPT_SELF:
			if !maintain:
				actor_side.erase(action.user)
				if actor_side:
					targets = [actor_side[randi() % actor_side.size()]]
				else: targets = []
				if action is ItemAction:
					continue
			else: targets = action.targets
		TargetType.SELF:
			targets = [action.user]
	return targets

func _spy_battler(user: BattleParticipant, target: BattleParticipant): # suspend func
	var dialog := []
	if !target.character.are_affinities_hidden():
		var hp_and_pp_dialog = ""
		if !target.immortal:
			hp_and_pp_dialog = tr("BATTLE_MSG_SPY_HP") % [String(target.get_target_hp()), String(target.get_stat(Character.MAXHP))]
		if target.get_stat(Character.MAXPP) > 0:
			if hp_and_pp_dialog != "":
				hp_and_pp_dialog += tr("BATTLE_MSG_SPY_SPACE")
			hp_and_pp_dialog += tr("BATTLE_MSG_SPY_PP") % [String(target.get_target_pp()), String(target.get_stat(Character.MAXPP))]
		if hp_and_pp_dialog != "":
			dialog.append(hp_and_pp_dialog)
		
		var stats_dialog = tr("BATTLE_MSG_SPY_OFFENSE") % String(target.get_stat(Character.OFFENSE))
		stats_dialog += tr("BATTLE_MSG_SPY_SPACE") + tr("BATTLE_MSG_SPY_DEFENSE") % String(target.get_stat(Character.DEFENSE))
		stats_dialog += tr("BATTLE_MSG_SPY_SPACE") + tr("BATTLE_MSG_SPY_SPEED") % String(target.get_stat(Character.SPEED))
		dialog.append(stats_dialog)
	
	var affinities_dialog := target.character.get_affinities_dialog()
	if target.character.has_mysterious_stats():
		dialog.append($Dialoguebox.format_battle_text("BATTLE_MSG_SPY_MYSTERIOUS", _context.set_actor(user).set_targets([target])))
	elif !target.character.are_affinities_hidden():
		if !affinities_dialog:
			dialog.append($Dialoguebox.format_battle_text("BATTLE_MSG_SPY_NO_AFFINITY", _context.set_actor(user).set_targets([target])))
		else:
			for affinity_dialog in affinities_dialog:
				dialog.append($Dialoguebox.format_battle_text(affinity_dialog, _context.set_actor(user).set_targets([target])))
	
	if target.character.get_description():
		dialog.append(tr("BATTLE_MSG_SPY_NOTES") + tr(target.character.get_description()))
	
	if !target.character.are_affinities_hidden():
		if _item_pool.do_you_get_item() and target == _item_pool.get_item_enemy():
			dialog.append($Dialoguebox.format_battle_text("BATTLE_MSG_SPY_PRESENT", _context.set_actor(user)))
			dialog.append($Dialoguebox.format_battle_text("BATTLE_MSG_SPY_PRESENT_INSIDE", _context.set_item_or_skill(_item_pool.item.get_data())))
	
	yield($Dialoguebox.start_from_array(dialog), "completed")

func _do_steal_item(skill: Dictionary, user: BattleParticipant, target: BattleParticipant): # suspend func
	var item: Item = null
	
	match target.get_type():
		Character.Type.PARTY_MEMBER:
			# Stealing item from the inventory
			if _stolen_item == null:
				var inv := (target.character as PartyMember).inv
				item = inv.get_random_item(true)
				if item:
					inv.drop_item(item)
					if user.get_type() == Character.Type.ENEMY:
						_stolen_item = item
						_stolen_item_definitive = item.is_battle_consumable() and (user.character as Enemy).get_data().get("eats_stolen_items", false)
		
		Character.Type.ENEMY:
			# Stealing item from the enemy drops
			var item_drops: Array = (target.character as Enemy).get_data().get("items", [])
			for item_drop in item_drops:
				for attempts in 2: # Twice the chance to get the item from stealing
					if rand_range(0, 100) < item_drop.chance:
						item = Item.new(item_drop.item)
						user.character.inv.add_item(item)
						break
				if item:
					break
	
	if item:
		yield($Dialoguebox.start_from_formatted("BATTLE_MSG_STEALING", _context.set_actor(user).set_targets([target]).set_item_or_skill(item.get_data())), "completed")
	elif skill.has("miss_dialog"):
		yield($Dialoguebox.start_from_formatted(skill.miss_dialog, _context.set_actor(user).set_targets([target]).set_item_or_skill(skill)), "completed")

func _use_passive_skill(passive_skill_data: Dictionary, skill: Dictionary, dealt_damage: int, user: BattleParticipant, target: BattleParticipant):
	var passive_skill_actions: Dictionary = passive_skill_data.get("actions", {})
	
	# Sound/vibration
	if passive_skill_actions.get("sound"):
		$AudioStreamPlayer.stream = _sound_effects[passive_skill_actions.sound]
		$AudioStreamPlayer.play()
	if passive_skill_actions.get("vibrate", 0) > 0:
		global.start_joy_vibration(0, 0.3, 0.6, passive_skill_actions.vibrate)
	
	# Hit dialogue
	if passive_skill_actions.has("dialogue_hit"):
		var item = globaldata.get_item_data(passive_skill_actions.get("context_item", "error"))
		yield($Dialoguebox.start_from_formatted(passive_skill_actions.dialogue_hit, _context.set_actor(user).set_targets([target]).set_item_or_skill(item)), "completed")
	
	# Counter attack
	if passive_skill_actions.get("counter_multiplier", 0) > 0:
		var damage: int = dealt_damage * passive_skill_actions.counter_multiplier
		yield(get_tree().create_timer(0.6), "timeout")
		yield(_do_generic_damage(user, damage, 0, Color.white, skill.get("hit_effect", ""), skill.get("hit_sound", "")), "completed")
	
	# Return attack
	if passive_skill_actions.get("return_attack", false):
		var counter_action = SkillAction.new(target)
		counter_action.targets = [user]
		counter_action.skill = skill
		yield(get_tree().create_timer(0.3), "timeout")
		yield(_do_attack_damage(counter_action, user), "completed")

	# Add/remove items
	if passive_skill_actions.has("remove_item"):
		target.character.inv.remove_item_by_name(passive_skill_actions.remove_item)
	if passive_skill_actions.has("add_item"):
		target.character.inv.add_item_by_name(passive_skill_actions.add_item)
	
	# Dialogue after
	if passive_skill_actions.has("dialogue_after"):
		yield($Dialoguebox.start_from_string(tr(passive_skill_actions.dialogue_after)), "completed")
	
	var p_skill_id: String = passive_skill_data.get("id", "")
	var did_hit_p_skill := target.try_hit_passive_skill(p_skill_id)
	if did_hit_p_skill:
		if did_hit_p_skill and !target.has_passive_skill(p_skill_id) and passive_skill_data.has("dialogue_vanish"):
			yield($Dialoguebox.start_from_formatted(passive_skill_data.dialogue_vanish, _context.set_actor(user).set_targets([target]).set_item_or_skill(skill)), "completed")

func pause_battle():
	_paused = true

func unpause_battle(_useless_parameter_that_is_necessary_for_some_goddamn_reason_i_fucking_hate_godot):
	_paused = false
	emit_signal("battle_unpaused")


####################################################################
########################## CALCULATIONS ############################
####################################################################

func _calculate_damage(action: Action, target: BattleParticipant, adrenaline: bool, smash: bool) -> int:
	var user := action.user
	var spec_value := action.skill.get("damage_or_heal", 0) as int
	var value_type: String = action.skill.get("value_type", "normal")
	var variance: int = action.skill.get("variance", 0)
	var val: float
	
	var defense: int = target.get_stat(Character.DEFENSE)
	
	match value_type:
		"fixed":
			val = floor(spec_value + (randf() * variance) - variance/2.0)
		"percentage":
			val = spec_value * target.get_target_hp() / 100.0
			val = floor(val + (randf() * variance) - variance/2.0)
		"reach_full_percent": # Reach for a specific percentage of max HP
			var max_hp := target.get_stat(Character.MAXHP)
			var value_to_reach := spec_value * max_hp / 100.0
			val = target.get_target_hp() - value_to_reach
			val = floor(val + (randf() * variance) - variance/2.0)
		"normal", "guts_based", "guts_offense":
			val = int(spec_value)
			
			if value_type in ["guts_based", "guts_offense"]:
				val += user.get_stat(Character.GUTS)
				if value_type == "guts_offense":
					val += user.get_stat(Character.OFFENSE)
			elif action.skill.skill_type == "psi":
				val += user.get_stat(Character.IQ) / 5
			else:
				val += user.get_stat(Character.OFFENSE)
			
			if action.skill.skill_type != "psi":
				var def = defense / 2.0
				val -= def
			
			if adrenaline: val *= ADRENALINE_MULT
			
			if smash:
				val *= SMASH_MULT
			
			val = max(val, 1) # At this point the minimum damage value is 1; then multipliers can still nullify it
			
			var all_multipliers := 1.0
			all_multipliers *= target.get_affinity_multiplier(action.skill.get("damage_type", ""))
			
			print(action.skill)
			all_multipliers *= target.get_affinity_multiplier(action.skill.get("class", ""))
			
			var user_modifier = user.get_combined_status_effect("dealt_mod")
			all_multipliers *= float(_get_damage_modifiers(user_modifier, action))
			var target_modifier = target.get_combined_status_effect("received_mod")
			all_multipliers *= float(_get_damage_modifiers(target_modifier, action))
			
			if all_multipliers <= 0: return -1
			
			val *= all_multipliers
	
	if target.defending: val /= 2.0
	
	val = floor(val + (randf() * variance) - variance/2.0)
	
	if val <= 0: return 0
	else:
		val = max(1, round(val))
		return int(val)

# Same method in PSIMenuUI for the overworld; ideally, we’d need a skills class
func _calculate_heal_value(action: Action, target: BattleParticipant) -> int:
	var user := action.user
	var spec_value := action.skill.get("damage_or_heal") as int
	var value_type := action.skill.get("value_type", "normal") as String
	var variance := action.skill.get("variance", 0) as int
	var val: float
	match value_type:
		"fixed":
			val = floor(spec_value + (randf() * variance) - variance/2.0)
		"percentage":
			val = spec_value * target.get_target_hp() / 100.0
			val = floor(val + (randf() * variance) - variance/2.0)
		"reach_full_percent": # Reach for a specific percentage of max HP
			var max_hp := target.get_stat(Character.MAXHP)
			var value_to_reach := spec_value * max_hp / 100.0
			val = value_to_reach - target.get_target_hp()
			val = floor(val + (randf() * variance) - variance/2.0)
		"normal", "guts_based":
			val = int(spec_value)
			if value_type == "guts_based":
				val += user.get_stat(Character.GUTS) / 2
			elif action.skill.skill_type == "psi":
				val += user.get_stat(Character.IQ) / 5
			
			val = floor(val + (randf() * variance) - variance/2.0)
	
	if val <= 0: return 0
	else:
		val = max(1, round(val))
		return int(val)

func _apply_damage(target: BattleParticipant, val: int, intended_target: BattleParticipant = null): # suspend func
	if target.is_incapacitated(): return
	
	if !_get_conscious(_party_BPs): return
	
	var old_hp := target.get_target_hp()
	target.change_hp_by(-val)
	target.emit_signal("bp_hit")
	var max_hp := target.get_stat(Character.MAXHP)
	match target.get_type():
		Character.Type.PARTY_MEMBER:
			if target.defending:
				_play_sfx("hurt2")
				target.get_sprite().play("guard")
				global.start_joy_vibration(0, 0.5, 0.5, 0.2)
			elif val > (1.0/16.0) * max_hp:
				global.start_joy_vibration(0, 0.8, 0.8, 0.3)
				_play_sfx("hurt2")
				target.get_sprite().bounce_up_hit(min(val / (max_hp / 2), 3))
				
				target.get_plate().quake(.1, 1.5)
			else:
				global.start_joy_vibration(0, 0.5, 0.5, 0.2)
				_play_sfx("hurt1")
				target.get_plate().quake(.1)
				target.get_sprite().shake(val / (max_hp / 2))
			if target.get_target_hp() <= 0:
				_play_sfx("mortaldamage")
				global.start_joy_vibration(0, 1, 1, 0.4)
				if old_hp > 0:
					yield($Dialoguebox.start_from_formatted("BATTLE_MSG_MORTAL_DAMAGE", _context.set_targets([target])), "completed")
		Character.Type.ENEMY:
			if target.get_target_hp() != 0:
				target.get_sprite().hit()
				return
			var on_dying_skill := target.character.get_data().get("swan_song", "") as String
			if on_dying_skill:
				var on_dying_action := SkillAction.new(target)
				on_dying_action.skill = globaldata.get_battle_skill(on_dying_skill)
				call_deferred("_start_action", on_dying_action)
				yield(on_dying_action, "done")
			target.defeat()
			if _show_intro_outro:
				yield(get_tree().create_timer(0.5), "timeout")
				var dialog = target.character.outro_message if target.character.outro_message != null else "{n0}{name} became tame!"
				yield($Dialoguebox.start_from_formatted(dialog, target), "completed")
		Character.Type.PARTY_NPC:
			if intended_target:
				$Dialoguebox.append_formatted("BATTLE_MSG_NPC_PROTECTION", _context.set_actor(target).set_targets([intended_target]), _sound_effects["hurt1"].resource_path)
			else:
				_play_sfx("hurt1")
			if target.get_target_hp() <= 0:
				target.defeat()
			yield($Dialoguebox.start_from_appended(), "completed")

func _do_attack_damage(action: Action, target: BattleParticipant, intended_target: BattleParticipant = null) -> int: # suspend func with return value
	if !_get_conscious(_party_BPs): 
		yield(get_tree(), "idle_frame")
		return 0
	
	var passive_skill_data := target.get_passive_skill_for_attack(action.skill)
	var passive_multiplier: float = passive_skill_data.get("actions", {}).get("damage_multiplier", 1)
	
	var use_flying_num := true
	var user := action.user
	var no_effect := false
	
	var smashed := false
	var adrenaline := false
	var shielded: bool = passive_skill_data.get("is_shield", false)
	var can_smash: bool = !passive_skill_data.get("actions", {}).get("block_smash", false)
	
	# Adrenaline check
	if user.is_type(Character.Type.PARTY_MEMBER) and user.get_target_hp() <= 0:
		adrenaline = true
		_add_sp(SP_TYPE.ADRENALINE)
	
	# Smash check
	var crit_chance = action.skill.get("crit_chance", 0)
	var guts := int(max(0, crit_chance + user.get_stat(Character.GUTS)))
	var min_chance = 5.0 if guts > 0.0 else 0.0
	var max_chance = guts/GUTS_MULT * 100.0
	var chance := max(min_chance, max_chance) 
	
	if can_smash: smashed = _chance_roll(chance)
	
	var damage := 0
	damage = _calculate_damage(action, target, adrenaline, smashed)
	if damage == -1:
		no_effect = true
		damage = 0
	
	if target != intended_target and _ongoing_npc_protection.get(target.character.get_name()):
		if _ongoing_npc_protection[target.character.get_name()].is_valid():
			yield(_ongoing_npc_protection[target.character.get_name()], "completed")
		_ongoing_npc_protection[target.character.get_name()] = null
	
	if no_effect:
		yield($Dialoguebox.start_from_formatted("BATTLE_MSG_TARGET_NO_EFFECT", _context.set_targets([target])), "completed")
		return damage
	
	if smashed:
		var smash_attack = _create_smash_attack(target)
		$SMASHBOX.add_child(smash_attack)
		_play_sfx("smash", 2)
		global.start_joy_vibration(0, 1, 1, 0.4)
		global.start_slowmo(0.5, 0.5)
	elif target.is_type(Character.Type.ENEMY):
		_play_sfx(action.skill.get("hit_sound", ""), 1)
		global.start_joy_vibration(0, 0.5, 0.8, 0.2)
	
	var damage_with_shields := int(ceil(damage * passive_multiplier))
	
	if passive_multiplier > 0:
		var damage_str := str(damage_with_shields)
		if shielded: 
			damage_str = "*" + damage_str # Shield effect goes before hit effect
		if adrenaline: damage_str = damage_str + "!"
		
		# Manage color
		var color := _get_damage_color(user.get_combined_status_effect("dealt_color"), action)
		var target_color := _get_damage_color(target.get_combined_status_effect("received_color"), action)
		if target_color != Color.white:
			color = target_color
		_create_rising_num(damage_str, target, color, use_flying_num)
	if shielded: 
		_do_shield_hit_effect(target._battle_passive_skills, action.skill.get("hit_sound", ""), target)
	_do_hit_effect(action.skill.get("hit_effect", ""), action.skill.get("hit_sound", ""), target)
	
	_try_add_attack_sp(action, target)
	
	var in_progress = _apply_damage(target, damage_with_shields, intended_target)
	if in_progress: yield(in_progress, "completed")
	else: yield(get_tree(), "idle_frame")
	# Status ailment that might come with a hit
	var statuses := action.skill.get("status_effects", {}) as Dictionary
	if damage_with_shields > 0 and statuses:
		yield(_try_afflict_statuses(statuses, target, false, target.get_affinity_multiplier(action.skill.get("class", ""))), "completed")
		yield(get_tree().create_timer(0.4), "timeout")
	
	return damage # Return the damage value not including shields

func _do_generic_damage(target: BattleParticipant, val: float, variance := 0, color := Color.white, hit_effect := "", hit_sound := ""): # suspend func
	if !_get_conscious(_party_BPs): 
		return
	val = floor(val + (randf() * variance) - variance/2.0)
	var val_int := int(val)
	var damage_num := str(val_int)
	_create_rising_num(damage_num, target, color)
	
	if target.is_type(Character.Type.ENEMY):
		_play_sfx(hit_sound, 1)
	
	_do_hit_effect(hit_effect, hit_sound, target)
	
	var in_progress = _apply_damage(target, val_int)
	if in_progress: yield(in_progress, "completed")
	
	yield(get_tree().create_timer(.575), "timeout")

func _mod_stat(stat: String, amt: int, user: BattleParticipant, target: BattleParticipant, with_fail_dialog := false): # suspend func
	if target.is_unconscious(): return
	
	var chance := int(100 * target.get_affinity_multiplier(stat))
	
	if !_chance_roll(chance):
		if with_fail_dialog:
			var dialog := "BATTLE_MSG_TARGET_FAIL"
			if chance == 0:
				dialog = "BATTLE_MSG_TARGET_NO_EFFECT"
			yield($Dialoguebox.start_from_formatted(dialog, _context.set_actor(user).set_targets([target])), "completed")
		return
	
	var cur_stat_mod = target.get_stat_mod(stat)
	# Add smaller amount if it’s close to the limit
	if cur_stat_mod < MAX_STAT_MODS and cur_stat_mod + amt > MAX_STAT_MODS:
		amt = MAX_STAT_MODS - cur_stat_mod
	elif cur_stat_mod > -MAX_STAT_MODS and cur_stat_mod + amt < -MAX_STAT_MODS:
		amt = -MAX_STAT_MODS - cur_stat_mod
	
	var dialog: String
	if abs(cur_stat_mod + amt) <= MAX_STAT_MODS:
		# Raises by base stat * 1/32 or a minimum of 3
		# Moves like Offense Up/Defense Up have an amt of 2, so it's more like it's raising it by 1/16
		var statRaise = round(amt * max(STAT_MOD_MINIMUM_AMOUNT, target.get_base_stat(stat, true) * STAT_MOD_STEP))
		if sign(amt) > 0:
			_play_sfx("statup", 1)
			global.start_joy_vibration(0, 0.3, 0, 0.2)
			if stat in STAT_MOD_ANIMS:
				_do_hit_effect_by_anim("stat_" + stat + "_up", target)
			dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_STATS_UP", _context.set_targets([target]).set_value(statRaise).set_stat(stat))
		elif sign(amt) < 0:
			_play_sfx("statdown", 1)
			global.start_joy_vibration(0, 0.3, 0, 0.2)
			if stat in STAT_MOD_ANIMS:
				_do_hit_effect_by_anim("stat_" + stat + "_down", target)
			dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_STATS_DOWN", _context.set_targets([target]).set_value(-statRaise).set_stat(stat))
		target.add_stat_mod(stat, amt)
	elif cur_stat_mod + amt > MAX_STAT_MODS:
		dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_STATS_UP_MAX", _context.set_targets([target]).set_stat(stat))
	
	elif cur_stat_mod + amt <= -MAX_STAT_MODS:
		dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_STATS_DOWN_MAX", _context.set_targets([target]).set_stat(stat))
	
	if dialog:
		yield($Dialoguebox.start_from_string(dialog), "completed")

func _try_add_attack_sp(action: Action, target: BattleParticipant):
	if !target.is_type(Character.Type.ENEMY):
		_add_sp(SP_TYPE.DAMAGED)
	elif !action.user.is_type(Character.Type.ENEMY) and action.skill.skill_type == "basic":
		_add_sp(SP_TYPE.BASIC)

# statuses_with_probs is a dictionary of status → chance_to_inflict (0-100)
func _try_afflict_statuses(statuses_with_probs: Dictionary, target: BattleParticipant, with_fail_dialog := false, mult: float = 1): # suspend func
	print("Trying to inflict %s with base %s multiplier." % [statuses_with_probs, mult])
	var unlucky_fail := false
	var performed_count: int = 0
	for status in statuses_with_probs:
		if status == Status.AILMENT_UNCONSCIOUS and (target.is_boss() or target.is_type(Character.Type.PARTY_MEMBER)):
			continue # Bosses and party members SHOULD NOT get OHKO'd by stuff like PK Flash and Beam Gamma
		
		if !target.is_incapacitated() and target.character.can_get_status(status):
			var chance := statuses_with_probs[status] as float
			var chance_mult := target.get_affinity_multiplier(status) * mult
			print("Trying %s with %s chance and %s mult" % [status, chance, chance_mult])
			if _chance_roll(chance, chance_mult):
				yield(_afflict_status(status, target, with_fail_dialog), "completed")
				performed_count += 1
			else:
				unlucky_fail = 0 < chance * chance_mult
		elif !globaldata.does_ailment_exist(status):
			push_warning("Unknown status ailment: %s" % status)
	if performed_count == 0 and with_fail_dialog:
		var dialog := "BATTLE_MSG_TARGET_FAIL" if unlucky_fail else "BATTLE_MSG_TARGET_NO_EFFECT"
		yield($Dialoguebox.start_from_formatted(dialog, _context.set_targets([target])), "completed")
	yield(get_tree(), "idle_frame")

func _afflict_status(status: String, target: BattleParticipant, with_fail_dialog := false): # suspend func
	var ailment_data := globaldata.get_ailment_data(status)
	if !globaldata.does_ailment_exist(status):
		yield(get_tree(), "idle_frame")
		return
	if target.has_status(status) and ailment_data.get("ignore_reinflict", false):
		if with_fail_dialog:
			yield($Dialoguebox.start_from_formatted("BATTLE_MSG_TARGET_NO_EFFECT", _context.set_targets([target])), "completed") # It had no effect on [target]!
			return
		else:
			yield(get_tree(), "idle_frame")
			return
	
	if status == Status.AILMENT_UNCONSCIOUS:
		target.defeat()
	else:
		_play_sfx("statusafflicted")
		target.set_status(status, true)
	
	var dialog := Status.get_status_message(status, "afflict_battle")
	if dialog:
		yield($Dialoguebox.start_from_formatted(dialog, _context.set_targets([target])), "completed")
	else:
		yield(get_tree(), "idle_frame")
	_try_party_defeat()

func _heal_status(status_list: Array, target: BattleParticipant): # suspend func
	var healed := false
	var heal_all = status_list.has("all")
	var target_statuses := target.get_all_status_effects()
	if heal_all: status_list = ["asthma", "blinded", "burned", "cold", "confused", "forgetful", "mushroomized", "nausea", "numb", "poisoned", "sleeping", "stone", "sunstroked", "unconscious"]
	for status in status_list:
		if !target.has_status(status):
			continue
		target.set_status(status, false)
		if !healed: _play_sfx("healstatus", 1)
		healed = true
		if heal_all and target_statuses.size() > 1: # Check if there are more than one status ailment
			continue
		var dialog_key := Status.get_status_message(status, "heal_battle")
		yield($Dialoguebox.start_from_formatted(dialog_key, _context.set_targets([target])), "completed")
	
	if !healed:
		var dialog_key := "BATTLE_MSG_HEAL_NONE"
		yield($Dialoguebox.start_from_formatted(dialog_key, _context.set_targets([target])), "completed")
		return
		
	if heal_all and target_statuses.size() > 1:
		var dialog_key := "BATTLE_MSG_HEAL_ALL"
		yield($Dialoguebox.start_from_formatted(dialog_key, _context.set_targets([target])), "completed")

func _check_status_effect(bp: BattleParticipant, before_turn := false, on_complete: FuncRef = null, on_complete_params: Array = []): # suspend func
	var effects_to_do := []
	for effect in bp.get_all_status_effects():
		for key in effect.keys():
			var dict = {key: effect[key]}
			if effect[key] is Dictionary:
				if effect[key].get("moment", "after") == "before" if before_turn else "after":
					effects_to_do.append(dict)
	
	for effect in effects_to_do:
		var in_progress = _do_status_effect(bp, effect)
		if in_progress: yield(in_progress, "completed")
	
	if on_complete:
		on_complete.call_funcv(on_complete_params)

func _do_status_effect(bp: BattleParticipant, effect: Dictionary):
	var key = effect.keys()[0]
	var value = effect.values()[0]
	match key:
		"damage":
			yield(get_tree().create_timer(.2), "timeout")
			yield($Dialoguebox.start_from_formatted(value.get("message", ""), _context.set_actor(bp)), "completed")
			var in_progress = _do_generic_damage(bp, value.get("value", 5), value.get("variance", 0), Color(value.get("color", "ffffff")))
			if in_progress: yield(in_progress, "completed")
		"die_after":
			var status := bp.get_status(value.get("status"))
			yield($Dialoguebox.start_from_formatted(value.get("message", [])[status.battle_turns], _context.set_actor(bp)), "completed")
			status.battle_turns += 1
			if status.battle_turns >= value.get("turns", 0):
				bp.defeat()
				return

func _apply_restore_hp(target: BattleParticipant, val: int, action: Action):
	if !target.is_targetable_for_action(action): return
	target.change_hp_by(val)

func _apply_restore_pp(target: BattleParticipant, val: int, action: Action):
	if !target.is_targetable_for_action(action): return
	target.change_pp_by(val)

func _add_sp(amt: int, multiplied := false):
	return sp_meter.add_sp(amt, multiplied)

func _remove_sp(amt: int, multiplied := false):
	sp_meter.remove_sp(amt, multiplied)

func _set_sp(amt: int):
	sp_meter.set_sp(amt)

func _apply_skill_sp_cost(skill: Dictionary):
	# Subtract sp costs
	if skill.get("sp_cost", 0) > 0: _remove_sp(skill.sp_cost, true)

func _try_apply_skill_costs(skill: Dictionary, user:BattleParticipant) -> bool:
	var hp_cost := skill.get("hp_cost", 0) as int
	var pp_cost := skill.get("pp_cost", 0) as int
	if hp_cost > user.get_target_hp() or pp_cost > user.get_target_pp():
		return false
	
	# Subtract hp/pp costs
	if hp_cost > 0: user.change_hp_by(-hp_cost)
	if pp_cost > 0: user.change_pp_by(-pp_cost)
	
	return true

func _drain_pp(drainer: BattleParticipant, target: BattleParticipant, pp_to_drain: int, give_to_drainer: bool):
	if target.is_incapacitated(): return
	
	# Randomize value of pp 
	var randomness := randi() % (pp_to_drain/5)
	pp_to_drain += randomness
	pp_to_drain += pp_to_drain / 10
	
	# Remove pp from target
	pp_to_drain = - target.change_pp_by(- pp_to_drain)
	
	# Give pp to drainer
	if give_to_drainer and drainer:
		pp_to_drain = drainer.change_pp_by(pp_to_drain)
		_create_rising_num(str(pp_to_drain), drainer, Color("d6b5ff"))
	# Otherwise just create rising num for the target
	else:
		_create_rising_num(str(pp_to_drain), target, Color.orange)

func _apply_confusion(action: Action):
	var has_confusion := false
	var effect = action.user.get_combined_status_effect("confusion")
	if effect and effect.get("enable", false):
		if _chance_roll(effect.get("prob", 50)):
			has_confusion = true
	if !has_confusion or !action is SkillAction or action.has_trait("confusion_proof") or \
			action.target_type == TargetType.SELF:
		return
	$Dialoguebox.append_formatted(effect.get("message"), _context.set_actor(action.user))
	match action.target_type:
		TargetType.ALL_ENEMIES, TargetType.ALL_ALLIES:
			action.target_type = [TargetType.ALL_ENEMIES, TargetType.ALL_ALLIES][randi() % 2]
		_:
			action.target_type = [TargetType.RANDOM_ENEMY, TargetType.RANDOM_ALLY][randi() % 2]

func _do_status_passive_heal(status: Status, bp: BattleParticipant):
	var info: Dictionary = status.get_data()
	if !info["healing"].get("passive_heal", false):
		return
	var mandatory_turns: int = info["healing"].get("mandatory_turns", 3)
	var turns_diff: int = status.battle_turns - mandatory_turns
	if _chance_roll(status.passive_heal_probability, turns_diff):
		yield(_heal_status([status.ailment], bp), "completed")
	else: 
		status.battle_turns += 1
		if turns_diff == 0 and bp.is_boss():
			status.passive_heal_probability += 50

func _do_status_hit_heal(bp:BattleParticipant, action:Action): # suspend func
	for status in bp.character.get_status_ailments():
		var info = status.get_data()
		if info.has("healing") and info.healing.has("by_hit"):
			if info.healing.by_hit.has("action") and !_compare_action_types(action, info.healing.by_hit.action):
				continue
			if _chance_roll(info.healing.by_hit.get("prob", HEAL_BY_HIT_PROB)):
				yield(_heal_status([status.ailment], bp), "completed")

func _do_status_transmission(transmitter:BattleParticipant, transmitted:BattleParticipant, action:Action): # suspend func
	for sts in transmitter.character.get_status_ailments():
		var info = sts.get_data()
		if info.has("transmit"):
			if info.transmit.has("action") and !_compare_action_types(action, info.transmit.action):
				continue
			var prob = info.transmit.get("prob", TRANSMIT_PROB)
			yield(_try_afflict_statuses({sts.ailment: prob}, transmitted), "completed")

func _get_damage_modifiers(effects: Array, action: Action) -> int:
	var modifier = 1
	for effect in effects:
		if effect.has("action") and _compare_action_types(action, effect.action):
			modifier *= effect.get("mod", 1)
	return modifier

func _get_damage_color(effects: Array, action: Action) -> Color:
	for effect in effects:
		if effect.has("action") and _compare_action_types(action, effect.action):
			return Color(effect.get("color", "FFFFFF"))
	return Color.white

# Here we buffer the death of party members so that they don't die during actions like using PSI or using an attack

func _check_buffered_player_defeat():
	print("Checking buffered defeat...")
	if _buffered_player_defeat:
		print("Has buffered defeats!")
		for party_bp in _buffered_player_defeat:
			_check_player_defeated(party_bp)
		_buffered_player_defeat.clear()

func _check_player_defeated(bp: BattleParticipant):
	if _active and _enemy_BPs:
		if bp.get_current_hp() != 0:
			return
		if _doing_actions and _current_action.user.is_type(Character.Type.PARTY_MEMBER) and \
				($ScreenEffect/AnimationPlayer.is_playing() or $PreHitEffect/AnimationPlayer.is_playing() or _is_party_member_attacking()):
			if !_buffered_player_defeat.has(bp):
				print("Buffered defeat for: %s" % bp.character.get_name())
				_buffered_player_defeat.append(bp)
		else:
			print("BP Defeated: %s" % bp.character.get_name())
			bp.defeat()

func _is_party_member_attacking() -> bool:
	for bp in _party_BPs:
		if !bp.is_incapacitated() and bp.get_sprite().is_attacking():
			return true
	return false

####################################################################
################# BATTLE PARTICIPANTS MANAGEMENT ###################
####################################################################

func _add_party_member(party_member: PartyMember):
	var bp := BattleParticipant.new(self, party_member)
	_party_BPs.append(bp)
	bp.connect("defeated", self, "_on_bp_defeated")
	emit_signal("party_changed", _get_conscious(_party_BPs))

func _add_party_npc(party_npc: PartyNPC):
	var bp := BattleParticipant.new(self, party_npc)
	_npc_BPs.append(bp)
	_special_npc_BPs[party_npc.get_name()] = bp
	bp.connect("defeated", self, "_on_bp_defeated")
	emit_signal("party_changed", _get_conscious(_npc_BPs))

func _add_enemy(enemy: Enemy, overworld_object = null) -> BattleParticipant:
	var enemy_name := enemy.get_id()
	_enemies_per_name[enemy_name] = _enemies_per_name.get(enemy_name, [])
	
	var new_enemy := BattleParticipant.new(self, enemy, _enemies_per_name[enemy_name].size())
	# Adding letter A to the first enemy of that name
	if _enemies_per_name[enemy_name]:
		_enemies_per_name[enemy_name][0].rename_as_first_homonym()
	
	_enemies_per_name[enemy_name].append(new_enemy)
	
	# Then exps, cashes, and items!!
	_exp_pool += new_enemy.character.get_exp()
	_cash_pool += new_enemy.character.get_cash()
	
	_enemy_BPs.append(new_enemy)
	emit_signal("enemy_party_changed", _get_conscious(_enemy_BPs))
	new_enemy.connect("defeated", self, "_on_bp_defeated")
	new_enemy.connect("start_boss_defeat_flash", $BossDefeatFlash, "start_defeat_animation")
	
	# Next, we set up enemy transitions, if there is an overworld sprite
	var enemy_sprite = null
	if overworld_object:
		if overworld_object.has_method("die"):
			new_enemy.set_overworld_obj(overworld_object)
			overworld_object.connect("enemy_erased", new_enemy, "set_overworld_obj", [null])
		overworld_object.hide()
		enemy_sprite = overworld_object.duplicate_sprite()
		# This duplicates the child nodes of the sprite so we have to remove them
		enemy_sprite.set_script(null)
		for child in enemy_sprite.get_children():
			child.queue_free()
		enemy_sprite.position = overworld_object.get_viewport().canvas_transform.xform(overworld_object.position)
	else: enemy_sprite = Sprite.new()
	$EnemyTransitions.add_child(enemy_sprite)
	return new_enemy

func _on_bp_defeated(bp: BattleParticipant, silent := false):
	match bp.get_type():
		Character.Type.PARTY_MEMBER:
			if !silent:
				_play_sfx("playerdefeated")
				global.start_joy_vibration(0, 1, 1, 0.5)
			_try_party_defeat()
			_try_leave_dead_party_member_menu(_party_BPs.find(bp))
			emit_signal("party_changed", _get_conscious(_party_BPs))
		Character.Type.ENEMY:
			_enemy_BPs.erase(bp)
			emit_signal("enemy_party_changed", _get_conscious(_enemy_BPs))
			if _enemy_BPs: _buffer_reorganize = true
			if bp.is_boss():
				for bp in _party_BPs:
					bp.get_plate().stop_scrolling()
				pause_battle()
				_active = false
		Character.Type.PARTY_NPC:
			if !silent:
				global.start_joy_vibration(0, 1, 1, 0.5)
				if bp == _special_npc_BPs.flyingman:
					$Dialoguebox.append_formatted("BATTLE_MSG_FLYING_MAN_COLLAPSED", _context.set_actor(bp), _sound_effects["playerdefeated"].resource_path)
				else:
					_play_sfx("playerdefeated")
			
			_special_npc_BPs.erase(bp.character.get_name())
			_npc_BPs.erase(bp)

func _kill_all_enemies():
	print("kill all enemies")
	var enemies_to_remove = []
	for enemy in _enemy_BPs:
		if !enemy.immortal:
			enemies_to_remove.append(enemy)
	for enemy in enemies_to_remove: enemy.defeat(true)

# Exit the menu of the party member who just died if their menu is open
func _try_leave_dead_party_member_menu(dead_party_member_index: int):
	if dead_party_member_index != _curr_party_mem: return
	_reset_page_stack()
	if !_encore_activated:
		_next_active_member()
	else:
		_set_encore_active(false)
	emit_signal("action_select_done")

func _reorganize_enemies(transition := true): # suspend func
	_buffer_reorganize = false
	var enemies_to_reorganize := []
	for enemy in _enemy_BPs:
		if !enemy.is_incapacitated() and !enemy.get_sprite().is_static():
			enemies_to_reorganize.append(enemy)
	yield($Enemies.reorganize(enemies_to_reorganize, _is_boss, _new_enemies, transition), "completed")

func _setup_npc_protection(action: Action, no_miss_targets: Array, out_protected_targets: Dictionary): # suspend func
	no_miss_targets.sort_custom(self, "_sort_by_low_hp")
	var protected_targets_count := 0
	for npc_name in _special_npc_BPs:
		if action.skill.damage_or_heal >= NPC_TAKING_HIT_THRESHOLD.get(npc_name, 0) \
				or protected_targets_count >= no_miss_targets.size():
			continue
		if !_chance_roll(NPC_TAKING_HIT_CHANCE.get(npc_name, 0)):
			continue
		var cur_target: BattleParticipant = no_miss_targets[protected_targets_count]
		out_protected_targets[cur_target.character.get_name()] = npc_name
		protected_targets_count += 1
		if cur_target == action.targets[0]:
			_ongoing_npc_protection[npc_name] = _special_npc_BPs[npc_name].get_sprite().protect_ally(cur_target)
			yield(get_tree().create_timer(_special_npc_BPs[npc_name].get_sprite().ENEMY_ATTACK_DELAY), "timeout")
		else:
			_ongoing_npc_protection[npc_name] = null

func _try_add_allies(user: BattleParticipant, allies: Array):
	# Lookin' for allies
	var all_weights := 0
	for ally in allies:
		all_weights += ally.weight
	var j = rand_range(0.0, float(all_weights))
	# Find where the random number landed
	var chosen_ally := ""
	var current_weight := 0
	for ally in allies:
		current_weight += ally.weight
		if j < current_weight:
			chosen_ally = ally.ally
			break
	if !chosen_ally: return
	if chosen_ally == "self":
		chosen_ally = user.character.get_id()
	var enemy_bp := _add_enemy(Enemy.new(chosen_ally))
	enemy_bp.add_battle_sprite($Enemies)
	enemy_bp.get_sprite().show()
	_new_enemies.append(enemy_bp)
	_buffer_reorganize = true

func _stash_enemy(enemy_bp: BattleParticipant):
	_enemy_stash.append(enemy_bp)
	_enemy_BPs.erase(enemy_bp)


####################################################################
########################### BATTLE END #############################
####################################################################

func _activate_on_screen_enemies():
	for on_screen_enemy in uiManager.get_on_screen_enemies():
		var overworld_object = on_screen_enemy.overworld_object
		if overworld_object and overworld_object.has_method("activate"):
			overworld_object.activate()

func _win(): # suspend func
	print("win!")
	_active = false
	_reset_actions()
	_set_encore_active(false, false)
	$Dialoguebox.set_auto_advance(false)
	if !$Dialoguebox.did_finish(): yield($Dialoguebox, "done")
	_activate_on_screen_enemies()
	
	if !audioManager.overworld_battle_music or _is_boss:
		audioManager.play_music(audioManager.CHANNELS.BATTLE, _musical_effects["youwonboss" if _is_boss else "youwon"])
		audioManager.queue_music(audioManager.CHANNELS.BATTLE, _musical_effects["victory"])
	
	_set_bp_end_battle()
	# Show player battle sprites + victory animation
	for bp in _get_conscious(_party_BPs):
		if !bp.get_sprite().state == bp.get_sprite().States.SHOWN:
			bp.get_sprite().show_in()
		bp.get_sprite().play("victory", true)
		
	
	yield($Dialoguebox.play_win(), "completed") # Text box
	
	var conscious_party := _get_conscious(_party_BPs)
	var receiving_party := []
	for mem in conscious_party:
		if mem.character.get_level() < PartyMember.LEVEL_CAP:
			receiving_party.append(mem)
	
	var exp_per_ally := 0
	
	if receiving_party:
		exp_per_ally = int(round(_exp_pool / receiving_party.size()))
	
	if exp_per_ally > 0:
		var dialog: String = _get_exp_dialog(receiving_party, exp_per_ally)
		yield($Dialoguebox.start_from_string(dialog), "completed")
		
	for mem in conscious_party: # Characters at level cap might also learn new skills
		var in_progress = _give_exp(mem, exp_per_ally)
		if in_progress: yield(in_progress, "completed")
	
	var items_to_overworld := []
	var in_progress = _do_rewards(items_to_overworld)
	if in_progress: yield(in_progress, "completed")
	
	_give_cash()
	
	_end_battle_to_overworld(Result.WIN, items_to_overworld)

func _get_exp_dialog(receiving_party : Array, exp_per_ally: int) -> String:
	var dialog : String
	match receiving_party.size():
		2:
			dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_EXP_TWO_ALLIES", _context.set_actor(receiving_party[0]).set_targets([receiving_party[1]]).set_value(exp_per_ally))
		1:
			dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_EXP_ONE_ALLY", _context.set_actor(receiving_party[0]).set_value(exp_per_ally))
		_:
			dialog = $Dialoguebox.format_battle_text("BATTLE_MSG_EXP_MANY_ALLIES", _context.set_actor(receiving_party[0]).set_value(exp_per_ally))
	if _received_exp_from_flee == true:
		var to_append : String = tr("BATTLE_MSG_FLEE_EXP")
		dialog = to_append + " " + dialog
	return dialog

func _flee():
	_active = false
	_set_bp_end_battle()
	_activate_on_screen_enemies()
	for enemy in _enemy_BPs:
		if enemy: enemy.stun_overworld()
	_end_battle_to_overworld(Result.FLEE)

func _try_flee(action: Action): # suspend func
	_fleeing_attempts += 1
	if _advantage == Advantage.PLAYER:
		print("Fleeing thanks to player advantage")
		_flee()
	elif _fleeing_attempts >= FLEEING_MAX_ATTEMPTS:
		print("Fleeing after %s attempts" % FLEEING_MAX_ATTEMPTS)
		_flee()
	else:
		var chances_multiplier := 1.0
		
		var max_enemy_speed = 0
		for enemyBP in _get_conscious(_enemy_BPs, true):
			max_enemy_speed = max(max_enemy_speed, enemyBP.get_stat(Character.SPEED))
			chances_multiplier *= enemyBP.get_affinity_multiplier("flee")
		
		var party_speed = 0
		for partyBP in _get_conscious(_party_BPs, true):
			party_speed = max(party_speed, partyBP.get_stat(Character.SPEED))
			chances_multiplier *= partyBP.get_affinity_multiplier("flee")
		
		var chance = (FLEEING_CHANCES_BASE * chances_multiplier) + (party_speed - max_enemy_speed) + (_turns_count * FLEEING_CHANCES_INCREASE)
		print("Flee chance: %s" % chance)
		if _chance_roll(chance):
			_flee()
		else:
			yield($Dialoguebox.start_from_string(tr("BATTLE_MSG_FLEE_FAIL")), "completed")
			action.emit_signal("done")

func _do_rewards(items_to_overworld: Array): # suspend func
	var dropped_item: Item = _item_pool.item
	
	if _stolen_item and !_stolen_item_definitive:
		dropped_item = _stolen_item
		_item_pool.item = null
	
	_item_pool.add_rare_drops_for_all_enemies()
	
	if dropped_item:
		var item_data := dropped_item.get_data()
		$Dialoguebox.append(tr("BATTLE_MSG_PRESENT"))
		$Dialoguebox.append_formatted("BATTLE_MSG_PRESENT_INSIDE", _context.set_item_or_skill(item_data))
		# Who has room in their inventory?
		var all_inventories_full := true
		for party_mem in _party_BPs:
			if !party_mem.character.inv.is_full():
				if !party_mem.is_incapacitated():
					$Dialoguebox.append_formatted("BATTLE_MSG_PRESENT_TAKING", _context.set_actor(party_mem).set_item_or_skill(item_data), "EB/itemget1.wav")
				else:
					$Dialoguebox.append_formatted("BATTLE_MSG_PRESENT_GIVING", _context.set_actor(party_mem).set_item_or_skill(item_data), "EB/itemget1.wav")
				party_mem.character.inv.add_item(dropped_item)
				all_inventories_full = false
				break
		if all_inventories_full:
			$Dialoguebox.append_formatted("BATTLE_MSG_PRESENT_FULL", _context.set_item_or_skill(item_data))
			var overworld_item = DroppedItemNode.instance()
			overworld_item.name = "EnemyDrop"
			overworld_item.item = dropped_item.item_name
			overworld_item.reset_when_consumed = true
			items_to_overworld.append(overworld_item)
		yield($Dialoguebox.start_from_appended(), "completed")
	
	if _win_flag and globaldata.flags.has(_win_flag):
		globaldata.set_flag(_win_flag, true)

func _give_exp(target: BattleParticipant, amount: int): # suspend func
	var changed_stats := {}
	var learned_skills := []
	target.character.give_exp(amount, changed_stats, learned_skills)
	if changed_stats or learned_skills:
		_level_up_or_learn_skills(target, changed_stats, learned_skills)
		$Dialoguebox.start_from_appended()
		yield($Dialoguebox, "done")

func _give_cash():
	uiManager.give_cash_to_bank(_cash_pool)

func _level_up_or_learn_skills(bp: BattleParticipant, changed_stats: Dictionary, learned_skills: Array): # suspend func
	if changed_stats:
		if !audioManager.overworld_battle_music or _is_boss:
			audioManager.play_music(audioManager.CHANNELS.BATTLE, _musical_effects["lvlup"])
			var start_time = audioManager.get_music_player_by_name(audioManager.CHANNELS.BATTLE).get_playback_position()
			var party_mem_level_up_music = _musical_effects["lvlup_" + bp.character.get_name()]
			audioManager.play_music("Lvlup_" + bp.character.get_name(), party_mem_level_up_music, start_time)
		
		var level = bp.character.get_level()
		$Dialoguebox.append_formatted("BATTLE_MSG_LEVEL_UP", _context.set_actor(bp).set_value(level), "M3/Cheering.mp3")
		for stat in changed_stats:
			var gain = changed_stats[stat]
			bp.get_plate().refresh_battle_plate(true)
			$Dialoguebox.append_formatted("BATTLE_MSG_LEVEL_UP_STAT", _context.set_actor(bp).set_value(gain).set_stat(stat))
	# Check skill table
	for new_skill in learned_skills:
		$Dialoguebox.append_formatted("BATTLE_MSG_LEARNING", _context.set_actor(bp).set_item_or_skill(globaldata.get_battle_skill(new_skill)), "M3/Learned PSI.wav")

func _end_battle_to_overworld(battle_result := Result.FLEE, items_to_overworld := []): # suspend func
	$Dialoguebox/Dialoguebox.hide() # Sorry
	$ActionMenuBox.hide()
	if !audioManager.overworld_battle_music or _is_boss:
		_remove_battle_music() # Remove victory and level up tracks
		
		# Resume overworld music
		var overworld_music_player = audioManager.get_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
		if overworld_music_player and overworld_music_player.stream_paused:
			audioManager.fadein_music_player_by_name(audioManager.CHANNELS.OVERWORLD,overworld_music_player.volume_db, 3)
			audioManager.resume_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
	$AnimScene.play("transitionOut")
	_drop_item_to_overworld(items_to_overworld)
	
	emit_signal("battle_to_ov")
	
	yield($AnimScene, "animation_finished")
	
	# Release player or play cutscene
	emit_signal("battle_ended", battle_result)
	
	if _post_battle_cutscenes.has(battle_result):
		uiManager.open_dialogue_box_and_unpause(_post_battle_cutscenes[battle_result])
	else: global.get_player().unpause()

func _end_battle_to_game_over(): # suspend func
	_reset_page_stack()
	_lose_battle = true
	_active = false
	$ActionMenuBox.hide()
	_remove_battle_music()
	audioManager.stop_all_music_players()
	
	if !$Dialoguebox.did_finish(): yield($Dialoguebox, "done")
	else: yield(get_tree().create_timer(0.5), "timeout")
	_play_sfx("partylose")
	yield($Dialoguebox.start_from_string(tr("BATTLE_MSG_GAME_OVER")), "completed")
	yield(uiManager.game_over(false), "completed")
	
	for obj in _party_orig_objects: obj.show()
	_hide_battle_BG()
	_restore_backup_inventories()
	emit_signal("battle_ended", Result.LOSE)

func _set_bp_end_battle():
	for bp in _get_conscious(_party_BPs):
		if bp.get_target_hp() <= bp.get_current_hp():
			bp.get_plate().stop_scrolling() # Stop rolling hp
		else:
			bp.character.set_hp(bp.get_target_hp())
		# If party member is still conscious but HP reached zero when the battle ended
		if bp.get_target_hp() == 0 or bp.get_current_hp() == 0:
			bp.set_target_hp(1)
			bp.character.set_hp(1)
		
		bp.reset_all_stat_mods()
		# Heal all non persistent ailments
		var status_to_remove = bp.character.get_status_ailments().duplicate()
		for status in status_to_remove:
			if !status.get_data()["healing"].get("persistent", false):
				bp.set_status(status.ailment, false)
	#HEALING SPECIAL PARTY NPCs LIKE FLYING MAN
	for npc_bp in _npc_BPs:
		var status_to_remove = npc_bp.character.get_status_ailments().duplicate()
		for status in status_to_remove:
			if !status.get_data()["healing"].get("persistent", false):
				npc_bp.set_status(status.ailment, false)

func _revive_party():
	for mem in global.party:
		mem.remove_all_statuses()
		if mem == global.party[0]:
			mem.set_hp(mem.get_stat(Character.MAXHP))
			mem.set_pp(mem.get_stat(Character.MAXPP))
		else:
			mem.add_status(Status.AILMENT_UNCONSCIOUS)
			mem.set_pp(mem.get_stat(Character.MAXPP))

func _drop_item_to_overworld(queued_dropped_items: Array): # suspend func
	yield(get_tree().create_timer(0.8), "timeout")
	var player_pos = global.get_player().get_viewport().canvas_transform.xform(global.get_player().position)
	var tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	for dropped_item in queued_dropped_items:
		var sprite = Sprite.new()
		var path := str("res://Graphics/Objects/Items/" + dropped_item.item + ".png")
		sprite.texture = load(path)
		sprite.position = player_pos - Vector2(0, 180)
		$EnemyTransitions.add_child(sprite)
		tween.tween_property(sprite, "position:y", player_pos.y, 1.3)
		tween.chain().tween_property(sprite, "position:y", player_pos.y - 8, 0.2).from(player_pos.y).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(sprite, "position:y", player_pos.y, 0.2).from(player_pos.y - 8)
	yield(tween, "finished")
	for dropped_item in queued_dropped_items:
		dropped_item.position = global.get_player().position
		var objects_layer = global.get_player().get_parent()
		if objects_layer == null:
			global.currentScene.add_child(dropped_item)
		else:
			dropped_item.show()
			objects_layer.add_child(dropped_item)
		dropped_item.disappear()
	
	for sprite in $EnemyTransitions.get_children():
		sprite.queue_free()

func _jump_to_overworld(): # suspend func
	if _lose_battle and _post_battle_cutscenes.has(Result.LOSE):
		for i in _party_orig_objects.size():
			_party_orig_objects[i].show()
		_revive_party()
		return
	_party_orig_positions.clear()
	for party_mem in _party_orig_objects:
		if is_instance_valid(party_mem):
			_party_orig_positions.append(party_mem.get_viewport().canvas_transform.xform(party_mem.position) - Vector2(0,4))
	_jump_npcs_to_overworld()
	for i in range($PlayerTransitions.get_child_count()):
		var sprite = $PlayerTransitions.get_child(i)
		var party_info = _party_info.get_child(i)
		# Set sprite back in position
		sprite.show()
		sprite.position = party_info.rect_global_position
		sprite.position.x += party_info.rect_size.x/2
		sprite.scale = Vector2.ONE
		
		# Do the tween stuff
		var tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		tween.tween_property(sprite, "position:x", _party_orig_positions[i].x, 0.55).set_trans(Tween.TRANS_LINEAR)
		
		tween.tween_property(sprite, "position:y", _party_orig_positions[i].y - 24, 0.35).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position:y", _party_orig_positions[i].y + 4, 0.2) \
				.from(_party_orig_positions[i].y - 24).set_delay(0.4)
		
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.4).from(Vector2(0.6, 1.2))
		tween.tween_property(sprite, "scale", Vector2(0.8, 1.1), 0.2).from(Vector2.ONE).set_delay(0.4)
		
		tween.connect("finished", sprite, "hide", [])
		tween.connect("finished", _party_orig_objects[i], "show", [])
		tween.connect("finished", _party_orig_objects[i], "set_direction", [Vector2(0, -1)])
		tween.connect("finished", _party_orig_objects[i].sprite, "set", ["frame_coords", SPRITE_FRAMES.crouch_up])
		
		_party_orig_objects[i].set_idle()
		
		sprite.frame_coords = SPRITE_FRAMES.jump_up
		yield(get_tree().create_timer(.05), "timeout")

func _jump_npcs_to_overworld(): # suspend func
	for i in range($NpcTransitions.get_child_count()):
		var sprite = $NpcTransitions.get_child(i)
		# Set sprite back in position
		sprite.show()
		sprite.scale = Vector2.ONE
		
		var index_in_objects = i + global.party.size()
		var orig_object = _party_orig_objects[index_in_objects]
		
		if !is_instance_valid(orig_object): continue
		var orig_position = _party_orig_positions[index_in_objects]
		var orig_position_prev = _party_orig_positions[index_in_objects - 1]
		
		# Do the tween stuff
		var tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		tween.tween_property(sprite, "position:x", orig_position.x, 0.55).set_trans(Tween.TRANS_LINEAR)
		
		tween.tween_property(sprite, "position:y", orig_position_prev.y - 24, 0.35).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position:y", orig_position.y + 4, 0.2).from(orig_position_prev.y - 24).set_delay(0.4)
		
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.3).from(Vector2(0.6, 1.2))
		tween.tween_property(sprite, "scale", Vector2(0.8, 1.1), 0.1).from(Vector2.ONE).set_delay(0.5)
		
		tween.connect("finished", sprite, "hide", [])
		tween.connect("finished", orig_object, "show", [])
		tween.connect("finished", orig_object, "set_direction", [Vector2(0, -1)])
		tween.connect("finished", orig_object.sprite, "set", ["frame_coords", SPRITE_FRAMES.crouch_up])
		
		sprite.frame_coords = SPRITE_FRAMES.jump_up
		yield(get_tree().create_timer(.05), "timeout")

func _remove_battle_music():
	var win_themes_path := "res://Audio/Music/You Win/"
	for audio_player in audioManager.get_music_player_list():
		audio_player = audio_player as AudioStreamPlayer
		if audio_player.stream and win_themes_path in audio_player.stream.resource_path:
			audioManager.stop_music_player_by_name(audio_player.name)
	audioManager.stop_music_player_by_name(audioManager.CHANNELS.BATTLE)
	audioManager.stop_music_player_by_name(audioManager.CHANNELS.MENU)
	if _is_boss and audioManager.overworld_battle_music:
		audioManager.remove_all_music_changers()
		audioManager.stop_music_player_by_name(audioManager.CHANNELS.OVERWORLD)

func _turn_party_to_overworld():
	for bp in _party_BPs:
		bp.get_sprite().hide_away()

func _rotate_party_to_original_direction():
	for party_obj in _party_orig_objects:
		if is_instance_valid(party_obj):
			party_obj.rotate_to(_party_orig_dirs.pop_front(), .05)

func _hide_battle_BG():
	uiManager.remove_ui(_battle_bg)
	var cam_tween = global.currentCamera.tween
	if cam_tween and cam_tween.is_valid():
		cam_tween.play()
	global.currentCamera.reset()

func _restore_backup_inventories():
	for bp in _party_BPs:
		var inv = bp.character.inv
		if inv in _saved_inventories:
			inv.init_from_serialized(_saved_inventories[inv])


####################################################################
########################## VISUALS/SFX #############################
####################################################################

func _play_sfx(sfx_name: String, channel := 0):
	if _sound_effects.has(sfx_name):
		audioManager.play_sfx(_sound_effects[sfx_name], "BattleSfx" + str(channel))

func _do_pre_hit_effect(target:BattleParticipant, effect: String): # suspend func
	if !effect or !$PreHitEffect/AnimationPlayer.has_animation(effect):
		yield(get_tree(), "idle_frame")
		return
	
	var targetPos = target.get_position(true)
	
	_darken_bg()
	$PreHitEffect.play(effect)
	$PreHitEffect.rect_position = targetPos
	yield($PreHitEffect, "apply_damage")
	_undarken_bg()

func _do_hit_effect(hit_effect: String, hit_sound: String, target: BattleParticipant):
	if !hit_effect or !$HitEffect/AnimationPlayer.has_animation(hit_effect): return
	
	# This is the stupidist way to find our target's ui in the scene, but we living it up out here
	var targetPos = target.get_position(true)
	
	$HitEffect/AnimationPlayer.play(hit_effect)
	$HitEffect/AnimationPlayer.advance(0)
	$HitEffect.rect_position = targetPos

# This is for shields and counters
func _do_shield_hit_effect(shield: Dictionary, hit_sound: String, target: BattleParticipant):
	#alter hit effect depending on the hp of the shield
	var shield_type : String = shield.keys()[0]
	var shield_hp : int = shield.values()[0]
	var hit_effect : String
	# Picks the correct animation to play based off of shield HP
	if shield_hp > 3: 
		hit_effect = shield_type + "_DAMAGED"
	elif shield_hp > 1:
		hit_effect = shield_type + "_BADLYDAMAGED"
	elif shield_hp == 1:
		hit_effect = shield_type + "_SHATTER"
	if !hit_effect or !$ShieldHitEffect/AnimationPlayer.has_animation(hit_effect): return
	
	var targetPos = target.get_position(true)
	$ShieldHitEffect/AnimationPlayer.play(hit_effect)
	$ShieldHitEffect/AnimationPlayer.advance(0)
	$ShieldHitEffect.rect_position = targetPos
	yield($ShieldHitEffect/AnimationPlayer, "animation_finished")

# Mainly used for stat buffs/debuffs
func _do_hit_effect_by_anim(anim: String, target: BattleParticipant):
	if !$HitEffect/AnimationPlayer.has_animation(anim): return
	
	var targetPos = target.get_position()
	
	$HitEffect/AnimationPlayer.play(anim)
	$HitEffect/AnimationPlayer.advance(0)
	$HitEffect.rect_position = targetPos

func _darken_bg():
	_bg_darkinator.darken_bg()

func _undarken_bg():
	_bg_darkinator.undarken_bg()

func _create_rising_num(text: String, who: BattleParticipant, color := Color.white, flying_num := false):
	var rising_num: Label = FlyingNumTscn.instance() if flying_num else RisingNumTscn.instance()
	rising_num.text = text
	add_child(rising_num)
	var target_pos = who.get_position(true, true)
	target_pos -= rising_num.rect_size/2
	rising_num.rect_position = target_pos
	rising_num.add_color_override("font_color", color)
	rising_num.run()

func _create_smash_attack(target: BattleParticipant) -> Sprite:
	_bg_darkinator.get_node("AnimationPlayer").play("smash")
	var smash_attack = SmashAttackTscn.instance()
	var target_pos = target.get_position(true, true)
	target_pos.y -= 32
	smash_attack.position = target_pos
	return smash_attack

func tilt_bars(position: Vector2):
	if _tween: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT).set_parallel(true)
	
	var top_center = Vector2(160, -1200)
	var top_rad_angle = top_center.direction_to(position).rotated(-PI/2).angle()
	_tween.tween_property($top, "rect_rotation", (top_rad_angle / PI) * 180, 0.2)
	
	var bottom_center = Vector2(160, 1500)
	var bottom_rad_angle = bottom_center.direction_to(position).rotated(PI/2).angle()
	_tween.tween_property($bottom, "rect_rotation", (bottom_rad_angle / PI) * 180, 0.2)

func _jump_to_battle(): # suspend func
	yield(get_tree().create_timer(.2), "timeout")
	for i in range($PlayerTransitions.get_child_count()):
		yield(get_tree().create_timer(.1), "timeout")
		_jump_player_to_partyinfo(i)
	yield(get_tree().create_timer(.2), "timeout")
	for i in range($NpcTransitions.get_child_count()):
		yield(get_tree().create_timer(.1), "timeout")
		_jump_npc_to_side(i)

func _jump_player_to_partyinfo(index: int):
	var sprite = $PlayerTransitions.get_child(index)
	var party_info = _party_info.get_child(index)
	var tween = create_tween().set_parallel()
	var jump_height = 0
	if sprite.position.y >= 90:
		jump_height = sprite.position.y - 90
	tween.tween_property(sprite, "position:x", party_info.rect_position.x + party_info.rect_size.x/2, 0.6) \
			.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	
	tween.tween_property(sprite, "position:y", sprite.position.y - (16 + jump_height), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position:y", 180, 0.3).from(sprite.position.y - (16 + jump_height)).set_delay(0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.tween_property(sprite, "scale:x", 0.3, 0.3).set_delay(0.3) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	
	if _advantage != Advantage.ENEMY:
		tween.tween_property(sprite, "scale:y", 2, 0.3).set_delay(0.3) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		sprite.frame_coords = SPRITE_FRAMES.jump_down
	
	tween.connect("finished", party_info, "quake", [0, .5])
	tween.connect("finished", sprite, "hide", [], CONNECT_DEFERRED)

func _jump_npc_to_side(index: int):
	var sprite = $NpcTransitions.get_child(index)
	var tween = create_tween().set_parallel()
	var jumpHeight = 0
	if sprite.position.y >= 90:
		jumpHeight = sprite.position.y - 90
	tween.tween_property(sprite, "position:x", 370, 0.6) \
			.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	
	tween.tween_property(sprite, "position:y", sprite.position.y - (42 + jumpHeight), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position:y", 90, 0.3).from(sprite.position.y - (42 + jumpHeight)).set_delay(0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.tween_property(sprite, "scale:x", sprite.scale.x, 0.2).from(0.8) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	
	tween.tween_property(sprite, "scale:y", sprite.scale.y, 0.2).from(1.2) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

func _enemy_to_position(): # suspend func
	_enemies_shaking = true
	for i in range($EnemyTransitions.get_child_count()):
		var sprite = $EnemyTransitions.get_child(i)
		var fullSprite = $Enemies.get_child(i)
		var tween = create_tween().set_parallel()
		tween.tween_property(sprite, "position", fullSprite.rect_position + fullSprite.rect_size/2, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "modulate", Color.black, 0.6)
		yield(get_tree().create_timer(0.2/$EnemyTransitions.get_child_count()), "timeout")

func _set_action_prep_anim(action: Action):
	if action is ItemAction:
		action.user.get_sprite().play("itemPrep")
	elif action is SkillAction:
		match action.skill.get("skill_type", ""):
			"psi":
				var colors = action.skill.get("user_anim_colors", [Color("ffffff"), Color("f81070"), Color("5757f0")]) # Default colors if not specified
				action.user.get_sprite().set_psi_colors(colors)
				action.user.get_sprite().play("psiPrep")
			_:
				if action.skill.get("user_anim", ""):
					action.user.get_sprite().play(action.skill.user_anim + "Prep")

func _add_players_and_npc_transitions(): # suspend func
	for party_mem in _party_orig_objects:
		party_mem.hide()
		var sprite = party_mem.duplicate_sprite()
		
		sprite.show()
		sprite.position = party_mem.get_viewport().canvas_transform.xform(party_mem.position) - Vector2(0,4)
		if party_mem.get_party_member().get_name() in global.POSSIBLE_PLAYABLE_MEMBERS:
			sprite.frame_coords = SPRITE_FRAMES["scared" if _advantage == Advantage.ENEMY else "crouch_down"]
			$PlayerTransitions.add_child(sprite)
		else:
			sprite.frame_coords = SPRITE_FRAMES.crouch_right
			$NpcTransitions.add_child(sprite)
		
		_party_orig_positions.append(sprite.position)
		var tween := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "scale", Vector2(1.1, 0.9), 0.1)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.1).from(Vector2(1.1, 0.9))
		
		if global.party.size() == 1 and abs(sprite.position.x - 160) < 4 and _advantage != Advantage.ENEMY:
			var dir = 1
			if (randi()%2+0) == 1: dir *= -1
			create_tween().tween_property(sprite, "position:x", sprite.position.x + 16 * dir, 0.2) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		yield(get_tree().create_timer(.01), "timeout")

func _show_enemy_sprites(): # suspend func
	for enemy in $Enemies.get_children():
		enemy.show()
		enemy.appear()
		yield(get_tree().create_timer(.1), "timeout")
	_enemies_shaking = false

func _remove_enemy_transitions(): # suspend func
	for enemy in $Enemies.get_children():
		$EnemyTransitions.get_child(0).queue_free()
		yield(get_tree().create_timer(.1), "timeout")

func _play_battle_sprite_anim(user: BattleParticipant, anim: String) -> bool:
	if user.is_type(Character.Type.PARTY_MEMBER):
		return user.get_sprite().play(anim, true)
	return false

func _start_joy_vibration(device: int = 0, weak_magnitude := 0.0, strong_magnitude := 0.0, duration: int = 0.2):
	global.start_joy_vibration(device, weak_magnitude, strong_magnitude, duration)

func _hide_enemies():
	$Enemies.hide()

####################################################################
########################### GETTERS/MISC. ##########################
####################################################################

func _get_conscious(bps: Array, only_who_can_attack := false) -> Array:
	var arr := []
	for bp in bps:
		if !bp.is_unconscious():
			if !only_who_can_attack or bp.can_act():
				arr.append(bp)
	return arr

func _get_targetables_for_action(bps: Array, action: Action) -> Array:
	var arr := []
	for bp in bps:
		if bp.is_targetable_for_action(action):
			arr.append(bp)
	return arr

func _chance_roll(percentage: float, multiplier := 1.0) -> bool:
	if percentage <= 0 or multiplier <= 0: return false
	
	var prob_frac := percentage / 100.0
	var prob_eff = 1.0 - pow(1.0 - prob_frac, multiplier)
	prob_eff *= 100
	
	print("Rolling with a chance of %s!" % prob_eff)
	
	var r := randi() % 100 + 1
	
	print("Rolled a %s! %s" % [r, "Success!" if r <= prob_eff else "Failure..."])
	
	return r <= prob_eff

func _compare_action_types(action: Action, desired_type: Dictionary) -> bool:
	var action_type = {"dict": desired_type.get("action_type", "any"), "compare": "action_type"}
	var skill_type = {"dict": desired_type.get("skill_type", "any"), "compare": "skill_type"}
	var damage_type = {"dict": desired_type.get("damage_type", "any"), "compare": "damage_type"}
	
	for typeDict in [action_type, skill_type, damage_type]:
		if !typeDict.dict is Array: typeDict.dict = [typeDict.dict]
		var is_type = false
		if "any" in typeDict.dict:
			is_type = true
		else:
			for type in typeDict.dict:
				if "skill" in action and action.skill.has(typeDict.compare):
					if type == action.skill.get(typeDict.compare):
						is_type = true
		if !is_type: return false
	return true

func _sort_party_objects(obj1: PartyObject, obj2: PartyObject) -> bool:
	var idx1 = PARTY_MEMBERS_ORDER.find(obj1.get_party_member().get_name())
	var idx2 = PARTY_MEMBERS_ORDER.find(obj2.get_party_member().get_name())
	return idx1 < idx2

func _sort_by_priority(a: Action, b: Action) -> bool:
	if a.priority > b.priority: return true
	# When in the same priority, speed matters
	elif a.priority == b.priority: return _sort_by_speed(a, b)
	else: return false

func _sort_by_speed(a: Action, b: Action) -> bool:
	if a.user.get_stat(Character.SPEED) > b.user.get_stat(Character.SPEED):
		return true
	# We dont randomize if both speeds are the same, godot doesn't like that
	else: return false

func _sort_by_low_hp(bp1: BattleParticipant, bp2: BattleParticipant):
	return bp1.get_target_hp() < bp2.get_target_hp()

func _get_miss_chance(action: Action) -> bool:
	var base_skill_miss_chance = action.skill.get("miss_chance", 0)
	if action.skill.action_type == ActionType.DAMAGE:
		var ailment_chance = action.user.get_combined_status_effect("miss_chance")
		return _chance_roll(ailment_chance + base_skill_miss_chance)
	return _chance_roll(base_skill_miss_chance)

func _get_bp_with_passive_skill(p_skill_id: String) -> BattleParticipant:
	for bp in _get_conscious(_party_BPs + _enemy_BPs):
		if bp.has_passive_skill(p_skill_id):
			return bp
	return null

func _was_action_done(action: Action) -> bool:
	return _current_action_index > _action_queue.find(action)

func _are_bps_in_opposite_sides(bp1: BattleParticipant, bp2: BattleParticipant) -> bool:
	return !bp2.is_type(Character.Type.ENEMY) if bp1.is_type(Character.Type.ENEMY) else bp2.is_type(Character.Type.ENEMY)
