shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Class colours for the whole crowd, in linear space. The instance carries
// only an index, so ten thousand knights share one material and one draw
// call — the weapon/shield silhouette itself comes from which of the
// per-class meshes this instance's tier actually is, not from this shader.
uniform vec4 class_colors[4];

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

// How far the outer corner of a boot sits from the centre line, as a fraction
// of height. Must match KnightMesh: the boots are centred at 0.085 and are
// 0.14 wide, so their outer edge is at 0.155. Same arrangement as HIP_FRACTION
// above, which tracks LEG_TOP for the same reason — the shader has to know
// where the model's landmarks are and there is nowhere cheaper to put that
// than a constant.
const float FOOT_REACH = 0.155;

void vertex() {
	// INSTANCE_CUSTOM.x is the class index, written once per bot at spawn.
	int bot_class = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 3);

	// COLOR.rgb is the shade of this part, COLOR.a is the class mask. A mask
	// of 0 leaves steel and leather alone; a mask of 1 tints the part with
	// the class colour, keeping the shade as a multiplier so the body can
	// sit a step darker than the helmet without a second material.
	COLOR = vec4(mix(COLOR.rgb, class_colors[bot_class].rgb * COLOR.rgb, COLOR.a), 1.0);

	// CrowdRenderer writes a negative value here for a corpse — never a real
	// speed — the same "spare slot doubles as a signal" trick BotManager
	// already uses on dwell_until and health once a bot is dead. From
	// straight above, a fallen body's silhouette was not always enough to
	// tell it apart from a standing one; draining its colour towards grey is
	// a cue that survives any viewing angle the living crowd's vivid team
	// colours do not share.
	bool dead = INSTANCE_CUSTOM.w < 0.0;
	if (dead) {
		float grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR.rgb = mix(COLOR.rgb, vec3(grey) * 0.4, 0.85);
	}

	// A standing knight has an amplitude of zero, so idle bots cost the same
	// arithmetic but do not twitch.
	float walk = dead ? 0.0 : clamp(INSTANCE_CUSTOM.w / reference_speed, 0.0, 1.0);
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

	// The roll turns the figure about its own origin, which is the point on the
	// ground between the feet, so the outer corner of the downhill boot lands
	// at x * sin(roll) — below the terrain, by up to four centimetres at full
	// stride. It only happened while walking, because a standing knight has no
	// roll, which is exactly how it was reported.
	//
	// Lifting by the same amount puts that corner back on the ground and lifts
	// the other foot instead, so the knight rocks from one planted foot to the
	// other rather than grinding a boot through the grass. Cheaper than rolling
	// about the hips, which barely helps: the x * sin(roll) term is what sinks
	// the foot, not the choice of pivot.
	VERTEX.y += abs(sr) * bot_height * FOOT_REACH;

	// Two bounces per step cycle, so the bob lands on each footfall.
	VERTEX.y += abs(swing_wave) * bot_height * BODY_BOB * walk;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
