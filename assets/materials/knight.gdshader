shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Team colours for the whole crowd, in linear space. The instance carries only
// an index, so ten thousand knights share one material and one draw call.
uniform vec4 team_colors[8];

void vertex() {
	// INSTANCE_CUSTOM.x is the team index, written once per bot at spawn.
	int team = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 7);

	// COLOR.rgb is the shade of this part, COLOR.a is the team mask. A mask of
	// 0 leaves steel and leather alone; a mask of 1 tints the part with the
	// team colour, keeping the shade as a multiplier so the body can sit a
	// step darker than the helmet without a second material.
	COLOR = vec4(mix(COLOR.rgb, team_colors[team].rgb * COLOR.rgb, COLOR.a), 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
