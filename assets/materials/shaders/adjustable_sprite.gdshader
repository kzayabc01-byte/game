shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint_color : source_color = vec4(1.0);
uniform float color_concentration : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float brightness : hint_range(0.25, 2.0, 0.01) = 1.0;
uniform float contrast : hint_range(0.25, 2.0, 0.01) = 1.0;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec4 texture_sample = texture(TEXTURE, UV);
	const vec3 luminance_weights = vec3(0.2126, 0.7152, 0.0722);
	float luminance = dot(texture_sample.rgb, luminance_weights);
	vec3 saturated = mix(vec3(luminance), texture_sample.rgb, saturation);
	vec3 tinted = mix(saturated, saturated * tint_color.rgb, color_concentration);
	vec3 contrasted = (tinted - vec3(0.5)) * contrast + vec3(0.5);
	COLOR = vec4(max(contrasted * brightness, vec3(0.0)), texture_sample.a * opacity);
}
