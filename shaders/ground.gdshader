// Overgrown ground: patchy grass, dirt and dead leaves, in world space.
shader_type spatial;

uniform vec3 grass_color : source_color = vec3(0.16, 0.2, 0.1);
uniform vec3 dry_color : source_color = vec3(0.27, 0.25, 0.16);
uniform vec3 dirt_color : source_color = vec3(0.17, 0.14, 0.11);

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.1; a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = fbm(p * 0.08);
	float detail = fbm(p * 1.3);
	vec3 col = mix(grass_color, dry_color, smoothstep(0.4, 0.7, n));
	col = mix(col, dirt_color, smoothstep(0.62, 0.75, fbm(p * 0.05 + 9.0)));
	col *= 0.7 + 0.6 * detail;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
