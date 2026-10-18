shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 render_size = vec2(640.0, 360.0);
uniform float color_steps : hint_range(8.0, 64.0, 1.0) = 24.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.012;
uniform float contrast : hint_range(0.8, 1.5) = 1.12;
uniform float saturation : hint_range(0.0, 1.5) = 0.78;
uniform vec4 shadow_tint : source_color = vec4(0.64, 0.78, 0.76, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.91, 0.75, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.12;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	// Anchor grain and ordered dithering to the 3D pixel grid, without animation.
	vec2 pixel = floor(SCREEN_UV * render_size);
	vec2 sample_uv = (pixel + 0.5) / render_size;
	vec3 color = textureLod(screen_texture, sample_uv, 0.0).rgb;
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, saturation);
	vec3 tint = mix(shadow_tint.rgb, highlight_tint.rgb, smoothstep(0.15, 0.8, luminance));
	color *= mix(vec3(1.0), tint, tint_strength);
	color = (color - 0.4) * contrast + 0.4;
	float edge = smoothstep(0.2, 0.72, length(SCREEN_UV - 0.5));
	color *= 1.0 - edge * vignette_strength;
	float grain = fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	color += grain * grain_strength;
	ivec2 cell = ivec2(mod(pixel, 4.0));
	float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float levels = max(color_steps - 1.0, 1.0);
	color = floor(clamp(color, 0.0, 1.0) * levels + mix(0.5, threshold, dither_strength)) / levels;
	COLOR = vec4(color, 1.0);
}
