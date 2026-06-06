shader_type canvas_item;

group_uniforms Dependencies;
/**
* Link viewport texture from a SubViewport at a slightly low resolution (like 1280/720).
* This is so that we can reduce GPU load as well as use the inbuilt anti-aliasing.
* In this case the occlusion data is packed into the alpha channel, so SubViewport Transparent BG must be enabled.
*/
uniform sampler2D raymarch_pass; 
/**
* Hacky way of doing this: use another SubViewport at a low proportional resolution, like 0.1 * resolution
* Note: the alpha channel needs to be set to 1.0 on the textureRect in the second Subviewport
* Godot's automatic mipmapping apparently worked at some point, but has now stopped working, we can't take a low LOD sample of the viewport texture
*/
uniform sampler2D downsampled_raymarch_pass;
uniform sampler2D blue_noise: repeat_enable;
uniform vec2 resolution = vec2(1920., 1080.);
uniform float focal_length = 2.;
uniform vec3 screen_coord = vec3(0.);
uniform vec3 screen_dir = vec3(0.);
uniform vec3 screen_up = vec3(0.);
uniform vec3 sun_dir = vec3(0.);

group_uniforms Godrays;
const int max_steps = 64;
const float density_factor = .8;
const float decay_factor = 0.95;
const float noise_dither = 0.02;
const float godrays_str = 0.04;

group_uniforms LensFlare;
uniform sampler2D scatter_gradient;
uniform sampler2D starburst_tex: repeat_enable;
uniform sampler2D lens_dirt;
const int ghost_count = 9;
const float ghost_spacing = .2;
const float ghost_threshold = .9;
const float ghost_str = 1.5;
const float halo_radius = .6;
const float halo_thickness = .05;
const float halo_threshold = 1.;
const float halo_str = 2.;

vec3 aces_tonemap(vec3 color) {
	const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

vec2 world_coordinate_to_uv(vec3 p, vec3 centre, vec3 forward, vec3 up) {
	
	if (abs(dot(forward, up)) > 0.99) {
		up = normalize(vec3(up.z, up.x, up.y));
	} 
	
	vec3 base_right = normalize(cross(up, forward));
	vec3 base_up = cross(forward, base_right);
	
	vec3 p_vec = p - centre;
	float uv_x = dot(p_vec, base_right);
	float uv_y = dot(p_vec, base_up);
	
	return vec2(uv_x, uv_y);
}

//line -> l0 + t.l = p, plane -> (p - p0).n = 0  {t is scalar}
vec3 ray_plane_intersection(vec3 l0, vec3 l, vec3 p0, vec3 n) {
	float t = dot(p0 - l0, n) / dot(l, n);
	return l0 + t * l;
}

//ray plane intersection, gives uv in clip space
vec2 sun_dir_to_uv(vec3 ray_origin, vec3 ray_dir) {
	vec3 sun_ray_intersection_point = ray_plane_intersection(ray_origin, ray_dir, screen_coord, screen_dir);
	vec2 sun_uv_clip = world_coordinate_to_uv(sun_ray_intersection_point, screen_coord, screen_dir, screen_up);
	
	return sun_uv_clip;
}

vec2 jitter_uv(vec2 uv, float dither_factor) {
	vec2 p = uv;
	p.x += (texture(blue_noise, uv * 2.).r * 2.0 - 1.0) * dither_factor;
	p.y += (texture(blue_noise, uv * 2. + 0.1).r * 2.0 - 1.0) * dither_factor;
	return p;
}

vec3 godrays_march(vec2 uv, vec2 sun_uv, sampler2D base_texture) {
	vec2 sun_vec_2d = sun_uv - uv;
	
	float dist = length(sun_vec_2d);
	if (dist < 0.0001) { return vec3(0.); }
	
	vec2 step_vec = sun_vec_2d / float(max_steps) * density_factor;
	vec2 p = jitter_uv(uv, noise_dither);
	
	vec3 godrays = vec3(0.);
	float decay = 1.;

	for (int i = 0; i < max_steps; i++) {
		p += step_vec;
		if (p.x < 0. || p.x > 1. || p.y < 0. || p.y > 1.) {
			decay *= decay_factor;
			continue;
		}
		vec4 s = texture(base_texture, p);
		godrays += s.rgb * s.a * decay;
		decay *= decay_factor;
	}
	
	return godrays * godrays_str;
}

float window_cubic(float _x, float _center, float _radius) {
	_x = min(abs(_x - _center) / _radius, 1.0);
	return 1.0 - _x * _x * (3.0 - 2.0 * _x);
}

vec3 apply_threshold(in vec3 _rgb, in float _threshold) {
	return max(_rgb - vec3(_threshold), vec3(0.0));
}

vec3 lens_flare(vec2 uv, float aspect, sampler2D downsampled_texture) {
	
	//based almost entirely on this article: https://john-chapman.github.io/2017/11/05/pseudo-lens-flare.html
	
	
	vec2 scaled_uv = vec2((uv.x - 0.5) * aspect + 0.5, uv.y);
	
	
	//ghosts
	vec3 ghost = vec3(0.);
	vec2 g_uv = vec2(1.) - uv;
	vec2 ghost_vec = (vec2(0.5) - g_uv) * ghost_spacing;
	
	for (int i = 0; i < ghost_count; i++) {
		vec2 s_uv = fract(g_uv + ghost_vec * vec2(float(i)));
		s_uv = jitter_uv(s_uv, 0.01);
		float d = distance(uv, vec2(0.5));
		float weight = 1. - smoothstep(0., 0.707, d);
		vec3 s = texture(downsampled_texture, s_uv).rgb;
		s = apply_threshold(s, ghost_threshold);
		ghost += s * weight;
	}
	
	ghost *= texture(scatter_gradient, vec2(distance(vec2(0.5), scaled_uv))).rgb;
	ghost *= ghost_str;


	//halo
	vec2 h_uv = (uv - vec2(0.5)) * vec2(aspect, 1.);
	h_uv = jitter_uv(h_uv, 0.02);
	
	vec2 haloVec = vec2(0.) - h_uv;
	haloVec = normalize(haloVec);
	float d = length(h_uv);
	float haloWeight = window_cubic(d, halo_radius, halo_thickness); 
	haloVec *= halo_radius;
	
	vec2 sample_uv = (h_uv + haloVec) / vec2(aspect, 1.) + vec2(0.5);
	vec3 halo = texture(downsampled_texture, sample_uv).rgb;
	halo = apply_threshold(halo, halo_threshold) * haloWeight;
	
	float halo_color_mask = 1. - clamp((halo_radius - d) / halo_thickness, 0., 1.);
	halo *= texture(scatter_gradient, vec2(halo_color_mask)).rgb;
	halo *= halo_str;
	
	//starburst
	vec2 centerVec = scaled_uv - vec2(0.5);
	d = length(centerVec);
	float radial = acos(centerVec.x / d);
	float offset = screen_dir.x + screen_dir.y;
	float burst_mask = texture(starburst_tex, vec2(radial + offset * 1.0, 0.0)).r
					* texture(starburst_tex, vec2(radial - offset * 0.5, 0.0)).r;
	burst_mask = clamp(burst_mask + (1.0 - smoothstep(0., 1., d)), 0., 1.);
	
	vec3 full_flare = (ghost + halo) * burst_mask;
	
	
	return full_flare;
}

void fragment() {
    vec4 tex_data = texture(raymarch_pass, UV);
    vec3 base_color = tex_data.rgb;

	float aspect = resolution.x / resolution.y;
	vec3 forward = normalize(screen_dir);
	vec3 cam_pos = screen_coord - forward * focal_length;
	
	vec2 sun_uv = sun_dir_to_uv(cam_pos, normalize(sun_dir));
	sun_uv.x = (sun_uv.x / (aspect * 2.0)) + 0.5;
	sun_uv.y = 0.5 - (sun_uv.y / 2.0);
	
	vec3 dirt = texture(lens_dirt, UV).rgb;
	vec3 godrays = vec3(0.);
	vec3 flare = lens_flare(UV, aspect, downsampled_raymarch_pass);
	if(dot(sun_dir, screen_dir) > 0.) {
		godrays = godrays_march(UV, sun_uv, raymarch_pass);
	}
    
	vec3 final_color = base_color;
	final_color += godrays + mix(flare, flare * dirt, .9);
	final_color = aces_tonemap(final_color);
	
    COLOR = vec4(final_color, 1.);
}