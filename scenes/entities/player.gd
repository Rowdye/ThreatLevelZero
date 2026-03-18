extends CharacterBody3D

@export var look_sens: float = 0.003
enum CameraStyle {
	FIRST_PERSON, THIRD_PERSON_FREELOOK
}
@export var camera_style: CameraStyle = CameraStyle.FIRST_PERSON:
	set(v):
		camera_style = v
		update_camera_style()

var wish_dir: Vector3 = Vector3.ZERO

@export var ground_friction: float = 5.0
@export var walk_speed: float = 3.5
@export var walk_accel: float = 15.0
@export var walk_decel: float = 5.0
@export var sprint_speed: float = 5.0
@export var sprint_accel: float = 2.5
@export var sprint_decel: float = 1.0

const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY: float = 2.4
var headbob_time: float = 0.0

const CROUCH_TRANSLATE: float = 0.7
const CROUCH_JUMP_ADD = CROUCH_TRANSLATE * 1.0
var is_crouched: bool = false

const MAX_STEP_HEIGHT = 0.5
var snapped_to_stairs_last_frame: bool = false
var last_frame_on_floor = -INF

@export var jump_velocity: float = 5.5

@export var air_cap: float = 0.5
@export var air_accel: float = 200.0
@export var air_move_speed: float = 1000.0

@export var push_strength: float = 15.0

@export var climb_speed: float = 3.0

var noclip_cam_wish_dir: Vector3 = Vector3.ZERO
var noclip_speed_multi: float = 2.0
var noclip_enabled: bool = false

func _ready() -> void:
	for child in %WorldModel.find_children("*", "VisualInstance3D"):
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)
	#for child in %WorldModel.find_children("*", "Node3D"):
		#child.visible = false
	
	update_camera_style()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("menu"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			if camera_style == CameraStyle.THIRD_PERSON_FREELOOK:
				%TPOrbitCamYaw.rotate_y(-event.relative.x * look_sens)
			
			%PlayerCamera.rotate_x(-event.relative.y * look_sens)
			%PlayerCamera.rotation.x = clamp(%PlayerCamera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
			%PlayerCamera.rotation.y = clamp(%PlayerCamera.rotation.y, 0, 0)
			
			%TPOrbitCamPitch.rotate_x(-event.relative.y * look_sens)
			%TPOrbitCamPitch.rotation.x = clamp(%TPOrbitCamPitch.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func get_move_speed() -> float:
	if is_crouched:
		return walk_speed * 0.5
	return sprint_speed if Input.is_action_pressed("sprint") else walk_speed

func get_move_celeration(acceleration: bool) -> float:
	#if acceleration:
		#return sprint_accel if Input.is_action_pressed("sprint") else walk_accel
	#else:
		#return sprint_decel if Input.is_action_pressed("sprint") else walk_decel
	
	if acceleration:
		return walk_accel
	else:
		return walk_decel

func _physics_process(delta: float) -> void:
	if is_on_floor(): last_frame_on_floor = Engine.get_physics_frames()
	
	update_camera_style()
	
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	wish_dir = self.global_transform.basis * Vector3(input_dir.x, 0., input_dir.y)
	noclip_cam_wish_dir = get_active_camera().global_transform.basis * Vector3(input_dir.x, 0., input_dir.y)
	
	if camera_style == CameraStyle.THIRD_PERSON_FREELOOK:
		wish_dir = %TPOrbitCamYaw.global_transform.basis * Vector3(input_dir.x, 0., input_dir.y)
	
	handle_crouch(delta)
	
	if not handle_noclip(delta) and not handle_ladder_physics(delta):
		if is_on_floor() or snapped_to_stairs_last_frame:
			handle_ground_physics(delta)
			if Input.is_action_just_pressed("jump"):
				self.velocity.y = jump_velocity
		else:
			handle_air_physics(delta)
		
		if not snap_up_stairs(delta):
			handle_rigidbodies()
			move_and_slide()
			snap_down_stairs()
	
	smooth_camera_to_origin(delta)

func handle_ground_physics(delta) -> void:
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var add_speed_until_cap = get_move_speed() - cur_speed_in_wish_dir
	if add_speed_until_cap > 0:
		var accel_speed = get_move_celeration(true) * delta * get_move_speed()
		accel_speed = min(accel_speed, add_speed_until_cap)
		self.velocity += accel_speed * wish_dir
	
	var control = max(self.velocity.length(), get_move_celeration(false))
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

@onready var orig_standing_height = $Collider.shape.height
func handle_crouch(delta) -> void:
	var crouched_last_frame = is_crouched
	if Input.is_action_pressed("crouch"):
		is_crouched = true
	elif is_crouched and not self.test_move(self.global_transform, Vector3(0, CROUCH_TRANSLATE, 0)) and is_on_floor():
		is_crouched = false
	
	var translate_y_check: float = 0.0
	if crouched_last_frame != is_crouched and not is_on_floor() and not snapped_to_stairs_last_frame:
		translate_y_check = CROUCH_JUMP_ADD if is_crouched else -CROUCH_JUMP_ADD
	
	if translate_y_check != 0.0:
		var result = KinematicCollision3D.new()
		self.test_move(self.global_transform, Vector3(0, translate_y_check, 0), result)
		self.position.y += result.get_travel().y
		%Head.position.y -= result.get_travel().y
		%Head.position.y = clampf(%Head.position.y, -CROUCH_TRANSLATE, 0)
	
	%Head.position.y = move_toward(%Head.position.y,-CROUCH_TRANSLATE if is_crouched else 0, 5.0 * delta)
	$Collider.shape.height = orig_standing_height - CROUCH_TRANSLATE if is_crouched else orig_standing_height
	$Collider.position.y = $Collider.shape.height / 2

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

var cur_ladder: Area3D = null
func handle_ladder_physics(delta) -> bool:
	var was_climbing_ladder: bool = cur_ladder and cur_ladder.overlaps_body(self)
	
	if not was_climbing_ladder:
		cur_ladder = null
		for ladder in get_tree().get_nodes_in_group("Ladder"):
			if ladder.overlaps_body(self):
				cur_ladder = ladder
				break
	if cur_ladder == null:
		return false
	
	var ladder_globaltransform: Transform3D = cur_ladder.global_transform
	var position_relative_to_ladder := ladder_globaltransform.affine_inverse() * self.global_position
	
	var up_axis := Input.get_action_strength("forward") - Input.get_action_strength("backward")
	var side_axis := Input.get_action_strength("right") - Input.get_action_strength("left")
	var ladder_up_axis = ladder_globaltransform.affine_inverse().basis * get_active_camera().global_transform.basis * Vector3(0, 0, -up_axis)
	var ladder_side_axis = ladder_globaltransform.affine_inverse().basis * get_active_camera().global_transform.basis * Vector3(side_axis, 0, 0)
	
	var ladder_strafe_velocity: float = climb_speed * (ladder_side_axis.x + ladder_up_axis.x)
	var ladder_climb_velocity: float = climb_speed * -ladder_side_axis.z
	var cam_up_amount: float = %PlayerCamera.basis.z.dot(cur_ladder.basis.z)
	var up_wish := Vector3.UP.rotated(Vector3(1, 0, 0), deg_to_rad(-45 * cam_up_amount)).dot(ladder_up_axis)
	ladder_climb_velocity += climb_speed * up_wish
	
	var should_dismount = false
	if not was_climbing_ladder:
		var mounting_from_top = position_relative_to_ladder.y > cur_ladder.get_node("TopOfLadderMarker").position.y
		if mounting_from_top:
			if ladder_climb_velocity > 0: should_dismount = true
		else:
			if (ladder_globaltransform.affine_inverse().basis * wish_dir).z >= 0: should_dismount = true
		
		if abs(position_relative_to_ladder.z) > 0.1: should_dismount = true
	
	if is_on_floor() and ladder_climb_velocity <= 0: should_dismount = true
	
	if should_dismount:
		cur_ladder = null
		return false
	
	if was_climbing_ladder and Input.is_action_just_pressed("jump"): 
		self.velocity = cur_ladder.global_transform.basis.z * (jump_velocity / 2)
		cur_ladder = null
		return false
	
	self.velocity = ladder_globaltransform.basis * Vector3(ladder_strafe_velocity, ladder_climb_velocity, 0)
	self.velocity = self.velocity.limit_length(climb_speed)
	
	position_relative_to_ladder.z = 0
	self.global_position = ladder_globaltransform * position_relative_to_ladder
	
	move_and_slide()
	return true

func _process(delta: float) -> void:
	if scan_for_interactables():
		scan_for_interactables().hover_cursor(self)
		if Input.is_action_just_pressed("interact"):
			scan_for_interactables().interact_with()
	
	if camera_style == CameraStyle.THIRD_PERSON_FREELOOK and wish_dir.length():
		var add_rotation_y = (-self.global_transform.basis.z).signed_angle_to(wish_dir.normalized(), Vector3.UP)
		var rot_towards = lerp_angle(self.global_rotation.y, self.global_rotation.y + add_rotation_y, max(0.1, abs(add_rotation_y/TAU))) - self.global_rotation.y
		self.rotation.y += rot_towards
		%TPOrbitCamYaw.rotation.y -= rot_towards

var camera_origin_pos = null
func save_camera_origin_smoothing():
	if camera_origin_pos == null:
		camera_origin_pos = %SmoothLayer.global_position

func smooth_camera_to_origin(delta):
	if camera_origin_pos == null: return
	%SmoothLayer.global_position.y = camera_origin_pos.y
	%SmoothLayer.position.y = clampf(%SmoothLayer.position.y, -0.7, 0.7)
	var move_amount = max(self.velocity.length() * delta, walk_speed/2 * delta)
	%SmoothLayer.position.y = move_toward(%SmoothLayer.position.y, 0.0, move_amount)
	camera_origin_pos = %SmoothLayer.global_position
	if %SmoothLayer.position.y == 0:
		camera_origin_pos = null

func headbob_effect(delta) -> void:
	headbob_time += delta * self.velocity.length()
	%ViewbobLayer.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)

func get_active_camera() -> Camera3D:
	if camera_style == CameraStyle.FIRST_PERSON:
		return %PlayerCamera
	else:
		return %ThirdPersonPlayerCamera

func update_camera_style() -> void:
	if not is_inside_tree():
		return
	var cameras = [%PlayerCamera, %ThirdPersonPlayerCamera]
	if not cameras.any(func(c: Camera3D): return c.current):
		return
	get_active_camera().current = true

func is_surface_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool:
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)

func snap_down_stairs() -> void:
	var did_snap: bool = false
	var floor_below: bool = %StairsUnderRaycast.is_colliding() and not is_surface_steep(%StairsUnderRaycast.get_collision_normal())
	var on_floor_last_frame: bool = Engine.get_physics_frames() - last_frame_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (on_floor_last_frame or snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			save_camera_origin_smoothing()
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	snapped_to_stairs_last_frame = did_snap

func snap_up_stairs(delta) -> bool:
	if not is_on_floor() and not snapped_to_stairs_last_frame: return false
	if self.velocity.y > 0 or (self.velocity * Vector3(1, 0, 1)).length() == 0: return false
	
	var expected_move_motion = self.velocity * Vector3(1,0,1) * delta
	var step_pos_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	var down_result = PhysicsTestMotionResult3D.new()
	if (run_body_test_motion(step_pos_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_result)) and (down_result.get_collider().is_class("StaticBody3D") or down_result.get_collider().is_class("CSGShape3D")):
		var step_height = ((step_pos_clearance.origin + down_result.get_travel()) - self.global_position).y
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT: return false
		%StairsFrontRaycast.global_position = down_result.get_collision_point() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_move_motion.normalized() * 0.1
		%StairsFrontRaycast.force_raycast_update()
		if %StairsFrontRaycast.is_colliding() and not is_surface_steep(%StairsFrontRaycast.get_collision_normal()):
			save_camera_origin_smoothing()
			self.global_position = step_pos_clearance.origin + down_result.get_travel()
			apply_floor_snap()
			snapped_to_stairs_last_frame = true
			return true
	return false

func handle_rigidbodies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			var push_dir = -c.get_normal()
			var velocity_diff_push_dir = self.velocity.dot(push_dir) - c.get_collider().linear_velocity.dot(push_dir)
			velocity_diff_push_dir = max(0., velocity_diff_push_dir)
			
			const PLAYER_MASS: float = 85.0
			var mass_ratio = min(1., PLAYER_MASS / c.get_collider().mass)
			
			push_dir.y = 0
			
			var push_force = mass_ratio * push_strength
			c.get_collider().apply_impulse(push_dir * velocity_diff_push_dir * push_force, c.get_position() - c.get_collider().global_position)

func scan_for_interactables() -> InteractableComponent:
	for i in %InteractShape.get_collision_count():
		if i > 0 and %InteractShape.get_collider(0) != $".":
			return null
		if %InteractShape.get_collider(i).get_node_or_null("InteractableComponent") is InteractableComponent:
			return %InteractShape.get_collider(i).get_node_or_null("InteractableComponent")
	return null
