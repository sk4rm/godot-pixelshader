/**
 * Ported from:
 *  https://github.com/KodyJKing/hello-threejs/blob/main/src/RenderPixelatedPass.ts
 */

shader_type spatial;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

uniform vec3 normal_edge_bias = vec3(1.0, 1.0, 1.0);
uniform float normal_edge_coefficient = 0.2;
uniform float normal_threshold = 0.1;
uniform float depth_edge_coefficient = 0.55;
uniform float depth_threshold = 0.25;
uniform float depth_smooth = 0.05;
uniform float initial_inverse_depth_value = 0.5;

const vec2 UP    = vec2( 0,  1);
const vec2 DOWN  = vec2( 0, -1);
const vec2 LEFT  = vec2(-1,  0);
const vec2 RIGHT = vec2( 1,  0);
const vec2 DIRECTIONS[4] = { UP, DOWN, LEFT, RIGHT };


float get_depth(vec2 uv, mat4 inverse_projection_matrix) {
	float depth = texture(DEPTH_TEXTURE, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inverse_projection_matrix * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}


vec3 get_normal(vec2 uv) {
	return texture(NORMAL_TEXTURE, uv).rgb * 2.0 - 1.0;
}


float get_neighbor_normal_edge_indicator(
	vec2 uv,
	float my_depth,
	vec3 my_normal,
	mat4 inverse_projection_matrix
) {
	float neighbor_depth = get_depth(uv, inverse_projection_matrix);
	vec3 neighbor_normal = get_normal(uv);

	float depth_difference = neighbor_depth - my_depth;
	float normal_difference = 
		dot(my_normal - neighbor_normal, normal_edge_bias);

	float depth_indicator = clamp(
		sign(depth_difference * 0.25 + 0.0025),
		0.0,
		1.0
	);
	float normal_indicator = clamp(
		smoothstep(-0.01, 0.01, normal_difference),
		0.0,
		1.0
	);

	return
		distance(my_normal, neighbor_normal)
		* depth_indicator
		* normal_indicator;
}


float get_depth_edge_indicator(
	vec2 uv,
	vec2 texel_size,
	mat4 inverse_projection_matrix,
	out float inverse_indicator
) {
	float depth = get_depth(uv, inverse_projection_matrix);

	float indicator = 0.0;
	inverse_indicator = initial_inverse_depth_value;
	for (int i = 0; i < DIRECTIONS.length(); i++) {
		vec2 neighbor_uv = DIRECTIONS[i] * texel_size + uv;
		float neighbor_depth = get_depth(
			neighbor_uv,
			inverse_projection_matrix
		);
		indicator += clamp(neighbor_depth - depth, 0.0, 1.0);
		inverse_indicator += depth - neighbor_depth;
	}
	//inverse_indicator = clamp(inverse_indicator, 0.0, 1.0);
	inverse_indicator = clamp(
		smoothstep(0.9, 0.9, inverse_indicator) * 10.0,
		0.0,
		1.0
	);

	return floor(
		smoothstep(
			depth_threshold,
			depth_threshold + depth_smooth,
			indicator
		) * 2.0
	) / 2.0;
}


float get_normal_edge_indicator(
	vec2 uv,
	vec2 texel_size,
	mat4 inverse_projection_matrix,
	float inverse_depth_indicator
	
) {
	float my_depth = get_depth(uv, inverse_projection_matrix);
	vec3 my_normal = get_normal(uv);

	float indicator = 0.0;
	for (int i = 0; i < DIRECTIONS.length(); i++) {
		vec2 neighbor_uv = DIRECTIONS[i] * texel_size + uv;
		indicator += get_neighbor_normal_edge_indicator(
			neighbor_uv,
			my_depth,
			my_normal,
			inverse_projection_matrix
		);
	}
	indicator = step(normal_threshold, indicator);

	//// Fix double lines using inverse depth indicator.
	//indicator = clamp(indicator - inverse_depth_indicator, 0.0, 1.0);

	return indicator;
}


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	vec2 texel_size = 1.0 / VIEWPORT_SIZE.xy;
	vec3 albedo = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	float inverse_depth_indicator = 0.0;

	float depth_indicator = get_depth_edge_indicator(
		SCREEN_UV,
		texel_size,
		INV_PROJECTION_MATRIX,
		inverse_depth_indicator
	);
	float normal_indicator = get_normal_edge_indicator(
		SCREEN_UV,
		texel_size,
		INV_PROJECTION_MATRIX,
		inverse_depth_indicator
	);

	float coefficient = 0.0;
	if (depth_indicator > 0.0)
		coefficient = 1.0 - depth_edge_coefficient * depth_indicator;
	else
		coefficient = 1.0 + normal_edge_coefficient * normal_indicator;

	ALBEDO = albedo * coefficient;

	//// Visualize normal edge detection.
	//ALBEDO = vec3(normal_indicator);

	//// Visualize depth edge detection.
	//ALBEDO = vec3(depth_indicator);

	//// Visualize inverse depth edge detection.
	//ALBEDO = vec3(inverse_depth_indicator);

	//// Visualize depth buffer.
	//ALBEDO = vec3(smoothstep(get_depth(SCREEN_UV, INV_PROJECTION_MATRIX), 0.0, 10.0));
	
	//// Visualize normal buffer.
	//ALBEDO = vec3(get_normal(SCREEN_UV));

	//// Visualize total edge detection.
	//ALBEDO = albedo * (depth_indicator + normal_indicator);
}


//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
