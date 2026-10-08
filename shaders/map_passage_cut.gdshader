shader_type spatial;
render_mode cull_disabled;

uniform mat4 mesh_to_map;
uniform vec3 passage_start;
uniform vec3 passage_end;
uniform float radius = 1.4;
uniform float spring_height = 1.6;
uniform int arch_segments = 12;
uniform float floor_start = -0.0834;
uniform float floor_end = -0.4279;
uniform vec2 floor_transition = vec2(0.55, 0.85);
varying vec3 map_position;

void vertex() {
	map_position = (mesh_to_map * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 direction = normalize(passage_end - passage_start);
	vec3 lateral = cross(direction, vec3(0.0, 1.0, 0.0));
	vec3 offset = map_position - passage_start;
	float t = dot(offset, direction) / length(passage_end - passage_start);
	float u = dot(offset, lateral);
	if (t > 0.0 && t < 1.0 && abs(u) < radius) {
		float floor_y = mix(floor_start, floor_end, clamp((t - floor_transition.x) / (floor_transition.y - floor_transition.x), 0.0, 1.0));
		float h = map_position.y - floor_y;
		if (h > -0.1 && h < spring_height + radius) {
			bool inside = true;
			float step_angle = PI / float(arch_segments);
			float limit = radius * cos(step_angle * 0.5);
			for (int i = 0; i < arch_segments; i++) {
				float angle = (float(i) + 0.5) * step_angle;
				if (cos(angle) * u + sin(angle) * (h - spring_height) > limit) {
					inside = false;
				}
			}
			if (inside) {
				discard;
			}
		}
	}
	ALBEDO = vec3(0.68, 0.67, 0.65);
	ROUGHNESS = 0.9;
}
