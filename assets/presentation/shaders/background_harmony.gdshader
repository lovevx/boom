shader_type canvas_item;
render_mode unshaded;

uniform float saturation = 0.75;
uniform float contrast = 0.85;
uniform float ground_saturation = 0.90;
uniform float ground_contrast = 0.94;
uniform vec4 haze_color : source_color = vec4(0.698, 0.804, 0.867, 1.0);
uniform float haze_strength = 0.10;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// The transparent ground layer retains the same full-canvas UVs as the backdrop.
	float near_ground = smoothstep(0.78, 0.94, UV.y);
	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 color = mix(vec3(luma), source.rgb, mix(saturation, ground_saturation, near_ground));
	color = (color - 0.5) * mix(contrast, ground_contrast, near_ground) + 0.5;
	float haze = smoothstep(0.35, 0.65, UV.y) * (1.0 - near_ground) * haze_strength;
	color = mix(color, haze_color.rgb, haze);
	COLOR = vertex_tint * vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
}
