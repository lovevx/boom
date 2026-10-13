shader_type canvas_item;
render_mode unshaded;
uniform vec4 dust_color : source_color = vec4(0.651, 0.608, 0.533, 1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float value = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vertex_tint * vec4(dust_color.rgb * (0.65 + value * 0.55), source.a);
}
