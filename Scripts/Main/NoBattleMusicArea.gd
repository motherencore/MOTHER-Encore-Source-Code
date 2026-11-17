extends Area2D



func _on_NoBattleMusicArea_body_entered(body):
	if body == global.get_player():
		audioManager.overworld_battle_music = true


func _on_NoBattleMusicArea_body_exited(body):
	if body == global.get_player():
		audioManager.overworld_battle_music = false
