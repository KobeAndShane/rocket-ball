shader_type canvas_item;
// Single full-screen pass. The overlay only draws when a colourblind mode is
// selected; normal play pays nothing but the hidden ColorRect.
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0; // 1 deuteranopia, 2 protanopia, 3 tritanopia
uniform float strength = 0.85;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	vec3 sim = c;
	if (mode == 1) {
		// Deuteranopia simulation.
		sim = vec3(
			0.625 * c.r + 0.375 * c.g + 0.000 * c.b,
			0.700 * c.r + 0.300 * c.g + 0.000 * c.b,
			0.000 * c.r + 0.300 * c.g + 0.700 * c.b);
	} else if (mode == 2) {
		// Protanopia simulation.
		sim = vec3(
			0.567 * c.r + 0.433 * c.g + 0.000 * c.b,
			0.558 * c.r + 0.442 * c.g + 0.000 * c.b,
			0.000 * c.r + 0.242 * c.g + 0.758 * c.b);
	} else if (mode == 3) {
		// Tritanopia simulation.
		sim = vec3(
			0.950 * c.r + 0.050 * c.g + 0.000 * c.b,
			0.000 * c.r + 0.433 * c.g + 0.567 * c.b,
			0.000 * c.r + 0.475 * c.g + 0.525 * c.b);
	}
	// Daltonise: push the lost difference into the channels the eye still sees.
	vec3 err = c - sim;
	vec3 corrected = c + vec3(
		err.g * 0.70 + err.b * 0.30,
		err.r * 0.70 + err.b * 0.20,
		err.r * 0.20 + err.g * 0.70);
	corrected = clamp(corrected, vec3(0.0), vec3(1.0));
	vec3 result = mix(c, corrected, mode == 0 ? 0.0 : strength);
	COLOR = vec4(result, 1.0);
}
