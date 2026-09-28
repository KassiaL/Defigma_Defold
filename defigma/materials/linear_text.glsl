highp vec2 linear_text_gradient_position(highp vec4 position, highp mat4 gradient_to_local, highp vec4 gradient_bounds)
{
    highp vec2 local_pos = (gradient_to_local * position).xy;
    highp vec2 normalized_pos = (local_pos - gradient_bounds.xy) / gradient_bounds.zw;
    return vec2(normalized_pos.x, 1.0 - normalized_pos.y);
}

mediump vec4 linear_text_face_color(highp vec2 gradient_pos, mediump vec4 grad_data, mediump vec4 gradient_stop0, mediump vec4 gradient_stop1, mediump float face_alpha)
{
    mediump vec2 start = grad_data.xy;
    mediump vec2 end = grad_data.zw;

    mediump vec2 dir_vec = end - start;
    mediump float length_dir = length(dir_vec);

    mediump vec4 gradient_color;
    if (length_dir < 0.0001) {
        gradient_color = gradient_stop0;
    } else {
        mediump vec2 dir = normalize(dir_vec);
        mediump vec2 rel = gradient_pos - start;
        mediump float t = dot(rel, dir);
        mediump float t_normalized = clamp(t / length_dir, 0.0, 1.0);
        gradient_color = mix(gradient_stop0, gradient_stop1, t_normalized);
    }

    return vec4(gradient_color.rgb * gradient_color.a, gradient_color.a) * face_alpha;
}
