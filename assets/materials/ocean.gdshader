shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

// A flat StandardMaterial3D read as a painted plane, not water. Two things
// sell "water" cheaply: a surface that visibly moves, and colour that shifts
// with the motion instead of sitting dead flat. Both come from sine waves,
// not real simulation — the same "cheap sine instead of real noise" trick
// already used for the meteor's cracks and its tail sparks.

uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.32, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.14, 0.36, 0.46, 1.0);
uniform float wave_height = 0.4;
uniform float wave_speed = 0.5;

varying float wave_lift;

void vertex() {
	// Two waves at unrelated frequencies and directions rather than one, so
	// the surface does not read as a single ripple repeating on a visible
	// period — the same reasoning the camera's own impact shake already
	// uses for its three sines.
	float t = TIME * wave_speed;
	float w = sin(VERTEX.x * 0.018 + t) * cos(VERTEX.z * 0.014 + t * 0.85)
		+ 0.5 * sin(VERTEX.x * 0.05 - t * 1.6 + VERTEX.z * 0.04);
	wave_lift = w;
	VERTEX.y += w * wave_height;
}

void fragment() {
	float shade = clamp(wave_lift * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shade);
	ROUGHNESS = 0.1;
	METALLIC = 0.25;
}
