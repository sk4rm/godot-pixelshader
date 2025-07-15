shader_type spatial;
render_mode unshaded;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

uniform float depth_threshold = 0.25;
uniform float reverse_depth_threshold = 0.25;
uniform float normal_threshold = 0.25;

/**
 * [code]0.0[/code] for 0% brightness, AKA black outline.
 * [code]1.0[/code] for 100% brightness, AKA no outline.
 */
uniform float outer_edge_brightness : hint_range(0.0, 1.0) = 0.25;
/**
 * todo))
 */
uniform float inner_edge_brightness : hint_range(0.0, 5.0) = 1.25;

const vec2 UP    = vec2( 0,  1);
const vec2 DOWN  = vec2( 0, -1);
const vec2 LEFT  = vec2(-1,  0);
const vec2 RIGHT = vec2( 1,  0);
const vec3 NORMAL_EDGE_BIAS = vec3(1.0, 1.0, 1.0);


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float get_depth(vec2 uv, mat4 inv_projection_matrix) {
	float depth = texture(DEPTH_TEXTURE, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}


vec3 get_normal(vec2 uv) {
	vec3 normal = texture(NORMAL_TEXTURE, uv).xyz;
	return normal * 2.0 - 1.0;
}


void fragment() {
	float depth = get_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 normal = get_normal(SCREEN_UV);
	vec3 albedo = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	vec2 texel_size = 1.0 / VIEWPORT_SIZE.xy;

	float depth_difference = 0.0;
	float reverse_depth_difference = 0.0;
	float normal_difference_sum = 0.0;
	float nearest_depth = depth;
	vec2 nearest_uv = SCREEN_UV;

	vec2 neighbors[4] = {
		//SCREEN_UV + texel_size * (LEFT + UP),
		//SCREEN_UV + texel_size * (LEFT + DOWN),
		//SCREEN_UV + texel_size * (RIGHT + UP),
		//SCREEN_UV + texel_size * (RIGHT + DOWN)
		SCREEN_UV + texel_size * UP,
		SCREEN_UV + texel_size * DOWN,
		SCREEN_UV + texel_size * LEFT,
		SCREEN_UV + texel_size * RIGHT
	};

	for (int i = 0; i < neighbors.length(); i++) {
		float neighbor_depth = get_depth(neighbors[i], INV_PROJECTION_MATRIX);
		vec3 neighbor_normal = get_normal(neighbors[i]);

		depth_difference += depth - neighbor_depth;
		reverse_depth_difference += neighbor_depth - depth;

		if (neighbor_depth < nearest_depth) {
			nearest_depth = neighbor_depth;
			nearest_uv = neighbors[i];
		}

		vec3 normal_difference = normal - neighbor_normal;
		float normal_indicator = smoothstep(-0.01, 0.01, dot(normal_difference, NORMAL_EDGE_BIAS));
		normal_difference_sum += dot(normal_difference, normal_difference) * normal_indicator;
	}

	float outer_edge_indicator = step(depth_threshold, depth_difference);
	float outer_edge = outer_edge_brightness * outer_edge_indicator;
	vec3 nearest_albedo = texture(SCREEN_TEXTURE, nearest_uv).rgb;

	float inner_edge_mask = step(reverse_depth_threshold, reverse_depth_difference);
	float inner_edge_indicator = step(normal_threshold, sqrt(normal_difference_sum) - inner_edge_mask);
	float inner_edge = inner_edge_brightness * inner_edge_indicator;

	if (outer_edge_indicator > 0.0) {
		ALBEDO = mix(albedo, nearest_albedo * outer_edge, outer_edge_indicator);
	} else {
		ALBEDO = mix(albedo, albedo * inner_edge, inner_edge_indicator);
	}
}
