shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.2, 0.55, 0.6, 0.55);
uniform vec4 deep_color : source_color = vec4(0.02, 0.12, 0.2, 0.85);
uniform float wave_speed = 0.6;
uniform float wave_height = 0.12;
uniform float wave_scale = 1.4;

varying float wave_h;

float wave(vec2 pos, float t) {
	float h = 0.0;
	h += sin(pos.x * wave_scale + t) * 0.5;
	h += sin(pos.y * wave_scale * 1.3 - t * 1.4) * 0.35;
	h += sin((pos.x + pos.y) * wave_scale * 0.7 + t * 0.8) * 0.3;
	return h;
}

void vertex() {
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME * wave_speed;
	float h = wave(wp, t) * wave_height;
	VERTEX.y += h;
	wave_h = h;

	float eps = 0.15;
	float hx = wave(wp + vec2(eps, 0.0), t) * wave_height;
	float hz = wave(wp + vec2(0.0, eps), t) * wave_height;
	NORMAL = normalize(vec3(h - hx, eps, h - hz));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 albedo = mix(deep_color.rgb, shallow_color.rgb, clamp(wave_h * 2.0 + 0.5, 0.0, 1.0));
	albedo = mix(albedo, vec3(1.0), fres * 0.4);
	ALBEDO = albedo;
	ALPHA = mix(deep_color.a, shallow_color.a, fres);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
