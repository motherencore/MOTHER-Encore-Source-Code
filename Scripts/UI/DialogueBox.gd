extends AbstractDialogueBox

signal done(result)

# node refs
onready var _name_label := $Dialoguebox/Namebox/ClipBox/Name
onready var _options_grid := $Dialoguebox/Options
onready var _camera := $Camera2D
onready var ActorChar := preload("res://Nodes/Reusables/actor.tscn")

var _actors := {}
var _item_not_given := false
var _options_count := 0
var _options := []
var _dialog_response := 0
var _can_input := true
var _set_respawn := false
var _dialogue_box_shown := false
var _name_box_shown := false
var _sub_menu_result # any type

var _queued_battle := false
var _post_battle_cutscenes := {}
var _battle_win_flag := ""

func _ready():
	_dialogue_box_node = $Dialoguebox
	_dialogue_label = $Dialoguebox/ClipBox/HBoxContainer/Dialogue
	_bullet_label = $Dialoguebox/ClipBox/HBoxContainer/DippinDots
	_cursor_down_sprite = $Dialoguebox/Cursor_Down

func start_from_id(dialogue_id: String, npc = null):
	var dialogue_path := "res://Data/Dialogue/%s.yaml" % dialogue_id
	if !File.new().file_exists(dialogue_path):
		return start_from_id("Reusable/error", npc)
	start_from_dict(YAMLParser.parse_file(dialogue_path), npc)

func start_from_dict(dialogue_dict: Dictionary, npc = null):
	global.in_cutscene = true
	uiManager.info_plates_hide()
	_dialog = dialogue_dict
	global.talker = npc
	_name_label.connect("item_rect_changed", self, "_set_nametag")
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	$Dialoguebox/Arrow.hide()
	_dialogue_label.visible_characters = 0
	_dialogue_label.bbcode_text = ""
	_bullet_label.bbcode_text = ""
	_handle_phrase()

# Override
func _advance_printing(delta: float):
	._advance_printing(delta)
	if global.talker != null:
		if !_dialogue_label.visible_characters >= len(_get_no_br_dialog_content()):
			if _curr_phrase.has("text") and _curr_phrase["text"] != "":
				if _get_last_visible_char() == TextTools.CHAR_WAIT:
					global.talker.talking = false
				else:
					global.talker.talking = true
		else:
			if global.talker != null:
				global.talker.talking = false

func _print_new_line():
	_dialogue_label.bbcode_text += "\n"
	_bullet_label.bbcode_text += "\n"

func _finish_phrase():
	_finished = true
	_add_dialog_options()
	if $WaitTimer.time_left == 0 and _can_input:
		_cursor_down_sprite.show()
		if _auto_advance:
			_next_phrase()

# Override
func _action_press(btn_next := false, btn_cancel := false):
	if !$AnimationPlayer.is_playing() and $WaitTimer.time_left == 0 and _can_input:
		if !_finished and !_stopped:
			if btn_cancel:
				_speed_multiplier_from_input = SPEED_UP_FROM_PRESS_B
			else:
				_speed_multiplier_from_input = SPEED_UP_FROM_PRESS_A
		elif btn_next:
			if _finished:
				if _curr_phrase.has("options"):
					var option = _options[$Dialoguebox/Arrow.cursor_index]
					if btn_cancel and _curr_phrase["options"].has("cancel"):
						option = "cancel"
					if _curr_phrase["options"][option]:
						_phrase_num = _curr_phrase["options"][option]
					else:
						_end_dialogue()
					$Dialoguebox/Arrow.hide()
					for i in _options_grid.get_children():
						i.hide()
					_options_count = 0
					_options.clear()
					_clear_dialogue()
					_handle_phrase()
					$InputSound.play()
				else:
					_next_phrase(true)
			elif _stopped:
				_stopped = false
				$InputSound.play()

# Override
func _handle_phrase() -> void:
	$WaitTimer.stop()
	_can_input = true
	_auto_advance = false
	_speed_multiplier_from_input = 1
	_speed_multiplier_from_tags = 1
	_t = 0
	
	$Dialoguebox/Arrow.cursor_index = 0
	_curr_phrase = _dialog.get(str(_phrase_num), {})
	
	_options_count = 0
	_finished = false
	
	if _phrase_num == "0":
		_dialogue_label.remove_line(1)
		_bullet_label.remove_line(1)
	
	# cleardialog: bool # Whether or not to delete all of the text present in the dialog box
	if _curr_phrase.has("cleardialog"):
		if _curr_phrase["cleardialog"]:
			_clear_dialogue()
	
	# item: String # Give an item Item to the player (this has to be handled before the text, in case the [ItemReceiver] is mentionned in dialogue)
	if _curr_phrase.has("item"):
		var item_data = globaldata.get_item_data(_curr_phrase["item"])
		_item_not_given = true #check if the item is given or not, if the item is not given, it will go to "inv_full" instead of "goto"
		if Inventory.has_inventory_space():
			_item_not_given = false
		if item_data.get("keyitem", false):
			_item_not_given = false
		global.item = Inventory.add_item_available(_curr_phrase["item"])
	
	# text: String # Set the text to be printed in the dialog box. Also shows the box
	if _curr_phrase.has("text"):
		_curr_phrase["text"] = TextTools.add_line_breaks(TextTools.replace_text(_curr_phrase["text"]), _dialogue_label)
		
		_show_box(true, _curr_phrase.get("boxsound", true))
		
		_print_dialogue_segment(true)
	elif _curr_phrase.has("wait") or _curr_phrase.has("autowait"):
		_show_box(false, _curr_phrase.get("boxsound", true))
	
	# changescene: String # Changes the scene to the map specified 
	# "res://Maps/" + targetScene + ".tscn"
	if _curr_phrase.has("changescene"):
		_change_scene(_curr_phrase["changescene"])
		yield(global, "scene_changed")
	
	# actors: replace npcs with actors
		# [actorname]: [actorpath]
		# actorname is the variable name you give to your actor
		# actorpath is the object path in the scene for the actor
		# actorpath can also be the name of one of your party members, or the party leader (leader/player, ninten, ana, lloyd, pippi, teddy, canarychick, flyingman, eve)
		# ==example==
		# distorto: Objects/npc
		# ninten: leader (you can also use "player" instead)
		# lloyd: lloyd
		# ana: ana
	if _curr_phrase.has("actors"):
		var actor_paths = _curr_phrase["actors"]
#		_add_partymember_actors(actor_paths)
		for actor_name in actor_paths:
			var npc := _actor_strings_to_node(actor_paths[actor_name])
			var new_actor := ActorChar.instance()
			if !npc:
				print("Could not create actor %s: %s" % [actor_name, actor_paths[actor_name]])
			else:
				new_actor.init(npc, true)
				npc.get_parent().call_deferred("add_child_below_node", npc, new_actor)
				yield(new_actor, "actor_ready")
				new_actor.make_persistent()
				_actors[actor_name] = new_actor
		yield(get_tree(), "idle_frame")
	
	# wait: float # Prevents the player from inputting in this amount of time.
	# caninput: bool # Whether or not the player can input anything or press anything during this phrase.
	# autoadvance: bool # Whether the phrase should automatically advance to the next one once the dialog is done.
	# autowait: float # Prevents the player from inputting in this amount of time and automatically proceeds to the next goto when the timer is done.
	# Used mainly in cutscenes. autowait basically just combines the 3 above it.
	if _curr_phrase.has("autowait"):
		$WaitTimer.start(_curr_phrase["autowait"])
		_can_input = false
		_auto_advance = true
	else:
		if _curr_phrase.has("wait"):
			$WaitTimer.start(_curr_phrase["wait"])
		
		if _curr_phrase.has("caninput"):
			_can_input = _curr_phrase["caninput"]
		else:
			_can_input = true
		
		if _curr_phrase.has("autoadvance"):
			_auto_advance = _curr_phrase["autoadvance"]
		else:
			_auto_advance = false
		
		
	#print("_can_input:" + str(_can_input))
	#print("_auto_advance:" + str(_auto_advance))
	
	# showbox: bool # Whether the box should be visible or not
	if _curr_phrase.has("showbox"):
		_show_box(_curr_phrase["showbox"], _curr_phrase.get("boxsound", true))
	
	# Parse Commands
	if _curr_phrase.has("commands"):
		for command in _curr_phrase["commands"]:
			var expression = Expression.new()
			expression.parse(command)
			var result = expression.execute([], self)
			print(result)  # 20
	
	# objectfunction: # Play multiple object functions
	# [objectPath]: String # The function the object should call
		# example
		# Objects/Trash: open_trash
	# Also works with parameters
		# example
		# BelowPlayer1/Door: open(param_1, param_2)
	if _curr_phrase.has("objectsfunction"):
		var objects = _curr_phrase["objectsfunction"]
		for i in objects:
			var object = global.currentScene.get_node_or_null(i)
			var func_name = objects[i].get_slice("(", 0)
			#if object != null and object.has_method(objects[i]):
			if object != null and object.has_method(func_name):
				
				# Check if function has arguments, and then call with
				# provided args converted to an array.
				if (objects[i].ends_with(')')):
					var args_str = objects[i].get_slice("(", 1).trim_suffix(")")
					var args = args_str.split(",")
					
					# Check if there are any actual args
					if args_str != "":
						object.callv(func_name, args)
					else:
						object.call_deferred(func_name)
				# This is for retaining backwards compatibility with
				# pre-existing YAML cutscenes.
				else:
					object.call_deferred(objects[i])
	
	# tweenpos: # Tweens an object's position on the scene
		# [objectpath]: 
			# x: int
			# y: int
			# duration: float # Duration of the movement in seconds
			# delay: float # The delay in seconds before starting
			# ease: String (linear, in, out, inout, outin)
			# globalposition: bool = true # whether to use global position or relative position
	if _curr_phrase.has("tweenpos"):
		
		for i in _curr_phrase["tweenpos"]:
			var object = global.currentScene.get_node_or_null(i)
			var is_global_position_type = _curr_phrase["tweenpos"][i].get(["globalposition"], true)
			var position_type = "global_position" if is_global_position_type else "position"
			var initial_value = object.global_position if is_global_position_type else object.get_position_in_parent()
			var x = _curr_phrase["tweenpos"][i].get("x", initial_value.x)
			var y = _curr_phrase["tweenpos"][i].get("y", initial_value.y)
			var new_value = Vector2(x, y) 
			var duration = _curr_phrase["tweenpos"][i].get("duration", 1)
			var delay = _curr_phrase["tweenpos"][i].get("delay", 0)
			var ease_type = _curr_phrase["tweenpos"][i].get("ease", "linear")
			var trans = Tween.TRANS_LINEAR if ease_type == "linear" else  Tween.TRANS_QUART
			var ease_match = {
				"linear": Tween.EASE_IN, 
				"in": Tween.EASE_IN, 
				"out": Tween.EASE_OUT, 
				"inout": Tween.EASE_IN_OUT, 
				"outin": Tween.EASE_OUT_IN
			}
			var easing = ease_match[ease_type]
			
			var tween = create_tween()
			tween.tween_property(object, position_type, 
				new_value, duration) \
				.set_trans(trans).set_ease(easing).set_delay(delay)
	
	#objectsteleport: for teleporting objects to set position
		# x: int
		# y: int
	if _curr_phrase.has("objectsteleport"):
		for i in _curr_phrase["objectsteleport"]:
			var object = global.currentScene.get_node_or_null(i)
			var is_global_position_type = _curr_phrase["objectsteleport"][i].get(["globalposition"], true)
			var position_type = "global_position" if is_global_position_type else "position"
			var initial_value = object.global_position if is_global_position_type else object.get_position_in_parent()
			var x = _curr_phrase["objectsteleport"][i].get("x", initial_value.x)
			var y = _curr_phrase["objectsteleport"][i].get("y", initial_value.y)
			var new_value = Vector2(x, y) 
			object.global_position = new_value
	
	# ovbattlemusic: bool # Sets the battle theme to the current overworld theme 
	if _curr_phrase.has("ovbattlemusic"):
		audioManager.overworld_battle_music = _curr_phrase["ovbattlemusic"]
	
	# music: String # Plays a song
	if _curr_phrase.has("music"):
		
		if _curr_phrase["music"] != "":
			audioManager.play_music(audioManager.CHANNELS.CUTSCENE, _curr_phrase["music"])
		else:
			var channel = audioManager.CHANNELS.CUTSCENE if audioManager.get_music_player_by_name(audioManager.CHANNELS.CUTSCENE).playing else audioManager.CHANNELS.OVERWORLD
			audioManager.fadeout_music_player_by_name(channel, 2)
	
	# musicvolume: float # Sets the music's volume to a certain db level
	if _curr_phrase.has("musicvolume"):
		yield(get_tree(), "idle_frame")
		var channel = audioManager.CHANNELS.CUTSCENE if audioManager.get_music_player_by_name(audioManager.CHANNELS.CUTSCENE).playing else audioManager.CHANNELS.OVERWORLD
		audioManager.fadeto_music_player_by_name(channel, _curr_phrase["musicvolume"])
	
	# sound: String # The sound effect that plays when a character is printed in the dialog box
	# Can either be Adult, Female, Kid, Robot, Shy or Strange
	if _curr_phrase.get("sound", null):
		if !_curr_phrase["sound"].begins_with("res://"):
			_curr_phrase["sound"] = "res://Audio/Sound effects/text/" + _curr_phrase["sound"]
		$AudioStreamPlayer.stream = load(_curr_phrase["sound"] +".mp3")
	else:
		$AudioStreamPlayer.stream = null
	
	# soundeffect: String # The name of a sound effect to play
	# "res://Audio/Sound effects/" + soundeffect
	if _curr_phrase.has("soundeffect"):
		if !_curr_phrase["soundeffect"].begins_with("res://"):
			_curr_phrase["soundeffect"] = "res://Audio/Sound effects/" + _curr_phrase["soundeffect"]
		audioManager.play_sfx(load(_curr_phrase["soundeffect"]), "dialogBoxSound")
	
	# font: String # The name of the font to display. Can either be EBZ or Saturn 
	if _curr_phrase.has("font"):
		if _curr_phrase["font"] == "EBZ" or _curr_phrase["font"] == "Saturn":
			_dialogue_label.add_font_override("normal_font",load("res://Fonts/saturn.tres"))
			_bullet_label.add_font_override("normal_font",load("res://Fonts/saturn.tres"))
	
	var party_changed := false
	
	# setpartymembers: # add or remove party members (ninten, ana, lloyd, pippi, teddy)
		# [partymembername]: Bool # set true to add the party member, and false to remove them
	if _curr_phrase.has("setpartymembers"):
		set_party_members(_curr_phrase["setpartymembers"])
		party_changed = true 
	
	# setpartynpcs: # add or remove party npcs (canarychick, )
		# [partymembername]: Bool # set true to add the party member, and false to remove them
	if _curr_phrase.has("setpartynpcs"):
		set_party_npcs(_curr_phrase["setpartynpcs"])
		party_changed = true 
	
	if party_changed:
		global.create_party_followers()
	
	# changereplaced: # change the npc an actor replaces
		# [actorname]: [objectpath] # the path to the object that the actor turns into at the end of a cutscene
		# when the cutscene ends, the actor will turn into the object specified here.
		# This is usually used for turning party members into npcs or vice versa. 
		# Could also be used for turning an actor into an enemy for example.
	if _curr_phrase.has("changereplaced"):
		_add_partymember_actors(_curr_phrase["changereplaced"])
		for i in _curr_phrase["changereplaced"]:
			if _actors.has(i):
				var replacement := _actor_strings_to_node(_curr_phrase["changereplaced"][i])
				if replacement in global.partyObjects:
					replacement.hide()
				_actors[i].change_replaced(replacement)
	
	# mutetalker: bool # Makes the current talker npc not do the talking animation when text is being printed
	# lowkey idk why we have this you can just set talker to null
	if _curr_phrase.has("mutetalker"):
		if global.talker != null:
			global.talker.mute = _curr_phrase["mutetalker"]
	
	# talker: [actorname] | null # Change talker to an actor or set it to null for no talker
	if _curr_phrase.has("talker"):
		if _curr_phrase["talker"] and _actors.has(_curr_phrase["talker"]):
			if global.talker: global.talker.talking = false
			global.talker = _actors[_curr_phrase["talker"]]
		else: 
			if global.talker: global.talker.talking = false
			global.talker = null
	
	# teleportactors: # teleports one or more actors to positions on the map instantly
		# [actorname]: # the name of an actor to teleport
			# - x: float 
			#   y: float
	if _curr_phrase.has("teleportactors"):
		for i in _curr_phrase["teleportactors"]:
			if _actors.has(i):
				_actors[i].global_position = Vector2(_curr_phrase["teleportactors"][i]["x"], _curr_phrase["teleportactors"][i]["y"])
	
	# actorsvisible: # sets the visibility for an actor
		# [actorname]: bool # the visibility of the actor
			
	if _curr_phrase.has("actorsvisible"):
		for i in _curr_phrase["actorsvisible"]:
			if _actors.has(i):
				_actors[i].visible = _curr_phrase["actorsvisible"][i]
	
	
	# teleportparty: teleports the party to a location on the map. 
		# x: float
		# y: float
		# disappear: bool # whether or not to hide the party when teleporting it
	# useful for moving the camera around between rooms.
	if _curr_phrase.has("teleportparty"):
		var new_pos = Vector2.ZERO
		var disappear = true
		if _curr_phrase["teleportparty"].has("x"):
			new_pos.x = _curr_phrase["teleportparty"]["x"]
		if _curr_phrase["teleportparty"].has("y"):
			new_pos.y = _curr_phrase["teleportparty"]["y"]
		if _curr_phrase["teleportparty"].has("disappear"):
			disappear = _curr_phrase["teleportparty"]["disappear"]
		global.get_player().position = new_pos
		if global.partySpace.size() > 1:
			for i in global.partySpace.size():
				global.partySpace.push_front(global.get_player().position)
				global.partySpace.pop_back()
			for i in range(1, global.partyObjects.size()):
				global.partyObjects[i].position = global.get_player().position
				if disappear:
					global.partyObjects[i].reinit()
					global.partyObjects[i].disappear()
	
	# actorsdir: For setting multiple actor's direction instantly
		# x: int
		# y: int
	if _curr_phrase.has("actorsdir"):
		for i in _curr_phrase["actorsdir"]:
			if _actors.has(i):
				var turner = _actors[i]
				var direction = Vector2.ZERO
				if _curr_phrase["actorsdir"][i].has("x"):
					direction.x = _curr_phrase["actorsdir"][i]["x"]
				if _curr_phrase["actorsdir"][i].has("y"):
					direction.y = _curr_phrase["actorsdir"][i]["y"]
				turner.set_direction(direction)
	
	# stopactorsloop: stop an actor's looping movement if it was set to true
		# [actorname]: bool
	if _curr_phrase.has("stopactorsloop"):
		for i in _curr_phrase["stopactorsloop"]:
			if _actors.has(i):
				_actors[i].stop_loop()
	
	# actorsblend: set if an actor's direction is set to their walking direction.
		# [actorname]: bool
	# for example if an actor is moving up, their animation direction will be set to up.
	if _curr_phrase.has("actorsblend"):
		for i in _curr_phrase["actorsblend"]:
			if _actors.has(i):
				_actors[i].set_blending(_curr_phrase["actorsblend"][i])
	
	# actorsshadow: set an actor's shadow's visibility
		# [actorname]: bool # the visibility of the shadow
	if _curr_phrase.has("actorsshadow"):
		for i in _curr_phrase["actorsshadow"]:
			if _actors.has(i):
				_actors[i].set_shadow(_curr_phrase["actorsshadow"][i])
	
	
	# actorsmove: #actor movements
		# [actorname]:
			# movement: Array
				# - x: int # The position or amount of steps to move to
				#   y: int # vector2
				
				# turnto: # Smoothly rotate to a direction
					# x: int
					# y: int
					# actor: [actorname] # Turn towards the position of another actor. x and y can overwrite the respective directions for this.
					# speed: float # Despite it's name, represents the interval between direction changes. Smaller number = faster
					# I would change this variable's name but i'm too lazy to update all the old cutscene yamls
				
				# setdir: # Turn instantly to a direction
					# x: int 
					# y: int
					# actor: [actorname] # Turn towards the position of another actor. x and y can overwrite the respective directions for this.
				
				# turnaround: bool # Instantly turn around to the opposite direction
				
				# spin:
					# enabled: bool # Whether to start or stop spinning
					# speed: float # Despite it's name, represents the interval between direction changes. Smaller number = faster
					# anticlockwise: bool # If true, makes the actor spin anticlockwise
				
				# shake: # Make the actor shake
					# x: int # Shake direction in the X axis 
					# y: int # Shake direction in the X axis 
					# length: float # How long the shake lasts
					# async: bool # True if the action can happen at the same time as the following actions
				
				# jump: # Make the actor jump
					# height: int # The height of the jump
					# length: float # The amount of time the jump lasts
					# times: float # The amount of times the actor should jump
					# shadow: bool # The shadow's visibility between jumps 
					# crouch: bool # Makes the actor play the crouching animation between jumps
					# async: bool # True if the action can happen at the same time as the following actions
				
				# visible: bool # Make the actor visible or invisible
				
				# emote: string # Make the actor emote
				
				# playsound: string # Make the actor play a sound effect
				
				# blend: bool # Set if an actor's direction follows their walking direction.
				
				# shadow: bool # Make the actor's shadow visible or hidden
				
				# playanim: # Make the actor play an animation
					# anim: String # name of the animation
					# speed: float # playback speed
					# type: 1 | 0 # 1 for special animation, 0 for regular animation
					# newidle: bool # Makes this animation the new idle animation for the actor (example: making walk the animation)
					# async: bool # True if the action can happen at the same time as the following actions
				
				# teleport: # Instantly teleport the actor to a position
					# x: int 
					# y: int
				
				# moonwalk: bool # Makes the character walk backwards if set to true in the middle of the movement
				
				# movespeed: float # Edit the speed that the actor should move in the middle of the movement 
				
				# animspeed: float # Edit the speed of the actor's animations
				
				# wait: float # Wait for an amount of seconds before the next action
				
			# animation: String # The animation that the actor should play as it performs the movement actions
			# speed: float # How fast the actor should move 
			# type: step | position
				# step is movement based on its current position
				# position is for moving to positions on the map
			# moonwalk: bool # Makes the character walk backwards if set to true
			# loop: bool # Makes the actions repeat infinitely
			# queue: bool # Whether to perform the action after another action like jump or turn to. 
				# NOTE: This is what I used before adding the turn to and jump actions to the move queue, so using this is kind of useless now.
	if _curr_phrase.has("actorsmove"):
		for i in _curr_phrase["actorsmove"]:
			if _actors.has(i):
				var character = _curr_phrase["actorsmove"][i]
				var movingActor = _actors[i]
				var move_queue := []
				var animation := ""
				var speed: float = 64.0
				var type := "0"
				var moonwalk := false
				var loop := false
				var queue := false
				if character.has("movement"):
					for j in character["movement"]:
						var action
						
						if j.has("wait"): 
							action = Actor.WaitAction.new(j["wait"])
						
						elif j.has("turnto"): 
							var dir = Vector2.ZERO
							if j["turnto"].has("actor"):
								dir = movingActor.position.direction_to(_actors[j["turnto"]["actor"]].position)
							if j["turnto"].has("x"):
								dir.x = j["turnto"]["x"]
							if j["turnto"].has("y"):
								dir.y = j["turnto"]["y"]
							var turnSpeed = j["turnto"].get("speed", 0.05)
							action = Actor.TurnToAction.new(dir, turnSpeed)
						
						elif j.has("setdir"): 
							var dir = Vector2.ZERO
							if j["setdir"].has("actor"):
								dir = movingActor.position.direction_to(_actors[j["setdir"]["actor"]].position)
							if j["setdir"].has("x"):
								dir.x = j["setdir"]["x"]
							if j["setdir"].has("y"):
								dir.y = j["setdir"]["y"]
							action = Actor.SetDirAction.new(dir)
						
						elif j.get("turnaround", false): 
							action = Actor.TurnAroundAction.new()
						
						elif j.has("spin"): 
							var dir = Vector2.ZERO
							var enabled = j["spin"].get("enabled", true)
							var spinSpeed = j["spin"].get("speed", 0.05)
							var anticlockwise = j["spin"].get("anticlockwise", false)
							action = Actor.SpinAction.new(enabled, spinSpeed, anticlockwise)
						
						elif j.has("shake"): 
							var offset = Vector2(j["shake"].get("x", 0), j["shake"].get("y", 0))
							var length = j["shake"].get("length", 1.0)
							var async = j["shake"].get("async", false)
							action = Actor.ShakeAction.new(offset, length, async)
						
						elif j.has("jump"): 
							var height = j["jump"].get("height", 8)
							var length = j["jump"].get("length", 0.2)
							var times = j["jump"].get("times", 1)
							var shadow = j["jump"].get("shadow", true)
							var crouch = j["jump"].get("crouch", false)
							var async = j["jump"].get("async", false)
							action = Actor.JumpAction.new(height, length, times, shadow, crouch, async)
						
						elif j.has("playanim"):
							var anim_speed = j["playanim"].get("speed", 1.0)
							var anim_type = j["playanim"].get("type", 0)
							var newidle = j["playanim"].get("newidle", true)
							var async = j["playanim"].get("async", true if anim_type == 0 else false)
							action = Actor.AnimAction.new(j["playanim"]["anim"], anim_speed, anim_type, newidle, async)
						
						elif j.has("visible"): 
							action = Actor.VisibilityAction.new(j["visible"])
						
						elif j.has("emote"): 
							action = Actor.EmoteAction.new(j["emote"])
						
						elif j.has("playsound"): 
							action = Actor.SoundEffectAction.new(j["playsound"])
						
						elif j.has("blend"): 
							action = Actor.BlendAction.new(j["blend"])
						
						elif j.has("shadow"): 
							action = Actor.ShadowAction.new(j["shadow"])
						
						elif j.has("moonwalk"): 
							action = Actor.MoonwalkAction.new(j["moonwalk"])
						
						elif j.has("movespeed"): 
							action = Actor.MoveSpeedAction.new(j["movespeed"])
						
						elif j.has("animspeed"): 
							action = Actor.AnimSpeedAction.new(j["animspeed"])
						
						elif j.has("teleport"): 
							var pos = movingActor.global_position
							if j["teleport"].has("x"):
								pos.x = j["teleport"]["x"]
							if j["teleport"].has("y"):
								pos.y = j["teleport"]["y"]
							action = Actor.TeleportAction.new(pos)
						
						else:
							var vector2 := Vector2(j["x"],j["y"])
							action = Actor.MoveAction.new(vector2)
						
						move_queue.append(action)
				if character.has("animation"):
					animation = character["animation"]
				if character.has("speed"):
					speed = character["speed"]
				if character.has("type"):
					type = character["type"]
				if character.has("moonwalk"):
					moonwalk = character["moonwalk"]
				if character.has("loop"):
					loop = character["loop"]
				if character.has("queue"):
					queue = character["queue"]
				movingActor.move_queue(move_queue, animation, speed, type, moonwalk, loop, queue)
	
	# actorsturn: For turning multiple actors' direction
		# [actorname]: 
			# x: int
			# y: int
			# actor: [actorname] # Turn towards the position of another actor. x and y can overwrite the respective directions for this.
			# speed: float # The interval of time between the angles turned
			# queue: bool # Whether this action should happen after other actions such as movement (not really needed anymore)
	if _curr_phrase.has("actorsturn"):
		for i in _curr_phrase["actorsturn"]:
			if _actors.has(i):
				var turner = _actors[i]
				var direction = Vector2.ZERO
				var speed = 0.08
				var queue = false
				if _curr_phrase["actorsturn"][i].has("actor"):
					direction = turner.position.direction_to(_actors[_curr_phrase["actorsturn"][i]["actor"]].position)
				if _curr_phrase["actorsturn"][i].has("x"):
					direction.x = _curr_phrase["actorsturn"][i]["x"]
				if _curr_phrase["actorsturn"][i].has("y"):
					direction.y = _curr_phrase["actorsturn"][i]["y"]
				if _curr_phrase["actorsturn"][i].has("speed"):
					speed = _curr_phrase["actorsturn"][i]["speed"]
				if _curr_phrase["actorsturn"][i].has("queue"):
					queue = _curr_phrase["actorsturn"][i]["queue"]
				turner.turn_to(direction, speed, queue)
	
	# actorsshake: Make actor shake
		# [actorname]:
			# x: int # Horizontal pixels the actor should shake
			# y: int # Vertical pixels the actor should shake
			# length: float # The length an actor should shake
			# queue: bool # Whether this action should happen after other actions such as movement
	if _curr_phrase.has("actorsshake"):
		for i in _curr_phrase["actorsshake"]:
			if _actors.has(i):
				var shaked = _actors[i]
				var length = 1.0
				var magnitude = Vector2.ZERO
				var queue = false
				if _curr_phrase["actorsshake"][i].has("x"):
					magnitude.x = _curr_phrase["actorsshake"][i]["x"]
				if _curr_phrase["actorsshake"][i].has("y"):
					magnitude.y = _curr_phrase["actorsshake"][i]["y"]
				if _curr_phrase["actorsshake"][i].has("length"):
					length = _curr_phrase["actorsshake"][i]["length"]
				if _curr_phrase["actorsshake"][i].has("queue"):
					queue = _curr_phrase["actorsshake"][i]["queue"]
				shaked.shake(magnitude, length, queue)
	
	# actorsjump: Makes actors jump
		# [actorname]: 
			# height: int # The height of the jump
			# length: float # The amount of time the jump lasts
			# times: float # The amount of times the actor should jump
			# shadow: bool # The shadow's visibility between jumps 
			# crouch: bool # Makes the actor play the crouching animation between jumps
			# queue: bool # Whether this action should happen after other actions such as movement (not really needed anymore)
	if _curr_phrase.has("actorsjump"):
		for i in _curr_phrase["actorsjump"]:
			if _actors.has(i):
				var jumper = _actors[i]
				var height = 8
				var speed = 0.2
				var times = 1
				var queue = false
				var crouch = false
				var shadow = true
				if _curr_phrase["actorsjump"][i].has("height"):
					height = _curr_phrase["actorsjump"][i]["height"]
				if _curr_phrase["actorsjump"][i].has("speed"):
					speed = _curr_phrase["actorsjump"][i]["speed"]
				if _curr_phrase["actorsjump"][i].has("length"):
					speed = _curr_phrase["actorsjump"][i]["length"]
				if _curr_phrase["actorsjump"][i].has("times"):
					times = _curr_phrase["actorsjump"][i]["times"]
				if _curr_phrase["actorsjump"][i].has("queue"):
					queue = _curr_phrase["actorsjump"][i]["queue"]
				if _curr_phrase["actorsjump"][i].has("shadow"):
					shadow = _curr_phrase["actorsjump"][i]["crouch"]
				if _curr_phrase["actorsjump"][i].has("crouch"):
					crouch = _curr_phrase["actorsjump"][i]["crouch"]
				jumper.jump(height, speed, times, queue, shadow, crouch)
	
	
	# actorsanim: # Make actor animate
		# [actorname]: 
			# anim: String # name of the animation
			# speed: float # playback speed
			# queue: bool # have the animation play after other actions or not
			# type: 1 | 0 # 1 for special animation, 0 for regular animation
			# newidle: bool # Makes this animation the new idle animation for the actor (example: making walk the animation)
	if _curr_phrase.has("actorsanim"):
		for i in _curr_phrase["actorsanim"]:
			if _actors.has(i):
				var animated = _actors[i]
				var speed := 1.0
				var queue := false
				var type := 0
				var newidle := false
				if _curr_phrase["actorsanim"][i].has("speed"):
					speed = _curr_phrase["actorsanim"][i]["speed"]
				if _curr_phrase["actorsanim"][i].has("queue"):
					queue = _curr_phrase["actorsanim"][i]["queue"]
				if _curr_phrase["actorsanim"][i].has("type"):
					type = _curr_phrase["actorsanim"][i]["type"]
				if _curr_phrase["actorsanim"][i].has("newidle"):
					newidle = _curr_phrase["actorsanim"][i]["newidle"]
				animated.play_anim(_curr_phrase["actorsanim"][i]["anim"], speed, queue, type, newidle)
	
	# eraseactors: # erase an actor from a scene
		# [actorname]: bool # erases this actor if set to true
	if _curr_phrase.has("eraseactors"):
		for i in _curr_phrase["eraseactors"]:
			if _curr_phrase["eraseactors"][i] == true:
				if global.talker == _actors[i]:
					global.talker = null
				_actors[i].erase()
				_actors.erase(i)
	
	# playeremote: String  # Make the player play an emote 
		# (example: angry, blueExclamation, dot, dotFast, exclamation, heart, question, shock, surprise, sweat) 
		# Check emotes.tscn for the full list of animations
	if _curr_phrase.has("playeremote"):
		global.get_player().emotes.animaPlayer.play(_curr_phrase["playeremote"])
	
	# talkeremote: String # A simple way of getting the talker to emote
	if _curr_phrase.has("talkeremote"):
		if global.talker != null:
			global.talker.emotes.animaPlayer.play(_curr_phrase["talkeremote"])
	
	# actorsemote: Make specific actor play an emote
		# [actorname]: String # The name of the emote the actor should play
	if _curr_phrase.has("actorsemote"):
		for i in _curr_phrase["actorsemote"]:
			if _actors.has(i):
				var emoter = _actors[i]
				emoter.emotes.animaPlayer.play(_curr_phrase["actorsemote"][i])
	
	# shakecam: Shake camera
		# x: int # horizontal movement. (either 0 or 1)
		# y: int # vertical movement. (either 0 or 1)
		# size: small | medium | big # the magnitude of the shake
		# length: float # the amount of time the camera should shake
	if _curr_phrase.has("shakecam"):
		var size = str(_curr_phrase["shakecam"].get(["size"], "small"))
		var length = 0.2
		var direction = Vector2.RIGHT
		if _curr_phrase["shakecam"].has("length"):
			length = _curr_phrase["shakecam"]["length"]
		if _curr_phrase["shakecam"].has("x"):
			direction.x = _curr_phrase["shakecam"]["x"]
		if _curr_phrase["shakecam"].has("y"):
			direction.y = _curr_phrase["shakecam"]["y"]
		match size:
			"small":
				global.start_joy_vibration(0, 0.4, 0.3, length)
				global.currentCamera.shake_camera(4, length, direction)
			"medium":
				global.start_joy_vibration(0, 0.5, 0.6, length)
				global.currentCamera.shake_camera(6, length, direction)
			"big":
				global.start_joy_vibration(0, 0.7, 0.8, length)
				global.currentCamera.shake_camera(8, length, direction)
	
	# changecam: [actorname] | null # Set current camera to follow an actor or none of them.
	if _curr_phrase.has("changecam"):
		if !_curr_phrase["changecam"]:
			_camera.set_current()
		elif _actors.has(_curr_phrase["changecam"]):
			_actors[_curr_phrase["changecam"]].camera.set_current()
		yield(get_tree(), "idle_frame")
	
	
	# movecam: # Move camera to a position on the map or an actor.
		# actor: [actorname] | parent # the actor the camera should move to. If set to "parent", moves to the current camera's actor/parent.
		# x: int # x coordinate on the map. If not present, will default to the current x position.
		# y: int # y coordinate on the map If not present, will default to the current y position.
		# length: float # the amount of time the camera should take to move to a position
		# trans: String # Transition type. Can be linear, sine, quint, quart, quad, expo, elastic, cubic, circ, bounce or back.
		# ease: String # Ease type. Can be in, out, in_out or out_in.
	if _curr_phrase.has("movecam"):
		var cam_pos = global.currentCamera.global_position
		var time = 1.0
		if _curr_phrase["movecam"].has("actor"): #moves camera to actor
			if _curr_phrase["movecam"]["actor"] == "parent":
				cam_pos = global.currentCamera.get_parent().global_position
			elif _actors.has(_curr_phrase["movecam"]["actor"]):
				
				cam_pos = _actors[_curr_phrase["movecam"]["actor"]].global_position
		if _curr_phrase["movecam"].has("x"):
			cam_pos.x = _curr_phrase["movecam"]["x"]
		if _curr_phrase["movecam"].has("y"):
			cam_pos.y = _curr_phrase["movecam"]["y"]
		if _curr_phrase["movecam"].has("length"):
			time = _curr_phrase["movecam"]["length"]
		var trans_types = ["linear", "sine", "quint", "quart", "quad", "expo", "elastic", "cubic", "circ", "bounce", "back"]
		var ease_types = ["in", "out", "in_out", "out_in"]
		var trans_type = trans_types.find(_curr_phrase["movecam"].get("trans", "sine"))
		var ease_type = ease_types.find(_curr_phrase["movecam"].get("ease", "out"))
		global.currentCamera.move_camera(cam_pos, time, trans_type, ease_type)
	
	# returncam: float # Moves the current camera's position to its actor/parent. 
	# Also represents the time it takes for the camera to do its movement.
	if _curr_phrase.has("returncam"):
		global.currentCamera.return_camera(_curr_phrase["returncam"])
	
	# fadefocus: [actorname] # Makes the screen fade focus on the position of an actor (usually used for circle fades or for the telepathy effect)
	if _curr_phrase.has("fadefocus"):
		uiManager.get_fade().focus_object(_actors[_curr_phrase["fadefocus"]])
	
	# fadein: # Screen fade in transition (from transparent to opaque)
		# anim: String # The fadein animation to play (example: Circle, Fade or Cut)
		# speed: float # the speed of the fade transition
		# color: String # The hex color number of the transition (Example: #000000 for black)
	if _curr_phrase.has("fadein"):
		var color = Color.black
		var speed = 1.0
		if _curr_phrase["fadein"].has("speed"):
			speed = _curr_phrase["fadein"]["speed"]
		if _curr_phrase["fadein"].has("color"):
			color = Color(_curr_phrase["fadein"]["color"])
		uiManager.get_fade().fade_in(_curr_phrase["fadein"]["anim"],color, speed)
	
	# fadeout: # Screen fade out transition (from opaque to transparent)
		# anim: String # The fadein animation to play (example: Circle, Fade or Cut)
		# speed: float the speed of the fade transition
		# color: String # The hex color number of the transition (Example: #000000 for black)
	if _curr_phrase.has("fadeout"):
		var color = Color.black
		var speed = 1
		if _curr_phrase["fadeout"].has("speed"):
			speed = _curr_phrase["fadeout"]["speed"]
		if _curr_phrase["fadeout"].has("color"):
			color = Color(_curr_phrase["fadeout"]["color"])
		uiManager.get_fade().fade_out(_curr_phrase["fadeout"]["anim"],color, speed)
	
	# fadesize: Set a fade's cut. For example, the screen's fade circle's size or the screen fade's opacity
		# size: float # Set fade cut from 0 to 1
		# speed: float # How fast the fade should transition into the cut.
	if _curr_phrase.has("fadesize"):
		var speed = _curr_phrase["fadesize"].get("speed", 1.0)
		
		uiManager.get_fade().set_cut(_curr_phrase["fadesize"]["size"])
	
	# fadespin: # make the fade spin, only works if it's a circle fade.
		# enabled: bool # turn the fadespin on or off
		# speed: float # the speed at which the fade should spin
	if _curr_phrase.has("fadespin"):
		var enabled = _curr_phrase["fadespin"].get("enabled", true)
		var speed = _curr_phrase["fadespin"].get("speed", 1.0)
		uiManager.get_fade().set_spin(enabled, speed)
	
	# disable/enable telepathy effect 
	# telepathyeffect: null (disable telepathy)
	# telepathyeffect: [actorname] (enable telepathy and focus towards actor)
	if _curr_phrase.has("telepathyeffect"):
		if _curr_phrase["telepathyeffect"] == null:
			uiManager.set_telepathy_effect(false)
		else:
			uiManager.set_telepathy_effect(true, _actors[_curr_phrase["telepathyeffect"]])
	
	# setflags: [flagname] # sets a flag to true
	if _curr_phrase.has("setflags"):
		_change_flags(_curr_phrase["setflags"], true)

	# unsetflags: [flagname] # sets a flag to false
	if _curr_phrase.has("unsetflags"):
		_change_flags(_curr_phrase["unsetflags"], false)
	
	# setrespawn: bool # Sets the respawn point upon death to the player position at the end of the cutscene
	if _curr_phrase.has("setrespawn"):
		_set_respawn = _curr_phrase["setrespawn"]
	
	# name: String # The text in the nametag
	# text: String # The text to print in the dialog box
	# cleardialog: bool # Whether to clear the text in the dialogbox before printing the text or not
	if _curr_phrase.has("name") and _curr_phrase.has("text"):
		_curr_phrase["name"] = TextTools.replace_text(_curr_phrase["name"])
		var old_name = _name_label.text
		_name_label.text = str(_curr_phrase["name"])
		if !_name_box_shown:
			$NameAnim.play("Open")
			_name_box_shown = true
			if !_curr_phrase.has("cleardialog"):
				_clear_dialogue()
				_print_dialogue_segment(true)
		
		elif old_name != _curr_phrase["name"]:
			if _phrase_num != "0":
				if !_curr_phrase.has("cleardialog"):
					_clear_dialogue()
					_print_dialogue_segment(true)
	elif (not _curr_phrase.has("name") and !(_curr_phrase.has("wait") and _curr_phrase.has("autoadvance")) and !_curr_phrase.has("autowait")) or !_dialogue_box_shown:
		var old_name = _name_label.text
		_name_label.text = ""
		if _name_box_shown:
			$NameAnim.play("Close")
			_name_box_shown = false
		if old_name != _name_label.text and _phrase_num != "0":
			if !_curr_phrase.has("cleardialog"):
				_clear_dialogue()
			if _curr_phrase.has("text"):
				_print_dialogue_segment(true)
	
	# save: any # Opens the save menu
	if _curr_phrase.has("save"):
		uiManager.open_save(SaveSelect.Type.SAVE, funcref(self, "_try_resume_dialogue"))
	
	# cash: bool # Sets the visibility of the cash number
	if _curr_phrase.has("cash"):
		if _curr_phrase["cash"] == false:
			uiManager.get_cash_box().close()
		else:
			uiManager.get_cash_box().open()
	
	# givecash: int | String # Give/Remove Money
	# can either be a number amount, or an amount based on the total cash amount
	# +all: doubles the player's cash
	# -all: removes all the player's cash
	# +half: adds half the player's cash
	# -half: removes half the player's cash
	if _curr_phrase.has("givecash"):
		var cash = _curr_phrase["givecash"]
		if cash is String:
			match cash:
				"+all":
					cash = globaldata.cash
				"-all":
					cash = -globaldata.cash
				"+half":
					cash = int(globaldata.cash / 2)
				"-half":
					cash = -int(globaldata.cash / 2)
				_:
					cash = int(cash)
		globaldata.cash += cash
		uiManager.get_cash_box().update()
	
	# cure: Cure one or all status effects to one or all party members
		# character: String | all # The affected party member. If set to "all", will affect all party members
		# status: String | all # The cured status effect. If set to "all", will cure every status effect
	if _curr_phrase.has("cure"):
		var char_value := str(_curr_phrase["cure"]["character"])
		var status := str(_curr_phrase["cure"]["status"])
		for party_mem in _get_party_mem_from_dict(char_value):
			if status != "all":
				party_mem.remove_status(status)
				if status == Status.AILMENT_UNCONSCIOUS and party_mem.get_hp() <= 0:
					party_mem.set_hp(1)
			else:
				party_mem.remove_all_statuses()
				if party_mem.get_hp() <= 0:
					party_mem.set_hp(1)
		
		for obj in global.partyObjects:
			obj.spritesheet()
	
	# givestatus: gives a status to party members
		# [partymembername]: String # The name of the status to give 
		# partymembername can also just be "leader" to give the status to the player
		# ==example==
		# leader: cold
	if _curr_phrase.has("givestatus"):
		for character in _curr_phrase["givestatus"]:
			var character_name = character
			var status = str(_curr_phrase["givestatus"][character])
			if character == "leader":
				character_name = global.party[0].get_name()
			globaldata.characters[character_name].add_status(status)
	
	# heal: String # Restores all HP to a party member or all of them
	# (ninten, ana, lloyd, etc.) 
	# ==example== 
	# heal: ninten # will heal ninten to full hp
	# heal: all # heals all conscious party members to full hp
	if _curr_phrase.has("heal"):
		var char_value := str(_curr_phrase["heal"])
		for party_mem in _get_party_mem_from_dict(char_value):
			if !party_mem.is_unconscious():
				party_mem.set_hp(party_mem.get_stat(Character.MAXHP))

	# restorepp: String | all # Restores all PP to a party member or all of them
	# (ninten, ana, etc.) 
	# ==example== 
	# restorepp: ninten # will restore ninten to max pp
	# restorepp: all # restores all pp to all party members
	if _curr_phrase.has("restorepp"):
		var char_value := str(_curr_phrase["restorepp"])
		for party_mem in _get_party_mem_from_dict(char_value):
			party_mem.set_pp(party_mem.get_stat(Character.MAXPP))
	
	# resetpartymember: reset's a party member's stats and inventory
		# [partymembername]: bool # Resets the party member if true
		# partymembername can also just be "leader" to reset the player (idk why you'd do that)
		# ==example==
		# leader: true
	if _curr_phrase.has("resetpartymembers"):
		for character in _curr_phrase["resetpartymembers"]:
			var character_name = character
			if character == "leader":
				character_name = global.party[0].get_name()
			if _curr_phrase["resetpartymembers"][character]:
				globaldata.characters[character_name].reset(false, true)
	
	# setpartymemberlevel: set a party member's level
		# [partymembername]: int # The level to set the party member to
		# partymembername can also just be "leader" to set the player's level
		# ==example==
		# leader: 20
	if _curr_phrase.has("setpartymemberlevel"):
		for character in _curr_phrase["setpartymemberlevel"]:
			var character_name = character
			var level = _curr_phrase["setpartymemberlevel"][character]
			if character == "leader":
				character_name = global.party[0].get_name()
			globaldata.characters[character_name].set_level(level)

	# setpartyleader: String # sets the party leader
	# ==example==
	# setpartyleader: ninten
	if _curr_phrase.has("setpartyleader"):
		global.set_party_leader(_curr_phrase["setpartyleader"])
	
	# open_shop: String # opens a shop menu
	# ==example==
	# open_shop: podunk_drug_store
	if _curr_phrase.has("open_shop"):
		uiManager.open_shop(_curr_phrase.open_shop, true, funcref(self, "_try_resume_dialogue"))
	
	# open_nosell_shop: String # opens a shop menu without the option to sell
	if _curr_phrase.has("open_nosell_shop"):
		uiManager.open_shop(_curr_phrase.open_nosell_shop, false, funcref(self, "_try_resume_dialogue"))
	
	# open_storage: any # Opens the storage menu
	if _curr_phrase.get("open_storage", false):
		uiManager.open_storage(false, funcref(self, "_try_resume_dialogue"))
	
	# use_atm: any # Opens the atm menu
	if _curr_phrase.get("use_atm", false):
		uiManager.open_atm(funcref(self, "_try_resume_dialogue"))
	
	# keyboard: String # Opens the keyboard menu (used for when the player enters their name)
	# ==example==
	# keyboard: playername # Opens the menu to enter the player's name
	if _curr_phrase.has("keyboard"):
		uiManager.open_keyboard(_curr_phrase["keyboard"], funcref(self, "_try_resume_dialogue"))
	
	# open_ocarina: any # opens the ocarina menu
	if _curr_phrase.get("open_ocarina"):
		uiManager.open_ocarina_screen(funcref(self, "_try_resume_dialogue"))
		uiManager.toggle_black_bars(false)
	
	# open_reticle_map: String # Opens the map with a controllable reticle 
	# (meant to be used in the duncan's factory missile launching sequence)
	# (UNUSED IN FINAL GAME)
#	if _curr_phrase.has("open_reticle_map"):
#		uiManager.open_map_screen(_curr_phrase["open_reticle_map"], _curr_phrase["open_reticle_map"], true, funcref(self, "_try_resume_dialogue"))
#		uiManager.toggle_black_bars(false)

	# removeitem: String # Removes the first occurence of the item in the player's inventory
	if _curr_phrase.has("removeitem"):
		if Inventory.party_has_item(_curr_phrase["removeitem"]):
			Inventory.remove_item_from_party(_curr_phrase["removeitem"])
	
	# removeitem: String # Removes the first occurence of the item in the player's inventory
	if _curr_phrase.has("addstorageitem"):
		globaldata.storage.add_item_by_name(_curr_phrase["addstorageitem"])
	
	# transformitem: String # Transforms all items in the player's inventory specified here into their transform item 
	# (Used for Red Herbs to turn into Magic Herbs)
	if _curr_phrase.has("transformitem"):
		Inventory.transform_items_for_all(_curr_phrase["transformitem"])
	
	# repairitem: String # repairs a single one of a specific party member's available to repair items
	# usually reserved for lloyd
	if _curr_phrase.has("repairitem"):
		var char_value = _curr_phrase["repairitem"]
		for inv_holder in _get_party_mem_from_dict(char_value, true):
			var new_item: Item = inv_holder.inv.repair_one_item()
			if new_item != null:
				global.item = new_item
				break
	
	# startbattle:# Starts the battle with the specified actors after the cutscene ends
		# battler: Array
			# [enemyname]: [actorname] | null
				# [enemyname] is the name of the enemy the actor should turn into when the battle starts
				# [actorname] Which actor should turn into the battler. Can also just be kept as null if you don't want the enemy to come from an actor.
		# actorskeep: Array
			# [actorname]: bool # Deletes the actor if set to false when the battle ends
		# wincutscene: String # Play cutscene after winning (1) the incoming battle
		# fleecutscene: String # Play cutscene after fleeing (0) the incoming battle
		# losecutscene: String # Play cutscene after losing (-1) the incoming battle
		# winflag: String # Set a flag to true after winning the incoming battle
	if _curr_phrase.has("startbattle"):
		var battle = _curr_phrase["startbattle"]
		if battle.has("battlers"):
			var enemies = battle["battlers"]
			for dict in enemies:
				for enemy in dict:
					var actor = dict[enemy]
					var battler = Enemy.new(enemy)
					var actor_node : Actor
					print("enemy " + enemy)
					print("actor " + actor)
					if actor != null:
						if actor == "talker":
							actor_node = global.talker
						else:
							actor_node = _actors[actor]
						actor_node.add_battle(battler)
					else:
						uiManager.add_on_screen_enemy(battler, null)
		
		if battle.has("actorskeep"):
			for actor in battle["actorskeep"]:
				_actors[actor].keepAfterBattle = battle["actorskeep"][actor]
		
		# Can’t use BattleSystem.Result enum because of those stupid cyclic dependencies
		if battle.has("wincutscene"):
			_post_battle_cutscenes[1] = battle["wincutscene"]
		if battle.has("fleecutscene"):
			_post_battle_cutscenes[0] = battle["fleecutscene"]
		if battle.has("losecutscene"):
			_post_battle_cutscenes[-1] = battle["losecutscene"]
		
		if battle.has("winflag"):
			_battle_win_flag = battle["winflag"]
		
		_queued_battle = true
		print("queuing battle")
	
	# learnskills: # Makes one or more party members learn a skill
		# [partymembername]: String | all # The party member and the name of the skill to learn. If set to "all", the party member will learn all of its skills.
	if _curr_phrase.has("learnskills"):
		var skill_per_members = _curr_phrase["learnskills"]
		for member in skill_per_members:
			var skill = skill_per_members[member]
			if skill == "all":
				for existing_skill in globaldata.get_all_battle_skills():
					globaldata.characters[member].add_skill(existing_skill)
			else:
				globaldata.characters[member].add_skill(skill)
	
	
	
	if !_curr_phrase.has("text") and !_curr_phrase.has("wait") and !_curr_phrase.has("autowait"):
		_next_phrase()

func _get_party_mem_from_dict(yaml_value: String, include_key_items := false) -> Array:
	var ret
	if yaml_value == "all":
		ret = global.party.duplicate()
	else:
		ret = [Inventory.get_inventory_holder(yaml_value)]
	if include_key_items:
		ret += [Inventory.get_inventory_holder(Inventory.INV_NAME_KEY)]
	return ret

func _add_dialog_options():
	# Parse Options
	# options:
		# [optionName]: int # The name of the option, and the phrase number it should send you to
		# cancel: int # Use "cancel" for the option if the player presses the cancel button
		# chk[partymember]: int # Use "chk[partymember]" to add an option based on a party member's name 
		# (chkninten, chklloyd, chkana, chkteddy, chkpippi)
	if _curr_phrase.has("options"):
		for i in _options_grid.get_children():
			i.hide()
		_options.clear()
		_print_new_line()
		var optionNode = load("res://Nodes/Ui/DialogueOptions.tscn")
		_options_count = 0

		var visibleOptions = {}

		for i in _curr_phrase["options"]:
			var nickname = ""
			var canAppend = true
			if i == "chkninten" or i == "chklloyd" or i == "chkana" or i == "chkteddy" or i == "chkpippi":
				var actualName
				canAppend = false
				nickname = i.replace("chk", "")
				for member in global.party.size():
					if global.party[member].get_name() == nickname:
						nickname = global.party[member].get_nickname()
						canAppend = true
						break
			if nickname == "":
				nickname = i
			if canAppend and i != "cancel":
				# Bulding a dictionary with all the _options that will actually appear in the dialogue box
				visibleOptions[i] = nickname

		# Now we know the exact number of visible _options because they are stored inside visibleOptions
		_options_count = visibleOptions.size()

		if _options_count == 4:					# 2×2 layout if 4 _options
			_options_grid.columns = 2
		else:
			_options_grid.columns = 3
		if _options_count > 3:
			_print_new_line()

		# The nodes already exist, we’re just showing them
		# (it works better that way, especially the cursor positionning)
		var idx = 0
		for i in visibleOptions:
			var option = _options_grid.get_child(idx)
			var nickname = visibleOptions[i]
			option.text = nickname
			option.set_name(nickname)
			option.show()
			_options.append(i)
			idx += 1

		$Dialoguebox/Arrow.show()
		$Dialoguebox/Arrow.on = true
		$Dialoguebox/Arrow.set_cursor_from_index(0, false)
		_options_grid.show()
		_cursor_down_sprite.hide()
	else:
		$Dialoguebox/Arrow.hide()
		$Dialoguebox/Arrow.on = false
		_options_grid.hide()

func _try_resume_dialogue(result = 0): # The result parameter can be any type, not just int
	if _finished:
		_end_dialogue()
	else:
		_sub_menu_result = result
		uiManager.toggle_black_bars(true)
		_next_phrase()

# Override
func _end_dialogue():
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	_clear_dialogue()
	
	global.set_phone_location("")
	
	$AudioStreamPlayer.volume_db = -80
	_dialogue_label.hide()
	if is_instance_valid(global.talker) and global.talker != null:
		global.talker.stop_interaction()
	global.talker = null
	if _name_label.text != "":
		$NameAnim.play("Close")
	uiManager.get_cash_box().close()
	uiManager.set_telepathy_effect(false)
	
	if _actors.size() != 0:
		for i in _actors:
			if !_queued_battle:
				_actors[i].update_npcs()
			elif !_actors[i].drafted:
				_actors[i].update_npcs()
			else:
				_actors[i].unmake_persistent()
		
		#update partyMember path
		if global.partySpace.size() > 1:
			var partyMembers = global.partyObjects.duplicate()
			
			partyMembers.invert()
			for i in global.partySpace.size():
				global.partySpace.push_front(partyMembers[0].position)
				global.partySpace.pop_back()
			
			for i in partyMembers.size() - 1:
				var maxDist = round(max(abs(partyMembers[i].position.x-partyMembers[i + 1].position.x), abs(partyMembers[i].position.y-partyMembers[i + 1].position.y)))
				if maxDist > 0:
					for dist in maxDist + 1:
						global.partySpace.push_front(lerp(partyMembers[i].position, partyMembers[i+1].position.round(), (dist+1)/maxDist))
						global.partySpace.pop_back()
				
				partyMembers[i].set_physics_process(true)
				partyMembers[i].find_path()
				partyMembers[i].active = true
	
	uiManager.update_key_indicator()
	global.emit_signal("cutscene_ended")
	global.in_cutscene = false
	_phrase_num = "0"
	_close_dialog_box()
	emit_signal("done", _dialog_response)
	if _queued_battle:
		uiManager.start_battle(0, false, [], _post_battle_cutscenes, _battle_win_flag)
		if global.currentCamera.tween: global.currentCamera.tween.pause()
	else:
		global.currentCamera.return_camera(0.5)
		global.currentCamera.return_offset(0.5)
		if _set_respawn:
			global.set_respawn()

func _clear_dialogue():
	_dialogue_label.bbcode_text = ""
	_bullet_label.bbcode_text = ""
	_dialogue_label.visible_characters = 0

# Override
func _next_phrase(with_sound := false):
	_dialog_response = _curr_phrase.get("set_response", _dialog_response)
	
	
	# if: Array # Checks conditions, and if all or one of these conditions are true, goes to another goto. Defaults to checking if all are true unless "or" is present
		# leader: String # Check if the leader is a certain character
		# flags: # Checks flags and their value
			# [flagname]: bool # Checks the flag and if it should be true or false
		# hascash: int # Checks if the player has a certain amount of money on hand
		# invspace: bool # Check if the player does or doesn't have enough inventory space
		# hasitem: String # Check if the player has a certain item
		# hasinstorage: String # Check if an item is in storage
		# hasrepairableitem: String # Check if the player has a repairable item
		# haspartymembers: Array # Check if the player has certain party members (including party NPCs)
			# [partymembernames]: bool # Whether this party member should be present or not
		# iscolliding: bool # Check if the player's raycast is colliding with anything
		# submenuresult: String # Check if the submenu is of a certain type
		# partySize: # Compares the number of party members with a size 
			# size: int # The number the party size should be compared with (example: partySize > 1)
			# symbol: = < > <= >= # The symbol with which to compare the number of party members with 
		# hasstatus: # check if a party member has a status ailment
			# character: String # The name of the party member
			# status: String # The status it should check
		
		# goto: String # Which phrase to go to if the conditions are met
		# or: any # If present, the if will only check for at least one of the conditions to be true
	if _curr_phrase.has("if"):
		var all_ifs = _curr_phrase["if"]
		if !all_ifs is Array:
			all_ifs = [_curr_phrase["if"]]
		
		for curr_if in all_ifs:
			var condition := true
			for cond in curr_if:
				var is_actual_condition = !cond in ["or", "goto", "redirect"]
				if curr_if.has("or") and is_actual_condition:
					condition = true
				# Checks if the player has a certain amount of money on hand
				if "hascash" in cond:
					if globaldata.cash < curr_if["hascash"]:
						condition = false
						if !curr_if.has("or"):
							break
				#Check if the player does or doesn't have enough inventory space
				if "invspace" in cond:
					if Inventory.has_inventory_space() != curr_if["invspace"]:
						condition = false
						if !curr_if.has("or"):
							break
				#Check if the player has a certain item
				if "hasitem" in cond:
					if !Inventory.party_has_item(curr_if[cond]):
						condition = false
						if !curr_if.has("or"):
							break
				#Check if an item is in storage
				if "hasinstorage" in cond:
					if !globaldata.storage.has_item(curr_if[cond]):
						condition = false
						if !curr_if.has("or"):
							break
				#Check if the player has a repairable item
				if "hasrepairableitem" in cond:
					var char_value = curr_if[cond]
					var item = null
					for inv_holder in _get_party_mem_from_dict(char_value, true):
						item = inv_holder.inv.find_repairable_item()
						if item:
							global.item = item
							break
					if !item:
						condition = false
						if !curr_if.has("or"):
							break
				#Check if the leader is a certain character
				if "leader" in cond:
					if global.party[0].get_name() != curr_if["leader"]:
						condition = false
						if !curr_if.has("or"):
							break
				#Check if the player has certain party members (including party NPCs)
				if "haspartymembers" in cond:
					var hasPartyMember = true
					for memberName in curr_if["haspartymembers"]:
						var hasMember = false
						var all_party = global.party + global.partyNpcs
						for member in all_party.size():
							if all_party[member].get_name() == memberName:
								hasMember = true
								if !curr_if.has("or"):
									break
						if hasMember != curr_if["haspartymembers"][memberName]:
							condition = false
							hasPartyMember = false
							if !curr_if.has("or"):
								break
					if !hasPartyMember:
						if !curr_if.has("or"):
							break
				if "iscolliding" in cond:
					if global.get_player().is_colliding() != curr_if["iscolliding"]:
						condition = false
						if !curr_if.has("or"):
							break
				if "submenuresult" in cond:
					if _sub_menu_result != curr_if["submenuresult"]:
						condition = false
						if !curr_if.has("or"):
							break
				# Compares the number of party members with a size
				if "partysize" in cond:
					condition = false
					match curr_if[cond]["symbol"]:
						">":
							if global.party.size() > curr_if[cond]["size"]:
								condition = true
						">=":
							if global.party.size() >= curr_if[cond]["size"]:
								condition = true
						"<":
							if global.party.size() < curr_if[cond]["size"]:
								condition = true
						"<=":
							if global.party.size() <= curr_if[cond]["size"]:
								condition = true
						"=":
							if global.party.size() == curr_if[cond]["size"]:
								condition = true
					if !condition:
						if !curr_if.has("or"):
							break
				#Check if character has status
				if "hasstatus" in cond:
					var has_status = true
					var status = curr_if[cond]["status"]
					var character = curr_if[cond]["character"]
					for member in global.party.size():
						if global.party[member].get_name() == character:
							if status != "":
								if !global.party[member].has_status(status.to_lower()):
									condition = false
									has_status = false
									break
							else:
								if global.party[member].get_status_ailments().size() != 0:
									condition = false
									has_status = false
									break
					if !has_status:
						if !curr_if.has("or"):
							break
							
				#Check if certain flags in globalData are true or false
				if "flags" in cond:
					var flag_correct = true
					for flagName in curr_if["flags"]:
						if globaldata.flags[flagName] != curr_if["flags"][flagName]:
							condition = false
							flag_correct = false
							if !curr_if.has("or"):
								break
					if !flag_correct:
						if !"or" in curr_if:
							break
				if curr_if.has("or") and is_actual_condition:
					if condition:
						break					

			if condition: #check if all of these are true to go to this "goto"
				_handle_gotos(curr_if, with_sound)
				return

	if _curr_phrase.has("redirect") or _curr_phrase.has("goto"):
		_handle_gotos(_curr_phrase, with_sound)
	else:
		_end_dialogue()

func _handle_gotos(phrase: Dictionary, with_sound := false):
	if phrase.has("redirect"):
		if with_sound:
			$InputSound.play()
		_phrase_num = "0"
		_dialog = YAMLParser.parse_file("res://Data/Dialogue/%s.yaml" % phrase["redirect"])
		_handle_phrase()
	elif phrase.has("goto"):
		if with_sound:
			$InputSound.play()
		_phrase_num = phrase["goto"]
		_handle_phrase()

func get_actors() -> Dictionary:
	return _actors

# Override
func _show_box(show: bool, sfx = true):
	if show and !_dialogue_box_shown:
		_dialogue_box_shown = true
		$AnimationPlayer.play("Open")
		if sfx:
			audioManager.play_sfx_by_name("menu_open", "menu_open")
		set_process_input(true)
		set_physics_process(true)
	if !show and _dialogue_box_shown:
		_dialogue_box_shown = false
		$AnimationPlayer.play("Close")
		if sfx:
			audioManager.play_sfx_by_name("menu_close", "menu_close")
		_clear_dialogue()
		set_process_input(false)
		set_physics_process(false)

func _set_nametag():
	var new_size = _name_label.rect_size.x + 20
	var old_size = $Dialoguebox/Namebox.rect_size.x 
	if new_size != old_size:
		create_tween().tween_property($Dialoguebox/Namebox, "rect_size", Vector2(new_size, 47), 0.2) \
				.from(Vector2(old_size, 47)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		$Dialoguebox/Namebox.rect_size.x = _name_label.rect_size.x + 20

func _close_dialog_box():
	if $Dialoguebox.rect_position.y != 180:
		$AnimationPlayer.play("Close")
		audioManager.play_sfx_by_name("menu_close", "menu_close")
		yield($AnimationPlayer, "animation_finished")
	uiManager.remove_ui(self)

func _on_WaitTimer_timeout():
	if _finished:
		_cursor_down_sprite.show()
	if _auto_advance:
		_next_phrase()

func _change_scene(targetScene):
	global.scene_transition.goto_scene("res://Maps/" + targetScene + ".tscn")
	
	var cam = global.currentCamera
	cam.limit_top = -10000000
	cam.limit_left = -10000000
	cam.limit_right = 10000000
	cam.limit_bottom = 10000000

func _actor_strings_to_node(actors_strings) -> Node2D:
	if !actors_strings is Array:
		actors_strings = [actors_strings]
	
	for actor_str in actors_strings:
		if actor_str == "leader" or actor_str == "player":
			return global.get_player()
		elif actor_str == "talker":
			return global.talker
		elif actor_str in globaldata.characters:
			var party = global.party + global.partyNpcs
			for i in global.partyObjects.size():
				if party[i].get_name() == str(actor_str):
					return global.partyObjects[i]
		elif "party." in actor_str:
			var split_str = actor_str.split(".")
			var idx = int(split_str[1])
			if global.partyObjects.size() > idx:
				return global.partyObjects[idx]
			else:
				return null
		else:
			var node = global.currentScene.get_node_or_null(str2var(actor_str))
			if node != null:
				return node
	return null

func _add_partymember_actors(actors):
	var present_party_members := {}
	var present_party_npcs := {}
	for actors_strings in actors:
		if typeof(actors_strings) != TYPE_ARRAY:
			actors_strings = [actors_strings]
		for actor_str in actors_strings:
			var actor_path = actors[actor_str]
			if actor_path in globaldata.characters:
				if globaldata.characters[actor_path].get_character_type() == Character.Type.PARTY_NPC:
					present_party_npcs[actor_path] = true
					break
				elif globaldata.characters[actor_path].get_character_type() == Character.Type.PARTY_MEMBER:
					present_party_members[actor_path] = true
					break
	set_party_members(present_party_members)
	set_party_npcs(present_party_npcs)
	global.create_party_followers()
	

func set_party_members(party_members: Dictionary):
	for i in party_members:
		if globaldata.characters.get(i) in global.party:
			if global.partyObjects.size() > 1 and !party_members[i]:
				global.party.erase(globaldata.characters.get(i))
		elif party_members[i]:
			global.party.append(globaldata.characters.get(i)) 
	

func set_party_npcs(party_npcs: Dictionary):
	for i in party_npcs:
		if globaldata.characters.get(i) in global.partyNpcs:
			if global.partyObjects.size() > 1 and !party_npcs[i]:
				global.partyNpcs.erase(globaldata.characters.get(i))
		elif party_npcs[i]:
			global.partyNpcs.append(globaldata.characters.get(i)) 

func _change_flags(flags, value):
	if !flags is Array:
		flags = [flags]
	for flag in flags:
		globaldata.set_flag(flag, value)
