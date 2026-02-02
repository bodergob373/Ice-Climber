shader_type canvas_item;

uniform float saturation_variation = 0.4;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = COLOR;

	float r = rand(UV + TIME);
	float sat = mix(1.0 - saturation_variation, 1.0, r);

	float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(gray), c.rgb, sat);

	COLOR = c;
}