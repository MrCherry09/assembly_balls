// Fake stencil outline by Sithoid
// Viewport logic by Leafshade Interactive
// Outline logic by Mark Raynsford
// Put on a fullscreen ColorRect; stencilMask = SubViewport texture (outline visual layer only).
shader_type canvas_item;

uniform float lineWeight : hint_range(0.5, 10.0) = 2.0;
uniform vec4 outlineColor : source_color = vec4(1.0, 0.85, 0.15, 0.95);
uniform sampler2D stencilMask : source_color, repeat_disable, filter_linear;

void fragment() {
	float dx = SCREEN_PIXEL_SIZE.x * lineWeight;
	float dy = SCREEN_PIXEL_SIZE.y * lineWeight;

	// Shift by half line size so expansion is uniform.
	vec2 uvCenter = vec2(SCREEN_UV.x - dx * 0.5, SCREEN_UV.y + dy * 0.5);
	vec2 uvRight = vec2(uvCenter.x + dx, uvCenter.y);
	vec2 uvTop = vec2(uvCenter.x, uvCenter.y - dy);
	vec2 uvTopRight = vec2(uvCenter.x + dx, uvCenter.y - dy);

	float mCenter = texture(stencilMask, uvCenter).a;
	float mTop = texture(stencilMask, uvTop).a;
	float mRight = texture(stencilMask, uvRight).a;
	float mTopRight = texture(stencilMask, uvTopRight).a;

	float delta = 0.0;
	delta = max(delta, abs(mCenter - mTop));
	delta = max(delta, abs(mCenter - mRight));
	delta = max(delta, abs(mCenter - mTopRight));

	COLOR = vec4(outlineColor.rgb, sign(delta) * outlineColor.a);
}
