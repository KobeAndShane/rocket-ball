shader_type canvas_item;
render_mode unshaded;
// Single full-screen pass used for the gravity-shift tint and the subtle
// chromatic-aberration pulse. Kept deliberately cheap: three texture reads and
// no blur/loop. The accessibility colourblind pass remains a separate opt-in
// overlay so this pass can stay disabled during normal play.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 tint_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aberration : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centred = uv - vec2(0.5);
	float edge = smoothstep(0.05, 0.75, length(centred));
	float offset = aberration * 0.012 * (0.35 + edge);

	vec3 colour;
	colour.r = texture(screen_texture, uv + centred * offset).r;
	colour.g = texture(screen_texture, uv).g;
	colour.b = texture(screen_texture, uv - centred * offset).b;

	// Tint the world only: HUD lives on a higher CanvasLayer.
	colour = mix(colour, tint_color.rgb, clamp(intensity * (0.08 + edge * 0.30), 0.0, 1.0));
	colour += tint_color.rgb * intensity * edge * 0.045;
	COLOR = vec4(colour, 1.0);
}
