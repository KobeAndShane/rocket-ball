shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 net_color : source_color = vec4(0.2, 0.9, 1.0, 0.35);
uniform float cells_x = 12.0;
uniform float cells_y = 8.0;

void fragment() {
	vec2 uv = UV * vec2(cells_x, cells_y);
	vec2 g = abs(fract(uv) - 0.5);
	float line = smoothstep(0.42, 0.5, max(g.x, g.y));
	ALBEDO = net_color.rgb;
	ALPHA = net_color.a + line * 0.35;
	EMISSION = net_color.rgb * line * 0.6;
}
