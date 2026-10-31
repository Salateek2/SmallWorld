shader_type canvas_item;
// SmallWorld water: soft light and dark ripples that slowly drift across lakes and ponds.
// Put on the Ground layer: it only touches pixels that are the water tile's blue,
// so grass, paths and everything else stay exactly as they are.

uniform vec3 water_color = vec3(0.0, 0.6, 0.859); // the plain water tile, (0, 153, 219)
uniform vec3 light_color = vec3(0.35, 0.76, 0.95);
uniform vec3 dark_color = vec3(0.0, 0.47, 0.78);
uniform float speed = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;
	if (distance(c.rgb, water_color) < 0.04) {
		// Whole game pixels only, so it stays crisp pixel art
		vec2 p = floor(world_pos);
		float t = TIME * speed;
		// Three slow waves crossing each other make drifting patches
		float w = sin(p.x * 0.07 + t * 0.9) + sin(p.y * 0.11 - t * 0.6) + sin((p.x - p.y) * 0.045 + t * 0.4);
		if (w > 2.15) {
			c.rgb = mix(c.rgb, light_color, 0.55);
		} else if (w < -2.25) {
			c.rgb = mix(c.rgb, dark_color, 0.6);
		}
	}
	COLOR = c;
}
