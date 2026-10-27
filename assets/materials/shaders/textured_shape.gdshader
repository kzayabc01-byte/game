shader_type canvas_item;
render_mode unshaded;

uniform sampler2D albedo_texture : repeat_enable, filter_linear;
uniform int material_mode : hint_enum("Matte", "Glass", "Ice") = 0;
uniform float tile_size_pixels : hint_range(16.0, 512.0, 1.0) = 96.0;
uniform vec2 texture_scale = vec2(1.0);
uniform vec2 texture_offset = vec2(0.0);
uniform vec2 shape_size_pixels = vec2(64.0);
uniform float texture_midpoint : hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float texture_detail_strength : hint_range(0.0, 1.0, 0.01) = 0.15;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float color_concentration : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float brightness : hint_range(0.25, 2.0, 0.01) = 1.0;
uniform float contrast : hint_range(0.25, 2.0, 0.01) = 1.0;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_strength : hint_range(0.0, 2.0, 0.01) = 0.0;
uniform vec4 edge_highlight_color : source_color = vec4(1.0);
uniform float edge_highlight_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

varying vec2 material_uv;
varying vec2 shape_uv;

void vertex() {
	material_uv = VERTEX / max(tile_size_pixels, 1.0);
	shape_uv = VERTEX / max(shape_size_pixels, vec2(1.0)) + vec2(0.5);
}

void fragment() {
	vec4 texture_sample = texture(albedo_texture, material_uv * texture_scale + texture_offset);
	const vec3 luminance_weights = vec3(0.2126, 0.7152, 0.0722);
	float texture_luminance = dot(texture_sample.rgb, luminance_weights);
	float detail = (texture_luminance - texture_midpoint) * 2.0 * texture_detail_strength * contrast;

	vec3 colored = mix(base_color.rgb, tint_color.rgb, color_concentration);
	float colored_luminance = dot(colored, luminance_weights);
	vec3 saturated = mix(vec3(colored_luminance), colored, saturation);
	vec3 lit = saturated * (1.0 + detail) * brightness;

	if (material_mode == 1) {
		float side_distance = clamp(abs(shape_uv.x - 0.5) * 2.0, 0.0, 1.0);
		float side_highlight = pow(side_distance, 2.4);
		float soft_center = 1.0 - smoothstep(0.0, 0.5, abs(shape_uv.x - 0.5));
		lit = saturated * (1.0 + detail) * brightness;
		lit += edge_highlight_color.rgb * edge_highlight_strength * side_highlight;
		lit += saturated * soft_center * 0.04;
	} else if (material_mode == 2) {
		float top_glow = clamp(1.0 - shape_uv.y, 0.0, 1.0);
		lit += edge_highlight_color.rgb * edge_highlight_strength * top_glow * 0.18;
	}

	vec3 emitted = emission_color.rgb * emission_strength;
	vec4 vertex_color = COLOR;

	COLOR = vec4(max(lit + emitted, vec3(0.0)), base_color.a * tint_color.a * opacity) * vertex_color;
}
