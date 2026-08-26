shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Team colours for the whole crowd, in linear space. The instance carries only
// an index, so ten thousand knights share one material and one draw call.
uniform vec4 team_colors[8];

// Model height, so the walk cycle can find the hips without being told twice.
uniform float bot_height = 2.4;
// Speed at which the walk reaches full amplitude.
uniform float reference_speed = 3.5;
// Radians per second of the step cycle. Constant rather than scaled by speed:
// a varying rate multiplied by TIME jumps the phase whenever speed changes.
uniform float step_rate = 9.0;

// How far a leg swings, how far the body rolls, how high it bobs.
const float LEG_SWING = 0.45;
const float BODY_ROLL = 0.10;
const float BODY_BOB = 0.022;

// The pivot sits exactly at the top of the legs, so no leg vertex is ever
// lifted above it and none can swing up into the torso.
// Everything below the hips and near the centre line is a leg. Deciding this
// from position rather than from an extra vertex attribute keeps the vertex
// format small, which matters when ten thousand instances are already the
// bottleneck. The sword and shield sit far enough out to be excluded.
const float HIP_FRACTION = 0.22;
const float LEG_HALF_WIDTH = 0.25;

void vertex() {
	// INSTANCE_CUSTOM.x is the team index, written once per bot at spawn.
	int team = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 7);

	// COLOR.rgb is the shade of this part, COLOR.a is the team mask. A mask of
	// 0 leaves steel and leather alone; a mask of 1 tints the part with the
	// team colour, keeping the shade as a multiplier so the body can sit a
	// step darker than the helmet without a second material.
	COLOR = vec4(mix(COLOR.rgb, team_colors[team].rgb * COLOR.rgb, COLOR.a), 1.0);

	// A standing knight has an amplitude of zero, so idle bots cost the same
	// arithmetic but do not twitch.
	float walk = clamp(INSTANCE_CUSTOM.w / reference_speed, 0.0, 1.0);
	float t = TIME * step_rate + INSTANCE_CUSTOM.y * TAU;
	float swing_wave = sin(t);

	float hip = bot_height * HIP_FRACTION;
	if (VERTEX.y < hip && abs(VERTEX.x) < bot_height * LEG_HALF_WIDTH) {
		// The legs counter-swing around the hip, one forward while the other
		// goes back.
		float swing = swing_wave * sign(VERTEX.x) * LEG_SWING * walk;
		float cs = cos(swing);
		float sn = sin(swing);
		float dy = VERTEX.y - hip;
		VERTEX.y = hip + dy * cs;
		VERTEX.z = VERTEX.z - dy * sn;
		NORMAL = vec3(NORMAL.x, NORMAL.y * cs + NORMAL.z * sn, NORMAL.z * cs - NORMAL.y * sn);
	}

	// The whole figure rocks side to side. This is what sells the toy: a
	// straight upright walk reads as a model sliding along the ground.
	float roll = swing_wave * BODY_ROLL * walk;
	float cr = cos(roll);
	float sr = sin(roll);
	vec3 p = VERTEX;
	VERTEX.x = p.x * cr - p.y * sr;
	VERTEX.y = p.x * sr + p.y * cr;
	vec3 n = NORMAL;
	NORMAL = vec3(n.x * cr - n.y * sr, n.x * sr + n.y * cr, n.z);

	// Two bounces per step cycle, so the bob lands on each footfall.
	VERTEX.y += abs(swing_wave) * bot_height * BODY_BOB * walk;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
