shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, ambient_light_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform float outline_width : hint_range(0.0, 0.25, 0.001) = 0.04;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
