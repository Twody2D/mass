shader_type spatial;

// Triplanar-sampled real photo textures, blended by the same three-band
// weights World.gd used to paint flat vertex colours with (sand -> grass ->
// rock). The heightmap mesh has no meaningful UVs at this scale — sampling
// by world position on whichever axis a face mostly faces is the standard
// way to texture a terrain that was never unwrapped, the same reason any
// other triplanar terrain shader exists.
uniform sampler2D sand_albedo : source_color;
uniform sampler2D grass_albedo : source_color;
uniform sampler2D rock_albedo : source_color;
// Metres per texture tile. Small enough that the weave in the grass photo
// reads as blades from a normal camera distance, large enough that the
// repeat is not obvious from directly overhead (Top mode, the minimap).
uniform float texture_scale = 0.08;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
// A real photo's own albedo runs darker than this project's flat "toy"
// palette ever did — COLOR_ROCK was 0.48 on every channel, the rock photo
// itself averages well under that. Left uncorrected, any slope not facing
// the sun directly reads as almost black, which a real screenshot caught
// on the volcano's shadowed side. These bring each texture back up near
// the brightness its flat-colour predecessor had, not an attempt at
// physically correct exposure.
uniform float sand_brightness = 1.15;
uniform float grass_brightness = 1.1;
uniform float rock_brightness = 1.75;

varying vec3 world_position;
varying vec3 world_normal;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


// One texture sampled on the three axis planes and blended by how much the
// surface normal faces each one — the textbook triplanar trick, so a
// vertical cliff face gets the same rock photo a flat plateau does instead
// of a stretched sliver of it.
vec3 triplanar(sampler2D tex, vec3 pos, vec3 blend, float scale) {
	vec3 x_axis = texture(tex, pos.yz * scale).rgb;
	vec3 y_axis = texture(tex, pos.xz * scale).rgb;
	vec3 z_axis = texture(tex, pos.xy * scale).rgb;
	return x_axis * blend.x + y_axis * blend.y + z_axis * blend.z;
}


void fragment() {
	vec3 blend = abs(world_normal);
	blend = blend / max(blend.x + blend.y + blend.z, 0.0001);

	// COLOR carries the same three band weights World._terrain_weights()
	// used to write a flat colour with, just consumed as a texture blend
	// instead — the geology World already worked out per vertex, reused
	// rather than recomputed here.
	vec3 weights = COLOR.rgb;
	weights = weights / max(weights.x + weights.y + weights.z, 0.0001);

	vec3 sand = triplanar(sand_albedo, world_position, blend, texture_scale) * sand_brightness;
	vec3 grass = triplanar(grass_albedo, world_position, blend, texture_scale) * grass_brightness;
	vec3 rock = triplanar(rock_albedo, world_position, blend, texture_scale) * rock_brightness;

	ALBEDO = sand * weights.x + grass * weights.y + rock * weights.z;
	ROUGHNESS = roughness_value;
}
