shader_type spatial;

// The crater floor, normally lit like the rest of the terrain (ALBEDO =
// vertex colour, no unshaded render mode) — this is meant to read as
// scorched ground, not as a decal of light. EMISSION is the one thing on
// top: hot right after impact, fading to nothing as Crater cools it down.

uniform vec3 fire_color = vec3(1.0, 0.5, 0.15);
uniform float glow = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = fire_color * glow;
}
