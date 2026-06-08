shader_type canvas_item;
render_mode blend_disabled;

group_uniforms ScreenUniforms;
uniform vec2 resolution = vec2(1920., 1080.);

group_uniforms CameraUniforms;
/**
* distance of camera (ray start position) from screen_coord
*/
uniform float focal_length = 2.; 
/**
* position of screen centre in world space
*/
uniform vec3 screen_coord = vec3(0.);
/**
* screen facing direction (local z) in world space
*/
uniform vec3 screen_dir = vec3(0.0, 0.0, 1.0);
/**
* local up direction in world space. this needs to be set from gdscript dynamically
*/
uniform vec3 screen_up = vec3(0.0, 1.0, 0.0);

group_uniforms RenderUniforms;
const int binary_search_steps = 8;
const float min_step_size = 0.01;
const float max_t = 100.;
const int max_steps = 256;
/**
* epsilon value when calculating normals
*/
const float d_norm = 0.05;
/**
* conservative step factor in sphere tracing
*/
const float ray_subdivision = 0.5;

group_uniforms LightUniforms;
uniform samplerCube star_cubemap: filter_linear_mipmap;
const float soft_shadow_k = .175;
const int max_shadow_steps = 64;
const float ambient_str = .15;
uniform vec3 sun_dir = vec3(1., 0., 0.);
uniform vec3 sun_col: source_color = vec3(1.);
const float sun_disc_angle = 0.03;
const float sun_intensity = 1.;
const int ao_max_steps = 3;
const float ao_step_size = 0.3;
const float ao_str = 1.;

group_uniforms PlanetUniforms;
uniform sampler3D noise_texture3d: repeat_enable, filter_linear_mipmap;
uniform sampler2D mountain_texture: repeat_enable, filter_linear_mipmap;
/**
* clamp minimum of 3d noise texture
*/
uniform float terrain_threshold_min = 0.63;
/**
* clamp range of 3d noise texture. This needs to be very small to prevent raymarch step wastage and artefacts.
*/
const float terrain_threshold_range = 0.085;

uniform float mountain_threshold_min = 0.1;
uniform float mountain_threshold_range = 1.;

const float terrain_scaling = 20.;
const float mountain_scaling = 1.;
uniform float mountain_height = 5.;
uniform float planet_radius = 30.;
uniform vec3 planet_centre = vec3(0., 0., 40.);
uniform vec3 planet_rotation_axis = vec3(0., 1., 0.);
uniform float planet_rotation_speed = 0.0;

group_uniforms TextureUniforms;
uniform sampler2D rock_texture: repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_normal: repeat_enable, filter_linear_mipmap;
const float rock_specular = 24.;
const float texture_scaling = .315;
const float texture_normal_map_strength = .7;
uniform vec3 beach_col: source_color;
uniform vec3 snow_col: source_color;

group_uniforms GrassUniforms;
uniform sampler2D grass_noise: repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_color;
const vec2 grass_elevation_range = vec2(1.6, 3.);
const float grass_density = 1.;
const float grass_coverage = .2;
const float grass_max_height = .3;
const float grass_frequency = 50.;
const float step_size_in_grass = 0.04;
const float wind_str = 2.;
const float wind_frq = .1;
const float wind_speed = .05;
const vec3 wind_dir = vec3(1., 0.5, 0.);


group_uniforms AtmosphereUniforms;
uniform float atm_radius = 55.;
const vec3 atm_scattering_coeff = vec3(0.1066, 0.3244, 0.683);
const float atm_scattering_str = 0.32;
const float atm_height_falloff = 4.;
const int atm_in_scatter_points = 6;
const int atm_optical_depth_points = 6;
const float atm_phase_constant = 0.65;

group_uniforms CloudUniforms;
uniform sampler3D cloud_texture: repeat_enable, filter_linear_mipmap;
uniform vec2 cloud_height_bounds = vec2(36., 44.);
const float cloud_speed = .01;
const float cloud_scaling_factor = 15.;
const float cloud_density = .6;
const float extinction_mult = .7;
const float scattering_mu = 1.33;
const float cloud_max_sample_distance = 50.;
const int cloud_max_steps = 64;
const int cloud_light_sample_max_steps = 6;
const int cloud_shadow_sample_max_steps = 8;

group_uniforms OceanUniforms;
uniform sampler2D ocean_noise_texture: repeat_enable, filter_linear_mipmap;
uniform sampler2D ocean_caustics_texture: repeat_enable, filter_linear_mipmap;
uniform sampler2D ocean_foam_texture: repeat_enable, filter_linear_mipmap;
const int water_max_steps = 64;
uniform float water_radius = 31.;
const vec3 water_diffusion = vec3(0.45, 0.07, 0.02);
/**
* gradient of water inscattering color, based on depth
*/
uniform sampler2D water_scatter_color_gradient;
const float water_scatter_str = .4;
const float air_to_water_io = 0.75;
const float water_to_air_io = 1.33;
const float water_fresnel_f0 = 0.02;
const float wave_scale = 10.0;
const float wave_strength = 0.06;
const float wave_speed = 0.05;
const float water_specularity = 256.;
const float water_specular_strength = .1;
const float caustics_scale = .03;
const float caustics_speed = .05;
const float caustics_str = 0.4;
const float beach_foam_dist = 1.;
const float beach_foam_wavelets = 3.;
const float wavelet_speed = 2.;
const float beach_foam_str = 1.;
/**
* fun warp effect, needs gdscript to trigger properly
* if p_from_centre.length() <= warp_radius * 0.5:
*	var scale_factor = outer_warp_radius / warp_radius
*	screen_coord = planet_centre + p_from_centre * scale_factor
*/
uniform float warp_radius = 3.;
uniform float outer_warp_radius = 90.;


mat2 rotate2D(float angle) {
	float s = sin(angle), c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

mat3 rotate3D(vec3 axis, float angle) {
	if (abs(angle) < 0.01) return mat3(1.);
    float s = sin(angle), c = cos(angle), oc = 1.0 - c;
	return mat3(
        vec3(oc*axis.x*axis.x + c,          oc*axis.x*axis.y - axis.z*s,   oc*axis.z*axis.x + axis.y*s),
        vec3(oc*axis.x*axis.y + axis.z*s,   oc*axis.y*axis.y + c,          oc*axis.y*axis.z - axis.x*s),
        vec3(oc*axis.z*axis.x - axis.y*s,   oc*axis.y*axis.z + axis.x*s,   oc*axis.z*axis.z + c)
    );
}

//transforms clip space uv to world coordinates
vec3 get_transformed_uv(vec2 uv, vec3 centre, vec3 forward, vec3 up) {
	
	if (abs(dot(forward, up)) > 0.99) {
		up = normalize(vec3(up.z, up.x, up.y));
	} 
	
	vec3 base_right = normalize(cross(up, forward));
	vec3 base_up = cross(forward, base_right);
	return centre + base_right * uv.x + base_up * uv.y;
}

//faster than triplanar, but need to fade out near poles to avoid pinching
vec2 get_spherical_uv(vec3 n) {
	float u = atan(n.z, n.x) / (2.0 * PI) + 0.5;
	float v = asin(n.y) / PI + 0.5;
	return vec2(u, v);
}

//returns (distance to intersection, distance travelled through sphere)
//distance to intersection = 0. if inside sphere, 1e10 / inf if outside sphere
vec2 ray_sphere_intersection(vec3 centre, float radius, vec3 p0, vec3 rd) {
	vec3 offset = p0 - centre;
	float b = 2. * dot(offset, rd);
	float c = dot(offset, offset) - radius * radius;
	float d = b * b - 4. * c;

	if (d > 0.) {
		float s = sqrt(d);
		float d_near = max(0., (-b - s) * 0.5);
		float d_far  = (-b + s) * 0.5;
		if (d_far >= 0.)
			return vec2(d_near, d_far - d_near);
	}
	return vec2(1e10, 0);
}

float opUnion(float a, float b)        { return min(a, b); }
float opSubtraction(float a, float b)  { return max(-a, b); }
float opIntersection(float a, float b) { return max(a, b); }

float sdSphere(vec3 p, float r) {
	return length(p) - r;
}

float sdBox( vec3 p, vec3 b ) {
	vec3 q = abs(p) - b;
	return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdOctahedron( vec3 p, float s ) {
	p = abs(p);
	float m = p.x+p.y+p.z-s;
	vec3 q;
	    if( 3.0*p.x < m ) q = p.xyz;
	else if( 3.0*p.y < m ) q = p.yzx;
	else if( 3.0*p.z < m ) q = p.zxy;
	else return m*0.57735027;

	float k = clamp(0.5*(q.z-q.y+s),0.0,s); 
	return length(vec3(q.x,q.y-s+k,q.z-k)); 
}


//orients global position to planet local position
vec3 planet_pos(vec3 p) {
    vec3 lp = p - planet_centre;
	if (abs(planet_rotation_speed) < 0.001) return lp / terrain_scaling;
    lp *= rotate3D(normalize(planet_rotation_axis), TIME * planet_rotation_speed);
	lp /= terrain_scaling;
    return lp;
}

vec4 triplanar_map(vec3 p, vec3 n, sampler2D tex, float scale, float sharpness, float lod) {
	vec3 s = sign(n);

	vec4 sx = textureLod(tex, vec2(p.z * s.x, p.y) / scale, lod);
	vec4 sy = textureLod(tex, vec2(p.x * s.y, p.z) / scale, lod);
	vec4 sz = textureLod(tex, vec2(p.x * s.z, p.y) / scale, lod);

	vec3 w = pow(abs(n), vec3(sharpness));
	w /= dot(w, vec3(1.0));
	return sx * w.x + sy * w.y + sz * w.z;
}

//main sdf / noise calculation for terrain
float map_terrain(vec3 p, float lod) {
	vec3 q = planet_pos(p);
	vec3 lp = p - planet_centre;
	vec3 radial_dir = normalize(lp);
	
	//lerp the sampled noise based on threshold and range
	//note that this is NOT clamped, which is actually better for conservative sphere tracing
	//however, threshold range must be kept small, as a large threshold range results in increasingly
	//smaller sdf values, which causes the ray to take smaller and smaller steps and causes artefacting
	float scene = 
		(textureLod(noise_texture3d, q, lod).r - terrain_threshold_min)
		/ terrain_threshold_range;
	
	//scene += 1.5 * max(elevation - planet_radius, 0.);
	
	{
		vec3 lp_rotating = lp * rotate3D(normalize(sun_dir), TIME * 0.5);
		scene = opIntersection(scene, sdSphere(lp, planet_radius));
		scene = opSubtraction(sdSphere(lp, warp_radius * 2.), scene);
		scene = opUnion(scene, sdBox(lp_rotating, vec3(warp_radius)));
		scene = opSubtraction(sdOctahedron(lp, warp_radius * 2.), scene);

		float noise_m = triplanar_map(q, radial_dir, mountain_texture, mountain_scaling, 10., lod).r;
		noise_m = clamp((noise_m - mountain_threshold_min) / mountain_threshold_range, 0., 1.);
		float s = opSubtraction(sdSphere(lp, planet_radius), scene - noise_m * mountain_height);
		scene = opUnion(scene, s);
	}
	
	vec2 spherical_uv = get_spherical_uv(radial_dir);
	float pole_fade = 1. - smoothstep(0.9, 1., abs(radial_dir.y));
	scene -= .2 * pole_fade * textureLod(rock_texture, spherical_uv / texture_scaling, lod).r;
	
	//moon
	scene = opUnion(scene, sdSphere(p - (planet_centre - vec3(1., .3, 0.) * 80.), 5.));
	
	return scene;
}

//gets normal at global position based on tetrahedron method, + triplanar map to get rock texture
//need to update to allow multiple textures
vec3 map_normal(vec3 pos, float lod) {
	vec2 e = vec2(1.0, -1.0) * 0.5773 * d_norm;
	vec3 geo_n = normalize(
		e.xyy * map_terrain(pos + e.xyy, lod) +
		e.yyx * map_terrain(pos + e.yyx, lod) +
		e.yxy * map_terrain(pos + e.yxy, lod) +
		e.xxx * map_terrain(pos + e.xxx, lod)
	);
	
	//if (lod > 5.) return geo_n;
	
	vec3 p = planet_pos(pos);
	vec3 s = sign(geo_n);

	vec3 tnX = textureLod(rock_normal, vec2(p.z * s.x, p.y) / texture_scaling, lod).rgb * 2.0 - 1.0;
	vec3 tnY = textureLod(rock_normal, vec2(p.x * s.y, p.z) / texture_scaling, lod).rgb * 2.0 - 1.0;
	vec3 tnZ = textureLod(rock_normal, vec2(p.x * s.z, p.y) / texture_scaling, lod).rgb * 2.0 - 1.0;

	vec3 nX = vec3(-tnX.z * s.x,  tnX.y,        tnX.x * s.x);
	vec3 nY = vec3( tnY.x * s.y, -tnY.z * s.y,  tnY.y      );
	vec3 nZ = vec3( tnZ.x * s.z,  tnZ.y,         tnZ.z * s.z);

	vec3 w = pow(abs(geo_n), vec3(10.0));
	w /= dot(w, vec3(1.0));
	return normalize(geo_n + texture_normal_map_strength * (nX * w.x + nY * w.y + nZ * w.z));
}


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 get_triplanar_uv(vec3 p, vec3 n) {
	p = fract(p);
	
	n.x += .2 * (hash21(p.yz) * 2.0 - 1.0);
	n.y += .2 * (hash21(p.xz) * 2.0 - 1.0);
	n.z += .2 * (hash21(p.xy) * 2.0 - 1.0);

	n = normalize(n);
	vec3 w = abs(n);
	w /= dot(w, vec3(1.0));
	
	return (w.x > w.y && w.x > w.z) ? p.yz 
		: (w.y > w.x && w.y > w.z) ? p.xz 
		: p.xy;
}

float is_p_in_grass(vec3 p) {
	float height_above_sealevel = distance(p, planet_centre) - planet_radius;
	float ratio =
		(height_above_sealevel - grass_elevation_range.x)
		/ (grass_elevation_range.y + grass_max_height - grass_elevation_range.x);
	if (ratio < 0. || ratio > 1.) return -1.;
	return ratio;
}

vec2 map_terrain_and_grass(vec3 p, float lod) {
	float base_terrain = map_terrain(p, lod);
	float grass_ratio = is_p_in_grass(p);
	if (grass_ratio < 0.) return vec2(base_terrain, 1.);
	if (base_terrain < min_step_size || base_terrain > grass_max_height) return vec2(base_terrain - grass_max_height * 0.9, 1.);
	
	vec3 terrain_normal = map_normal(p, lod);
	vec3 planet_normal = normalize(p - planet_centre);
	
	float sample_wind = texture(grass_noise, (p - base_terrain * terrain_normal).xz * wind_frq + TIME * wind_speed).r;
	sample_wind = sample_wind * 2.0 - 1.0;
	float wave = sample_wind * wind_str;
	vec3 wind_disp = normalize(wind_dir) * wave * base_terrain;
	p += wind_disp;
	
	vec2 s_uv = get_triplanar_uv(p, terrain_normal); 
	
	float base_grass_mask = 
		smoothstep((1. - grass_density), 1.,
		hash21(floor(s_uv * grass_frequency)));
	base_grass_mask *= 
		smoothstep(0., 1. - grass_coverage,
		textureLod(grass_noise, get_triplanar_uv(p, planet_normal) * .2, lod).r);

	float height_mask = 
		1. - smoothstep(0., base_grass_mask * grass_max_height, base_terrain);
		
	height_mask *=
		smoothstep(0., 0.5, grass_ratio) 
		* smoothstep(1., 0.5, grass_ratio)
		* smoothstep(0.4, 0.7, dot(terrain_normal, planet_normal));
	
	
	float dist_from_centre = length(fract(s_uv * grass_frequency) - vec2(0.5));
	float taper_mask = 1. - smoothstep(0., 0.707 * height_mask, dist_from_centre);
	
	if (taper_mask > 0.) return vec2(0., 1. - height_mask);
	
	return vec2(step_size_in_grass, 1.);
}


//if p0 + rd * t still at safe position, but next step would result in collision
float binary_refinement(float t, float step_size, vec3 p0, vec3 rd, float lod) {
	float t_safe = t;
	float binary_term = 0.5;
	for (int i = 0; i < binary_search_steps; i++) {
		float mid_t = t_safe + step_size * binary_term;
		if (map_terrain(p0 + rd * mid_t, lod) > 0.0)
			t_safe = mid_t;
		binary_term *= 0.5;
	}
	return t_safe;
}

//colour of terrain at global position, samples rock texture
//need to update to allow multiple materials
vec3 colour_terrain(vec3 p, vec3 n, float lod) {
	vec3 q = planet_pos(p);
	vec3 base_color = triplanar_map(q, n, rock_texture, texture_scaling, 10., lod).rgb;
	float slope = abs(dot(normalize(q), n));
	float dist_to_centre =  distance(p, planet_centre);
	float elevation = dist_to_centre - planet_radius;
	float elevation_sea_level = dist_to_centre - water_radius;
	float jittered_elevation = elevation + 1. * (texture(ocean_noise_texture, p.xz).r * 2.0 - 1.0);
	
	float snow_layer = smoothstep(3.2, 4.0, jittered_elevation) * smoothstep(10., 3.5, jittered_elevation);
	float steep_mask = smoothstep(.2, .25, slope);
	
	vec3 final_color = mix(base_color, snow_col, step(0.1, snow_layer * steep_mask));
	
	float beach_mask = step(0., elevation_sea_level) * smoothstep(grass_elevation_range.x, grass_elevation_range.x - .3, elevation) * smoothstep(0.2, 0.3, slope);
	final_color = mix(final_color, beach_col * base_color, beach_mask);
	
	return final_color;
}

//simple ambient occlusion march
float ao_terrain(vec3 pos, vec3 n) {
	float ao = 0.;
	vec3 p = pos;
	for (int i = 0; i < ao_max_steps; i++) {
		float h = map_terrain(p, 0.5);
		ao += ((float(i) * ao_step_size + min_step_size) - h) / float(i + 1);
		p += n * ao_step_size;
	}
	return 1. - clamp(ao * ao_str, 0., 1.);
}

//normalized blinn phong specular reflection
float get_specular(vec3 view_dir, vec3 light_dir, vec3 normal, float specular_strength) {
	vec3 half_vec = normalize(light_dir + view_dir);
	float specular = pow(max(dot(normal, half_vec), 0.0), specular_strength) * (specular_strength + 8.0) / (8.0 * PI);
	return specular;
}

float atm_phase_function(float costh) {
	return atm_phase_constant * (1. + costh * costh);
}

//atmosphere density at height, p is global position
float atm_density(vec3 p) {
	float h = (length(p - planet_centre) - planet_radius) / (atm_radius - planet_radius);
	return max(0., exp(-h * atm_height_falloff) * (1. - h));
}

vec3 get_space_color(vec3 p0, vec3 rd, vec3 sun_dir_norm) {
	float dot_sun = dot(sun_dir_norm, rd);
	vec3 starmap = texture(star_cubemap, rd).rgb;
	
	
	//mask to hide stars, 0 -> 1 ; weak -> strong
	float sun_dir_mask = smoothstep(0.0, 0.8, dot_sun);
	
	vec3 local_up = normalize(p0 - planet_centre);
	float sun_horizon_elevation = dot(sun_dir_norm, local_up);
	float day_mask = smoothstep(-0.1, 0.1, sun_horizon_elevation);
	
	float net_mask = clamp(sun_dir_mask + day_mask, 0.0, 1.0);
	
	//mask the mask itself if camera above altitude threshold
	float atm_height_mask = smoothstep(0.0, 0.5, atm_density(p0));
	float star_mask = net_mask * atm_height_mask;
	
	starmap *= (1.0 - star_mask);
	
	return mix(starmap, sun_col * 1.5, step(0., dot_sun - cos(sun_disc_angle)));
}


//casts ray towards sun direction to find transmitted sunlight (luminance?)
float optical_depth(vec3 p0, vec3 rd, float ray_length) {
	float step_size = ray_length / float(atm_optical_depth_points);
	float depth = 0.;
	for (int i = 0; i < atm_optical_depth_points; i++) {
		depth += atm_density(p0) * step_size;
		p0 += step_size * rd;
	}
	return depth;
}

//darkens existing color based on atmospheric transmittance, then adds in-scattered light
vec3 march_atmosphere(vec3 p0, vec3 rd, float t_terrain, vec3 col_terrain, vec3 sun_dir_norm, vec2 ocean_hit) {
	const float epsilon = 0.001;
	vec3 scattering_coeff = atm_scattering_coeff * atm_scattering_str;

	t_terrain = min(t_terrain, ocean_hit.x);

	vec2 atm_hit = ray_sphere_intersection(planet_centre, atm_radius, p0, rd);
	float atm_ray_length = min(atm_hit.y, max(0.0, t_terrain - atm_hit.x)) - epsilon;

	if (atm_ray_length < 0.01) return col_terrain;

	float step_size = atm_ray_length / float(atm_in_scatter_points);
	float phase = atm_phase_function(dot(-rd, sun_dir_norm));

	vec3 p = p0 + (atm_hit.x + epsilon) * rd;
	vec3 in_scattered_light = vec3(0.);
	float atm_optical_depth = 0.;
	vec3 transmittance;

	for (int i = 0; i < atm_in_scatter_points; i++) {
		float sun_ray_length = ray_sphere_intersection(planet_centre, atm_radius, p, sun_dir_norm).y;
		float sun_depth = optical_depth(p, sun_dir_norm, sun_ray_length);
		float local_density = atm_density(p);
		atm_optical_depth += local_density * step_size;
		transmittance = exp(-(sun_depth + atm_optical_depth) * scattering_coeff);

		in_scattered_light +=
			local_density *
			transmittance *
			scattering_coeff *
			phase *
			sun_col *
			sun_intensity *
			step_size;
		p += step_size * rd;
	}
	
	return in_scattered_light + exp(-atm_optical_depth * scattering_coeff) * col_terrain;
}

//it just works
float HenyeyGreenstein(float g, float costh) {
	return (1. / (PI * 4.)) * ((1. - g * g) / pow(1. + g * g - 2. * g * costh, 1.5));
}

//it just works
float MultipleOctaveScattering(float density, float mu) {
	const float attenuation = 0.2, contribution = 0.4, phaseAttenuation = 0.1;
	const float octaves = 4.0;
	float a = 1., b = 1., c = 1., luminance = 0.;

	for (float i = 0.; i < octaves; i++) {
		luminance += b * HenyeyGreenstein(0.3 * c, mu) * exp(-density * extinction_mult * a);
		a *= attenuation;
		b *= contribution;
		c *= 1. - phaseAttenuation;
	}
	return luminance;
}

//samples the 3d cloud texture at planet's local position, but uses a slower rotation speed than the planet
//also warps and moves the cloud texture
float sample_cloud_noise(vec3 p, float lod) {
    vec3 lp = p - planet_centre;
    lp *= rotate3D(normalize(planet_rotation_axis), TIME * planet_rotation_speed * .8);
	
	vec3 q = lp;
	////q += .3 * hash(p.xy) * normalize(q);
	
	q.xz *= rotate2D(TIME * cloud_speed);
	q /= (cloud_scaling_factor + 2. * sin(TIME * cloud_speed * 10.));

	vec4 n = textureLod(cloud_texture, q, lod);
	float base_shape = n.r;
	float detail = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
	float noise = clamp(base_shape - detail * (1.0 - base_shape), 0.0, 1.0);

	float p_height = length(p - planet_centre);
	noise *= smoothstep(cloud_height_bounds.x, cloud_height_bounds.x + 2., p_height)
		   * smoothstep(cloud_height_bounds.y, cloud_height_bounds.y - 5., p_height);

	float threshold = 1.0 - cloud_density;
	const float edge_softness = 0.2;
	return smoothstep(threshold - edge_softness, threshold + edge_softness, noise);
}

//gets the in scattering light at the given point
vec3 sample_cloud_light(vec3 p0, float ray_length, vec3 scattered_sun_col, vec3 sun_dir_norm, float lod) {
	float accum_density = 0.;
	float step_size = ray_length / float(cloud_light_sample_max_steps);
	for (int j = 0; j < cloud_light_sample_max_steps; j++) {
		accum_density += sample_cloud_noise(p0, max(2., lod * 4.)) * step_size;
		p0 += step_size * sun_dir_norm;
	}
	return MultipleOctaveScattering(accum_density, scattering_mu) * scattered_sun_col * sun_intensity;
}

//similar to atmospheric scattering
//in-scattering uses multiple octave scattering to get correct backlighting and stronger silver lining
vec4 march_clouds(vec3 p0, vec3 rd, float t_terrain, vec3 atm_col, vec3 sun_dir_norm, vec2 ocean_hit) {
	vec2 cloud_outer = ray_sphere_intersection(planet_centre, cloud_height_bounds.y, p0, rd);
	float d_in  = cloud_outer.x;
	float d_out = min(cloud_outer.x + cloud_outer.y, min(t_terrain, ocean_hit.x));

	float ray_dist = clamp(d_out - d_in, 0., cloud_max_sample_distance);
	if (ray_dist < 0.01) return vec4(atm_col, 1.);

	float step_size = ray_dist / float(cloud_max_steps);
	const float lod_bias = 10.;
	float lod = (ray_dist / cloud_max_sample_distance) * lod_bias;
	
	vec3 p = p0 + rd * d_in;
	//vec2 atm_sun_hit = ray_sphere_intersection(planet_centre, atm_radius, p, sun_dir_norm);
	//vec3 scattering_coeff = atm_scattering_coeff * atm_scattering_str;
	//vec3 scattered_sun_col = sun_col * exp(-optical_depth(p, sun_dir_norm, atm_sun_hit.y) * scattering_coeff);

	vec3 cloud_c = vec3(0.);
	float t = 0.;
	float cloud_optical_depth = 0.;
	float transmittance = 1.;

	for (int i = 0; i < cloud_max_steps && t < max_t; i++) {
		if (length(p - planet_centre) < cloud_height_bounds.x) {
			p += rd * step_size;
			t += step_size;
			continue;
		}

		float local_density = sample_cloud_noise(p, lod);
		cloud_optical_depth += local_density * step_size;

		transmittance = exp(-cloud_optical_depth * extinction_mult);
		if (transmittance < 0.001) break;

		float light_ray_len = ray_sphere_intersection(planet_centre, cloud_height_bounds.y, p, sun_dir_norm).y;
		cloud_c += sample_cloud_light(p, light_ray_len, sun_col, sun_dir_norm, lod)
			* transmittance * local_density * step_size;

		p += rd * step_size;
		t += step_size;
	}
	
	vec3 cloud_color = cloud_c + atm_col * exp(-cloud_optical_depth * extinction_mult);
	return vec4(cloud_color, transmittance);
}

float get_soft_shadow(vec3 p0, vec3 n, vec3 light_dir, float lod) {
	float shadow = 1.;
	float ph = 1e10;
	p0 += n * (min_step_size * 4.);
	float t = min_step_size;

	for (int i = 0; i < max_shadow_steps && t < max_t; i++) {
		float h = map_terrain(p0 + light_dir * t, lod);

		if (h <= min_step_size || shadow <= 0.001) {
			shadow = 0.;
			break;
		}

		float y = h * h / (2.0 * ph);
		float d = sqrt(h * h - y * y);
		shadow = min(shadow, d / (soft_shadow_k * max(0.0, t - y)));

		ph = h;
		t += h;
	}
	return shadow;
}

//helper to sample only cloud density towards sun direction
float cloud_shadow_transmittance(vec3 p, vec3 sun_dir_norm) {
	vec2 cloud_hit = ray_sphere_intersection(planet_centre, cloud_height_bounds.y, p, sun_dir_norm);
	if (cloud_hit.y < 0.01) return 1.0;

	float step_size = cloud_hit.y / float(cloud_shadow_sample_max_steps);
	float accum_density = 0.0;
	vec3 p0 = p + cloud_hit.x * sun_dir_norm;
    
	for (int i = 0; i < cloud_shadow_sample_max_steps; i++) {
	    accum_density += sample_cloud_noise(p0, 4.0) * step_size;
	    p0 += step_size * sun_dir_norm;
	}
	return exp(-accum_density * extinction_mult);
}

//calculates diffuse + shadow + specular (blinn phong) at given point
//ambient light is added to shadow so that terrain deep underwater doesn't get fully dark
vec3 light_terrain(vec3 p0, vec3 rd, vec3 n, vec3 sun_dir_norm, float lod) {
	float diffuse = clamp(dot(sun_dir_norm, n), 0., 1.);
	float ao = ao_terrain(p0, n);
	
	float specular = get_specular(-rd, sun_dir_norm, n, rock_specular);
	float cloud_shadow = cloud_shadow_transmittance(p0, sun_dir_norm);
	float terrain_shadow = get_soft_shadow(p0, n, sun_dir_norm, lod);
	float shadow = clamp(terrain_shadow * cloud_shadow + ambient_str * ao, 0., 1.);
 
	return sun_col * shadow * (diffuse + specular) * sun_intensity;
}

vec3 light_grass(vec3 p, vec3 rd, vec3 normal, vec3 sun_dir_norm, float lod) {
	vec3 tangent = normal; 
	vec3 view_dir = -rd;

	float dotTL = max(dot(tangent, sun_dir_norm), 0.);
	float diffuse = sqrt(max(1.0 - dotTL * dotTL, 0.0));

	vec3 half_vector = normalize(sun_dir_norm + view_dir);
	float dotTH = max(dot(tangent, half_vector), 0.);
	float sinTH = sqrt(max(1.0 - dotTH * dotTH, 0.0));
	float specular = .5 * pow(sinTH, 96.);
	float terrain_shadow = get_soft_shadow(p, normal, sun_dir_norm, lod);
	float cloud_shadow = cloud_shadow_transmittance(p, sun_dir_norm);
	float shadow = clamp(terrain_shadow * cloud_shadow + ambient_str, 0., 1.);
	return sun_col * shadow * (diffuse + specular) * sun_intensity;
}

float get_fresnel(float f0, float ndotv) {
	return f0 + (1. - f0) * pow(1. - max(0., ndotv), 5.);
}

//adds white texture to the ocean near landmasses
//multiply sin(sdf * wavelet_num * 2PI) to divide up the foam into wavelets
float get_beach_foam(vec3 p, vec3 light_dir, float lod) {
	float h = map_terrain(p, 0.);
	vec3 n = normalize(p - planet_centre);
	
	float pole_fade = 1. - smoothstep(.9, 1., abs(n.y));
	float mask = (1. - smoothstep(0., 1., h / beach_foam_dist));
	
	vec2 s_uv = get_spherical_uv(n);
	float noise1 = textureLod(ocean_foam_texture, (s_uv + TIME * 0.001) * 5., lod).r;
	float noise2 = textureLod(ocean_foam_texture, (s_uv - TIME * 0.003) * 15., lod).r;
	float noise_mask = (noise1 + noise2) * 0.5;
	
	
	noise_mask = clamp((noise_mask - 0.4) * 5., 0., 1.);
	float surf_white = 1. - smoothstep(0., 0.2 * beach_foam_dist, h);
	
	float wavelet = (sin(beach_foam_wavelets * 2. * PI *  h / beach_foam_dist + TIME * wavelet_speed) + 1.) * 0.5;
	float tex_foam = (wavelet) * mask * noise_mask;
	
	return max(surf_white, tex_foam) * pole_fade;  
}

//scrolls the wave texture to simluate waves, using spherical coordinates
//poles need to be faded out to prevent pinched waves
float get_ocean_height(vec3 p, float lod) {
	vec3 rotated = normalize(planet_pos(p));
	vec2 uv = get_spherical_uv(rotated) * wave_scale;
	
	float t1 = TIME * wave_speed;
	float t2 = TIME * wave_speed * 1.3;
	
	float h1 = textureLod(ocean_noise_texture, uv + vec2(t1, 0.0), lod).r;
	float h2 = textureLod(ocean_noise_texture, uv * 1.5 - vec2(0.0, t2), lod).r;
	
	float base_wave = (h1 + h2) * 0.5;
	
	const float max_dist = 2.;
	const float max_wave_height = .5;
	vec3 player_pos = screen_coord - screen_dir * focal_length;
	float player_dist = distance(p, player_pos);
	if (player_dist < max_dist) {
		float ratio = player_dist / max_dist;
		float player_tangent_dist = player_dist - length(normalize(player_pos - planet_centre) * (distance(player_pos, planet_centre) - water_radius));
		float wave_mask = sin(25. * player_tangent_dist / max_dist - 10. * TIME);
		base_wave += wave_mask * max_wave_height * (1. - ratio);
	}
	
	return base_wave;
}

//calculates forward difference normal based on virtual wave height
vec3 ocean_normal(vec3 p, float lod) {
	vec3 base_n = normalize(p - planet_centre);
	float pole_fade = 1.0 - smoothstep(0.85, 0.98, abs(base_n.y));
	
	if (pole_fade < 0.001) return base_n;
	
	vec3 pole = planet_rotation_axis;
	if (abs(dot(pole, base_n)) > 0.999) pole = vec3(1.0, 0.0, 0.0); 
	
	vec3 T = normalize(cross(pole, base_n));
	vec3 B = normalize(cross(base_n, T));
	
	const float epsilon = 0.01; 
	float h  = get_ocean_height(p, lod);
	float ht = get_ocean_height(p + T * epsilon, lod);
	float hb = get_ocean_height(p + B * epsilon, lod);
	
	float grad_t = (ht - h) / epsilon;
	float grad_b = (hb - h) / epsilon;
	
	vec3 perturbed_n = normalize(base_n - (T * grad_t + B * grad_b) * (wave_strength) * pole_fade);
	
	return perturbed_n;
}

//divided into underwater and abovewater (only if ray is reflected / refracted to outside water) passes
//when looking into water, reflection and refraction added based on fresnel effect
//when looking from water, above water light is refracted
//in both cases, underwater terrain color is subject to transmittance and in-scattering 
//additionally beach foam and caustics are added via simple noise texture mapping
vec4 march_ocean(vec3 p0, vec3 rd, float t_terrain, vec3 sun_dir_norm, vec2 ocean_hit) {
	if (ocean_hit.y < 0.01) return vec4(vec3(0.), 1.);
	if (t_terrain < ocean_hit.x) return vec4(0.);
	
	p0 = p0 + rd * ocean_hit.x;
	
	const float epsilon = 0.001;
	const float lod_bias = 10.;
	float lod = 0.;
	
	vec3 p = p0;
	vec3 p0_above = p0;
	float under_costh = 0.;
	float above_costh = 0.;
	
	float occlusion = 0.;
	
	bool above_surface = false;
	
	vec3 init_rd = rd;
	vec3 above_rd = vec3(0.);
	vec3 ocean_n = vec3(0.);
	{
		lod = ocean_hit.x / lod_bias;
		ocean_n = ocean_normal(p, lod);
		vec3 refract_rd = rd;
		if (ocean_hit.x > 0.01) {
			refract_rd = refract(rd, ocean_n, air_to_water_io);
			above_rd = reflect(rd, ocean_n);
			above_costh = dot(-rd, ocean_n);
			above_surface = true;
			p0_above = p + above_rd * epsilon;
		}
		rd = refract_rd;
	}
	
	vec2 warp_hit = ray_sphere_intersection(planet_centre, warp_radius, p0, rd);
	
	float t = 0.;
	float prev_t = 0.;
	float reflection_t = 0.;
	
	//underwater march
	for (int i = 0; i < max_steps && t < max_t; i++) {
		float h = map_terrain(p, lod);
		
		if (h <= min_step_size) {
			t = binary_refinement(prev_t, t - prev_t, p0, rd, lod);
			p = p0 + rd * t;
			break;
		}
		prev_t = t;
		t += h * ray_subdivision;
		p = p0 + rd * t;
		
		if (t >= ocean_hit.y && reflection_t < 0.001) {
			p = p0 + rd * ocean_hit.y;
			lod = t / lod_bias;
			vec3 under_surface_normal = - ocean_normal(p, lod);
			under_costh = dot(-rd, under_surface_normal);
			
			occlusion = 1.;
			
			reflection_t = t;
			t = 0.;
			prev_t = 0.;
			vec3 refract_rd = refract(rd, under_surface_normal, water_to_air_io);
			rd = reflect(rd, under_surface_normal);
			if (dot(refract_rd, refract_rd) > 0.01) {
				above_surface = true;
				above_rd = refract_rd;
				p0_above = p + above_rd * epsilon;
			}
			p += rd * epsilon;
			p0 = p;
		}
		
		if (t >= warp_hit.x) {
			t = warp_hit.x;
			p = p0 + rd * t;
			
			float scale_factor = outer_warp_radius / warp_radius;
			vec3 p_scaled = planet_centre + (p - planet_centre) * scale_factor;
			vec3 focal_correction = screen_dir * focal_length * (scale_factor - 1.0);
			
			above_rd = rd;
			p0_above = p_scaled + focal_correction - above_rd * 20.;
			
			above_surface = true;
			under_costh = dot(-rd, normalize(p - planet_centre));
			occlusion = 1.;
			break;
		}
		
	}

	vec3 water_transmission = exp( - (t + reflection_t) * water_diffusion );
	vec3 underwater_n = map_normal(p, lod);
	vec3 underwater_light = light_terrain(p, rd, underwater_n, sun_dir_norm, lod);
	
	vec3 vec_to_centre = p - planet_centre;
	float dist_to_centre = length(vec_to_centre);
	
	float depth = water_radius - dist_to_centre;
	float relative_depth = clamp(depth / water_radius, 0., 1.);
	float depth_strength = clamp(relative_depth + max(dot(normalize(vec_to_centre), sun_dir_norm), 0.), 0.2, 1.);
	vec3 water_scatter_color = texture(water_scatter_color_gradient, vec2(relative_depth, 0.5)).rgb;
	
	vec3 base_underwater_n = vec_to_centre / dist_to_centre;
	float pole_fade = 1. - smoothstep(0.9, 1., abs(base_underwater_n.y));
	vec2 caustics_uv = get_spherical_uv(base_underwater_n) / caustics_scale;
	vec3 caustics = textureLod(ocean_caustics_texture, (caustics_uv + TIME * caustics_speed), 0.).rgb;
	
	caustics *= 
		get_soft_shadow(p, underwater_n, sun_dir_norm, lod)
		* exp( - depth * water_diffusion)
		* sun_col * sun_intensity
		* pole_fade;
	
	underwater_light += caustics * caustics_str;
	
	vec3 underwater_col = colour_terrain(p, underwater_n, lod) * (underwater_light);
	
	underwater_col *= water_transmission;
	underwater_col += water_scatter_str 
					* water_scatter_color 
					* depth_strength
					* (1.0 - water_transmission);
					//* clamp(relative_depth, .3, 1.);
	
	occlusion = min(occlusion, dot(water_transmission, vec3(0.3333)));
	
	if (!above_surface) return vec4(underwater_col, 0.);
	
	float t_air = 0.;
	vec3 p_air = p0_above;
	
	//abovewater march
	for (int i = 0; i < water_max_steps && t_air < max_t; i++) {
		float h = map_terrain(p_air, 3.);
		if (h <= min_step_size) {
			occlusion = 0.;
			break;
		}
		t_air += h;
		p_air = p0_above + above_rd * t_air;
	}
	vec3 base_above_col;
	
	if (t_air >= max_t) {
		t_air = 1e10;
		base_above_col = get_space_color(p0_above, above_rd, sun_dir_norm);
	} else {
		vec3 abovewater_n = map_normal(p_air, 3.);
		base_above_col = colour_terrain(p_air, abovewater_n, 3.) * light_terrain(p_air, above_rd, abovewater_n, sun_dir_norm, 3.);
	}
	
	vec2 new_ocean_hit = ray_sphere_intersection(planet_centre, water_radius, p0_above, above_rd);
	vec4 cloud_col = march_clouds(p0_above, above_rd, t_air, base_above_col, sun_dir_norm, new_ocean_hit);
	vec3 above_col = march_atmosphere(p0_above, above_rd, t_air, cloud_col.rgb, sun_dir_norm, new_ocean_hit);
	
	occlusion = min(occlusion, cloud_col.a);
	
	float fresnel;
	vec3 final_col;

	if (ocean_hit.x > 0.01) {
		
		float soft_shadow = cloud_col.a * get_soft_shadow(p0, normalize(p0 - planet_centre), sun_dir_norm, 3.);
		float specular = get_specular(-init_rd, sun_dir_norm, ocean_n, water_specularity);
		float beach_foam = get_beach_foam(p0, sun_dir_norm, lod);
		
		fresnel = get_fresnel(water_fresnel_f0, above_costh);
		
		final_col = mix(underwater_col, above_col, fresnel);
		final_col += beach_foam * (max(soft_shadow, 0.02)) * sun_col * sun_intensity * beach_foam_str;
		final_col += specular * soft_shadow * sun_col * sun_intensity * water_specular_strength;
		occlusion = 0.;
	} 
	else {
		vec3 incoming_col = 
			above_col
			* exp(-reflection_t * water_diffusion);
		fresnel = get_fresnel(water_fresnel_f0, under_costh);
		final_col = mix(incoming_col, underwater_col, fresnel);
	}
	
	return vec4(final_col, occlusion);
}


//main raymarch loop
//order -> terrain pass -> (space if ray exits sky, ocean pass if ray enters ocean sphere) -> clouds -> atmosphere
//occlusion is calculated and added during terrain, ocean and atmosphere pass
//occlusion is passed through alpha channel for post processing godrays
vec4 march_terrain(vec3 p0, vec3 rd) {
	vec3 sun_dir_norm = normalize(sun_dir);
	
	//first fast-forward ray to inside planet
	vec2 planet_hit = ray_sphere_intersection(planet_centre, planet_radius * 3., p0, rd);
	p0 += rd * planet_hit.x;
	
	//prevent ray from going beyond ocean
	vec2 ocean_hit = ray_sphere_intersection(planet_centre, water_radius, p0, rd);
	
	const float lod_bias = 15.;
	float lod = 0.;

	vec3 p = p0;
	float t = 0.0;
	float prev_t = 0.0;
	float occlusion = 1.0;
	vec2 h = vec2(1e10, 1.);

	for (int i = 0; i < max_steps && t < max_t; i++) {
	    lod = t / lod_bias;
	    h = map_terrain_and_grass(p, lod);
	    if (h.x <= min_step_size) {
	        t = binary_refinement(prev_t, t - prev_t, p0, rd, lod);
			if (t >= ocean_hit.x) t = ocean_hit.x;
	        p = p0 + rd * t;
			occlusion = 0.;
	        break;
	    }
		if (t >= ocean_hit.x) {
			t = ocean_hit.x;
			p = p0 + rd * t;
			break;
		}
	    prev_t = t;
	    t += h.x * ray_subdivision;
	    p = p0 + rd * t;
	}

	vec3 lit_col;
	if (t >= max_t) {
		t = 1e10;
		lit_col = get_space_color(p0, rd, sun_dir_norm);
		occlusion = 1.;
	}
	else if (t >= ocean_hit.x) {
		vec4 ocean_col = march_ocean(p0, rd, t, sun_dir_norm, ocean_hit);
	    lit_col = ocean_col.rgb;
		occlusion = min(occlusion, ocean_col.a);
	} else {
		vec3 n = map_normal(p, lod);
		if (h.y > 0.95) {
			lit_col = colour_terrain(p, n, lod) * light_terrain(p, rd, n, sun_dir_norm, lod).rgb;
		}
		else {
			lit_col = texture(grass_color, vec2(h.y)).rgb * light_grass(p, rd, n, sun_dir_norm, lod);
		}
	}

	vec4 cloud_col = march_clouds(p0, rd, t, lit_col, sun_dir_norm, ocean_hit);
	vec3 atm_col = march_atmosphere(p0, rd, t, cloud_col.rgb, sun_dir_norm, ocean_hit);
	
	occlusion = min(occlusion, cloud_col.a);
	
	return vec4(atm_col, occlusion);
}

//converts uv to clip space, then to world space
void fragment() {
	float aspect = resolution.x / resolution.y;
	vec2 uv = vec2((UV.x - 0.5) * aspect, 0.5 - UV.y) * 2.0;
	vec3 forward = normalize(screen_dir);
	vec3 up = normalize(screen_up);
	vec3 uv_world = get_transformed_uv(uv, screen_coord, forward, up);
	vec3 cam_pos = screen_coord - forward * focal_length;

	COLOR = march_terrain(cam_pos, normalize(uv_world - cam_pos));
}
