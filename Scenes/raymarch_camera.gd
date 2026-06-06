extends Node
class_name CameraController

@export_category("Dependencies")
@export var ray_march_sprite : ColorRect
@export var post_process_texture : TextureRect

@export_category("Character Controls")
@export var mouse_sens := .01
@export var speed := 3.
@export var max_speed := 10.
@export var turn_speed := 3.
@export var acceleration := 3.
@export var max_pitch_angle := PI/2.
@export var max_tilt_angle := PI/5.
@export var base_focal_length = 2.2
@export var min_focal_length = 1.5

@export_category("Environment Controls")
@export var wave_amplitude = .1;
@export var tide_fluctuation = 1.;
@export var wave_time_period = 10.;
@export var tide_time_period = 120.;
@export var day_cycle_time = 120.;

var raymarch_shader : ShaderMaterial
var post_process_shader : ShaderMaterial

var mouse_motion : Vector2

var player_position := Vector3(0., 1., 0.)
var resolution : Vector2
var sun_dir : Vector3
var planet_centre : Vector3
var planet_radius : float
var cloud_bounds : Vector2 #lower and upper radius of cloud layer
var atm_radius : float
var cur_sun_dir : Vector3
var water_radius : float
var cur_water_radius : float
var warp_radius : float
var outer_warp_radius : float
var rotation_axis : Vector3

var char_transform := Transform3D()
var camera_basis : Basis

var cur_speed := 0.0
var local_pitch := 0.0
var tilt := 0.0
var focal_length : float

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	focal_length = base_focal_length
	
	if ray_march_sprite:
		raymarch_shader = ray_march_sprite.material
		sun_dir = raymarch_shader.get_shader_parameter("sun_dir")
		sun_dir = sun_dir.normalized()
		cur_sun_dir = sun_dir
		resolution = raymarch_shader.get_shader_parameter("resolution")
		water_radius = raymarch_shader.get_shader_parameter("water_radius")
		cur_water_radius = water_radius
		rotation_axis = raymarch_shader.get_shader_parameter("planet_rotation_axis")
		rotation_axis = rotation_axis.normalized()
		planet_centre = raymarch_shader.get_shader_parameter("planet_centre")
		planet_radius = raymarch_shader.get_shader_parameter("planet_radius")
		atm_radius = raymarch_shader.get_shader_parameter("atm_radius")
		cloud_bounds = raymarch_shader.get_shader_parameter("cloud_height_bounds")
		warp_radius = raymarch_shader.get_shader_parameter("warp_radius")
		outer_warp_radius = raymarch_shader.get_shader_parameter("outer_warp_radius")
		
	if post_process_texture:
		post_process_shader = post_process_texture.material
		
		post_process_shader.set_shader_parameter("resolution", resolution)
		post_process_shader.set_shader_parameter("sun_dir", sun_dir)
	
	char_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.MODEL_FRONT), player_position)
	update_shader()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("esc"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion:
		mouse_motion += event.relative

func _process(delta: float) -> void:
	handle_character_movement(delta)
	handle_environment(delta)
	update_shader()

func handle_character_movement(delta: float) -> void:
	var input_dir := Input.get_vector("left", "right", "down", "up")
	var input_v_dir := Input.get_axis("ctrl", "space")
	
	var p_from_centre = player_position - planet_centre
	
	var gravity_dir := - p_from_centre.normalized()
	var local_up := - gravity_dir

	var dist := p_from_centre.length()
	var d_norm := dist / planet_radius
	
	var surface_band := 0.2
	var align_weight := exp(-pow((d_norm - 1.0) / surface_band, 2.0))

	var current_up := char_transform.basis.y
	var align_quat := Quaternion(current_up, local_up)
	var partial_quat := Quaternion.IDENTITY.slerp(align_quat, 5.0 * align_weight * delta)
	char_transform.basis = Basis(partial_quat) * char_transform.basis

	char_transform.basis = char_transform.basis.rotated(char_transform.basis.y, mouse_motion.x * mouse_sens * delta).orthonormalized()
	local_pitch = clamp(local_pitch + mouse_motion.y * mouse_sens * delta, -max_pitch_angle, max_pitch_angle)
	tilt = lerp_angle(tilt, - max_tilt_angle * input_dir.x, delta * turn_speed)
	
	camera_basis = char_transform.basis
	camera_basis = camera_basis.rotated(char_transform.basis.x, local_pitch).orthonormalized()
	camera_basis = camera_basis.rotated(camera_basis.z, tilt).orthonormalized()
	mouse_motion = mouse_motion.lerp(Vector2.ZERO, delta * 10.0)

	var move_dir := (
		(camera_basis.z * input_dir.y) +
		(camera_basis.x * input_dir.x) +
		(camera_basis.y * input_v_dir)
	).normalized()
	
	var target_speed := 0. \
	if move_dir.is_equal_approx(Vector3.ZERO) \
	else max_speed if Input.is_action_pressed("shift") \
	else speed

	cur_speed = lerp(cur_speed, target_speed, delta * acceleration)
	var speed_ratio = max((cur_speed - speed) / (max_speed - speed), 0.)
	focal_length = lerp(base_focal_length, min_focal_length, clamp(speed_ratio, 0., 1.))
	
	player_position += move_dir * cur_speed * delta
	
	var camera_from_centre = player_position + camera_basis.z * focal_length - planet_centre;
	if camera_from_centre.length() <= warp_radius * 0.5:
		var scale_factor = outer_warp_radius / warp_radius
		player_position = planet_centre + camera_from_centre * scale_factor - camera_basis.z * focal_length

var e_time := 0.;
func handle_environment(delta: float):
	e_time += delta;
	cur_sun_dir = sun_dir.rotated(rotation_axis, 2. * PI * e_time / day_cycle_time).normalized()
	var tide = sin(2. * PI * e_time / tide_time_period) * tide_fluctuation
	cur_water_radius = (water_radius + tide) + sin(e_time * 2. * PI / wave_time_period) * wave_amplitude

func update_shader():
	var screen_coord = player_position + camera_basis.z * focal_length

	if raymarch_shader:
		raymarch_shader.set_shader_parameter("screen_dir", camera_basis.z)
		raymarch_shader.set_shader_parameter("screen_up", camera_basis.y)
		raymarch_shader.set_shader_parameter("screen_coord", screen_coord)
		raymarch_shader.set_shader_parameter("sun_dir", cur_sun_dir)
		raymarch_shader.set_shader_parameter("water_radius", cur_water_radius)
		raymarch_shader.set_shader_parameter("focal_length", focal_length)
	
	if post_process_shader:
		post_process_shader.set_shader_parameter("screen_dir", camera_basis.z)
		post_process_shader.set_shader_parameter("screen_up", camera_basis.y)
		post_process_shader.set_shader_parameter("screen_coord", screen_coord)
		post_process_shader.set_shader_parameter("sun_dir", cur_sun_dir)
		post_process_shader.set_shader_parameter("focal_length", focal_length)
