shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Team paint with a baked-in mask: centre stripe, side pods and a darker rear
// get contrasting trim while keeping the car clearly readable from above.

uniform vec4 team_color : source_color = vec4(0.18, 0.64, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(0.65, 0.92, 1.0, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.32;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.22;
uniform float body_scale_hint : hint_range(0.5, 2.0) = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = local_pos * body_scale_hint;
	float centre = 1.0 - smoothstep(0.08, 0.28, abs(p.x));
	float side = smoothstep(0.52, 0.86, abs(p.x));
	float rear = smoothstep(0.95, 1.55, abs(p.z + 0.10));
	float mask = clamp(centre * 0.55 + side * 0.70 + rear * 0.20, 0.0, 1.0);
	vec3 paint = mix(team_color.rgb, accent_color.rgb, mask * 0.72);
	ALBEDO = paint;
	METALLIC = mix(metallic_amount, 0.20, mask);
	ROUGHNESS = mix(roughness_amount, 0.52, mask);
	EMISSION = accent_color.rgb * emission_strength * (0.30 + mask * 0.45);
}
