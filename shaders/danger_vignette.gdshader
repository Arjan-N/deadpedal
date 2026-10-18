// Full-screen red vignette that pulses like a heartbeat as danger rises.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.6;
	float d = length(uv);
	float edge = smoothstep(0.35 - 0.12 * intensity, 0.95, d);
	float a = edge * (intensity * 0.85 + pulse * 0.25 * intensity);
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.9));
}
