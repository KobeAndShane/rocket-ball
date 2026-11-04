shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// PBR ball shell with glowing latitude/longitude seams. The panel mask is
// generated from the sphere direction, so it needs no texture and stays crisp.

uniform vec4 base_color : source_color = vec4(0.84, 0.88, 0.96, 1.0);
uniform vec4 seam_color : source_color = vec4(0.16, 0.68, 1.0, 1.0);
uniform float seam_glow : hint_range(0.0, 3.0) = 0.85;

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = normalize(VERTEX);
}

void fragment() {
	vec3 p = sphere_dir;
	float lon = atan(p.z, p.x);
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon_line = abs(fract(lon * 3.0 / PI + 0.5) - 0.5);
	float lat_line = abs(fract(lat * 2.0 / PI + 0.5) - 0.5);
	float seam = 1.0 - smoothstep(0.0, 0.045, min(lon_line, lat_line));
	float panel = smoothstep(0.20, 0.75, abs(p.y));
	vec3 base = mix(base_color.rgb * 0.90, base_color.rgb, panel);
	ALBEDO = mix(base, seam_color.rgb, seam * 0.55);
	METALLIC = mix(0.42, 0.18, seam);
	ROUGHNESS = mix(0.30, 0.48, seam);
	EMISSION = base_color.rgb * 0.035 + seam_color.rgb * seam * seam_glow;
}
