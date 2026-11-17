extends Control

# Emitted when a music player is updated or the songs they're playing is updated
signal music_players_updated

enum { MUSIC, FILTER, MORE_FILTER }

const BUSES = ["Music", "Filter", "More Filter"]
const SILENT_SOUND_THRESHOLD = -80

const CHANNELS = {
	OVERWORLD = "Overworld", 
	BATTLE = "Battle", 
	MENU = "Menu", 
	CUTSCENE = "Cutscene",
}

const CROSSFADE_CHANNEL = "Crossfade_"
const MAX_CROSSFADES = 64 # I doubt we'll ever reach a point where the game will need 64 crossfades but it doesn't hurt to be safe! Also just to prevent infinite crossfades from existing.

const MUSIC_RESOURCE_PATH = "res://Audio/Music/"

var _tweens := {}

var _sound_effects := {
	"menu_open": preload("res://Audio/Sound effects/M3/menu_open.wav"),
	"menu_open2": preload("res://Audio/Sound effects/M3/menu_open2.wav"),
	"menu_close": preload("res://Audio/Sound effects/M3/menu_close.wav"),
	"menu_close2": preload("res://Audio/Sound effects/M3/menu_close2.wav"),
	"back": preload("res://Audio/Sound effects/M3/curshoriz.wav"),
	"cursor1": preload("res://Audio/Sound effects/Cursor 1.mp3"),
	"cursor2": preload("res://Audio/Sound effects/Cursor 2.mp3"),
	"restricted": preload("res://Audio/Sound effects/M3/bump.wav"),
	"equip": preload("res://Audio/Sound effects/M3/equip.wav"),
	"clear": preload("res://Audio/Sound effects/EB/close.wav"),
	"timeout": preload("res://Audio/Sound effects/EB/dodge.wav"),
	"cash": preload("res://Audio/Sound effects/M3/register.wav"),
	"save": preload("res://Audio/Sound effects/Save.mp3"),
}

# The previous overworld track playback positions are used to record the playback positions of overworld songs when they stop playing.
# When the overworld track plays again, it can play again from the same playback position as when it stopped previously.
# We only need to hold a certain amount of tracks in the memory because we only need to do it for songs that you just listened to recently. 
const MAX_PREVIOUS_OVERWORLD_TRACK_MEMORY := 5
var _previous_overworld_track_memory := [] 
var _previous_overworld_track_playback_positions := {}

# Music changers are the Area2Ds which says what song should play when the player is inside of them.
var _music_changers := []
var _previous_music_changer: MusicChanger
var _previous_music_changer_fadeout_length: float = 1.5
var _overworld_music_changed := false

const _DEFAULT_FADEOUT_LENGTH := 1.5

var _sfx_pitch_scale := 1.0

var overworld_battle_music := false

func _ready():
	for channel in CHANNELS:
		_add_music_player(CHANNELS[channel])

func add_music_changer(music_changer: Node2D):
	if !music_changer in _music_changers:
		_music_changers.push_front(music_changer)
		_overworld_music_changed = true

func remove_music_changer(music_changer: MusicChanger):
	if music_changer in _music_changers:
		_music_changers.erase(music_changer)
		_overworld_music_changed = true

func remove_all_music_changers():
	_music_changers.clear()
	_overworld_music_changed = true

# In the event that two or more music changer events happen at the same time, we only need to take into account one of these events.
func _physics_process(_delta):
	if _overworld_music_changed and !global.changing_scenes:
		_on_music_changers_updated()
		_overworld_music_changed = false

func _reset_previous_music_changer():
	_previous_music_changer = null
	_previous_music_changer_fadeout_length = _DEFAULT_FADEOUT_LENGTH

func _on_music_changers_updated():
	var overworld_music_player = get_music_player_by_name(CHANNELS.OVERWORLD) as AudioStreamPlayer
	if _music_changers.size() == 0:
		crossfadeout_overworld_music(_previous_music_changer_fadeout_length)
		_reset_previous_music_changer()
		return
	
	if !is_instance_valid(_previous_music_changer):
		_reset_previous_music_changer()
	
	var main_music_changer = _music_changers[0] as MusicChanger
	if _previous_music_changer == main_music_changer:
		return
	
	var fadein_length = main_music_changer.fadein_length
	var song = main_music_changer.loop
	var volume_db = main_music_changer.volume_db
	
	var active_crossfade_player = _get_crossfade_music_player_playing_song(song)
	var overworld_song_playing = _is_music_player_audible(overworld_music_player) or active_crossfade_player
	var new_song_same_as_previous = _is_song_playing_on_music_player(overworld_music_player, song)
	
	if _previous_music_changer:
		# Checks if there was a music changer previously
		var overworld_playback_position: float = overworld_music_player.get_playback_position() if _previous_music_changer.diegetic and _is_music_player_audible(overworld_music_player) else 0.0
		
		if overworld_song_playing and !new_song_same_as_previous:
			if active_crossfade_player:
				# If the song that's about to play is already playing within one of the crossfades,
				# We can just swap the crossfade's song back into the main overworld music player,
				# And swap the current overworld song into the crossfade player.
				_swap_music_players(overworld_music_player, active_crossfade_player)
				_fadeto_music_player(overworld_music_player, volume_db, fadein_length)
				_fadeout_music_player(active_crossfade_player, _previous_music_changer.fadeout_length)
			else:
				# Otherwise we just crossfadeout the current overworld song, and we play the new song in a later step
				crossfadeout_overworld_music(_previous_music_changer.fadeout_length)
		if new_song_same_as_previous:
			# If the song is already playing in the overworld music player, we just fade the song to the volume of the new music changer
			fadeto_music_player_by_name(CHANNELS.OVERWORLD, volume_db, fadein_length)
		elif !active_crossfade_player:
			# If the new song isn't already playing, and isn't playing in the crossfade players, we start playing the song and make it fade in.
			var use_previous_playback_position = !_previous_music_changer.diegetic
			play_music(CHANNELS.OVERWORLD, song, overworld_playback_position, use_previous_playback_position)
			_fadein_music_player(overworld_music_player, volume_db, fadein_length)
	else:
		# If we're starting fresh with no other music changers playing previously
		if active_crossfade_player:
			# If the song was already playing in one of the crossfade players
			# We move it back into the overworld music player
			_move_over_music_player(active_crossfade_player, overworld_music_player)
			_fadeto_music_player(overworld_music_player, volume_db, fadein_length)
		else:
			if overworld_song_playing and !new_song_same_as_previous:
				# Move over the old overworld song into crossfade
				crossfadeout_overworld_music(main_music_changer.fadeout_length)
			# Play the new music into the overworld music player
			play_music(CHANNELS.OVERWORLD, song, 0.0, true)
			overworld_music_player.volume_db = volume_db
	
	_previous_music_changer = main_music_changer
	_previous_music_changer_fadeout_length = _previous_music_changer.fadeout_length

# Instead of simply fading out the overworld music, we move it to a crossfade music player 
# so that any new overworld music can crossfade with the old overworld music.
# Crossfades are usually only used for overworld music.
func crossfadeout_overworld_music(fadeout_length: float):
	var music_player = get_music_player_by_name(CHANNELS.OVERWORLD)
	if _is_music_player_audible(music_player):
		var inactive_crossfade_player = _get_inactive_or_new_crossfade_music_player()
		_move_over_music_player(music_player, inactive_crossfade_player)
		_fadeout_music_player(inactive_crossfade_player, fadeout_length)

func _add_music_player(node_name: String) -> AudioStreamPlayer:
	var music_player = AudioStreamPlayer.new()
	music_player.bus = BUSES[MUSIC]
	$MusicPlayers.add_child(music_player)
	music_player.name = node_name
	
	emit_signal("music_players_updated")
	return music_player

func get_music_player_by_name(node_name: String) -> AudioStreamPlayer:
	return $MusicPlayers.get_node_or_null(node_name) as AudioStreamPlayer

func get_or_add_music_player_by_name(node_name: String) -> AudioStreamPlayer:
	var music_player = $MusicPlayers.get_node_or_null(node_name) as AudioStreamPlayer
	if !music_player:
		_add_music_player(node_name)
		music_player = get_music_player_by_name(node_name) as AudioStreamPlayer
	return music_player

func get_music_player_list() -> Array:
	return $MusicPlayers.get_children()

func get_music_player_list_with_name(name: String) -> Array:
	var list = []
	for i in get_music_player_list():
		if name in i.name:
			list.append(i)
	return list

# Plays a song to a music player with a certain name. Usually you should use the constant channels like CHANNELS.OVERWORLD, 
# but you can also use a music player with a different name if the basic ones aren't enough like for the ocarina music or level up music. 
# You can also set the start playback position, and whether or not to use the recorded playback position.
# The recorded playback position is used to replay an overworld track from the moment it stopped playing before.
func play_music(node_name: String, song: String, start := 0.0, use_recorded_playback_position := false) -> AudioStreamPlayer:
	var music_player: AudioStreamPlayer = get_or_add_music_player_by_name(node_name) as AudioStreamPlayer
	var path = MUSIC_RESOURCE_PATH + song
	var music_file = load(path)
	
	return _play_stream(music_player, music_file, start, use_recorded_playback_position)

# Plays another song on an audio player after it is done playing. 
# Obviously this won't work if the song that's already playing is looping.
func queue_music(node_name: String, song: String, start := 0.0):
	var music_player: AudioStreamPlayer = get_music_player_by_name(node_name) as AudioStreamPlayer
	if !music_player or !get_music_player_by_name(node_name).playing:
		play_music(node_name, song, start)
	if music_player:
		music_player.connect("finished", self, "play_music", [node_name, song, start], CONNECT_ONESHOT)

func _play_stream(music_player: AudioStreamPlayer, stream: AudioStream, start := 0.0, use_recorded_playback_position := false) -> AudioStreamPlayer:
	var node_name = music_player.name
	
	if music_player.stream != stream or !_is_music_player_audible(music_player):
		_kill_tween(node_name)
		
		if music_player.is_connected("finished", self, "play_music"):
			music_player.disconnect("finished", self, "play_music")
		
		if node_name == CHANNELS.OVERWORLD or CROSSFADE_CHANNEL in node_name:
			_record_music_player_playback_position(node_name)
			
			if use_recorded_playback_position and node_name == CHANNELS.OVERWORLD and stream in _previous_overworld_track_playback_positions:
				start = _previous_overworld_track_playback_positions[stream]
		
		music_player.stream = stream
		music_player.stream_paused = false
		music_player.volume_db = 0.0
		music_player.play(start)
	
	emit_signal("music_players_updated")
	
	return music_player

# Copies a music player to another one and overwrites it.
# Stop old can be used to say if the old music player should stop playing in the end
func _move_over_music_player(old_music_player: AudioStreamPlayer, new_music_player: AudioStreamPlayer, stop_old := true):
	_kill_tween(old_music_player.name)
	_kill_tween(new_music_player.name)
	_play_stream(new_music_player, old_music_player.stream, old_music_player.get_playback_position())
	if !old_music_player.playing: # For some reason setting the playing variable to true even if it's already true causes it to play from the start
		new_music_player.playing = false
	new_music_player.stream_paused = old_music_player.stream_paused
	new_music_player.volume_db = old_music_player.volume_db
	if stop_old:
		_stop_music_player(old_music_player)

# Switches the streams of two music players as well as their attributes
func _swap_music_players(old_music_player: AudioStreamPlayer, new_music_player: AudioStreamPlayer):
	var new_music_player_duplicate: AudioStreamPlayer = new_music_player.duplicate()
	new_music_player_duplicate.playing = new_music_player.playing
	new_music_player_duplicate.stream_paused = new_music_player.stream_paused
	new_music_player_duplicate.volume_db = new_music_player.volume_db
	new_music_player_duplicate.seek(new_music_player.get_playback_position())
	_move_over_music_player(old_music_player, new_music_player, false)
	_move_over_music_player(new_music_player_duplicate, old_music_player, false)

# Record playback position of an overworld or crossfade music player's stream so that we can replay the same stream from the same position as when it last stopped playing
func _record_music_player_playback_position(music_player: AudioStreamPlayer) -> void:
	var overworld_or_crossfade_list = []
	overworld_or_crossfade_list.append(get_music_player_by_name(CHANNELS.OVERWORLD))
	overworld_or_crossfade_list.append_array(get_music_player_list_with_name(CROSSFADE_CHANNEL))
	
	if music_player in overworld_or_crossfade_list:
		_previous_overworld_track_playback_positions[music_player.stream] = music_player.get_playback_position()
		if _previous_overworld_track_memory.has(music_player.stream):
			_previous_overworld_track_memory.erase(music_player.stream)
		_previous_overworld_track_memory.append(music_player.stream)
		if _previous_overworld_track_memory.size() > MAX_PREVIOUS_OVERWORLD_TRACK_MEMORY:
			_previous_overworld_track_playback_positions.erase(_previous_overworld_track_memory.pop_front())

func clear_previous_overworld_track_playback_positions() -> void:
	_previous_overworld_track_playback_positions.clear()
	_previous_overworld_track_memory.clear()

func muffle_music_player_by_name(node_name: String, level: int) -> void:
	var music_player = get_music_player_by_name(node_name)
	if music_player:
		music_player.bus = BUSES[level]

func get_music_player_playback_position_by_name(node_name: String) -> float:
	var music_player := $MusicPlayers.get_node_or_null(node_name) as AudioStreamPlayer
	if music_player != null:
		return music_player.get_playback_position()
	return 0.0

func set_music_player_volume_by_name(node_name: String, volume: float):
	var music_player = get_music_player_by_name(node_name)
	if music_player:
		music_player.volume_db = volume

func stop_music_player_by_name(node_name: String):
	var music_player = get_music_player_by_name(node_name)
	if music_player:
		_stop_music_player(music_player)

func stop_all_music_players():
	for music_player in get_music_player_list():
		_stop_music_player(music_player)

func _stop_music_player(music_player: AudioStreamPlayer):
	if music_player.is_connected("finished", self, "play_music"):
		music_player.disconnect("finished", self, "play_music")
	_record_music_player_playback_position(music_player)
	_kill_tween(music_player.name, true)
	music_player.playing = false

func pause_music_player_by_name(node_name: String):
	var music_player = get_music_player_by_name(node_name)
	if music_player: 
		_pause_music_player(music_player)

func pause_all_music_players():
	for music_player in get_music_player_list():
		_pause_music_player(music_player)

func _pause_music_player(music_player: AudioStreamPlayer):
	_kill_tween(music_player.name, true)
	music_player.stream_paused = true

# We don't have a "resume_all_music_players" cuz it would genuinely resume every song that is paused, 
# which would be unwise unless you wanted to blast your eardrums.
func resume_music_player_by_name(node_name: String):
	var music_player = get_music_player_by_name(node_name)
	if music_player: 
		music_player.stream_paused = false

# Tweens a music player's volume using an AudioTween. 
# AudioTweens are able to tween linear volume into volume_db
# so that the transition sounds more normal to the human ear.
func _tween_music_player(music_player: AudioStreamPlayer, end_volume: float, duration: float, override_tween := true) -> AudioTween:
	var node_name = music_player.name
	
	if _tweens.has(node_name) and is_instance_valid(_tweens[node_name]):
		if override_tween:
			_kill_tween(node_name)
		else:
			return _tweens[node_name]
	
	if music_player.volume_db == end_volume:
		return null
	
	var tween: AudioTween = AudioTween.new(music_player, end_volume, duration)
	_tweens[node_name] = tween
	
	return tween

func _kill_tween(node_name: String, goto_end := false) -> void:
	if _tweens.has(node_name) and is_instance_valid(_tweens[node_name]):
		var tween = _tweens[node_name] as AudioTween
		tween.kill(goto_end)
		
	_tweens.erase(node_name)

# Fades the volume from its current volume to SILENT
# Also stops the audio player once the fadeout ends
func fadeout_music_player_by_name(node_name: String, duration := 1.0, override_tween := true) -> void:
	var music_player = get_music_player_by_name(node_name) as AudioStreamPlayer
	if music_player:
		_fadeout_music_player(music_player, duration, override_tween)

func _fadeout_music_player(music_player: AudioStreamPlayer, duration: float, override_tween := true) -> void:
	_record_music_player_playback_position(music_player)
	var tween = _tween_music_player(music_player, SILENT_SOUND_THRESHOLD, duration, override_tween)
	if !tween:
		_on_fadeout_finished(music_player)
	elif !tween.is_connected("finished", self, "_on_fadeout_finished"):
		tween.connect("finished", self, "_on_fadeout_finished", [music_player])

func fadeout_all_music_players(duration, override_tween := true):
	for music_player in get_music_player_list():
		_fadeout_music_player(music_player, duration, override_tween)

func _on_fadeout_finished(music_player: AudioStreamPlayer) -> void:
	_record_music_player_playback_position(music_player)
	music_player.stop()

# Fades the music from SILENT to the specified volume
func fadein_music_player_by_name(node_name: String, volume: float, duration := 1.0, override_tween := true) -> void:
	var music_player = get_music_player_by_name(node_name) as AudioStreamPlayer
	if music_player:
		_fadein_music_player(music_player, volume, duration, override_tween)

func _fadein_music_player(music_player: AudioStreamPlayer, volume: float, duration : float, override_tween := true) -> void:
	music_player.volume_db = SILENT_SOUND_THRESHOLD
	_tween_music_player(music_player, volume, duration, override_tween)

# Fades the music from the current volume to the specified volume
func fadeto_music_player_by_name(node_name: String, volume: float, duration := 1.0, override_tween := true) -> void:
	var music_player = get_music_player_by_name(node_name) as AudioStreamPlayer
	if music_player:
		_fadeto_music_player(music_player, volume, duration, override_tween)

func _fadeto_music_player(music_player: AudioStreamPlayer, volume: float, duration : float, override_tween := true) -> void:
	_tween_music_player(music_player, volume, duration, override_tween)

# Returns a crossfade that isn't playing or a new one.
func _get_inactive_or_new_crossfade_music_player() -> AudioStreamPlayer:
	for i in MAX_CROSSFADES:
		var node_name = CROSSFADE_CHANNEL + str(i)
		var music_player = get_or_add_music_player_by_name(node_name)
		if !_is_music_player_audible(music_player):
			return music_player
	return null

# Returns a crossfade that is currently playing a certain song.
func _get_crossfade_music_player_playing_song(song: String) -> AudioStreamPlayer:
	for music_player in get_music_player_list_with_name(CROSSFADE_CHANNEL):
		if _is_song_playing_on_music_player(music_player, song):
			return music_player
	return null

# Returns a boolean value whether a music player is playing music and can be heard.
func _is_music_player_audible(music_player: AudioStreamPlayer) -> bool:
	return music_player and music_player.playing and !music_player.stream_paused and music_player.volume_db > SILENT_SOUND_THRESHOLD

# Returns a boolean value whether a music player is playing a specific song.
func is_song_playing_on_music_player_by_name(node_name: String, song: String) -> bool:
	var music_player: AudioStreamPlayer = get_music_player_by_name(node_name) as AudioStreamPlayer
	if music_player:
		return _is_song_playing_on_music_player(music_player, song)
	return false

func _is_song_playing_on_music_player(music_player: AudioStreamPlayer, song: String) -> bool:
	return _is_music_player_audible(music_player) and song in music_player.stream.resource_path

# Returns the resource path of a music player's stream without the music resource path.
func get_song_name_from_music_player(music_player: AudioStreamPlayer) -> String:
	if !music_player or !music_player.stream:
		return ""
	
	return music_player.stream.resource_path.replace(MUSIC_RESOURCE_PATH, "")

func set_sfx_audio_pitch(pitch: float) -> void:
	_sfx_pitch_scale = pitch
	for soundEffect in $Sfx.get_children():
		soundEffect.pitch_scale = pitch

func add_sfx(stream: AudioStream, node_name: String) -> AudioStreamPlayer:
	var sfx_node: AudioStreamPlayer = get_sfx(node_name)
	if !sfx_node:
		sfx_node = AudioStreamPlayer.new()
		sfx_node.bus = "SFX"
		sfx_node.name = node_name
		sfx_node.pitch_scale = _sfx_pitch_scale
		$Sfx.add_child(sfx_node)
	sfx_node.stream = stream
	return sfx_node

func add_sfx_by_name(sfx_name: String, node_name: String) -> AudioStreamPlayer:
	return add_sfx(_sound_effects[sfx_name], node_name)

func play_sfx(stream: AudioStream, node_name: String) -> AudioStreamPlayer:
	var sfx_node: AudioStreamPlayer = add_sfx(stream, node_name)
	sfx_node.play()
	return sfx_node

func play_sfx_by_name(sfx_name: String, node_name: String) -> AudioStreamPlayer:
	return play_sfx(_sound_effects[sfx_name], node_name)

func get_sfx(node_name: String) -> AudioStreamPlayer:
	return $Sfx.get_node_or_null(node_name) as AudioStreamPlayer
