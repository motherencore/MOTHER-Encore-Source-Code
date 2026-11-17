# BORN TO DIE
# WORLD IS A FUCK
# 青鬼 Kill Em All 2008
# I am blue demon
# 410,757,864,530 DEAD NINTENS

# Okay so this is what made the infamous Ao Oni jumpscare of the 0.3.0.1 update
# that scared the hell out of so many people and made others laugh work (actually,
# there's some important code in other scripts, you should find it by searching
# "AoOni" in Search in files). The idea and the sprites were made by Benichi,
# and the programming was made by Danionel (your most humble servant).

# Every time you entered a room, there would be a 1/1000 chance of Ao Oni appearing.
# Had the probability been met, it would chase you (it has the same running speed as the player),
# and if it touched you, you would get an instant game over. Then, your browser would
# open an image of a screaming purple Luigi (this was actually my idea, not Benichi's).

# It was purposely added in the game without any of the devs' knowledge and, with
# the exception of some people that were told about it by Benichi, only one person
# in the dev team noticed it. Luckily, he did not snitch on us and he even helped
# me to fix something that was making it not work.

# And so the update came, and we were victorious. Ao Oni was in Mother Encore.
# Shout out to the first person who encountered Ao Oni and reported it, rainbowspoon.
# Well, I know this is not why you are here, so...
# Let's get down to business.


# HOW TO REACTIVATE AO ONI

# So, you need to go res://Scripts/Main/Door.gd. There, you'll need to go to line 182
# (or just search "Ao oni code" in the search tab). You have to uncomment all the
# commented lines below "Ao oni code". And that would be it. Ao Oni. Note that it
# was intentionally programmed so it wouldn't appear in debug builds, so if you don't
# delete the "!OS.is_debug_build()" part, it will appear only on non-debug exported builds.

# If you want to straight up making it appear, just lower the range at "rand.randi_range"
# or just define the variable random as 1.

# Ummm yeah that's it byeeeeeeeeee

extends "res://Scripts/Main/Basic Enemy.gd"
var anuelaa = load("res://Nodes/Overworld/Door.tscn")
var firstAppearance = true
var exitCount = 0
var thePosition

func _ready():
	audioManager.stop_all_music_players()
	exitCount = 0
	firstAppearance = true
	modulate = Color.transparent
	thePosition = global.get_player().position - (global.get_player().get_direction() * 10)
	position = thePosition
	new_pos = thePosition
	start_pos = thePosition
	sprite = "AoOni"
	$CharacterSprite.animationTree.active = true
	set_spritesheet()
	set_physics_process(true)
	$Shadow.visible = shadow
	_input_vector.x = round(rand_range(-1, 1))
	_input_vector.y = round(rand_range(-1, 1))
	if walk_frequency != 0:
		$WanderRadius/Timer.wait_time = rand_range(0.1, walk_frequency)
		$WanderRadius/Timer.start()
	state = WANDER

func set_spritesheet():
	var path = "res://Nodes/Overworld/Enemies/AoOni.png"
	character_sprite.set_sprite(path)
	var animPath = ""
	if anim == "":
		animPath = "res://Data/Animations/BasicEnemy.yaml"
	else:
		animPath = "res://Data/Animations/" + anim + ".yaml"
	character_sprite.set_animation(animPath, connections)
	
	character_sprite.set_spritesheet()
	character_sprite.set_sprite_offset(Vector2(spriteOffset[0], spriteOffset[1]))
	_vector_sprite_offset = character_sprite.offset

func _physics_process(delta):
	if !global.get_player().is_paused():
		$CharacterSprite.animationTree.active = true
		eventRayCaster.look_at(global.get_player().global_position + global.get_player().get_node("CollisionShape2D").position * 2)
		if eventRayCaster.get_collider() == global.get_player() and position.distance_to(start_pos) <= maxDistance:
			if state != CHASE and state != STUNNED:
				if (_seeing == true or (global.get_player().is_running() and global.get_player().has_substantial_movement())) and state != CHASE and !_blind and !firstAppearance:
					start_chase()
		var oldPos = position
		match state:
			WANDER:
				if new_pos != null and position != new_pos:
					_input_vector = position.direction_to(new_pos)
					global_position = global_position.move_toward(new_pos, delta * maxSpeed)
					$CharacterSprite.travel("Walk")
				else:
					$CharacterSprite.travel("Idle")
			RETURN:
				if $Timer.time_left == 0:
					_input_vector = position.direction_to(new_pos)
					position = position.move_toward(new_pos, maxSpeed * delta)
					$CharacterSprite.travel("Walk")
				if (position == new_pos):
					_input_vector = Vector2.ZERO
					state = WANDER
					$CharacterSprite.travel("Idle")
			CHASE:
				if _underlevel:
					_input_vector = global.partyObjects[int(global.partyObjects.size()/2)].global_position.direction_to(global_position)
				else:
					_input_vector = global_position.direction_to(global.partyObjects[int(global.partyObjects.size()/2)].global_position)
				if $ChaseTimer.time_left == 0:
					velocity = velocity.move_toward(_input_vector * maxSpeed, acceleration * delta)
					$CharacterSprite.travel("Walk")
		_input_vector = global_position.direction_to(global.partyObjects[int(global.partyObjects.size()/2)].global_position)
		if $ChaseTimer.time_left == 0:
			velocity = velocity.move_toward(_input_vector * maxSpeed, acceleration * delta)
			$CharacterSprite.travel("Walk")
		
		_input_vector = _input_vector.round()
		
		velocity = move_and_slide(velocity)
		_knockback = _knockback.move_toward(Vector2.ZERO, 200 * delta)
		_knockback = move_and_slide(_knockback)
		
		position = position.round()
		
		var newDirection = position.direction_to(new_pos)
		if oldPos != position and (newDirection.x == 0 or newDirection.x == 0):
			_direction = oldPos.direction_to(position)
		else:
			_direction = _input_vector
		#if character_sprite.offset.y == spriteOffset[1]:
		$CharacterSprite.blend_position(_direction)
	else:
		$CharacterSprite.animationTree.active = true

func _move():
	if !firstAppearance:
		var oldPos = position
		
		var x = position.x
		var y = position.y
		
		if randi()%2 == 1: 
			x = rand_range(start_pos.x, start_pos.x+$WanderRadius/CollisionShape2D2.shape.radius)
		else:
			y = rand_range(start_pos.y, start_pos.y+$WanderRadius/CollisionShape2D2.shape.radius)
		var travelPos = Vector2(round(x),round(y))
		$RayCast2D.enabled = true
		$RayCast2D.set_cast_to(travelPos - position)
		var ample_distance_x = travelPos.x - oldPos.x
		var ample_distance_y = travelPos.y - oldPos.y
		if !$RayCast2D.is_colliding() and (ample_distance_x > 8 or ample_distance_x <-8 or ample_distance_y > 8 or ample_distance_y <-8):
			new_pos = travelPos
			_input_vector = oldPos.direction_to(new_pos)
		else:
			$RayCast2D.enabled = false
			_move()

func jump():
	$CharacterSprite.travel("Walk")
	_tween.interpolate_property($CharacterSprite, "offset",
		_vector_sprite_offset, _vector_sprite_offset - Vector2(0, 5), 0.1,
		Tween.TRANS_LINEAR, Tween.EASE_OUT)
	_tween.interpolate_property($CharacterSprite, "offset",
		_vector_sprite_offset - Vector2(0, 5), _vector_sprite_offset, 0.1,
		Tween.TRANS_LINEAR, Tween.EASE_IN, 0.1)
	_tween.start()

func start_chase():
	if (state == WANDER or state == RETURN) and !emotes.animaPlayer.is_playing() and !global.get_player().is_paused():
		state = CHASE
		if _underlevel:
			emotes.animaPlayer.play("blueExclamation")
		else:
			emotes.animaPlayer.play("exclamation")
		$ChaseTimer.start()

func _on_interact_body_entered(body):
	if visible and (body.name == "player" or "PartyFollower" in body.name) and !uiManager.is_in_cutscene() and !firstAppearance:
		if global.get_player().is_paused():
			yield(global.get_player(), "unpaused")
		if enemy != "":
			$interact/CollisionShape2D.set_deferred("disabled", true)
			chase_stop()
			global.get_player().game_over()
			audioManager.stop_all_music_players()
			OS.shell_open("https://static.wikia.nocookie.net/rfti/images/6/65/Wega.png/revision/latest?cb=20230213144525")

func _on_Hurtbox_area_entered(area):
	if !global.get_player().is_paused() and !uiManager.is_in_cutscene():
		if area.get_collision_layer_bit(1) == true or area.get_collision_layer_bit(3) == true or area.get_collision_layer_bit(7) == true:
			drafted = true
			$AudioStreamPlayer.play()
			global.start_joy_vibration(0, 0.6, 0.6, 0.2)
			global.currentCamera.shake_camera(3, 0.1, global.get_player().position.direction_to(position))
			var bash = globaldata.get_battle_skill(globaldata.SKILL_BASH)
			var mod = global.party[0].get_stat(Character.OFFENSE)
			var defense := 50
			var val := 0
			val = max(1, bash.damage_or_heal + mod - (defense/2.0))
			# apply variance
			val = floor(val + (randf() * bash.variance) - bash.variance/2.0)
			val = int(round(val))
			if global.party[0].is_incapacitated():
				val = int(round(val/4))
			_tween.interpolate_property(self, "position",
				position, position - (_direction * 30), 0.5,
				Tween.TRANS_LINEAR, Tween.EASE_OUT)
			_tween.start()
			uiManager.create_flying_num(val, global_position)
			_knockback = global.get_player().get_direction() * 120
			$DamageAnimation.play("Flash")
			yield($DamageAnimation,"animation_finished")
			#if startingHP <= 0:
			#	audioManager.stop_all_music_players()
			#	get_parent().remove_child(self)
		elif area.get_collision_layer_bit(2) == true:
			#lloyd stun gun
			area.get_parent().create_spark("Explosion")
			area.get_parent().disappear()
			stun()

func _on_screen_exited():
	thePosition = global.get_player().position - (global.get_player().get_direction() * 10)
	yield(get_tree().create_timer(.7), "timeout")
	position = thePosition
	new_pos = thePosition
	start_pos = thePosition
	exitCount += 1
	if exitCount == 5:
		audioManager.stop_all_music_players()
		get_parent().remove_child(self)

func activate():
	set_physics_process(true)
	show()
	emotes.show()
	#startingHP = 100
	velocity = Vector2.ZERO

func _on_Enemy_tree_exiting():
	exitCount += 1
	if exitCount == 5:
		audioManager.stop_all_music_players()
		get_parent().remove_child(self)

func _on_SpawnArea_body_exited(body):
	if body == global.get_player() and firstAppearance:
		firstAppearance = false
		modulate = Color.white
		audioManager.play_music_on_latest_player("AoOni.mp3", "AoOni.mp3")
		start_chase()
