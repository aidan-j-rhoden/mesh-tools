shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// =========================================================================
//  MELTED METAL  -  fully procedural, animated molten surface with a
//  glowing hot rim on every edge and pulsing glowing veins inside.
//  Godot 4.x  ->  attach to a ShaderMaterial and assign to any mesh.
// =========================================================================

// ---- Surface colours -----------------------------------------------------
uniform vec4  metal_color : source_color = vec4(0.18, 0.19, 0.23, 1.0);
uniform vec4  hot_color   : source_color = vec4(1.0, 0.35, 0.05, 1.0);

uniform float metallic    : hint_range(0.0, 1.0) = 1.0;
uniform float roughness   : hint_range(0.0, 1.0) = 0.45;

// ---- Procedural flow -----------------------------------------------------
uniform float noise_scale : hint_range(0.5, 100.0) = 4.0;   // pattern density
uniform float flow_speed  : hint_range(0.0, 2.0)  = 0.15;  // how fast it melts

// ---- Edge glow -----------------------------------------------------------
uniform float fresnel_power      : hint_range(0.5, 8.0)  = 3.0;   // edge tightness
uniform float edge_glow_strength : hint_range(0.0, 10.0) = 3.5;   // rim brightness

// ---- Inner molten veins --------------------------------------------------
uniform float vein_threshold     : hint_range(0.0, 1.0)  = 0.45;
uniform float vein_glow_strength : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed        : hint_range(0.0, 10.0) = 2.0;

// ---- Optional geometric wobble (subtle "liquid" motion) ------------------
uniform float displacement : hint_range(0.0, 0.5) = 0.03;

// -------------------------------------------------------------------------
//  Value noise + FBM (no textures required)
// -------------------------------------------------------------------------
float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
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
vec2 flow_uv(vec2 uv) {
	vec2 flow = vec2(0.0, TIME * flow_speed);
	vec2 warp = vec2(fbm(uv + flow), fbm(uv + flow + vec2(5.2, 1.3)));
	return uv + warp * 0.5 + flow;
}

// -------------------------------------------------------------------------
void vertex() {
	if (displacement > 0.0) {
		vec2 uv = UV * noise_scale;
		float d = fbm(flow_uv(uv)) - 0.5;
		VERTEX += NORMAL * d * displacement;   // gentle drifting ripples
	}
}

void fragment() {
	vec2 uv  = UV * noise_scale;
	vec2 cuv = flow_uv(uv);
	float n  = fbm(cuv);

	// --- Molten metal body ---
	ALBEDO    = metal_color.rgb * (0.55 + 0.45 * n);
	METALLIC  = metallic;
	ROUGHNESS = clamp(roughness - n * 0.25, 0.0, 1.0);

	// --- Glowing veins sitting in the low pockets of the noise ---
	float veins = 1.0 - smoothstep(vein_threshold, vein_threshold + 0.18, n);
	veins *= 0.7 + 0.3 * sin(TIME * pulse_speed + n * 12.0);   // slow pulse

	// --- Hot fresnel rim: every silhouette edge burns ---
	float rim = fresnel(fresnel_power, NORMAL, VIEW);

	EMISSION = hot_color.rgb * (rim * edge_glow_strength + veins * vein_glow_strength);
}
