extends VBoxContainer

const LABEL_FONT = preload("res://Fonts/EBMainOutline.tres")
const ACTIVE_COLOR = Color.white
const INACTIVE_COLOR = Color.darkgray

var music_player_labels = {}

func _ready():
	if OS.is_debug_build():
		audioManager.connect("music_players_updated", self, "_on_music_players_updated")
		Debug.connect("music_player_labels_toggled", self, "_toggle_visibility")
	else:
		queue_free()

func _toggle_visibility():
	visible = !visible
	if visible:
		_on_music_players_updated()

func _on_music_players_updated():
	if OS.is_debug_build() and visible:
		for music_player in audioManager.get_music_player_list():
			var label = music_player_labels.get(music_player.name)
			if !label:
				label = Label.new()
				label.add_font_override("font", LABEL_FONT)
				music_player_labels[music_player.name] = label
				add_child(label)
			format_label_text(label, music_player)

func _process(_delta):
	if OS.is_debug_build() and visible:
		for music_player_name in music_player_labels:
			var label = music_player_labels[music_player_name]
			var music_player = audioManager.get_music_player_by_name(music_player_name)
			format_label_text(label, music_player)

func format_label_text(label: Label, music_player: AudioStreamPlayer):
	var song_name = audioManager.get_song_name_from_music_player(music_player)
	var stream_paused = "||" if music_player.stream_paused else ">"
	label.text = "%s: %s %s vol %s" % [music_player.name, song_name, str(stepify(db2linear(music_player.volume_db), 0.01)), stream_paused]
	label.modulate = ACTIVE_COLOR if music_player.playing else INACTIVE_COLOR
