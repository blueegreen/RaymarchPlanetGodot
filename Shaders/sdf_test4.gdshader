shader_type canvas_item;
render_mode blend_disabled;

group_uniforms ScreenUniforms;
uniform vec2 resolution = vec2(1920., 1080.);

group_uniforms CameraUniforms;
uniform float focal_length = 3.0;
uniform vec3 screen_coord = vec3(0.);
uniform vec3 screen_dir = vec3(0.0, 0.0, 1.0);

group_uniforms RenderUniforms;
uniform float min_step_size = 0.005;
uniform float max_t = 50.;
uniform int max_steps = 256;
uniform float d_norm = 0.05;
uniform float ray_subdivision = 0.35;
uniform int ray_trace_max_steps = 256;
uniform float reflection_str = 0.5;
uniform int ray_max_bounces = 3;
uniform int ao_max_steps = 4;
uniform float ao_step_size = 0.25;
uniform float ao_str = 1.;

group_uniforms LightUniforms;
uniform float soft_shadow_k = .1;
uniform vec3 sun_dir = vec3(-2., 1.5, .3);
uniform vec3 sun_col: source_color = vec3(0.8, 0.8, 0.7);
uniform samplerCube sky_cubemap: filter_linear_mipmap;
uniform float sun_intensity = 0.2;
uniform float ambient_str = 0.3;
uniform float fog_str = 0.15;

group_uniforms SDFUniforms;
uniform sampler2D noise_texture: repeat_enable, filter_linear_mipmap;
uniform float tree_grid_size = 1.;
uniform float landscape_step_mult = 14.;
uniform float tree_height = 1.;
uniform float tree_bulb_radius = 0.2;
uniform float tree_uprightness = 0.5;
uniform float tree_wind_str = 0.2;
uniform vec3 tree_wind_dir = vec3(1., 0., 0.);

struct Surface {
	float sd;
	vec3 albedo;
	float roughness;
	float metallic;
	float transmission;
	float ior; 
};

struct Material {
	vec3 albedo;
	float roughness;
	float metallic;       // 0 = dielectric, 1 = metal
	float transmission;   // 0 = opaque, 1 = fully transmissive
	float ior; 
};

struct Light {
	bool sun;
	vec3 dir;
	vec3 pos;
	vec3 color;
	float intensity;
};

Surface surf(float sd, Material mat) {
	return Surface(sd, mat.albedo, mat.roughness, mat.metallic, mat.transmission, mat.ior);
}

float light_i(vec3 p, Light l) {
	if (l.sun) return l.intensity;
	vec3 toLight = l.pos - p;
	float d2 = dot(toLight, toLight);
	return l.intensity / (d2 + 0.001);
}

vec3 aces_tonemap(vec3 color) {
	const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

mat2 rotate2D(float angle) {
	float s = sin(angle), c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 get_transformed_uv(vec2 uv, vec3 centre, vec3 forward) {
	vec3 world_up = vec3(0.0, 1.0, 0.0);
	vec3 base_right = normalize(cross(world_up, forward));
	vec3 base_up = cross(forward, base_right);
	return centre + base_right * uv.x + base_up * uv.y;
}

vec3 opRepetition(vec3 p, vec3 s) {
	return p - s * round(p / s);
}

vec3 opLimitedRepetition(vec3 p, float s, vec3 l) {
	return p - s * clamp(round(p / s), -l, l);
}

float opDisplace(vec3 p) {
	return sin(20. * p.x) * sin(20. * p.y) * sin(20. * p.z);
}

vec3 opTwist(vec3 p, float k) {
	mat2 m = rotate2D(k);
	return vec3(m * p.xz, p.y);
}

float opUnion(float a, float b)        { return min(a, b); }
float opSubtraction(float a, float b)  { return max(-a, b); }
float opIntersection(float a, float b) { return max(a, b); }
float opXor(float a, float b)          { return max(min(a, b), -max(a, b)); }

float opSmoothUnionSimple(float a, float b, float k) {
	k *= 4.0;
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

float opSmoothSubtractionSimple(float a, float b, float k) {
	return -opSmoothUnionSimple(a, -b, k);
}

float opSmoothIntersectionSimple(float a, float b, float k) {
	return -opSmoothUnionSimple(-a, -b, k);
}


Surface opSmoothUnion(Surface a, Surface b, float k) {
	k *= 4.0;
	float h = max(k - abs(a.sd - b.sd), 0.0) / k;
	float blended_dist = min(a.sd, b.sd) - h * h * k * 0.25;
	float mat_mix = 0.5 + 0.5 * sign(b.sd - a.sd) * (1.0 - h);
	return Surface(
		blended_dist,
		mix(b.albedo, a.albedo, mat_mix),
		mix(b.roughness, a.roughness, mat_mix),
		mix(b.metallic, a.metallic, mat_mix),
		mix(b.transmission, a.transmission, mat_mix),
		mix(b.ior, a.ior, mat_mix)
	);
}

Surface opSmoothSubtraction(Surface a, Surface b, float k) {
	Surface res = opSmoothUnion(a, Surface(-b.sd, b.albedo, b.roughness, b.metallic, b.transmission, b.ior), k);
	res.sd = -res.sd;
	return res;
}

Surface opSmoothIntersection(Surface a, Surface b, float k) {
	Surface res = opSmoothUnion(
		Surface(-a.sd, a.albedo, a.roughness, a.metallic, a.transmission, a.ior),
		Surface(-b.sd, b.albedo, b.roughness, b.metallic, b.transmission, b.ior),
		k
	);
	res.sd = -res.sd;
	return res;
}

float opRound(float sdf, float rad)           { return sdf - rad; }
float opOnion(float sdf, float thickness)     { return abs(sdf) - thickness; }
float opCutY(float sdf, vec3 p)               { return max(sdf, p.y); }

float sdSphere(vec3 p, float r) {
	return length(p) - r;
}

float sdBox(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdRoundBox(vec3 p, vec3 b, float r) {
	vec3 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

float sdCone(vec3 p, vec2 c, float h) {
	vec2 q = h * vec2(c.x / c.y, -1.0);
	vec2 w = vec2(length(p.xz), p.y);
	vec2 a = w - q * clamp(dot(w, q) / dot(q, q), 0.0, 1.0);
	vec2 b = w - q * vec2(clamp(w.x / q.x, 0.0, 1.0), 1.0);
	float k = sign(q.y);
	float d = min(dot(a, a), dot(b, b));
	float s = max(k * (w.x * q.y - w.y * q.x), k * (w.y - q.y));
	return sqrt(d) * sign(s);
}

float sdCappedCylinder(vec3 p, float r, float h) {
	vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdOctahedron(vec3 p, float s) {
	p = abs(p);
	float m = p.x + p.y + p.z - s;
	vec3 q;
	if      (3.0 * p.x < m) q = p.xyz;
	else if (3.0 * p.y < m) q = p.yzx;
	else if (3.0 * p.z < m) q = p.zxy;
	else return m * 0.57735027;
	float k = clamp(0.5 * (q.z - q.y + s), 0.0, s);
	return length(vec3(q.x, q.y - s + k, q.z - k));
}

float sdCutHollowSphere(vec3 p, float r, float h, float t) {
	float w = sqrt(r * r - h * h);
	vec2 q = vec2(length(p.xz), p.y);
	return ((h * q.x < w * q.y) ? length(q - vec2(w, h)) : abs(length(q) - r)) - t;
}

float sdPlane(vec3 p, vec3 n, float h) {
	return dot(p, normalize(n)) + h;
}

float sdNoisePlane(vec3 pos, float scale_mult, float h_mult, float h) {
	return pos.y - h_mult * 2. * (texture(noise_texture, pos.xz / scale_mult).r - 0.5) - h;
}

float sdMandelbulb(vec3 p) {
	vec3 z = p;
	float dr = 1.0, r = 0.;
	float power = mod(TIME, 16.);
	for (int i = 0; i < 15; i++) {
		r = length(z);
		if (r > 2.0) break;
		float theta = acos(z.z / r);
		float phi = atan(z.y, z.x);
		dr = pow(r, power - 1.0) * power * dr + 1.0;
		float zr = pow(r, power);
		theta *= power;
		phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
		z += p;
	}
	return 0.5 * log(r) * r / dr;
}

Surface sdf_scene(vec3 pos) {
	Material white_r = Material(vec3(1.), .9, 0., 0., 0.);
	Material white_s = Material(vec3(1.), .0, 0., 0., 0.);
	Material pink = Material(vec3(1., .5, .5), .4, 0., 0., 0.);

	Surface scene = Surface(1e10, vec3(0.0), 0.0, 0.0, 0.0, 0.0);
	
	//{
		//vec3 q = pos - vec3(0., 0., 0.);
		//float s = sdSphere(q, 3.);
		//s = opCutY(s, q);
		//scene = opSmoothUnion(scene, surf(s, white_s), 0.1);
	//}

	return scene;
}

vec3 sdf_normal(vec3 pos) {
	vec2 e = vec2(1.0, -1.0) * 0.5773 * d_norm;
	return normalize(
		e.xyy * sdf_scene(pos + e.xyy).sd +
		e.yyx * sdf_scene(pos + e.yyx).sd +
		e.yxy * sdf_scene(pos + e.yxy).sd +
		e.xxx * sdf_scene(pos + e.xxx).sd
	);
}

float sdf_ao(vec3 pos, vec3 n) {
	float ao = 0.;
	vec3 p = pos;
	for (int i = 0; i < ao_max_steps; i++) {
		float h = sdf_scene(p).sd;
		ao += ((float(i) * ao_step_size + min_step_size) - h) / float(i + 1);
		p += n * ao_step_size;
	}
	return 1. - clamp(ao * ao_str, 0., 1.);
}

//lod -> level of detail, rough objects would sample less lod
vec3 get_sky_color(vec3 v, float lod) {
	v = normalize(v);
	vec3 dir = vec3(v.x, v.z, v.y);
	return textureLod(sky_cubemap, dir, 8. * lod).rgb;
}

float compute_light(vec3 p, vec3 n, vec3 rd, vec3 l_dir, vec3 l_pos, float spec) {
	float diffuse = max(dot(l_dir, n), 0.);
	if (diffuse < 0.01) return 0.;

	float shadow = 1.;
	p += n * (min_step_size * 2.);
	float t = min_step_size;
	float ph = 1e20;

	for (int i = 0; i < max_steps && t < max_t; i++) {
		vec3 p1 = p + l_dir * t;
		Surface h = sdf_scene(p1);

		if (dot(l_dir, l_pos - p1) < 0.) break;
		if (h.sd <= min_step_size || shadow <= 0.001) return 0.;

		float y = h.sd * h.sd / (2.0 * ph);
		float d = sqrt(h.sd * h.sd - y * y);
		shadow = min(shadow, d / (soft_shadow_k * max(0.0, t - y)));

		ph = h.sd;
		t += h.sd;
	}

	vec3 half_vec = normalize(l_dir - rd);
	float spec_angle = max(dot(n, half_vec), 0.0);
	float specular = pow(spec_angle, spec) * (spec + 8.0) / (8.0 * PI);

	return (diffuse + specular) * shadow;
}

vec3 sdf_light(vec3 pos, vec3 rd) {
	Surface h = sdf_scene(pos);
	vec3 normal = sdf_normal(pos);
	float ao = sdf_ao(pos, normal);
	float specular = mix(32., 256., 1. - h.roughness);

	Light sun = Light(true, sun_dir, vec3(0.), sun_col, sun_intensity);
	vec3 q = vec3(4.);
	q.xz *= rotate2D(TIME);
	Light point = Light(false, vec3(0.), q, sun_col, 10.);
	
	Light[] lights = {sun, point};
	int l_num = 2;
	
	vec3 direct_light = vec3(0.);
	for (int i = 0; i < l_num; i++) {
		Light l = lights[i];
		float l_i = light_i(pos, l);
		vec3 l_dir = l.sun ? normalize(l.dir) : normalize(l.pos - pos);
		vec3 l_pos = l.sun ? pos + l.dir * 1e10 : l.pos;
		direct_light += compute_light(pos, normal, rd, l_dir, l_pos, specular) * l_i * l.color;
	}

	vec3 ambient_light = get_sky_color(rd, h.roughness) * ambient_str * ao;
	return ambient_light + direct_light;
}

float fresnel(float r0, vec3 v, vec3 n) {
	return r0 + (1. - r0) * pow(1. - max(0., dot(n, -v)), 5.);
}

vec3 sdf_surface_color(vec3 p, vec3 rd, vec3 albedo) {
	return sdf_light(p, rd) * albedo;
}

vec3 fog(vec3 p, vec3 rd, vec3 col, float d) {
    float sun_dot = max(dot(rd, normalize(sun_dir)), 0.0);
    float b = fog_str;
    float fog_a;
    if (abs(rd.y) < 1e-4) {
        fog_a = 0.2 * exp(-p.y * b) * d * b;
    } else {
        fog_a = 0.2 * exp(-p.y * b) * (1. - exp(-d * rd.y * b)) / rd.y;
    }
    vec3 fog_c = mix(get_sky_color(rd, 0.), sun_col, pow(sun_dot, 2.));
    return mix(col, fog_c, clamp(fog_a, 0., 1.));
}

vec4 render_scene(vec3 p0, vec3 rd) {
	vec3 p = p0;
	float t = 0.;
	Surface h = Surface(1e10, vec3(0.), 0., 0., 0., 0.);

	for (int i = 0; i < max_steps && t < max_t; i++) {
		p = p0 + rd * t;
		h = sdf_scene(p);
		if (h.sd <= min_step_size) break;
		t += h.sd * ray_subdivision;
	}
	
	if (t >= max_t) return vec4(fog(p0, rd, get_sky_color(rd, 0.), max_t), 1.);
	float depth_map = clamp(t/max_t, 0., 1.);

	vec3 n = sdf_normal(p);
	float r0 = clamp(reflection_str * (1. - h.roughness), 0., 1.);
	float r1 = fresnel(r0, rd, n);

	vec3 accumulated_color = sdf_surface_color(p, rd, h.albedo);
	vec3 throughput = vec3(r1);
	vec3 rd_r = reflect(rd, n);
	p += n * 0.002;
	vec3 p0_r = p;

	float t_r = 0.;
	int bounce = 1;

	for (int i = 0; i < ray_trace_max_steps && t_r < max_t; i++) {
		h = sdf_scene(p);

		if (h.sd <= min_step_size) {
			n = sdf_normal(p);
			accumulated_color += throughput * fog(p0_r, rd_r, aces_tonemap(sdf_surface_color(p, rd_r, h.albedo)), t_r);

			float r0_new = clamp(reflection_str * (1. - h.roughness), 0., 1.);
			throughput *= fresnel(r0_new, rd_r, n) * h.albedo;
			rd_r = reflect(rd_r, n);
			p += n * 0.002;
			p0_r = p;
			bounce += 1;

			if (bounce >= ray_max_bounces || length(throughput) <= 0.1) break;
		}

		float dt = h.sd * ray_subdivision;
		p += rd_r * dt;
		t_r += dt;
	}

	accumulated_color += throughput * get_sky_color(rd_r, h.roughness);
	return vec4(fog(p0, rd, aces_tonemap(accumulated_color), t), depth_map);
}





float get_terrain_height(vec3 p) {
	const float scale_mult = 20.;
	const float h_mult = 6.;
	float height = h_mult * 2. * (texture(noise_texture, p.xz / scale_mult).r - 0.5);
	float stepped_height = floor(height * landscape_step_mult) /landscape_step_mult;
	height = stepped_height - height * 0.3;
	return height - 1.;
}

vec3 terrain_normal(vec3 p) {
	float h_slope = 
		get_terrain_height(p + d_norm * vec3(1., 0., 0.)) -
		get_terrain_height(p - d_norm * vec3(1., 0., 0.));
	float v_slope = 
		get_terrain_height(p + d_norm * vec3(0., 0., 1.)) -
		get_terrain_height(p - d_norm * vec3(0., 0., 1.));

	return normalize(vec3(-h_slope, 2. * d_norm, -v_slope));
}

float map_terrain(vec3 p) {
	float h = get_terrain_height(p);
	float scene = (p.y - h);
	scene = opRound(scene, 0.4);
	vec3 w;
	{
		vec2 m = floor(p.xz / tree_grid_size);
		vec2 c = tree_grid_size * m + tree_grid_size / 2.;
		vec3 c1 = vec3(c.x, 0., c.y);
		
		vec3 root = vec3(c.x, get_terrain_height(c1), c.y);

		vec3 n = terrain_normal(root);
		n = mix(n, vec3(0., 1., 0.), tree_uprightness);
		n = normalize(n + normalize(tree_wind_dir) * tree_wind_str * (sin(length(p.xz) + TIME) + .7));
		
		vec3 t = normalize(cross(vec3(0., 0., 1.), n)); 

		vec3 b = cross(n, t); 
		
		vec3 p_diff = p - root;
		w = vec3(dot(p_diff, t), dot(p_diff, n), dot(p_diff, b));		
	}

	
	{
		float s = sdCappedCylinder(w, .01, tree_height);
		scene = opSmoothUnionSimple(scene, s, 0.1);
		
		s = sdSphere(w - vec3(0., tree_height, 0.), tree_bulb_radius); 
		scene = opSmoothUnionSimple(scene, s, .05);
	}
	
	return scene; 
}
vec3 map_normal(vec3 pos) {
	vec2 e = vec2(1.0, -1.0) * 0.5773 * d_norm;
	return normalize(
		e.xyy * map_terrain(pos + e.xyy) +
		e.yyx * map_terrain(pos + e.yyx) +
		e.yxy * map_terrain(pos + e.yxy) +
		e.xxx * map_terrain(pos + e.xxx)
	);
}

vec3 light_terrain(vec3 p0) {
	vec3 sun_dir_norm = normalize(sun_dir);
	vec3 normal_t = map_normal(p0);
	float diffuse = clamp(dot(sun_dir_norm, normal_t), 0., 1.);

	float shadow = 1.;
	float h = 1e10;
	p0 += normal_t * (min_step_size * 2.);
	float t = min_step_size;
	float ph = 1e10;
	
	
	for (int i = 0; i < max_steps && t < max_t; i++) {
		vec3 p1 = p0 + sun_dir_norm * t;
		h = map_terrain(p1);

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
	
	vec3 ambient_light = get_sky_color(normal_t, 1.) * ambient_str;
	vec3 direct_light = sun_col * diffuse * shadow * sun_intensity;
	return direct_light + ambient_light;
}
// ── Water constants ──────────────────────────────────────────────────────────
const float IOR_WATER    = 1.333;
const float ETA_INTO     = 1.0 / IOR_WATER;   // air → water
const float ETA_OUTOF    = IOR_WATER;          // water → air  (TIR can occur here)
const float F0_WATER     = 0.02;               // Schlick F0 for air/water

// Beer-Lambert extinction (RGB).  High red/green → deep water looks cyan/teal.
const vec3  WATER_EXTINCT = vec3(0.45, 0.12, 0.07);
const vec3  WATER_SCATTER = vec3(0.02, 0.18, 0.24);   // ambient in-scatter tint

// ── Schlick Fresnel ───────────────────────────────────────────────────────────
float fresnel_schlick(float cos_theta, float f0) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

vec3 water_normal(vec3 p) {
    const float eps  = 0.05;
    const float AMP1 = 0.055;
    const float AMP2 = 0.022;
    float t = TIME;

    #define WH(x,z) (sin((x)*1.8+t*0.90)*cos((z)*2.1+t*0.70)*AMP1 \
                   + sin((x)*4.3-t*1.30)*cos((z)*3.7+t*1.10)*AMP2)

    float hc = WH(p.x,       p.z);
    float hx = WH(p.x + eps, p.z);
    float hz = WH(p.x,       p.z + eps);

    #undef WH
    return normalize(vec3(-(hx-hc)/eps, 1.0, -(hz-hc)/eps));
}

// ── Beer-Lambert water tint ──────────────────────────────────────────────────
// Apply to any colour that has travelled `dist` units through water.
vec3 water_absorb(vec3 col, float dist) {
    vec3 transmit = exp(-WATER_EXTINCT * dist);
    return col * transmit + WATER_SCATTER * (1.0 - transmit);
}

// ── Core terrain march ───────────────────────────────────────────────────────
// No water surface handling.  Returns tone-mapped + fogged colour.
// t_hit = max_t means sky was hit.
vec3 march_terrain(vec3 p0, vec3 rd, out float t_hit) {
    vec3  p = p0;
    float t = 0.0;
    t_hit   = max_t;

    for (int i = 0; i < max_steps && t < max_t; i++) {
        p     = p0 + rd * t;
        rd.y += 0.0001 * sin(length(p - p0) + TIME);
        float h = map_terrain(p);
        if (h <= min_step_size) { t_hit = t; break; }
        t += h * ray_subdivision;
    }

    if (t_hit >= max_t)
        return fog(p0, rd, get_sky_color(rd, 0.0), max_t);

    return fog(p0, rd, aces_tonemap(light_terrain(p)), t_hit);
}

// ── Main render ───────────────────────────────────────────────────────────────
vec4 render_terrain(vec3 p0, vec3 rd) {

    float water_height = -1.0 + sin(TIME / 3.0);
    bool  above_water  = (p0.y > water_height);

    // Analytic ray-plane intersection
    float t_water = (water_height - p0.y) / rd.y;

    // ════════════════════════════════════════════════════════════════════════
    // ABOVE WATER
    // ════════════════════════════════════════════════════════════════════════
    if (above_water) {
        bool hits_water = (rd.y < -1e-4) && (t_water > 0.0);

        float t_hit;
        vec3  terrain_col = march_terrain(p0, rd, t_hit);

        // Terrain closer than (or equal to) water surface → no interaction
        if (!hits_water || t_hit <= t_water)
            return vec4(terrain_col, 1.0);

        vec3 pw = p0 + rd * t_water;
        vec3 wn = water_normal(pw);            // points UP (into air)

        // Fresnel
        float cos_i   = clamp(dot(-rd, wn), 0.0, 1.0);
        float fresnel = fresnel_schlick(cos_i, F0_WATER);

        // Reflection (above water, no absorption needed)
        vec3  rd_refl = reflect(rd, wn);
        float t_refl;
        vec3  refl_col = march_terrain(pw + wn * 0.002, rd_refl, t_refl);

        // Refraction: air → water, eta = n_air/n_water
        vec3 rd_refr = refract(rd, wn, ETA_INTO);
        if (dot(rd_refr, rd_refr) < 0.001) rd_refr = rd;  // shouldn't TIR but guard it

        float t_refr;
        vec3  refr_col = march_terrain(pw - wn * 0.002, rd_refr, t_refr);
        refr_col = water_absorb(refr_col, t_refr);

        vec3 water_col = mix(refr_col, refl_col, fresnel);

        // Atmospheric fog from camera to water surface only
        water_col = fog(p0, rd, water_col, t_water);
        return vec4(water_col, 1.0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // BELOW WATER
    // Normal convention flip: wn still points UP (into air), so the normal
    // pointing into the *incident* medium (water) is -wn.
    // ════════════════════════════════════════════════════════════════════════

    bool hits_surface = (rd.y > 1e-4) && (t_water > 0.0);

    float t_hit;
    vec3  terrain_col = march_terrain(p0, rd, t_hit);

    // Ray hits terrain without reaching the surface (downward or blocked)
    if (!hits_surface || t_hit <= t_water) {
        terrain_col = water_absorb(terrain_col, min(t_hit, max_t));
        return vec4(terrain_col, 1.0);
    }

    // Ray reaches the water surface from below
    vec3 pw   = p0 + rd * t_water;
    vec3 wn   = water_normal(pw);    // UP
    vec3 wn_i = -wn;                 // DOWN — points into incident medium (water)

    // Refraction: water → air, eta = n_water/n_air.
    // GLSL refract() returns vec3(0) when TIR occurs (angle > critical ~48.75°).
    vec3 rd_refr_air = refract(rd, wn_i, ETA_OUTOF);
    bool tir = dot(rd_refr_air, rd_refr_air) < 0.001;

    float cos_i   = clamp(dot(-rd, wn_i), 0.0, 1.0);
    float fresnel = tir ? 1.0 : fresnel_schlick(cos_i, F0_WATER);

    vec3 surface_col;

    if (tir) {
        // ── Total Internal Reflection ────────────────────────────────────────
        // Ray bounces back into the water.  The ceiling becomes a mirror.
        vec3  rd_tir = reflect(rd, wn_i);
        float t_tir;
        vec3  tir_col = march_terrain(pw + wn_i * 0.002, rd_tir, t_tir);
        surface_col   = water_absorb(tir_col, t_tir);

    } else {
        // ── Partial refraction + partial reflection ──────────────────────────

        // Refracted ray exits into air (atmospherically fogged from pw upward)
        float t_air;
        vec3  above_col = march_terrain(pw + wn * 0.002, rd_refr_air, t_air);

        // Reflected component (bounces back down into water)
        vec3  rd_refl_w = reflect(rd, wn_i);
        float t_refl_w;
        vec3  refl_col = march_terrain(pw + wn_i * 0.002, rd_refl_w, t_refl_w);
        refl_col = water_absorb(refl_col, t_refl_w);

        surface_col = mix(above_col, refl_col, fresnel);
    }

    // Beer-Lambert for the underwater segment from camera to surface
    surface_col = water_absorb(surface_col, t_water);

    return vec4(surface_col, 1.0);
}

void fragment() {
	float aspect = resolution.x / resolution.y;
	vec2 uv = vec2((UV.x - 0.5) * aspect, 0.5 - UV.y) * 2.0;
	vec3 forward = normalize(screen_dir);
	vec3 uv_world = get_transformed_uv(uv, screen_coord, forward);
	vec3 cam_pos = screen_coord - forward * focal_length;
	
	vec4 scene = render_terrain(cam_pos, normalize(uv_world - cam_pos));
	COLOR = scene;
}
