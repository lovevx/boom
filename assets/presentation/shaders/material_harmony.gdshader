shader_type canvas_item;
render_mode unshaded;

uniform float saturation = 0.86;
uniform float contrast = 0.90;
uniform bool block_surface = false;
uniform bool glass_surface = false;
uniform float detail_strength = 1.0;
uniform vec4 surface_base : source_color = vec4(0.627, 0.655, 0.651, 1.0);
uniform vec4 sunlight : source_color = vec4(1.0, 0.941, 0.808, 1.0);
uniform vec4 frame_color : source_color = vec4(0.204, 0.294, 0.357, 1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec2 sample_uv = UV;
	if (block_surface && !glass_surface) {
		// Replace the original white tile rims with the adjacent interior texel.
		// Sampling stays nearest: this removes the checkerboard seam without blur.
		sample_uv = clamp(UV, TEXTURE_PIXEL_SIZE * 1.5, vec2(1.0) - TEXTURE_PIXEL_SIZE * 1.5);
	}
	vec4 source = texture(TEXTURE, sample_uv);
	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 color = mix(vec3(luma), source.rgb, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color = mix(surface_base.rgb, color, detail_strength);
	if (block_surface) {
		vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
		vec2 last = vec2(1.0) / TEXTURE_PIXEL_SIZE - vec2(1.0);
		bool upper = pixel.y < 1.0 || pixel.x < 1.0;
		bool lower = pixel.y >= last.y || pixel.x >= last.x;
		if (glass_surface) {
			color = min(color, vec3(0.88));
			if (upper || lower) {
				color = frame_color.rgb * (upper ? 1.12 : 0.83);
			}
		} else {
			if (upper) { color = mix(color, sunlight.rgb, 0.055); }
			if (lower) { color = mix(color, frame_color.rgb, 0.13); }
		}
	}
	COLOR = vertex_tint * vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
}
