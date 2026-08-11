shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// =========================================================================
//  MELTED METAL  -  fully procedural, animated molten surface with a
//  glowing hot rim on every edge and pulsing glowing veins inside.
//
//  SEAMLESS VERSION: the pattern is driven by 3D object-space position
//  instead of UVs, so it wraps cleanly around cylinders, spheres and any
//  other mesh that has a UV seam. Cubes look identical to before.
//  Godot 4.x  ->  attach to a ShaderMaterial and assign to any mesh.
// =========================================================================

// ---- Surface colours -----------------------------------------------------
uniform vec4  metal_color : source_color = vec4(0.18, 0.19, 0.23, 1.0);
uniform vec4  hot_color   : source_color = vec4(1.0, 0.35, 0.05, 1.0);

uniform float metallic    : hint_range(0.0, 1.0) = 1.0;
uniform float roughness   : hint_range(0.0, 1.0) = 0.45;

// ---- Procedural flow -----------------------------------------------------
// NOTE: noise_scale now multiplies object-space position, not 0..1 UVs, so
// its "right" value depends on your mesh size. Retune once per mesh scale.
uniform float noise_scale : hint_range(0.5, 100.0) = 4.0;   // pattern density
uniform float flow_speed  : hint_range(0.0, 2.0)  = 0.15;  // how fast it melts

// ---- Edge glow -----------------------------------------------------------
uniform float fresnel_power      : hint_range(0.5, 8.0)  = 3.0;   // edge tightness
uniform float edge_glow_strength : hint_range(0.0, 10.0) = 3.5;   // rim brightness

// ---- Inner molten veins --------------------------------------------------
uniform float vein_threshold     : hint_range(0.0, 1.0)  = 0.45;
uniform float vein_glow_strength : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed        : hint_range(0.0, 10.0) = 2.0;

// Threshold breathes on a sine wave so the veins grow and shrink over time.
uniform float vein_pulse_amplitude : hint_range(0.0, 0.5)  = 0.1;   // how far it swings
uniform float vein_pulse_frequency : hint_range(0.0, 10.0) = 1.0;   // how fast it swings

// ---- Optional geometric wobble (subtle "liquid" motion) ------------------
uniform float displacement : hint_range(0.0, 0.5) = 0.03;

// Object-space position passed from vertex -> fragment so both stages sample
// the exact same continuous coordinate. This is what kills the seam.
varying vec3 model_pos;

// -------------------------------------------------------------------------
//  3D value noise + FBM (no textures, no UV seam)
// -------------------------------------------------------------------------
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), u.x),
		    mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), u.x),
		    mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), u.x), u.y),
		u.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

// Fresnel: bright where the surface faces away from the camera -> edges.
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

// Domain-warped, time-scrolling coordinates -> the swirling molten look.
// Scrolls along the object's local Y axis, just like the old flow_uv did.
vec3 flow_pos(vec3 p) {
	vec3 flow = vec3(0.0, TIME * flow_speed, 0.0);
	vec3 warp = vec3(
		fbm(p + flow),
		fbm(p + flow + vec3(5.2, 1.3, 2.7)),
		fbm(p + flow + vec3(1.7, 9.2, 3.4)));
	return p + warp * 0.5 + flow;
}

// -------------------------------------------------------------------------
void vertex() {
	model_pos = VERTEX;   // in vertex(), VERTEX is model/object space
	if (displacement > 0.0) {
		vec3 p = model_pos * noise_scale;
		float d = fbm(flow_pos(p)) - 0.5;
		VERTEX += NORMAL * d * displacement;   // gentle drifting ripples
	}
}

void fragment() {
	vec3 p  = model_pos * noise_scale;
	vec3 cp = flow_pos(p);
	float n = fbm(cp);

	// --- Molten metal body ---
	ALBEDO    = metal_color.rgb * (0.55 + 0.45 * n);
	METALLIC  = metallic;
	ROUGHNESS = clamp(roughness - n * 0.25, 0.0, 1.0);

	// --- Glowing veins sitting in the low pockets of the noise ---
	float pulsed_threshold = vein_threshold
		+ sin(TIME * vein_pulse_frequency) * vein_pulse_amplitude;
	pulsed_threshold = clamp(pulsed_threshold, 0.0, 1.0);
	float veins = 1.0 - smoothstep(pulsed_threshold, pulsed_threshold + 0.18, n);
	veins *= 0.7 + 0.3 * sin(TIME * pulse_speed + n * 12.0);   // slow pulse

	// --- Hot fresnel rim: every silhouette edge burns (already seamless) ---
	float rim = fresnel(fresnel_power, NORMAL, VIEW);

	EMISSION = hot_color.rgb * (rim * edge_glow_strength + veins * vein_glow_strength);
}
