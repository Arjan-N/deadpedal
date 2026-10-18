// Asphalt road with faded lane markings, cracks, patches and puddles.
// UV.x runs 0..1 across the road, UV.y is distance along the road in metres.
shader_type spatial;

uniform float road_width = 10.0;
uniform vec3 asphalt_color : source_color = vec3(0.27, 0.27, 0.275);
uniform vec3 line_color : source_color = vec3(0.75, 0.74, 0.68);
uniform vec3 moss_color : source_color = vec3(0.17, 0.22, 0.1);

// Integer hash: exact and stable for any (whole-number) input, unlike
// sin()-based hashes which break down for large world coordinates on GPUs.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	q *= uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) / 4294967295.0;
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 m = vec2(UV.x * road_width, UV.y);   // metres
	float n = fbm(m * 0.35);
	vec3 col = asphalt_color * (0.75 + 0.5 * fbm(m * 2.5));
	float rough = 0.88;

	// Repair patches.
	float patch = step(0.72, noise(floor(m / vec2(2.5, 4.0)) * 0.7));
	col = mix(col, asphalt_color * 0.65, patch * 0.8);

	// Lane markings: edge lines + dashed centre line, worn away by noise.
	float wear = smoothstep(0.35, 0.65, fbm(m * 1.7 + 7.0));
	float edge = step(abs(m.x - 0.55), 0.08) + step(abs(m.x - (road_width - 0.55)), 0.08);
	float centre = step(abs(m.x - road_width * 0.5), 0.07) * step(fract(m.y / 9.0), 0.45);
	col = mix(col, line_color, clamp(edge + centre, 0.0, 1.0) * wear * 0.85);

	// Cracks.
	float crack = 1.0 - smoothstep(0.0, 0.018, abs(fbm(m * 0.6 + 3.0) - 0.5));
	col *= 1.0 - crack * 0.6;

	// Moss creeping in from the edges.
	float edge_dist = min(m.x, road_width - m.x);
	float moss = (1.0 - smoothstep(0.0, 1.4, edge_dist)) * smoothstep(0.45, 0.7, n);
	col = mix(col, moss_color, moss * 0.9);

	// Puddles: darker and glossy.
	float puddle = smoothstep(0.62, 0.66, fbm(m * 0.12 + 11.0)) * (1.0 - moss);
	col = mix(col, col * 0.45, puddle);
	rough = mix(rough, 0.08, puddle);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
