shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, diffuse_lambert, specular_disabled;

// Smoke is made of blobs, and blobs have edges. Left alone they cut into each
// other with hard silhouettes and the column reads as a pile of boulders, which
// is exactly what the first version looked like. Fading each blob out towards
// its own rim lets them merge into one soft mass instead.
//
// Depth writing is off for the same reason: blobs that write depth punch hard
// holes in the ones behind them.

// Per blob brightness: dirty at the base of the column, light at the top. An
// instance uniform rather than vertex colour, so every blob can share one mesh.
// Baking the shade into the vertices meant a mesh per blob, and building ninety
// of them cost thirty milliseconds in the tick a meteor landed.
instance uniform vec3 shade = vec3(1.0);

uniform vec3 tint = vec3(0.34, 0.32, 0.32);
uniform float alpha = 1.0;
// Hot for the first moment after the impact, then nothing.
uniform float glow = 0.0;
// How much of the blob is edge. Higher is softer and wispier.
uniform float softness = 0.8;

void fragment() {
	// 1 looking into the middle of a blob, 0 at its silhouette.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint * shade;
	EMISSION = tint * shade * glow;
	ALPHA = alpha * smoothstep(0.0, softness, facing);
}
