extends Node
class_name FetchPlayerData
@export var camera : CameraController

var _prev_underwater : bool = false
var _water_splash : int = 0
var _started_boost : bool = false
var _prev_is_boosting : bool = false

func _process(_delta: float) -> void:
	var dist = (camera.player_position - camera.planet_centre).length()
	var cur_underwater = dist < camera.cur_water_radius
	if cur_underwater and not _prev_underwater:
		_water_splash = 1
	elif not cur_underwater and _prev_underwater:
		_water_splash = -1
	else:
		_water_splash = 0
	_prev_underwater = cur_underwater

	var is_boosting = Input.is_action_pressed("shift")
	_started_boost = is_boosting and not _prev_is_boosting
	_prev_is_boosting = is_boosting

func get_player_position() -> Vector3:
	return camera.player_position

func get_sun_direction() -> Vector3:
	return camera.cur_sun_dir

## returns [0., inf) -> height within atmosphere (0. -> 1. within atmosphere, > 1. in space)
## note: atmosphere ends where water begins
func get_atmosphere_height() -> float:
	var dist = (camera.player_position - camera.planet_centre).length()
	return (dist - camera.cur_water_radius) / (camera.atm_radius - camera.cur_water_radius)

## returns (negative, positive) -> (0. - 1. -> height within cloud layer)
func get_cloud_layer_height() -> float:
	var dist = (camera.player_position - camera.planet_centre).length()
	return (dist - camera.cloud_bounds.x) / (camera.cloud_bounds.y - camera.cloud_bounds.x)

## returns [0., 1.] -> depth underwater (1. would be at the core)
func get_underwater_depth() -> float:
	var dist = (camera.player_position - camera.planet_centre).length()
	return maxf(0., (camera.cur_water_radius - dist) / camera.cur_water_radius)

## returns [-1, 1] -> negative: night, positive: day
## this doesn't make much sense high / beyond the atmosphere, or deep underwater
func get_time_of_day() -> float:
	var local_up = (camera.player_position - camera.planet_centre).normalized()
	return camera.cur_sun_dir.dot(local_up)

## returns [0., 1.] -> 0. low tide, 1. high tide
func get_time_of_tide() -> float:
	return (sin(2. * PI * camera.e_time / camera.tide_time_period) + 1.) * 0.5

## returns -1 if exiting water surface this frame, +1 if entering water surface this frame, 0 otherwise
func get_water_splash() -> int:
	return _water_splash

## returns true if started boosting this frame
func is_started_boost() -> bool:
	return _started_boost

## returns [0., 2.] -> (0. - 1. -> full brake to regular speed ; 1. - 2. ->  regular speed to max boost speed)
func get_speed_ratio() -> float:
	if camera.cur_speed <= camera.speed:
		return camera.cur_speed / camera.speed
	return 1. + (camera.cur_speed - camera.speed) / (camera.max_speed - camera.speed)
