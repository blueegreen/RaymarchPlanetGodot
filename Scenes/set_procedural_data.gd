extends Node
class_name SetProcData

@export_category("Dependencies")
@export var ray_march_sprite : ColorRect
var shader : ShaderMaterial

func _ready() -> void:
	if not ray_march_sprite:
		return
	shader = ray_march_sprite.material
	set_3d_noise()
	set_mountains()
	
func set_3d_noise():
	var noise_3d := NoiseTexture3D.new()
	noise_3d.seamless = true
	noise_3d.seamless_blend_skirt = 0.5
	
	var noise_generator := FastNoiseLite.new()
	noise_generator.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_generator.seed = randi()
	noise_generator.frequency = randf_range(0.015, 0.04)
	noise_generator.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	
	noise_3d.noise = noise_generator
	shader.set_shader_parameter("noise_texture3d", noise_3d)
	shader.set_shader_parameter("terrain_threshold_min", randf_range(0.6, 0.75))
	
func set_mountains():
	var noise_2d := NoiseTexture2D.new()
	noise_2d.seamless = true
	noise_2d.seamless_blend_skirt = 0.4
	
	var noise_generator := FastNoiseLite.new()
	noise_generator.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_generator.frequency = randf_range(0.0005, 0.002)
	noise_generator.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_generator.fractal_gain = randf_range(0.4, 0.7)
	
	noise_2d.noise = noise_generator
	
	shader.set_shader_parameter("mountain_texture", noise_2d)
	shader.set_shader_parameter("mountain_threshold_min", randf_range(0.2, 0.4))
	shader.set_shader_parameter("mountain_threshold_range", randf_range(0.3, 1.))
	shader.set_shader_parameter("mountain_height", randf_range(3., 7.))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("right_click"):
		_ready()
