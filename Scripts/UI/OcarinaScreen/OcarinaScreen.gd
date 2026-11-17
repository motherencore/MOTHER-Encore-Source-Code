extends CanvasLayer

const MELODIES_FILE_PATTERN := "OcarinaOfHope/OcarinaOfHope%s.mp3"
const DRUMS_FILE := "OcarinaOfHope/OcarinaOfHopeDrum.mp3"
const INTRO_DRUMS_FILE := "OcarinaOfHope/OcarinaOfHopeIntro.mp3"
const MELODY_FLAGS := ["doll_melody", "canary_melody", "monkey_melody", "piano_melody", "cactus_melody", "dragon_melody", "eve_melody", "grave_melody"]
const PLAYER_VOLUME := 10
const TEMPO := 65.0
const TIME_PER_BEAT := 60.0 / TEMPO
const MELODY_BEATS := 4
const SEGMENT_START_DELAY := 1.0/4
const NOTES_SEQUENCE := [
	[0, .5, .5, .5, .5],
	[0, .5, .5, .5, .5],
	[0, .5, .5, .5, 1],
	[0, .5, .5, .5],
	[0, 1, 1, 1],
	[0, .5, .5, .5, .5, .5, .5, .5],
	[0, .5, .5, .5, .5, 1],
	[0, 1, .5, .5],
]

const START_DELAY_DURATION := SEGMENT_START_DELAY * TIME_PER_BEAT
const MELODY_DURATION := MELODY_BEATS * TIME_PER_BEAT

const ORBS_PULSE_DELAY := -0.02
const ORBS_POS_SYNC_FACTOR := 0.1
const ORBS_TRANSITION_DELAY := 0.2

const INTRO_PLAYER_NAME: String = "OcarinaIntro"
const DRUMS_PLAYER_NAME: String = "OcarinaDrums"
const MELODY_PLAYER_NAME: String = "OcarinaMelody_"

export (Array, NodePath) var _melody_anim_nodes: Array
export (NodePath) onready var _playing_orbs = get_node(_playing_orbs) as Control

onready var BackgroundRes := load("res://Graphics/Battle BGS/ocarina.bbg")

var _close_cb: FuncRef
var _curr_melody_num := -1

var _drums_player_name = INTRO_PLAYER_NAME

var _note_to_play := 0 # array index
var _last_note_pos := 0.0 # in number of beats

var closing = false

func init(close_cb: FuncRef):
	_close_cb = close_cb

func _ready():
	_init_background()
	_init_melody_nodes()
	audioManager.pause_all_music_players()
	_start_playing_with_intro()

func _init_background():
	var bg_node := CanvasLayer.new()
	bg_node.add_child(BackgroundRes.instance())
	bg_node.layer = 1
	add_child(bg_node)
	
func _init_melody_nodes():
	_melody_anim_nodes = _melody_anim_nodes.duplicate()
	for i in _melody_anim_nodes.size():
		var is_obtained = _is_melody_obtained(i)
		_melody_anim_nodes[i] = get_node(_melody_anim_nodes[i])
		_melody_anim_nodes[i].init_melody(is_obtained)

func _start_playing_with_intro():
	_play_music(INTRO_PLAYER_NAME, INTRO_DRUMS_FILE)
	_drums_player_name = INTRO_PLAYER_NAME

func _physics_process(delta):
	var melody_playback_pos := audioManager.get_music_player_playback_position_by_name(_drums_player_name) as float
	if _curr_melody_num >= 0 and _curr_melody_num < NOTES_SEQUENCE.size():
		_handle_melody_notes(melody_playback_pos)
	_handle_playing_orbs(melody_playback_pos)
	if melody_playback_pos > MELODY_DURATION and _curr_melody_num < MELODY_FLAGS.size() and !closing:
		_on_melody_finished()

func _input(event):
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		closing = true
		for name in _get_ocarina_music_player_names():
			audioManager.fadeout_music_player_by_name(name)
		Input.action_release("ui_accept")
		Input.action_release("ui_cancel")
		get_tree().set_input_as_handled()
		uiManager.get_fade().fade_in("Circle Focus")
		yield(uiManager.get_fade(), "fade_in_done")
		uiManager.remove_ui(self)

func _play_melody():
	_last_note_pos = 0
	_note_to_play = 0
	var got_melody := _is_melody_obtained(_curr_melody_num)
	if got_melody:
		_play_music(MELODY_PLAYER_NAME + str(_curr_melody_num), MELODIES_FILE_PATTERN % (_curr_melody_num + 1))
	_play_music(DRUMS_PLAYER_NAME, DRUMS_FILE)
	_drums_player_name = DRUMS_PLAYER_NAME
	_play_stop_anim(_curr_melody_num, true)

func _play_music(node_name: String, music: String):
	audioManager.stop_music_player_by_name(node_name)
	audioManager.play_music(node_name, music, 0.0)
	audioManager.set_music_player_volume_by_name(node_name, PLAYER_VOLUME)

func _handle_melody_notes(melody_pos: float):
	if _is_melody_obtained(_curr_melody_num):
		var melody_notes_sequence := NOTES_SEQUENCE[_curr_melody_num] as Array
		if _note_to_play < melody_notes_sequence.size():
			var next_note_pos_in_beats := _last_note_pos + (melody_notes_sequence[_note_to_play] as float)
			var next_note_pos_in_time := next_note_pos_in_beats * TIME_PER_BEAT + START_DELAY_DURATION
			if melody_pos - ORBS_PULSE_DELAY > next_note_pos_in_time:
				_playing_orbs.pulse()
				_last_note_pos = next_note_pos_in_beats
				_note_to_play += 1

func _handle_playing_orbs(playback_pos: float):
	if _curr_melody_num >= 0 and _curr_melody_num < NOTES_SEQUENCE.size():
		if _curr_melody_num == 0 or playback_pos > ORBS_TRANSITION_DELAY or !_playing_orbs.is_visible():
			_playing_orbs.set_visible(_is_melody_obtained(_curr_melody_num))
		_playing_orbs.set_tint(_melody_anim_nodes[_curr_melody_num].get_tint())
		_playing_orbs.center_pos += (_melody_anim_nodes[_curr_melody_num].center_pos - _playing_orbs.center_pos) * ORBS_POS_SYNC_FACTOR
	elif _curr_melody_num >= MELODY_FLAGS.size():
		_playing_orbs.scatter_away()
	else:
		_playing_orbs.set_visible(false)

func _on_melody_finished():
	var anim_id_to_stop = _curr_melody_num
	_curr_melody_num += 1
	if _curr_melody_num < MELODY_FLAGS.size():
		_play_melody()
	else:
		yield(get_tree().create_timer(1.5), "timeout")
		uiManager.get_fade().fade_in("Circle Focus")
		yield(uiManager.get_fade(), "fade_in_done")
		uiManager.remove_ui(self)
	if anim_id_to_stop > 0:
		_play_stop_anim(anim_id_to_stop, false)

func _is_melody_obtained(index: int) -> bool:
	return globaldata.flags[MELODY_FLAGS[index]]

func _play_stop_anim(index: int, play: bool):
	yield(get_tree().create_timer(START_DELAY_DURATION), "timeout")
	var anim_node = _melody_anim_nodes[index] as Node
	if play:
		anim_node.play()
	else:
		anim_node.stop()

func close():
	audioManager.resume_music_player_by_name(audioManager.CHANNELS.OVERWORLD)
	if _close_cb and _close_cb.is_valid():
		_close_cb.call_func()
		_close_cb = null
	queue_free()

func _get_ocarina_music_player_names() -> Array:
	var list = []
	list.append_array([INTRO_PLAYER_NAME, DRUMS_PLAYER_NAME])
	for i in MELODY_FLAGS.size():
		list.append(MELODY_PLAYER_NAME + str(i))
	return list
