shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.01, 0.06, 0.12, 1.0);
uniform vec4 accent : source_color = vec4(0.12, 0.8, 1.0, 1.0);
uniform vec2 grid_size = vec2(48.0, 48.0);

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, uv.y);
	vec2 p = uv * grid_size;
	vec2 g = abs(fract(p) - 0.5);
	float line = 1.0 - smoothstep(0.47, 0.5, min(g.x, g.y));
	col += accent.rgb * line * 0.045;
	float glow = exp(-length(uv - vec2(0.78, 0.38)) * 3.2);
	col += accent.rgb * glow * 0.22;
	float vignette = smoothstep(0.95, 0.25, length(uv - 0.5));
	col *= mix(0.55, 1.0, vignette);
	COLOR = vec4(col, 1.0);
}
