tool
extends KinematicBody2D
##For better visualization in the editor,no other use besides debugging
export var _name:String
export (String) var sprite setget _set_engine_sprite # The npc's sprite
export (String) var dialog: String # The normal spoken dialogue of the npc
export (String) var _thoughts: String # The dialog spoken when using telepathy
export (String, FILE, "*.yaml") var yaml: String # The yaml file for animations
export (Array, Array) var connections = [["Talk", "Idle", 2]] 
export var appear_flag := ""
export var disappear_flag := ""
export (Array, PoolStringArray) var _all_dialog: Array
export (Array, PoolStringArray) var _all_thoughts: Array
export (Array, PoolStringArray) var event_positions: Array
export var player_turn := { 
	"y": true, # Make "x" true if you want the player to turn left/right to face npc
	"x": true # Make "y" true if you want the player to turn up/down to face npc
}  # Putting both to true will apply both effects
export var turn_to_player_on_interact := true
export var turn_to_player_on_telepathy:bool = false
export var no_problem_thoughts := false # Say no problem here if read thoughts
export (bool) var _automatic_shadow
export (bool) var no_shadow # Turn this on to remove the npc's shadow.
export (bool) var no_collision # Turn this on to remove the npc's collisions.
export (int, "None", "Normal", "Longer", "Much longer") var extended_interact := 0 # Turn this on to extend the interact collision shape of the npc downwards
export var sprite_offset := Vector2.ZERO setget _set_engine_sprite_offset # The offset of the sprite
export var initial_dir := Vector2.ZERO # The direction the npc is facing originally
export (String, "Idle", "Walk", "Talk") var idle_animation = "Idle" # The animation to play when idle
export (String, "Idle", "Walk", "Talk", "TalkIdle") var talk_idle_animation = "Idle" # The animation to play when the npc is the current talker and is finished talking
export var staring := false # If the npc will turn to look at the player if they get close enough
export var wander := false # If the npc walks around in the overworld
export var speed := 64 # The speed at which the npc walks
export var walk_frequency := 2 # The amount of time inbetween each set of walk
export var debug_npc := false

onready var emotes = $CharacterSprite/emotes
onready var character_sprite = $CharacterSprite
onready var interact_area = $interact/CollisionShape2D
onready var wander_radius = $WanderRadius/CollisionShape2D2
onready var wander_timer = $WanderRadius/Timer
onready var collisions = $CollisionShape2D


var _is_party_member := false
var _pause_for_interact := false
var start_pos = null
var new_pos = null
var mute := false
var talking := false
var player = null
var velocity := Vector2.ZERO
var _input_vector := Vector2.ZERO
var _is_looking := false
var _player_nearby := false

func _ready():
	if !OS.is_debug_build() and debug_npc:
		queue_free()
	
	if Engine.editor_hint:
		set_physics_process(false)
		_set_engine_sprite(sprite)
		return
	
	if dialog and (_all_dialog.empty() or _all_dialog[0][0] != ""):
		_all_dialog.push_front(["", dialog])
	if _thoughts and (_all_thoughts.empty() or _all_thoughts[0][0] != ""):
		_all_thoughts.push_front(["", _thoughts])
	_check_flags()
	_set_event_positions()
	_update_sprite_and_animations()
	_set_start_pos()
	
	if sprite == "":
		push_warning("NPC sprite is missing for " + get_path())
	
	character_sprite.travel(idle_animation)
	
	new_pos = global_position
	if initial_dir == Vector2.ZERO:
		initial_dir = Vector2(0,1)
	_input_vector = initial_dir
	if _automatic_shadow:
		var size = float($Shadow.texture.get_width())/5
		$Shadow.scale.x = $Shadow.scale.x + float(size/10)
	if no_shadow and has_node("Shadow"):
		$Shadow.visible = false
	elif has_node("Shadow"):
		$Shadow.visible = true
	if no_collision:
		$CollisionShape2D.disabled = true
	if !has_dialog():
		interact_area.disabled = true
	
	if extended_interact:
		var shape := (interact_area.shape as RectangleShape2D).duplicate()
		interact_area.shape = shape
		if initial_dir.y != 0:
			var old_height = shape.extents.y
			var new_height = old_height * (1 + 0.2 * extended_interact)
			shape.extents.y = new_height
			interact_area.position.y += (new_height - old_height) * sign(initial_dir.y)
		elif initial_dir.x != 0:
			var old_width = shape.extents.x
			var new_width = old_width * (1 + 0.7 * extended_interact)
			shape.extents.x = new_width
			interact_area.position.x += (new_width - old_width) * sign(initial_dir.x)
	connect("visibility_changed", self, "update_visibility_changed")
	update_visibility_changed()
	

func _physics_process(delta: float):
	character_sprite.blend_position(_input_vector)
	var old_pos = global_position
	if wander and new_pos != null and !_pause_for_interact and !global.get_player().is_paused() and !uiManager.is_in_battle():
		var difference = max(ceil(abs(speed * delta)), 1)
		if !talking and (abs(new_pos.x - global_position.x) > difference or abs(new_pos.y - global_position.y) > difference) and !_is_looking and !_player_nearby:
			_input_vector = global_position.direction_to(new_pos)
			velocity = move_and_slide(_input_vector * speed)
			if (abs(old_pos.x - global_position.x) > 0.5 or abs(old_pos.y - global_position.y) > 0.5):
				character_sprite.travel("Walk")
			else:
				character_sprite.travel(idle_animation)
				global_position = global_position.round()
		else:
			new_pos = global_position
			character_sprite.travel(idle_animation)
			global_position = global_position.round()
	else:
		character_sprite.travel(idle_animation)
	if _is_looking and !talking and (abs(old_pos.x - global_position.x) < 1 or abs(old_pos.y - global_position.y) < 1):
		_input_vector = global_position.direction_to(global.get_player().global_position)
	
	if uiManager.is_stack_empty():
		talking = false
		_pause_for_interact = false
	else:
		if talking and !mute:
			character_sprite.travel("Talk")
		elif global.talker == self:
			character_sprite.travel(talk_idle_animation)
		else:
			character_sprite.travel(idle_animation)

func _set_engine_sprite(value: String):
	sprite = value
	if Engine.editor_hint:
		_update_sprite_and_animations()

func _set_engine_sprite_offset(value: Vector2):
	sprite_offset = value
	if Engine.editor_hint:
		_update_sprite_and_animations()

func _update_sprite_and_animations():
	if !character_sprite or sprite == "":
		return
	character_sprite.set_sprite("res://Graphics/Character Sprites/%s.png" % sprite)
	var yaml_path = yaml
	if !"Npcs" in sprite and !"Enemies" in sprite:
		_is_party_member = true
		yaml_path = "res://Data/Animations/PartyMember.yaml"
	elif yaml_path == "":
		yaml_path = "res://Data/Animations/4dir.yaml"
	if yaml_path != "":
		character_sprite.set_animation(yaml_path, connections)
	if !Engine.editor_hint: 
		yaml = yaml_path
	character_sprite.set_spritesheet()
	character_sprite.set_sprite_offset(sprite_offset)

func is_party_member() -> bool:
	return _is_party_member

func has_dialog() -> bool:
	return _get_right_dialog(false) != ""

func has_thoughts() -> bool:
	return _get_right_dialog(true) != ""

func interact():
	uiManager.close_commands_menu(true, false)
	global.talker = self
	_pause_for_interact = true
	new_pos = global_position
	if turn_to_player_on_interact:
		_input_vector = global_position.direction_to(global.get_player().global_position)
		character_sprite.blend_position(_input_vector)
	
	uiManager.open_dialogue_box(_get_right_dialog(false, true), null, self)

func stop_interaction():
	talking = false
	_pause_for_interact = false
	mute = false
	if !staring:
		get_tree().create_timer(1).connect("timeout", self, "return_to_init_dir")

func telepathy():
	_pause_for_interact = true
	if turn_to_player_on_telepathy:
		new_pos = global_position
		_input_vector = global_position.direction_to(global.get_player().global_position)
		character_sprite.blend_position(_input_vector)
	uiManager.open_dialogue_box(_get_right_dialog(true, true))
	uiManager.set_telepathy_effect(true, self)

func duplicate_sprite():
	return character_sprite.duplicate()

func set_direction(direction: Vector2):
	_input_vector = direction
	blend_position(_input_vector)

func get_direction() -> Vector2:
	return _input_vector

func blend_position(vector2: Vector2):
	character_sprite.blend_position(vector2.round())

func get_sprite_texture() -> Texture:
	return character_sprite.texture

func _set_start_pos():
	start_pos = global_position

# Similar in door_npc.gd
func _get_right_dialog(is_thoughts: bool, mark_as_seen := false) -> String:
	var dialog_array := _all_dialog if !is_thoughts else _all_thoughts
	var ret := ""
	var last_dialog_hash := ""
	for i in dialog_array.size():
		var flag: String = dialog_array[i][0]
		if flag == "" or globaldata.flags.get(flag, false):
			for j in range(1, dialog_array[i].size()):
				var cur_dialog: String = dialog_array[i][j]
				var dialog_hash := "%s:%s:%s:%s" % [get_path(), flag, j, cur_dialog]
				if !globaldata.seen_dialogue_flags.get(dialog_hash, false) or j == dialog_array[i].size() - 1:
					ret = cur_dialog
					last_dialog_hash = dialog_hash
					break
	if mark_as_seen and last_dialog_hash:
		globaldata.seen_dialogue_flags[last_dialog_hash] = true
	return ret

func _set_event_positions():
	for flags in event_positions:
		var flag = flags[0]
		var newpositionx = flags[1]
		var newpositiony = flags[2]
		if flag != "":
			if globaldata.flags.get(flag, false):
					global_position = Vector2(float(newpositionx), float(newpositiony))

func _check_flags():
	visible = check_appear_flags()
	update_visibility_changed()

func update_visibility_changed():
	collisions.disabled = !is_visible_in_tree()
	interact_area.disabled = !is_visible_in_tree() or !has_dialog()
	
	set_physics_process(is_visible_in_tree())

func _on_ViewArea_body_entered(body):
	if body == global.get_player() and staring:
		_is_looking = true

func _on_ViewArea_body_exited(body):
	if body != global.get_player() or !staring:
		return
	_is_looking = false
	if !wander:
		get_tree().create_timer(1).connect("timeout", self, "return_to_init_dir")

func return_to_init_dir():
	if !_is_looking and !_pause_for_interact:
		_input_vector = initial_dir

func _on_Timer_timeout():
	if self == null:
		return
	if wander and start_pos != null and !_is_looking and !_pause_for_interact and !global.get_player().is_paused():
		_move()
	wander_timer.wait_time = rand_range(walk_frequency - 0.5,walk_frequency + 0.5)

func _move():
	if _player_nearby:
		new_pos = global_position
		return
	
	var oldPos = global_position
	
	var x = global_position.x
	var y = global_position.y
	
	if randi()%2 == 1: 
		x = rand_range(start_pos.x - wander_radius.shape.radius/2, start_pos.x + wander_radius.shape.radius/2)
	else:
		y = rand_range(start_pos.y - wander_radius.shape.radius/2, start_pos.y + wander_radius.shape.radius/2)
	var travelPos = Vector2(round(x),round(y))
	$RayCast2D.enabled = true
	$RayCast2D.set_cast_to(travelPos - global_position)
	var ample_distance_x = abs(travelPos.x - oldPos.x)
	var ample_distance_y = abs(travelPos.y - oldPos.y)
	if (ample_distance_x > 8 or ample_distance_y > 8):
		if $RayCast2D.get_collider() == null:
			new_pos = travelPos
			_input_vector = oldPos.direction_to(new_pos)
	else:
		_move()

func check_appear_flags() -> bool:
	return globaldata.check_appear_disappear_flags(appear_flag, disappear_flag)

func _on_VisibilityNotifier2D_screen_entered():
	if uiManager.is_in_cutscene():
		return
	if check_appear_flags():
		show()
	if wander:
		wander_timer.wait_time = rand_range(0.1,walk_frequency)
		wander_timer.start()

func _on_VisibilityNotifier2D_screen_exited():
	if uiManager.is_in_cutscene():
		return
	hide()
	if wander:
		wander_timer.stop()

func _on_npc_tree_exiting():
	if !Engine.editor_hint and !global.is_persistent(self):
		wander_timer.stop()


func _on_NearPlayerArea_body_entered(body):
	if body is PartyMemberPlayer:
		_player_nearby = true


func _on_NearPlayerArea_body_exited(body):
	if body is PartyMemberPlayer:
		_player_nearby = false
