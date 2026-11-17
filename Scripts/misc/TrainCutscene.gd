extends Node2D
class_name TrainCutscene

enum Themes {INTERIOR, YUCCA, MERRYSVILLE, REINDEER, SPOOKANE, SNOWMAN}

const INTERIOR_THEMES := [Themes.INTERIOR]
const FULL_ROUTE := [Themes.YUCCA, Themes.MERRYSVILLE, Themes.INTERIOR, Themes.REINDEER, Themes.SPOOKANE, Themes.SNOWMAN]
const FULL_ROUTE_DISTANCES := [16000, 16000, 18000, 300000, 200000, 200000]
const SCREEN_WIDTH := 320
const RAIL_TILE_WIDTH := 32
const DISTANCE_BEFORE_FADE := 120
const TRAIN_SPEED := 250
const INTERIOR_DIM_TRAIN_COLOR := Color(0.7, 0.5, 0.5)

const TUNNEL_NODE_NAMES := "%s-Tunnel%s%s"

const FG_SAMPLE_NODE_NAME := "%s-Repeatable"
const FG_NODES_INTERVAL := {
	Themes.MERRYSVILLE: 90, 
	Themes.REINDEER: 288
}
const FG_NODES_HEIGHT_VARIANCE := 12

const DESTINATION_SCENES := {
	Themes.MERRYSVILLE: "Merrysville/Thanksgiving Station",
	Themes.REINDEER: "Title screen"
}

var _phase_themes := [Themes.MERRYSVILLE, Themes.INTERIOR, Themes.REINDEER]
var _phase_distances := [16000, 20000, 200000]
var _direction := 1

onready var _node_scroller := $ParallaxBackground
onready var _node_train := $ParallaxBackground/TrainLayer/Train
onready var _node_repeatable_layer := $ParallaxBackground/FG
onready var _node_door := $Objects/Door

onready var _tunnel_nodes := []
onready var _repeatable_node: Node2D
onready var _repeated_node_last_x := 0.0

export var _train_offset := 104

var _covered_distance := 0.0
var _ending_started := false


#####################
# Lifecycle methods #
#####################

func init_params(origin: String, destination: String, distance_override := 0, train_offset := _train_offset) -> void:
	_train_offset = train_offset
	var origin_idx := FULL_ROUTE.find(_get_theme_id(origin))
	var destination_idx := FULL_ROUTE.find(_get_theme_id(destination))
	_direction = 1 if origin_idx <= destination_idx else -1
	_phase_themes = []
	_phase_distances = []
	for i in range(origin_idx, destination_idx + _direction, _direction):
		_phase_themes.append(FULL_ROUTE[i])
		if distance_override == 0:
			_phase_distances.append(FULL_ROUTE_DISTANCES[i])
		else:
			_phase_distances.append(distance_override)

func _ready():
	global.get_player().pause(true)
	global.get_player().hide()
	
	global.currentCamera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	global.currentCamera.current = false
	
	
	_reset()

func _next_phase():
	if _phase_themes.size() > 1:
		var fade: CanvasLayer = uiManager.get_fade()
		uiManager.get_fade().fade_in("Fade", Color.black, 0.7)
		yield(uiManager.get_fade(), "fade_in_mostly_done")
		_phase_themes.pop_front()
		_phase_distances.pop_front()
		uiManager.get_fade().fade_out("Fade", Color.black, 0.5)
		_reset()
	else:
		_close(_get_theme_name(_get_current_theme()))

func _reset():
	_covered_distance = 0.0
	_ending_started = false
	_filter_nodes_per_theme()
	_init_train()
	_init_tunnel_entrance()
	_init_foreground()
	_draw_repeated_nodes()

func _close(goto_scene := ""):
	if goto_scene:
		_node_door.targetScene = DESTINATION_SCENES[_get_current_theme()]
		_node_door.enter()
		yield(_node_door, "entered")
	audioManager.stop_all_music_players()
#	global.get_player().show()
	global.currentCamera.current = true
	global.currentCamera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER

#####################
#   Init  methods   #
#####################

func _filter_nodes_per_theme():
	for dest in Themes:
		for node in get_tree().get_nodes_in_group(dest.capitalize()):
			node.visible = (Themes[dest] == _get_current_theme())

func _init_train():
	_node_train.position.x = SCREEN_WIDTH / 2 - _direction * abs(SCREEN_WIDTH / 2 - _train_offset)
	if _get_current_theme() in INTERIOR_THEMES:
		_node_train.modulate = INTERIOR_DIM_TRAIN_COLOR
	else:
		_node_train.modulate = Color(1, 1, 1)

func _init_tunnel_entrance():
	_tunnel_nodes.clear()
	var dir_names := { -1: "Left", 1: "Right" }
	var parts := ["Front", "Back"]
	var theme_name := _get_theme_name(_get_current_theme())
	for dir in dir_names:
		for part in parts:
			var tunnel_node := _node_scroller.find_node(TUNNEL_NODE_NAMES % [theme_name, part, dir_names[dir]])
			if tunnel_node:
				if dir == _direction and _phase_themes.size() > 1:
					tunnel_node.show()
					_tunnel_nodes.append(tunnel_node)
				else:
					tunnel_node.hide()

func _init_foreground():
	var theme_name := _get_theme_name(_get_current_theme())
	_repeatable_node = _node_repeatable_layer.get_node_or_null(FG_SAMPLE_NODE_NAME % theme_name)
	if _repeatable_node:
		_repeatable_node.position.x = - _direction * abs(_repeatable_node.position.x)
		_repeated_node_last_x = _repeatable_node.position.x


#####################
# Scrolling methods #
#####################

func _draw_repeated_nodes():
	if _repeatable_node:
		while _repeated_node_last_x * _direction < _get_scroll_offset() * _node_repeatable_layer.motion_scale.x * _direction:
			var new_node := _repeatable_node.duplicate()
			_repeatable_node.get_parent().add_child(new_node)
			var theme_name = _get_current_theme()
			var interval := _add_randomness(FG_NODES_INTERVAL[theme_name], FG_NODES_INTERVAL[theme_name] * 0.1)
			_repeated_node_last_x += interval * _direction
			new_node.position.x = _repeated_node_last_x
			new_node.position.y += _add_randomness(0, FG_NODES_HEIGHT_VARIANCE)

func _get_scroll_offset() -> int:
	return _get_screen_edge_x() - _node_scroller.scroll_offset.x

func _set_scroll_offset(value: float) -> void:
	_node_scroller.scroll_offset.x = _get_screen_edge_x() - value

func _move_scroll_offset(delta: float) -> void:
	_set_scroll_offset(_get_scroll_offset() + delta)

func _process(delta: float) -> void:
	_covered_distance += TRAIN_SPEED * delta
	if _covered_distance < _phase_distances[0]:
		for node in _tunnel_nodes:
			node.position.x = _snap_value(_get_scroll_offset(), RAIL_TILE_WIDTH)
	else:
		if _covered_distance > _phase_distances[0] + DISTANCE_BEFORE_FADE + (SCREEN_WIDTH / 2 - _train_offset) and !_ending_started:
			_ending_started = true
			_next_phase()

	_move_scroll_offset(TRAIN_SPEED * delta * _direction)
	_draw_repeated_nodes()

func pan_height(height: int, length: float):
	var tween = get_tree().create_tween()
	tween.tween_property(_node_scroller, "scroll_base_offset:y", height, length)\
	.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.play()
	

#####################
#  Utility methods  #
#####################

func _get_theme_name(theme_id: int) -> String:
	return Themes.keys()[theme_id].capitalize()

func _get_theme_id(theme_name: String) -> int:
	return Themes[theme_name.to_upper()]

func _get_current_theme() -> int:
	return _phase_themes[0]

func _get_screen_edge_x() -> int:
	if _direction > 0:
		return SCREEN_WIDTH
	else:
		return 0

func _add_randomness(value: int, variance: float) -> int:
	return value + int(randf() * variance * 2 - variance)

func _snap_value(value: int, snap_to: int) -> int:
	return int(round(value / snap_to) * snap_to)
