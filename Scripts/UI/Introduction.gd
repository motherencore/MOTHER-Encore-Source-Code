extends Control

var current_text: int = 0
var finished := true
var t: float = 0
var text_speed := 0.08
var text := [
	"INTRO_CUTSCENE_OLD_01",
	"INTRO_CUTSCENE_OLD_02",
	"INTRO_CUTSCENE_OLD_03",
	"INTRO_CUTSCENE_OLD_04",
	"INTRO_CUTSCENE_OLD_05",
	"INTRO_CUTSCENE_OLD_06",
	"INTRO_CUTSCENE_OLD_07",
	"INTRO_CUTSCENE_OLD_08",
	"INTRO_CUTSCENE_OLD_09",
	"INTRO_CUTSCENE_OLD_10",
	"INTRO_CUTSCENE_OLD_11",
	"INTRO_CUTSCENE_OLD_12"
]

onready var dialogue_label = $Text/HBoxContainer/ScrollingText

func _ready():
	global.get_player().pause(true)
	dialogue_label.visible_characters = 0
	dialogue_label.text = ""
	$Timer.connect("timeout", self, "set_process", [true])
	yield(get_tree().create_timer(2), "timeout")
	$AnimationPlayer.play("Introduction")

func _process(delta: float):
	for i in 5:
		var path = "Images/Intro_" + var2str(i)
		get_node(path).rect_position = get_node(path).rect_position.round()
	if !finished:
		var spaceless_test = _get_spaceless_text(dialogue_label.text)
		t += delta
		if t > text_speed:
			dialogue_label.visible_characters += 1
			t = 0
			$AudioStreamPlayer.play()
			if _get_last_visible_character(dialogue_label) in tr("INTRO_CUTSCENE_PUNCTUATION") and dialogue_label.visible_characters < len(spaceless_test):
				$Timer.start()
				set_process(false)
		if dialogue_label.visible_characters >= len(spaceless_test):
			finished = true
			dialogue_label.visible_characters = len(spaceless_test)
			t = 0

func _physics_process(_delta: float):
	if Input.is_action_just_pressed("ui_select") and $AnimationPlayer.is_playing():
		Input.action_release("ui_select")
		$AnimationPlayer.stop()
		stop_music()
		_on_AnimationPlayer_animation_finished("Introduction")

func _get_last_visible_character(label: Label):
	var spaceless_text = _get_spaceless_text(label.text)
	return spaceless_text[min(dialogue_label.visible_characters, spaceless_text.length()) - 1]

func _get_spaceless_text(string: String):
	return string.replace(" ", "").replace("\n", "")

func hide_text():
	create_tween().tween_property(dialogue_label, "rect_position:y", -36, 0.5).set_ease(Tween.EASE_OUT)

func reset_text():
	dialogue_label.text = ""
	dialogue_label.visible_characters = 0
	
	dialogue_label.rect_position.y = (dialogue_label.get_parent().rect_size.y - dialogue_label.rect_size.y) / 2
	finished = true

func next_text():
	reset_text()
	set_process(true)
	if dialogue_label.text != "":
		dialogue_label.text += "\n"
	
	dialogue_label.text += _snap_text_to_tiles(tr(text[current_text]))
	finished = false
	current_text += 1

func _snap_text_to_tiles(string: String):
	var splitString = string.split("\n")
	for i in splitString.size():
		if splitString[i].length() % 2 == 1:
			splitString[i] += " " # Same parity in length makes centering look good
	return splitString.join("\n")

func slow_down_text():
	text_speed = 0.15

func reset_text_speed():
	text_speed = 0.08

func stop_music():
	audioManager.fadeout_all_music_players(5)

func _on_AnimationPlayer_animation_finished(_anim_name):
	$Objects/Door.enter()
