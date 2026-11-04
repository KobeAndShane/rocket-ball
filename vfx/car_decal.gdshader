shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 line_color : source_color = vec4(0.2, 1.0, 0.9, 1.0);
uniform float pattern : hint_range(0.0, 2.0) = 0.0;
uniform float glow = 0.8;

void fragment() {
	// 0 = hidden, 1 = twin stripes, 2 = hex lattice.
	float mask = 0.0;
	if (pattern > 1.5) {
		vec2 p = UV * vec2(7.0, 13.0);
		vec2 g = abs(fract(p) - 0.5);
		vec2 h = abs(fract(p + vec2(0.5, 0.5)) - 0.5);
		mask = 1.0 - smoothstep(0.40, 0.47, min(g.x + g.y, h.x + h.y));
	} else if (pattern > 0.5) {
		float band = abs(fract(UV.x * 2.0) - 0.5);
		mask = 1.0 - smoothstep(0.16, 0.23, band);
	} else {
		discard;
	}
	ALBEDO = line_color.rgb;
	EMISSION = line_color.rgb * glow;
	ALPHA = mask;
}
