shader_type canvas_item;

group_uniforms ScreenUniforms;
uniform vec2 resolution = vec2(1920., 1080.);

group_uniforms CameraUniforms;
uniform float focal_length = 2.;
uniform vec3 screen_coord = vec3(0., 0., -3.);
uniform vec3 screen_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 screen_up = vec3(0.0, 1.0, 0.0);

group_uniforms RenderUniforms;
uniform float min_step_size = 0.005;
uniform float max_t = 50.;
uniform int max_steps = 256;

group_uniforms HairUniforms;
uniform sampler2D wind_noise: repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_color;
uniform float hair_dither_blend = 0.2;
uniform float hair_max_height = 0.7;
uniform float hair_min_height = 0.3;
uniform float hair_density = 40.;
uniform float step_size_in_hair = 0.03;
uniform float hair_specular_str = .2;
uniform float hair_specular_exp = 128.;
uniform float wind_str = 2.;
uniform float wind_frq = .05;
uniform float wind_speed = .05;
uniform vec3 wind_dir = vec3(1., 0.5, 0.);

group_uniforms LightUniforms;
uniform vec3 sun_dir = vec3(0.5, 0.5, 0.0);
uniform vec3 sun_color: source_color;
uniform vec3 sky_color: source_color;
uniform float shadow_k = 0.175;
uniform int shadow_max_steps = 32;
uniform float ambient_str = 0.2;

group_uniforms CloudUniforms;
uniform sampler3D cloud_noise: repeat_enable, filter_linear_mipmap;
uniform float cloud_lower_y = 6.0;
uniform float cloud_upper_y = 24.0;
uniform float cloud_scaling_factor = 16.;
uniform float cloud_density = .8;
uniform float extinction_mult = 1.0;
uniform float scattering_mu = 1.33;
uniform int cloud_max_steps = 64;
uniform int cloud_light_sample_max_steps = 6;

vec3 aces_tonemap(vec3 color) {
	const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float saturate(float f) {
	return clamp(f, 0., 1.);
}

mat2 rotate2D(float angle) {
	float s = sin(angle), c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

vec3 get_transformed_uv(vec2 uv, vec3 centre, vec3 forward, vec3 up) {
	if (abs(dot(forward, up)) > 0.99)
		up = normalize(vec3(up.z, up.x, up.y));

	vec3 base_right = normalize(cross(up, forward));
	vec3 base_up = cross(forward, base_right);
	return centre + base_right * uv.x + base_up * uv.y;
}

vec2 get_triplanar_uv(vec3 p, vec3 n) {
	p = fract(p);
	
	n.x += hair_dither_blend * (hash21(p.yz) * 2.0 - 1.0);
	n.y += hair_dither_blend * (hash21(p.xz) * 2.0 - 1.0);
	n.z += hair_dither_blend * (hash21(p.xy) * 2.0 - 1.0);

	n = normalize(n);
	vec3 w = abs(n);
	w /= dot(w, vec3(1.0));
	
	return (w.x > w.y && w.x > w.z) ? p.yz 
		: (w.y > w.x && w.y > w.z) ? p.xz 
		: p.xy;
}

float sdSphere(vec3 p, float r) {
	return length(p) - r;
}

float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz)-t.x,p.y);
	return length(q)-t.y;
}

float opUnion(float a, float b) { return min(a, b); }

float opSmoothUnion(float a, float b, float k) {
	k *= 4.0;
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

float map_base_sdf(vec3 p) {
	float scene = 1e10;
	scene = opUnion(scene, p.y + 1.);
	scene = opUnion(scene, sdSphere(p, 1.));
	vec3 q = p - vec3(1.5, 1.5, 0.);
	q.yz *= rotate2D(PI/2.);
	scene = opSmoothUnion(scene, sdTorus(q, vec2(1., 0.1)), .2);
	return scene;
}

vec3 base_gradient(vec3 p) {
	const float eps = 0.001;
	const float inv_4eps = 250.0;
	const vec2 k = vec2(-1.0, 1.0);
	return (
		k.xyy * map_base_sdf(p + k.xyy * eps) +
		k.yyx * map_base_sdf(p + k.yyx * eps) +
		k.yxy * map_base_sdf(p + k.yxy * eps) +
		k.xxx * map_base_sdf(p + k.xxx * eps)
	) * inv_4eps;
}

vec2 map_hair(vec3 p) {
	float base_sdf = map_base_sdf(p);
	if (base_sdf < min_step_size || base_sdf > hair_max_height) return vec2(base_sdf - hair_max_height * 0.9, 0.);
	
	vec3 normal = normalize(base_gradient(p));
	
	float sample_wind = texture(wind_noise, (p - base_sdf * normal).xz * wind_frq + TIME * wind_speed).r;
	sample_wind = sample_wind * 2.0 - 1.0;
	float wave = sample_wind * wind_str;
	vec3 wind_disp = normalize(wind_dir) * wave * base_sdf;
	p += wind_disp;
	
	vec2 s_uv = get_triplanar_uv(p, normal); 
	
	float base_hair_mask = hash21(floor(s_uv * hair_density)) * (1. - hair_min_height) + hair_min_height;
	float height_mask = 1. - smoothstep(0., base_hair_mask * hair_max_height, base_sdf);
	
	float dist_from_centre = length(fract(s_uv * hair_density) - vec2(0.5));
	float taper_mask = 1. - smoothstep(0., 0.707 * height_mask, dist_from_centre);
	
	if (taper_mask > 0.) return vec2(0., 1. - height_mask);
	
	return vec2(step_size_in_hair, 1.);
}

vec2 intersect_slab(vec3 p0, vec3 rd, float y_min, float y_max) {
	if (abs(rd.y) < 1e-5) {
		if (p0.y >= y_min && p0.y <= y_max) return vec2(0.0, 1e10);
		return vec2(-1.0, -1.0);
	}
	float t1 = (y_min - p0.y) / rd.y;
	float t2 = (y_max - p0.y) / rd.y;
	return vec2(min(t1, t2), max(t1, t2));
}

float sample_cloud_noise(vec3 p) {
	vec3 q = p / cloud_scaling_factor;
	q.xy *= rotate2D(TIME / 50.);
	q.z += TIME / 15.;
	
	vec3 n = texture(cloud_noise, q).rgb;
	float sample_noise = clamp(n.r - (1.0 - n.g) * 0.5 - (1.0 - n.b) * 0.25, 0.0, 1.0);
	
	float h = abs(p.y - (cloud_upper_y + cloud_lower_y) * 0.5) - (cloud_upper_y - cloud_lower_y) * 0.5;
	sample_noise *= smoothstep(0.0, -1.0, h);
	sample_noise = clamp(sample_noise + cloud_density - 1., 0., 1.);
	return sample_noise;
}

float get_cloud_density_along_ray(vec3 p0, vec3 ray_dir) {
	vec2 hit = intersect_slab(p0, ray_dir, cloud_lower_y, cloud_upper_y);
	if (hit.y < 0.0) return 0.0;
	
	float t_in = max(0.0, hit.x);
	float t_out = min(max_t, hit.y);
	if (t_in >= t_out) return 0.0;
	
	float step_size = (t_out - t_in) / float(cloud_max_steps);
	float total_density = 0.0;
	float t = t_in + step_size * 0.5;
	
	for (int i = 0; i < cloud_max_steps; i++) {
		vec3 p = p0 + ray_dir * t;
		float d = sample_cloud_noise(p);
		total_density += d * step_size;
		
		if (exp(-total_density * extinction_mult) < 0.001) {
			break;
		}
		t += step_size;
	}
	
	return total_density;
}

float calc_soft_shadow(vec3 p, vec3 n, vec3 light_dir) {
	float shadow = 1.0;
	float ph = 1e10;
	vec3 start_p = p + n * min_step_size;
	float t = min_step_size;

	for (int i = 0; i < shadow_max_steps && t < max_t; i++) {
		float h = map_base_sdf(start_p + light_dir * t) - hair_max_height * 0.2;
		if (h <= min_step_size || shadow <= 0.001) {
			shadow = 0.0;
			break;
		}
		float y = h * h / (2.0 * ph);
		float d = sqrt(h * h - y * y);
		shadow = min(shadow, d / (shadow_k * max(0.0, t - y)));
		ph = h;
		t += h;
	}
	
	if (shadow > 0.001) {
		float density = get_cloud_density_along_ray(p, light_dir);
		float cloud_transmittance = max(exp(-density * extinction_mult), 0.4);
		shadow *= cloud_transmittance;
	}

	return shadow;
}

vec3 calc_light(vec3 p, vec3 rd, vec3 light_dir, vec3 normal) {
	vec3 tangent = normal; 
	vec3 view_dir = -rd;

	float dotTL = saturate(dot(tangent, light_dir));
	float diffuse = sqrt(max(1.0 - dotTL * dotTL, 0.0));

	vec3 half_vector = normalize(light_dir + view_dir);
	float dotTH = saturate(dot(tangent, half_vector));
	float sinTH = sqrt(max(1.0 - dotTH * dotTH, 0.0));
	float specular = hair_specular_str * pow(sinTH, hair_specular_exp);
	float shadow = calc_soft_shadow(p, normal, light_dir);
	vec3 final_light = sun_color * (diffuse + specular) * shadow + ambient_str * sky_color;

	return final_light;
}

float HenyeyGreenstein(float g, float costh) {
	return (1. / (PI * 4.)) * ((1. - g * g) / pow(1. + g * g - 2. * g * costh, 1.5));
}

float MultipleOctaveScattering(float density, float mu) {
	float attenuation = 0.2;
	float contribution = 0.4;
	float phaseAttenuation = 0.1;
	
	const float scatteringOctaves = 6.0;
	
	float a = 1.;
	float b = 1.;
	float c = 1.;
	
	float luminance = .05;
	
	for (float i = 0.; i < scatteringOctaves; i++) {
		float phaseFunction = HenyeyGreenstein(0.3 * c, mu);
		float d = density * extinction_mult * a;
		float beers_powder = exp(-d);
		
		luminance += b * phaseFunction * beers_powder;
		
		a *= attenuation;
		b *= contribution;
		c *= 1. - phaseAttenuation;
	}
	return luminance;
}

vec3 sample_cloud_light(vec3 p0) {
	vec3 l_dir = normalize(sun_dir);
	vec2 hit = intersect_slab(p0, l_dir, cloud_lower_y, cloud_upper_y);
	
	float t_out = hit.y;
	float step_size = max(t_out / float(cloud_light_sample_max_steps), 0.01);
	float t = step_size * 0.5;
	float total_density = 0.0;
	
	for (int j = 0; j < cloud_light_sample_max_steps; j++) {
		if (t > t_out) break;
		vec3 p = p0 + l_dir * t;
		total_density += sample_cloud_noise(p) * step_size;
		t += step_size;
	}
	
	vec3 accum_light = sky_color * ambient_str;
	accum_light += MultipleOctaveScattering(total_density, scattering_mu) * sun_color;
	
	return accum_light;
}

vec3 render_clouds(vec3 p0, vec3 rd, vec3 background_color, float max_dist) {
	vec2 hit = intersect_slab(p0, rd, cloud_lower_y, cloud_upper_y);
	if (hit.y < 0.0) return background_color;
	
	float t_in = max(0.0, hit.x);
	float t_out = min(max_dist, hit.y);
	if (t_in >= t_out) return background_color;
	
	float step_size = (t_out - t_in) / float(cloud_max_steps);
	float t = t_in + step_size * 0.5;
	float cloud_t = 0.0;
	vec3 cloud_c = vec3(0.0);
	
	for (int i = 0; i < cloud_max_steps; i++) {
		vec3 p = p0 + rd * t;
		float d = sample_cloud_noise(p);
		
		if (d > 0.001) {
			float current_transmittance = exp(-cloud_t * extinction_mult);
			if (current_transmittance < 0.001) {
				break;
			}
			vec3 cloud_light = sample_cloud_light(p);
			cloud_c += cloud_light * current_transmittance * (d * step_size);
			cloud_t += d * step_size;
		}
		t += step_size;
	}
	
	float cloud_accum = exp(-cloud_t * extinction_mult);
	vec3 final_color = cloud_c + background_color * cloud_accum;
	
	return final_color;
}

vec3 main_raymarch_loop(vec3 p0, vec3 rd) {
	vec3 p = p0;
	float t = 0.0;
	float steps = 0.0;
	vec2 h = vec2(1e10, 1.);
	
	for (int i = 0; i < max_steps && t < max_t; i++) {
		h = map_hair(p);
		if (h.x < min_step_size) break;
		steps += 1.;
		t += h.x * 0.9;
		p = p0 + rd * t;
	}
	
	vec3 terrain_color;
	float hit_distance = t;
	
	if (t >= max_t || steps >= float(max_steps)) {
		terrain_color = sky_color;
		hit_distance = max_t;
	} else {
		vec3 normal = normalize(base_gradient(p));
		vec3 light = calc_light(p, rd, normalize(sun_dir), normal);
		light *= h.y;
		terrain_color = texture(grass_color, vec2(h.y)).rgb * light;
	}
	
	vec3 cloud_col = render_clouds(p0, rd, terrain_color, hit_distance);
	
	return aces_tonemap(cloud_col);
}

void fragment() {
	float aspect = resolution.x / resolution.y;
	vec2 uv = vec2((UV.x - 0.5) * aspect, 0.5 - UV.y) * 2.0;
	vec3 forward = normalize(screen_dir);
	vec3 up = normalize(screen_up);
	vec3 uv_world = get_transformed_uv(uv, screen_coord, forward, up);
	vec3 cam_pos = screen_coord - forward * focal_length;

	COLOR.rgb = main_raymarch_loop(cam_pos, normalize(uv_world - cam_pos));
}