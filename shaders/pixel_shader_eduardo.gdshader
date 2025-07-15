shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

uniform float light_intensity = 1.25;
uniform float line_alpha = 0.7;
uniform bool use_lighting = true;
uniform float line_highlight = 0.2;
uniform float line_shadow = 0.55;

varying vec2 screen_uv;
varying float line_mask;


float get_linear_depth(vec2 offset_uv, sampler2D depth_texture, mat4 inv_projection_matrix, float mask) {
	// Raw depth to linear depth code from:
	// https://docs.godotengine.org/en/latest/tutorials/shaders/advanced_postprocessing.html
	float depth = texture(depth_texture, offset_uv).x * mask;
	vec3 ndc = vec3(offset_uv * 2.0 - 1.0, depth);
    vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}


vec3 get_normal(vec2 uv, sampler2D normal_texture, float mask) {
	vec3 normal = texture(normal_texture, uv).rgb;
	normal = normal * 2.0 - 1.0 * mask;
	return normal;
}


float normal_edge_indicator(vec3 normal_edge_bias, vec3 normal, vec3 neighbor_normal, float depth_difference) {
	//From Kody King: https://threejs.org/examples/webgl_postprocessing_pixel.html
	float normal_difference = dot(normal - neighbor_normal, normal_edge_bias);
	float normal_indicator = clamp(smoothstep(-.01, .01, normal_difference), 0.0, 1.0);
	float depth_indicator = clamp(sign(depth_difference * .25 + .0025), 0.0, 1.0);
	return (1.0 - dot(normal, neighbor_normal)) * depth_indicator * normal_indicator;
}


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	vec2 texel_size = 1.0 / VIEWPORT_SIZE.xy;
	screen_uv = SCREEN_UV;

	// UV offsets
	vec2 neighbor_uvs[4];
	neighbor_uvs[0] = SCREEN_UV + vec2(0.0, -1.0) * texel_size;
	neighbor_uvs[1] = SCREEN_UV + vec2(0.0, 1.0) * texel_size;
	neighbor_uvs[2] = SCREEN_UV + vec2(1.0, 0.0) * texel_size;
	neighbor_uvs[3] = SCREEN_UV + vec2(-1.0, 0.0) * texel_size;

	// Using alpha channel (screen roughness) to mask objects to not receive outlines
	float outline_mask = texture(NORMAL_TEXTURE, SCREEN_UV).a;
	outline_mask = ceil(outline_mask); // Objects with Roughness = 0 will not have and outline

	// Edge detection with Depth
	float depth_difference = 0.0;
	float inverse_depth_difference = 0.5;
	float depth = get_linear_depth(SCREEN_UV, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outline_mask);

	for (int i = 0; i < neighbor_uvs.length(); i++){
		float dOff = get_linear_depth(neighbor_uvs[i],DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outline_mask);
		depth_difference += clamp(dOff - depth, 0.0, 1.0);
		inverse_depth_difference += depth - dOff;
	}
	inverse_depth_difference = clamp(inverse_depth_difference, 0.0, 1.0);
	inverse_depth_difference = clamp(smoothstep(0.9, 0.9, inverse_depth_difference) * 10.0 , 0.0, 1.0);
	depth_difference = smoothstep(0.25, 0.3, depth_difference);

	// Edge detection with Normals
	float normal_difference = 0.;
	vec3 normal_edge_bias = vec3(1.0, 1.0, 1.0);
	vec3 normal = get_normal(SCREEN_UV, NORMAL_TEXTURE, outline_mask);

	for (int i = 0; i < neighbor_uvs.length(); i++){
		vec3 nOff = get_normal(neighbor_uvs[i],NORMAL_TEXTURE, outline_mask);
		normal_difference += normal_edge_indicator(normal_edge_bias, normal, nOff, depth_difference);
	}
	normal_difference = smoothstep(0.2, 0.2, normal_difference);
	normal_difference = clamp(normal_difference - inverse_depth_difference, 0.0, 1.0);


	ALBEDO = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	line_mask = clamp(0.1, line_alpha, (depth_difference + normal_difference * 5.0));


	if (!use_lighting){
		ALBEDO += clamp((normal_difference - depth_difference), 0.0, 1.0) * line_highlight;
		ALBEDO -= ALBEDO * depth_difference * line_shadow;
	}
}


void light() {
	if (use_lighting) {
		vec4 normal = texture(NORMAL_TEXTURE, screen_uv);
		normal = normal * 2.0 - 1.0;

		// Calculate light direction
		float dotNL = dot(normal.rgb, LIGHT);
		dotNL = pow(dotNL, 2.5);
		dotNL = clamp(dotNL, 0.0, 1.0);

		if(LIGHT_IS_DIRECTIONAL)
			DIFFUSE_LIGHT += mix(vec3(1.0), dotNL * LIGHT_COLOR * light_intensity, line_mask);
	}
	else
		DIFFUSE_LIGHT = vec3(1.0);
}
