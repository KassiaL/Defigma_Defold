#version 140

in mediump vec2 var_texcoord0;
in mediump vec4 var_face_color;
in mediump vec4 var_outline_color;
in mediump vec4 var_shadow_color;
in mediump vec4 var_sdf_params;
in mediump vec4 var_layer_mask;

out vec4 out_fragColor;

uniform mediump sampler2D texture_sampler;

uniform fs_uniforms {
    mediump vec4 texture_size_recip;
};

uniform uniforms {
    mediump vec4 grad_data;
    mediump vec4 gradient_stop0;
    mediump vec4 gradient_stop1;
};

void main()
{
    mediump vec4 df_sample = texture(texture_sampler, var_texcoord0);

    mediump float distance        = df_sample.x;
    mediump float distance_shadow = df_sample.z;

    mediump float sdf_edge      = var_sdf_params.x;
    mediump float sdf_outline   = var_sdf_params.y;
    mediump float sdf_smoothing = var_sdf_params.z;
    mediump float sdf_shadow    = var_sdf_params.w;

    mediump float sdf_shadow_as_outline = floor(sdf_shadow);
    mediump float sdf_is_single_layer   = var_layer_mask.a;

    mediump float face_alpha    = smoothstep(sdf_edge - sdf_smoothing, sdf_edge + sdf_smoothing, distance);
    mediump float outline_alpha = smoothstep(sdf_outline - sdf_smoothing, sdf_outline + sdf_smoothing, distance);
    mediump float shadow_alpha  = smoothstep(sdf_shadow - sdf_smoothing, sdf_edge + sdf_smoothing, distance_shadow);

    shadow_alpha = mix(shadow_alpha, outline_alpha, sdf_shadow_as_outline);

    mediump vec2 normalized_pos = vec2(
        fract(var_texcoord0.x / texture_size_recip.z),
        fract(var_texcoord0.y / texture_size_recip.w)
    );

    mediump vec2 start = vec2(grad_data.x, grad_data.y);
    mediump vec2 end = vec2(grad_data.z, grad_data.w);

    mediump vec2 dir_vec = end - start;
    mediump float length_dir = length(dir_vec);

    mediump vec4 gradient_color;
    if (length_dir < 0.0001) {
        gradient_color = gradient_stop0;
    } else {
        mediump vec2 dir = normalize(dir_vec);
        mediump vec2 rel = normalized_pos - start;
        mediump float t = dot(rel, dir);
        mediump float t_normalized = clamp(t / length_dir, 0.0, 1.0);
        gradient_color = mix(gradient_stop0, gradient_stop1, t_normalized);
    }

    mediump vec4 face_color_grad = vec4(gradient_color.rgb * gradient_color.a, gradient_color.a);

    out_fragColor = face_alpha * face_color_grad * var_layer_mask.x +
        outline_alpha * var_outline_color * var_layer_mask.y * (1.0 - face_alpha * sdf_is_single_layer) +
        shadow_alpha * var_shadow_color * var_layer_mask.z * (1.0 - min(1.0, outline_alpha + face_alpha) * sdf_is_single_layer);
}
