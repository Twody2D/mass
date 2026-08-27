shader_type spatial;

// The rock stays the same normally lit, flat-shaded stone BlobMesh always
// built — COLOR still carries its dark/light facet variation, ALBEDO is
// untouched by any of this. Everything below is additive EMISSION on top,
// so the base rock is unchanged wherever both effects are zero.

// World-space direction of travel, transformed into the rock's own current
// (spinning) local space by MeteorProjectile every tick. Comparing against
// this rather than the fragment's engine-transformed NORMAL is what keeps
// the hot side facing the way the rock is actually falling, regardless of
// which facets currently happen to point forward.
uniform vec3 local_heading = vec3(0.0, -1.0, 0.0);
uniform vec3 fire_color = vec3(1.0, 0.55, 0.16);
uniform float heat_intensity = 0.0;
uniform float crack_strength = 0.0;
// Offsets the crack pattern so every meteor's rock cracks differently, the
// same reasoning BlobMesh's own mesh_seed already gives the facets.
uniform float crack_seed = 0.0;

// Object-space normal, captured before Godot transforms NORMAL for its own
// lighting pass. A crack is a feature of the rock's own surface: it has to
// turn with the rock as it spins, not swim across it.
varying vec3 v_object_normal;

void vertex() {
	v_object_normal = NORMAL;
}

// Three sine "fracture planes" at unrelated angles and frequencies — the
// same reasoning CameraRig's own impact shake already uses instead of real
// noise: cheap, deterministic, and enough to read as a network of glowing
// seams without simulating an actual fracture.
float crack_pattern(vec3 n) {
	vec3 q = n * 5.0 + vec3(crack_seed);
	float a = abs(sin(dot(q, vec3(3.1, 1.7, 2.3))));
	float b = abs(sin(dot(q, vec3(-2.1, 3.3, 1.1))));
	float c = abs(sin(dot(q, vec3(1.9, -2.7, 3.7))));
	return 1.0 - smoothstep(0.0, 0.08, min(a, min(b, c)));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	float lead = clamp(dot(normalize(v_object_normal), normalize(local_heading)), 0.0, 1.0);
	float heat = pow(lead, 3.0) * heat_intensity;
	float cracks = crack_pattern(v_object_normal) * crack_strength;
	EMISSION = fire_color * (heat + cracks);
}
