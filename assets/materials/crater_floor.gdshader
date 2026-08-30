shader_type spatial;
render_mode cull_disabled;

// The crater floor, normally lit like the rest of the terrain (ALBEDO =
// vertex colour, no unshaded render mode) — this is meant to read as
// scorched ground, not as a decal of light. EMISSION is the one thing on
// top: hot right after impact, fading to nothing as Crater cools it down.
//
// cull_disabled because the floor's facet normals follow the real terrain
// (Crater._triangle() derives them from actual geometry, not a fixed
// straight-up), which on a steep slope can tilt a triangle's true front
// face away from a camera looking across it — the default cull_back would
// then drop the triangle and show the real ground straight through the
// crater, on any impact rugged enough for this to matter. Found on a real
// run: reported as "two layers of texture," which is exactly what a culled
// hole through an opaque decal onto the terrain behind it looks like.

uniform vec3 fire_color = vec3(1.0, 0.5, 0.15);
uniform float glow = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = fire_color * glow;
}
