extends Line2D

var laser
var point
export (int)var length = 0
export var _finalTrail:= false

func _ready():
	laser = get_parent()
	visible = true
	global_position = Vector2.ZERO
	global_rotation = 0

func _physics_process(_delta):
	global_position = Vector2.ZERO
	global_rotation = 0
	if !laser.gone:
		point = laser.global_position 
		add_point(point) 
		while get_point_count() > length:
			remove_point(0)
	elif get_point_count() > 0:
		remove_point(0)
	if laser.gone and get_point_count() == 0 and _finalTrail:
		get_parent().get_parent().queue_free()

