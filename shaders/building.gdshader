// Procedural facade: one material for every building. Windows, shop fronts,
// grime and per-building colour variation are all computed here, so buildings
// are just boxes. Expects un-scaled BoxMeshes centred on the node.
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 color_b : source_color = vec3(0.33, 0.35, 0.36);
uniform vec3 color_c : source_color = vec3(0.45, 0.33, 0.27);
uniform float cell_width = 3.0;
uniform float floor_height = 3.2;
uniform float lit_chance = 0.05;
uniform float burnt = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

// Integer hash: exact and stable for any (whole-number) input, unlike
// sin()-based hashes which break down for large world coordinates on GPUs.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	q *= uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) / 4294967295.0;
}
float hash3(vec3 p) { return hash(p.xz + vec2(p.y * 17.0, p.y * 31.0)); }

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-building variation from the object's position (same for every pixel).
	vec3 origin = floor(MODEL_MATRIX[3].xyz);
	float h = hash3(origin);
	float h2 = hash3(origin + 3.0);
	vec3 wall = h < 0.33 ? color_a : (h < 0.66 ? color_b : color_c);
	wall *= 0.8 + 0.4 * h2;
	vec3 col = wall;
	vec3 emit = vec3(0.0);
	float rough = 0.92;
	float metal = 0.0;
	float height_above_ground = world_pos.y;

	if (abs(local_normal.y) < 0.5) {
		// Horizontal facade coordinate (centred so windows sit symmetrically).
		float u = abs(local_normal.x) > 0.5 ? local_pos.z : local_pos.x;
		float floor_idx = floor((height_above_ground - 0.2) / floor_height);
		vec2 cell = vec2(u / cell_width + 0.5, (height_above_ground - 0.2) / floor_height);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float r = hash(id + origin.xz);

		// Vertical rain streaks / grime.
		float streak = hash(vec2(floor(u * 2.0), origin.x)) * 0.25;
		col *= 1.0 - streak * smoothstep(0.0, 1.0, f.y);
		col *= mix(0.55, 1.0, smoothstep(0.0, 2.5, height_above_ground));

		if (floor_idx < 1.0) {
			// Ground floor: shop fronts with rolled shutters or smashed glass.
			bool shop = f.x > 0.08 && f.x < 0.92 && height_above_ground > 0.3 && height_above_ground < 2.6;
			if (shop) {
				if (r < 0.55) {
					float slat = step(0.5, fract(height_above_ground * 6.0));
					col = vec3(0.32, 0.33, 0.34) * (0.8 + 0.2 * slat);
					metal = 0.4; rough = 0.6;
				} else {
					col = vec3(0.03, 0.035, 0.04);
					rough = 0.15;
				}
			}
		} else {
			bool win = f.x > 0.25 && f.x < 0.75 && f.y > 0.28 && f.y < 0.82;
			if (win) {
				if (r < lit_chance) {
					col = vec3(0.9, 0.62, 0.3);
					emit = vec3(1.0, 0.6, 0.25) * 1.2;
				} else if (r < 0.25) {
					col = vec3(0.24, 0.17, 0.1) * (0.8 + 0.4 * step(0.5, fract(f.y * 8.0)));
				} else {
					col = vec3(0.04, 0.05, 0.06) + vec3(0.06) * r;
					rough = 0.12; metal = 0.3;
				}
			} else if (f.y < 0.28 && f.y > 0.22 && f.x > 0.2 && f.x < 0.8) {
				col *= 0.7; // window sill shadow
			}
		}
	} else if (local_normal.y > 0.5) {
		col = vec3(0.16, 0.16, 0.15) * (0.8 + 0.4 * hash(floor(world_pos.xz)));
	}

	col = mix(col, col * vec3(0.18, 0.16, 0.15), burnt);
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = rough;
	METALLIC = metal;
}
