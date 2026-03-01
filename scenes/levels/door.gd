extends AnimatableBody3D

@export var open: bool = false :
	set(v):
		if v != open:
			open = v
			update_door()

func update_door():
	if open:
		$AnimationPlayer.play("door_open2")
	else:
		$AnimationPlayer.play_backwards("door_open2")
	$AnimationPlayer.set_active(true)

func toggle_open():
	open = !open
