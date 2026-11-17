extends Node
class_name BattleParticipant

signal defeated
signal start_boss_defeat_flash(sprite_center)
signal bp_hit
signal action_choice
signal before_action(action)
signal acted(action)
signal stat_mod_added(stat, value)

const BattleScript = preload("res://Scripts/UI/Battle/BattleScript.gd")
const PartyInfoTscn = preload("res://Nodes/Ui/Battle/PartyInfoPlate.tscn")
const StatusBubbleTscn = preload("res://Nodes/Ui/Battle/StatusBubble.tscn")
const EnemySprite := preload("res://Nodes/Ui/Battle/EnemySprite.tscn")
const RatKingSprite := preload("res://Nodes/Ui/Battle/RatKingSprite.tscn")

const PARTY_BATTLE_SPRITES := {
	PartyMember.NINTEN: preload("res://Nodes/Ui/Battle/BattleSpriteNinten.tscn"),
	PartyMember.LLOYD: preload("res://Nodes/Ui/Battle/BattleSpriteLloyd.tscn"),
	PartyMember.ANA: preload("res://Nodes/Ui/Battle/BattleSpriteAna.tscn"),
	PartyMember.PIPPI: preload("res://Nodes/Ui/Battle/BattleSpritePippi.tscn"),
	PartyMember.TEDDY: preload("res://Nodes/Ui/Battle/BattleSpriteTeddy.tscn"),
	PartyNPC.CANARY_CHICK: null,
	PartyNPC.FLYING_MAN: preload("res://Nodes/Ui/Battle/BattleSpriteFlyingMan.tscn"),
	PartyNPC.EVE: preload("res://Nodes/Ui/Battle/BattleSpriteEVE.tscn")
}

var PartyBattleSpriteDefault = preload("res://Nodes/Ui/Battle/BattleSpriteDefault.tscn")

const MODDABLE_STATS := [Character.OFFENSE, Character.DEFENSE, Character.SPEED, Character.IQ, Character.GUTS]

var character: Character setget ,_get_character

var defending := false setget _set_defending
var immortal := false

var cur_dialog := {}
var cur_scripted_skill := ""

var _battle_sprite: Control
# only for players
var _party_info: Control = null

var _battle_script = null

var _bp_name: String
var _bp_name_letter := -1
var _sprite_name: String
var _stat_mods := {}

var _hp_stopped_scrolling_cb: FuncRef

var _overworld_obj: Node

var _battle_passive_skills := {} # keys = names, values = health points
var _battle_skills := [] # Array of EnemySkill


func _init(battle_obj, t_character: Character, homonymes_count := 0):
	character = t_character
	if character.get_nickname():
		_bp_name = TextTools.replace_text(character.get_nickname())
	else:
		_bp_name = tr(character.get_name())
	if homonymes_count > 0:
		_bp_name_letter = homonymes_count
	reset_skills()
	battle_obj.connect("round_done", self, "_on_new_turn")
	
	if is_type(Character.Type.ENEMY) and character.get_data().has("battlescript"):
		_battle_script = BattleScript.new(self, character.get_data().battlescript, battle_obj)


func add_info_plate(container: Node, placement: int, hp_stopped_scrolling_cb: FuncRef):
	if get_type() != Character.Type.PARTY_MEMBER:
		push_warning("Can’t add info plate to a non-party member")
		return
	var plate = PartyInfoTscn.instance()
	container.add_child(plate)
	plate.set_character(character)
	plate.hide_max_num()
	plate.connect("hp_scroll_done", self, "hp_stopped_scrolling")
	plate.connect("pp_scroll_done", self, "pp_stopped_scrolling")
	_party_info = plate
	plate.rect_position = Vector2(placement, 20)
	_hp_stopped_scrolling_cb = hp_stopped_scrolling_cb
	
	_battle_sprite = PARTY_BATTLE_SPRITES.get(character.get_name(), PartyBattleSpriteDefault).instance()
	
	
	plate.add_child(_battle_sprite)
	plate.move_child(_battle_sprite, 0)
	
	_battle_sprite.add_status_bubble(StatusBubbleTscn.instance())
	refresh_status_info()


func add_battle_sprite(container: Node, ov_sprite: Sprite = null, inherit_sprite = null):
	if is_type(Character.Type.PARTY_MEMBER):
		push_warning("Can’t add battle sprite to a party member")
		return
	elif is_type(Character.Type.PARTY_NPC):
		var battle_sprite_scene = PARTY_BATTLE_SPRITES.get(character.get_name())
		if battle_sprite_scene:
			_battle_sprite = battle_sprite_scene.instance()
			_battle_sprite.init_from_ov_sprite(ov_sprite)
			container.add_child(_battle_sprite)
		return
	
	_sprite_name = character.get_sprite()
	var sprite_path_pattern := "res://Graphics/Battle Sprites/%s.png"
	var sprite_path : String = sprite_path_pattern % _sprite_name
	var texture = EnemySprite.instance()
	if inherit_sprite != null:
		var global_pos = inherit_sprite.get_global_position()
		if inherit_sprite.get_parent() != null:
			inherit_sprite.get_parent().remove_child(inherit_sprite)
		texture = inherit_sprite
		texture.set_global_position(global_pos)
	if character.get_id() == "ratking":
		texture = RatKingSprite.instance()
	_battle_sprite = texture
	container.add_child(_battle_sprite)
	if ResourceLoader.exists(sprite_path):
		_battle_sprite.set_texture(sprite_path)
	else:
		print("could not load sprite: ", sprite_path)
		_battle_sprite.set_texture(sprite_path_pattern % "invalidsprite")
	
	# put texture off screen
	if inherit_sprite == null:
		_battle_sprite.rect_position = Vector2(320, 0) + _battle_sprite.texture.get_size()
		_battle_sprite.hide()
	
	_battle_sprite.add_status_bubble(StatusBubbleTscn.instance())
	
	if OS.is_debug_build():
		_battle_sprite.add_debug_stat_info(self)

func get_name() -> String:
	if _bp_name_letter == -1:
		return _bp_name
	var actual_letter := tr("BATTLE_LETTER_ALPHABET")[_bp_name_letter % tr("BATTLE_LETTER_ALPHABET").length()]
	return tr("BATTLE_LETTER_SPACING").format([_bp_name, actual_letter])

func get_id() -> String:
	return character.get_id()

func rename_as_first_homonym():
	_bp_name_letter = 0

func _set_defending(value: bool):
	defending = value
	if is_type(Character.Type.PARTY_MEMBER):
		_party_info.user_defending = value

func _get_character() -> Character:
	return character

func reassign_sprite(new_sprite: Control, container: Node):
	_battle_sprite = new_sprite
	var global_pos = _battle_sprite.get_global_position()
	if _battle_sprite.get_parent() != null:
		_battle_sprite.get_parent().remove_child(_battle_sprite)
	container.add_child(_battle_sprite)
	_battle_sprite.set_global_position(global_pos)

func get_sprite() -> Control:
	return _battle_sprite

func get_speech_bubble() -> Control:
	return _battle_sprite.get_speech_bubble() if is_type(Character.Type.ENEMY) else null

func speech_from_string(text: String, auto_advance := false):
	yield(get_speech_bubble().start_from_string(text, auto_advance), "completed")

func speech_from_dialog(text_dict: Dictionary, auto_advance := false):
	yield(get_speech_bubble().start_from_scripted_dialog(text_dict, auto_advance), "completed")

func set_speech_bubble_pos(dir: Vector2):
	_battle_sprite.set_speech_bubble_pos(dir)

func get_type() -> int:
	return character.get_character_type()

func is_type(type: int) -> bool:
	return get_type() == type

func get_plate() -> Control:
	return _party_info

func can_act() -> bool:
	return !is_incapacitated() and !get_combined_status_effect("turn_skip").get("enable", false)

func get_passive_skills() -> Array:
	var ret := character.get_passive_skills()
	if !_battle_passive_skills.empty():
		ret += _battle_passive_skills.keys()
	ret.sort_custom(self, "_sort_passive_skills")
	return ret

func has_passive_skill(p_skill_id) -> bool:
	return character.get_passive_skills().has(p_skill_id) or \
			_battle_passive_skills.has(p_skill_id)

func _sort_passive_skills(skill_id_1: String, skill_id_2: String) -> bool:
	var skill_1 := globaldata.get_passive_skill(skill_id_1)
	var skill_2 := globaldata.get_passive_skill(skill_id_2)
	return skill_1.get("priority", 0) > skill_2.get("priority", 0)

func add_passive_skill(p_skill_id: String):
	var p_skill_data := globaldata.get_passive_skill(p_skill_id)
	# if it’s a shield, replace the potential current shield
	if p_skill_data.get("is_shield", false):
		var cur_shield_id := _get_cur_shield_id()
		if cur_shield_id != "":
			_battle_passive_skills.erase(cur_shield_id)
	_battle_passive_skills[p_skill_id] = p_skill_data.get("health", -1)

func try_remove_passive_skill(p_skill_id: String) -> bool:
	return _battle_passive_skills.erase(p_skill_id)

func try_remove_shield() -> bool:
	return try_remove_passive_skill(_get_cur_shield_id())

func try_hit_passive_skill(p_skill_id: String) -> bool:
	if !_battle_passive_skills.has(p_skill_id):
		return false
	_battle_passive_skills[p_skill_id] -= 1
	if _battle_passive_skills[p_skill_id] == 0:
		_battle_passive_skills.erase(p_skill_id)
	return true

func _get_cur_shield_id() -> String:
	for p_skill_id in _battle_passive_skills:
		if globaldata.get_passive_skill(p_skill_id).get("is_shield", false):
			return p_skill_id
	return ""

func has_shield() -> bool:
	return !!_get_cur_shield_id()

func get_affinity_multiplier(element: String) -> float:
	var multipliers := character.get_affinity_multipliers()
	return multipliers.get(element, 1)

func get_passive_skill_for_attack(attack: Dictionary) -> Dictionary:
	for key in get_passive_skills():
		var passive_skill := globaldata.get_passive_skill(key)
		var are_conditions_met := true
		for cond_key in passive_skill.conditions:
			var cond_values: Array = passive_skill.conditions[cond_key]
			match cond_key:
				"skill":
					are_conditions_met = are_conditions_met and attack.id in cond_values
				"skill_type":
					are_conditions_met = are_conditions_met and attack.skill_type in cond_values
				"damage_type":
					are_conditions_met = are_conditions_met and attack.get("damage_type", "") in cond_values
		if are_conditions_met:
			return passive_skill
	return {}
	
func handle_battler_script():
	if _battle_script: _battle_script.emit_signal("check_script")

func is_scripted_battle() -> bool: # Unused
	return !!_battle_script

func is_boss() -> bool:
	return character.is_boss() if is_type(Character.Type.ENEMY) else false

func select(dark := false):
	match(get_type()):
		Character.Type.ENEMY:
			_battle_sprite.select(dark)
		Character.Type.PARTY_MEMBER:
			_party_info.select(dark)

func deselect():
	match(get_type()):
		Character.Type.ENEMY:
			_battle_sprite.deselect()
		Character.Type.PARTY_MEMBER:
			_party_info.deselect()

func is_incapacitated() -> bool:
	return character.is_incapacitated()

func is_unconscious() -> bool:
	return character.is_unconscious()

func is_targetable() -> bool: # All characters except a few NPCs (nothing to do with status)
	return character.is_targetable()

func is_targetable_for_action(action) -> bool:
	return character.is_targetable() and (action.target_unconscious or !is_unconscious()) and \
		(action.target_incapacitated or !is_incapacitated())

func get_position(of_plate := false, of_plate_top := false) -> Vector2:
	match(get_type()):
		Character.Type.PARTY_MEMBER:
			if of_plate_top:
				return _party_info.rect_global_position + Vector2(_party_info.rect_size.x/2, 0)
			elif of_plate:
				return _party_info.rect_global_position + _party_info.rect_size/2
			else:
				return _battle_sprite.rect_global_position + _battle_sprite.rect_size/2
		Character.Type.ENEMY:
			return _battle_sprite.rect_global_position + _battle_sprite.rect_size/2
		Character.Type.PARTY_NPC:
			return _battle_sprite.get_position()
		_:
			return Vector2.ZERO

func get_size() -> Vector2:
	return _battle_sprite.rect_size

func defeat(silent := false):
	character.add_status(Status.AILMENT_UNCONSCIOUS)
	match(get_type()):
		Character.Type.PARTY_MEMBER:
			_party_info.set_instant_hp(0)
		Character.Type.ENEMY:
			_battle_sprite.status_bubble.hide()
			
			_battle_sprite.defeat(is_boss(), silent)
			
			_kill_overworld()
		Character.Type.PARTY_NPC:
			if character.get_name() == PartyNPC.FLYING_MAN:
				global.partyNpcs.erase(character)
				globaldata.flags["flying_man_in_party"] = false
				global.create_party_followers()
				global.emit_signal("party_changed")
			elif character.get_name() == PartyNPC.EVE:
				pass # TODO in 10 years i guess
	refresh_status_info()
	emit_signal("defeated", self, silent)
	if is_boss() and !silent:
		audioManager.pause_all_music_players()
		yield(_battle_sprite, "start_boss_defeat_flash")
		emit_signal("start_boss_defeat_flash", get_battle_sprite_center())

func enemy_flee():
	if !is_type(Character.Type.ENEMY):
		push_warning("You can’t make one party member flee!")
		return

	character.add_status(Status.AILMENT_UNCONSCIOUS)
	_battle_sprite.status_bubble.hide()
	_battle_sprite.flee()
	_kill_overworld()
	emit_signal("defeated", self, false)

func set_overworld_obj(node: Node):
	_overworld_obj = node

func stun_overworld():
	if _overworld_obj == null:
		return
	_overworld_obj.stun()
	_overworld_obj.get_node("interact/CollisionShape2D").set_deferred("disabled", false)
	_overworld_obj.flash(3, 0.2, 0, true)

func _kill_overworld():
	if _overworld_obj == null or _overworld_obj.get("keepAfterBattle"):
		return
	
	if _overworld_obj.has_method("remove_battle"):
		_overworld_obj.remove_battle()
	_overworld_obj.die()

func has_status(status: String, type = null) -> bool:
	return character.has_status(status)

func get_status(status: String, type = null) -> Status:
	return character.get_status(status)

func get_combined_status_effect(effect_name: String):
	return character.get_combined_status_effect(effect_name)

func get_all_status_effects() -> Array:
	return character.get_status_effects()

# Returns the type of actions (basic, skills, PSI, etc.) a party member can perform
# despite their possible current status ailments
func get_selectable_action_types() -> Array:
	if !is_type(Character.Type.PARTY_MEMBER):
		return []
	var party_mem := character as PartyMember
	var actions := ["basic", "defend"]
	var unusable_actions = get_combined_status_effect("cant_select").keys()
	if party_mem.get_usable_skills("skills"):
		actions.append("skills")
	if party_mem.get_usable_skills("psi"):
		actions.append("psi")
	if get_usable_items():
		actions.append("items")
	for i in actions:
		if i in unusable_actions:
			actions.erase(i)
	return actions

func reset_skills(reset_cooldown := false):
	if !is_type(Character.Type.PARTY_MEMBER):
		_battle_skills.clear()
		_battle_skills += character.get_skills()
		if reset_cooldown:
			for skill in _battle_skills:
				skill.remaining_cooldown = 0

func add_skill(skill_id: String, weight: int = 1, cooldown: int = 0):
	if !is_type(Character.Type.PARTY_MEMBER) and !skill_id in _battle_skills:
		var skill_entry := {"skill": skill_id, "weight": weight, "cooldown": cooldown}
		_battle_skills.append(EnemySkill.new(skill_entry))

func remove_skill(skill_id: String):
	if is_type(Character.Type.PARTY_MEMBER):
		return
	for entry in _battle_skills:
		if entry.skill_id == skill_id:
			_battle_skills.erase(entry)
			return

func change_skill_weight(skill_id: String, new_weight: int):
	if is_type(Character.Type.PARTY_MEMBER):
		return
	for entry in _battle_skills:
		if entry.skill_id == skill_id:
			entry.weight = new_weight
			return

func set_skill_cooldown(skill_id: String, new_cooldown: int):
	if is_type(Character.Type.PARTY_MEMBER):
		return
	for entry in _battle_skills:
		if entry.skill_id == skill_id:
			entry.cooldown = new_cooldown
			return

func start_cooldown(skill_id: String, turns := 0):
	if is_type(Character.Type.PARTY_MEMBER):
		return
	for entry in _battle_skills:
		if entry.skill_id == skill_id:
			var cooldown_turns = entry.cooldown if turns == 0 else turns
			entry.remaining_cooldown = cooldown_turns
			return

func get_usable_skills() -> Array: # This method is only for non-Party members!!
	var usable_skills := []
	for skill in _battle_skills:
		if skill.can_be_used():
			usable_skills.append(skill)
	return usable_skills

func get_usable_items() -> Array:
	var usable_items := []
	for item in character.inv.get_items():
		if item.is_battle_usable():
			usable_items.append(item)
	return usable_items

func _reafflict_status(status_name: String):
	var status := get_status(status_name)
	if status != null:
		status.battle_turns = 0
		status.times_afflicted += 1

func set_status(status_name: String, value: bool):
	if value:
		if has_status(status_name):
			_reafflict_status(status_name)
		else:
			character.add_status(status_name)
	else:
		character.remove_status(status_name)
	refresh_status_info()

func refresh_status_info():
	if !is_type(Character.Type.PARTY_NPC):
		for ailment in globaldata.get_all_ailments():
			var ailment_info = globaldata.get_ailment_data(ailment)
			var value = has_status(ailment)
			if value:
				_battle_sprite.status_bubble.add_status(ailment)
			else:
				_battle_sprite.status_bubble.remove_status(ailment)
	
	if _party_info:
		_party_info.refresh_ailments()
	
	if is_type(Character.Type.PARTY_MEMBER):
		_party_info.modulate = Color.white.darkened(0.4 if is_incapacitated() else 0.0)
		if is_incapacitated(): 
			_battle_sprite.die()
			if _battle_sprite.state == _battle_sprite.States.SHOWN:
				_battle_sprite.hide_away()
		else:
			_battle_sprite.revive()
		
	_refresh_sprite()

func _refresh_sprite():
	if !_sprite_name:
		_sprite_name = character.get_sprite()
	var is_enemy := is_type(Character.Type.ENEMY)
	var path := "res://Graphics/Battle Sprites/" if is_enemy \
			else "res://Graphics/Character Sprites/" + _sprite_name + "/"
	var status = get_combined_status_effect("change_sprite")
	var paralyzed = get_combined_status_effect("paralyzed_sprite")
	var final_path: String
	if status != "":
		final_path = path + status
	else:
		final_path = path + _sprite_name if is_enemy else path + "battle"
	if is_type(Character.Type.PARTY_MEMBER):
		_battle_sprite.sprite.texture = load(final_path + ".png")
		_battle_sprite.set_paralyzed(paralyzed)
	elif is_type(Character.Type.ENEMY):
		_battle_sprite.set_texture(final_path + ".png")

func change_sprite(new_sprite: String, refresh := true):
	_sprite_name = new_sprite
	if refresh: _refresh_sprite()

func change_character_data(new_character: String):
	if is_type(Character.Type.ENEMY):
		character.update_data(new_character)

func get_base_stat(stat: String, with_boosts: bool) -> int:
	return character.get_base_stat(stat, with_boosts)

func get_stat(stat: String) -> int:
	var base_stat = character.get_stat(stat)
	var final_stat = base_stat
	if stat in MODDABLE_STATS:
		final_stat = base_stat + max(3, floor(base_stat / 8)) * _stat_mods.get(stat, 0)
	return final_stat

func get_target_hp() -> int:
	return _party_info.get_target_hp() if is_type(Character.Type.PARTY_MEMBER) else character.get_hp()

func get_current_hp() -> int:
	return _party_info.get_current_hp() if is_type(Character.Type.PARTY_MEMBER) else get_target_hp()

func get_target_pp() -> int:
	return _party_info.get_target_pp() if is_type(Character.Type.PARTY_MEMBER) else character.get_pp()

func set_target_hp(new_value: int):
	if is_type(Character.Type.PARTY_MEMBER):
		_party_info.set_target_hp(new_value)
	else:
		character.set_hp(new_value)

func change_hp_by(delta: int) -> int:
	var old_value := get_target_hp()
	set_target_hp(old_value + delta)
	return old_value - get_target_hp()

func set_target_pp(new_value: int):
	if is_type(Character.Type.PARTY_MEMBER):
		_party_info.set_target_pp(new_value)
		character.set_pp(new_value)
	else:
		character.set_pp(new_value)

func change_pp_by(delta: int) -> int:
	var old_value := get_target_pp()
	set_target_pp(old_value + delta)
	return old_value - get_target_pp()

func add_stat_mod(stat: String, mod: int):
	if stat in MODDABLE_STATS:
		_stat_mods[stat] = _stat_mods.get(stat, 0) + mod
		emit_signal("stat_mod_added", stat, _stat_mods.get(stat, 0))

func get_stat_mod(stat) -> int:
	return _stat_mods.get(stat, 0)

func reset_stat_mod(stat: String):
	_stat_mods.erase(stat)

func reset_all_stat_mods():
	_stat_mods = {}

func hp_stopped_scrolling():
	character.set_hp(_party_info.get_target_hp())
	if _hp_stopped_scrolling_cb:
		_hp_stopped_scrolling_cb.call_func(self)

func pp_stopped_scrolling():
	character.set_pp(_party_info.get_target_pp())

func set_scripted_skill(skill_name: String):
	cur_scripted_skill = skill_name

func do_skill(skill_name: String, overwrite_skill:= true):
	_battle_script.emit_signal("do_skill", self, skill_name, overwrite_skill)

func wait_before_action():
	yield(self, "before_action")

func wait_action():
	yield(self, "acted")

func wait_actions(times: int):
	for i in range(times):
		yield(wait_action(), "completed")

func set_scripted_text(text_path: String):
	cur_dialog = YAMLParser.parse_file("res://Data/BattleScripts/%s.yaml" % text_path)

func get_enemy_battle_sprite() -> EnemyBattleSprite:
	if _battle_sprite is EnemyBattleSprite:
		return _battle_sprite as EnemyBattleSprite
	return null

func get_battle_sprite_position() -> Vector2:
	return _battle_sprite.rect_global_position

func get_battle_sprite_size() -> Vector2:
	return _battle_sprite.rect_size

func get_battle_sprite_center() -> Vector2:
	return get_battle_sprite_position() + get_battle_sprite_size()/2

func get_party_info_position() -> Vector2:
	return get_plate().rect_global_position

func get_party_info_size() -> Vector2:
	return get_plate().rect_size

func get_party_info_center() -> Vector2:
	return get_party_info_position() + get_party_info_size()/2

func get_target_position() -> Vector2:
	return get_party_info_position() if is_type(Character.Type.PARTY_MEMBER) else get_battle_sprite_position()

func get_target_center() -> Vector2:
	return get_party_info_center() if is_type(Character.Type.PARTY_MEMBER) else get_battle_sprite_center()

func get_battle_sprite_shown_position() -> Vector2:
	return _battle_sprite.get_shown_global_position() if _battle_sprite.has_method("get_shown_global_position") else get_battle_sprite_position()

func _on_new_turn(turn_count: int):
	for p_skill_id in _battle_passive_skills:
		if globaldata.get_passive_skill(p_skill_id).get("ends_after_turn", false):
			_battle_passive_skills.erase(p_skill_id)

#  Dictionary stats (replacement for active or battleEnemies)
# - Hp = 60
# - Str = 10
# - Skills = ["bash", "pkFireA", etc]
# - Status = ailments.whatever
# - Etc

