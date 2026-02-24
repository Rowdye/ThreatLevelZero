extends CharacterBody3D

@export var look_sens: float = 0.003

var wish_dir: Vector3 = Vector3.ZERO

@export var walk_speed: float = 3.5
@export var sprint_speed: float = 5.0
@export var ground_accel: float = 17.0
@export var ground_decel: float = 5.0
@export var ground_friction: float = 4.0

const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY: float = 2.4
var headbob_time: float = 0.0

@export var jump_velocity: float = 5.5

@export var air_cap: float = 0.85
@export var air_accel: float = 200.0
@export var air_move_speed: float = 1000.0

var noclip_cam_wish_dir: Vector3 = Vector3.ZERO
var noclip_speed_multi: float = 2.0
var noclip_enabled: bool = false

func _ready() -> void:
	for child in %WorldModel.find_children("*", "VisualInstance3D"):
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("menu"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sens)
			%PlayerCamera.rotate_x(event.relative.y * look_sens)
	%PlayerCamera.rotation.x = clamp(%PlayerCamera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func get_move_speed() -> float:
	return sprint_speed if Input.is_action_pressed("sprint") else walk_speed

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("left", "right", "forward", "backward").normalized()
	wish_dir = self.global_transform.basis * Vector3(-input_dir.x, 0., -input_dir.y)
	noclip_cam_wish_dir = %PlayerCamera.global_transform.basis * Vector3(input_dir.x, 0., input_dir.y)
	
	if not handle_noclip(delta):
		if is_on_floor():
			handle_ground_physics(delta)
			if Input.is_action_just_pressed("jump"):
				self.velocity.y = jump_velocity
		else:
			handle_air_physics(delta)
		move_and_slide()

func handle_ground_physics(delta) -> void:
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var add_speed_until_cap = get_move_speed() - cur_speed_in_wish_dir
	if add_speed_until_cap > 0:
		var accel_speed = ground_accel * delta * get_move_speed()
		accel_speed = min(accel_speed, add_speed_until_cap)
		self.velocity += accel_speed * wish_dir
	
	var control = max(self.velocity.length(), ground_decel)
	var drop = control * ground_friction * delta
	var new_speed = max(self.velocity.length() - drop, 0.0)
	if self.velocity.length() > 0:
		new_speed /= self.velocity.length()
	self.velocity *= new_speed
	
	headbob_effect(delta)

func handle_air_physics(delta) -> void:
	self.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var capped_speed = min((air_move_speed * wish_dir).length(), air_cap)
	
	var add_speed_until_cap = capped_speed - cur_speed_in_wish_dir
	if add_speed_until_cap > 0:
		var accel_speed = air_accel * air_move_speed * delta
		accel_speed = min(accel_speed, add_speed_until_cap)
		self.velocity += accel_speed * wish_dir

func handle_noclip(delta) -> bool:
	if Input.is_action_just_pressed("dev_noclip") and OS.has_feature("debug"):
		noclip_enabled = !noclip_enabled
	
	$Collider.disabled = noclip_enabled
	
	if not noclip_enabled:
		return false
	
	var speed = get_move_speed() * noclip_speed_multi
	if Input.is_action_pressed("sprint"):
		speed *= 2.0
	elif Input.is_action_pressed("crouch"):
		speed /= 4.0
	
	self.velocity = noclip_cam_wish_dir * speed
	global_position += self.velocity * delta
	
	return true

func _process(delta: float) -> void:
	pass

func headbob_effect(delta) -> void:
	headbob_time += delta * self.velocity.length()
	%ViewbobLayer.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)
