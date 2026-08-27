shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// A blast is light, not a ball. A sphere with a constant colour reads as a
// painted balloon however faint it is, because its edge is a hard silhouette.
// Fading it out towards the rim is what turns the same sphere into a glow.

uniform vec3 core_color = vec3(1.0, 0.52, 0.18);
// Written every frame by BlastEffect, so the fade lives in one place.
uniform float strength = 0.0;

void fragment() {
	// 1 where we are looking straight into the sphere, 0 at the silhouette.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// The centre goes white hot; the rim gives out entirely, which is what
	// removes the edge.
	ALBEDO = mix(core_color, vec3(1.0), pow(facing, 10.0));
	ALPHA = pow(facing, 2.2) * strength;
}
