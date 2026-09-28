const highp float SDF_DIAGONAL_SPREAD = 1.4142;
const highp float SDF_SMOOTHING_PIXEL = 0.25;
const highp float PIXEL_SIGMA = 0.45;
const highp float TAP_STEP_SHARE = 1.0;
const highp float EDGE_SIGMA_SHARE = 0.4;
const highp float EDGE_REACH_SIGMAS = 3.0;
const mediump float GAUSSIAN_CDF_LIMIT = 4.0;
const int TAP_COUNT = 5;
const mediump float TAP_WEIGHT_CENTER = 0.4265;
const mediump float TAP_WEIGHT_NEAR = 0.2423;
const mediump float TAP_WEIGHT_FAR = 0.0444;
const highp vec2 GLYPH_CACHE_SIZE = vec2(1024.0, 512.0);

highp float text_face_spread(highp vec4 sdf_params)
{
    return SDF_DIAGONAL_SPREAD * (1.0 - sdf_params.x) / (1.0 - 2.0 * sdf_params.x + sdf_params.y);
}

highp float text_world_scale(highp vec4 sdf_params)
{
    return SDF_SMOOTHING_PIXEL / (text_face_spread(sdf_params) * sdf_params.z);
}

highp float text_front_shadow_layer(mediump vec3 layer_mask)
{
    return layer_mask.y * (1.0 - layer_mask.x);
}

highp vec4 text_layer_shadow(mediump vec3 layer_mask, highp vec4 back_shadow, highp vec4 front_shadow)
{
    return mix(back_shadow, front_shadow, text_front_shadow_layer(layer_mask));
}

mediump vec4 text_layer_shadow_color(mediump vec3 layer_mask, mediump vec4 back_color, mediump vec4 front_color)
{
    mediump vec4 color = mix(back_color, front_color, text_front_shadow_layer(layer_mask));
    return vec4(color.xyz * color.w, color.w);
}

highp vec4 text_shadow_position(highp vec4 position, mediump vec3 layer_mask, highp float world_scale, highp vec2 offset)
{
    highp float shadow_layer = max(layer_mask.y, layer_mask.z) * (1.0 - layer_mask.x);
    return vec4(position.xy + offset * world_scale * shadow_layer, position.z, 1.0);
}

highp vec3 text_shadow_blur(highp vec4 sdf_params, highp float world_scale, highp float sigma)
{
    highp float spread = text_face_spread(sdf_params);
    highp float pixel_sigma = PIXEL_SIGMA / world_scale;
    highp float edge_sigma = sqrt(EDGE_SIGMA_SHARE * EDGE_SIGMA_SHARE * sigma * sigma + pixel_sigma * pixel_sigma);
    highp float tap_step = TAP_STEP_SHARE * sigma;
    highp float reach = 0.5 * float(TAP_COUNT - 1) * tap_step + EDGE_REACH_SIGMAS * edge_sigma;
    highp float cutoff = sdf_params.x - (1.0 - sdf_params.x) * reach / spread;
    return vec3(tap_step, spread / ((1.0 - sdf_params.x) * edge_sigma), cutoff);
}

mediump float gaussian_cdf(mediump float x)
{
    mediump float t = min(abs(x), GAUSSIAN_CDF_LIMIT) * 0.7071068;
    mediump float p = 1.0 + t * (0.278393 + t * (0.230389 + t * (0.000972 + t * 0.078108)));
    p *= p;
    return 0.5 + sign(x) * (0.5 - 0.5 / (p * p));
}

mediump float text_face_alpha(mediump float distance, mediump vec4 sdf_params)
{
    return smoothstep(sdf_params.x - sdf_params.z, sdf_params.x + sdf_params.z, distance);
}

mediump float tap_weight(int index)
{
    mediump float distance = abs(float(index - TAP_COUNT / 2));
    return distance < 0.5 ? TAP_WEIGHT_CENTER : (distance < 1.5 ? TAP_WEIGHT_NEAR : TAP_WEIGHT_FAR);
}

mediump float text_shadow_alpha(mediump sampler2D glyphs, highp vec2 uv, mediump float distance, mediump vec4 sdf_params, highp vec3 blur)
{
    if (distance < blur.z)
    {
        return 0.0;
    }
    highp vec2 tap_step = blur.x / GLYPH_CACHE_SIZE;
    highp vec2 origin = uv - 0.5 * float(TAP_COUNT - 1) * tap_step;
    mediump float alpha = 0.0;
    for (int x = 0; x < TAP_COUNT; x++)
    {
        for (int y = 0; y < TAP_COUNT; y++)
        {
            mediump float tap_distance = texture(glyphs, origin + vec2(float(x), float(y)) * tap_step).x;
            alpha += tap_weight(x) * tap_weight(y) * gaussian_cdf((tap_distance - sdf_params.x) * blur.y);
        }
    }
    return alpha;
}

mediump float text_shadow_layer(mediump vec4 layer_mask)
{
    return max(layer_mask.y, layer_mask.z);
}

mediump vec4 text_layers_color(mediump vec4 face, mediump vec4 shadow, mediump vec4 layer_mask, mediump float face_alpha)
{
    return face * layer_mask.x + shadow * text_shadow_layer(layer_mask) * (1.0 - face_alpha * layer_mask.a);
}
