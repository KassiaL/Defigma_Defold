#version 140

in mediump vec2 var_uv;
in mediump vec4 var_color;
in mediump vec4 var_params;

out mediump vec4 out_fragColor;

uniform lowp sampler2D texture_sampler;


mediump float edge_coverage(mediump float distance, mediump vec2 gradient, mediump vec2 uv_dx, mediump vec2 uv_dy)
{
    mediump float aa = length(vec2(dot(gradient, uv_dx), dot(gradient, uv_dy)));
    return clamp(0.5 - distance / max(aa, 1e-6), 0.0, 1.0);
}

mediump float rrect_distance(mediump vec2 q, mediump float radius)
{
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

mediump vec2 rrect_gradient(mediump vec2 q)
{
    if (q.x > 0.0 && q.y > 0.0)
    {
        return normalize(q);
    }
    return q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
}

mediump float ellipse_stroke(mediump vec2 uv, mediump vec2 axes, mediump float width, mediump float align, mediump vec2 uv_dx, mediump vec2 uv_dy)
{
    mediump vec2 scaled = uv / axes;
    mediump float radius = max(length(scaled), 1e-6);
    mediump vec2 gradient = scaled / (axes * radius);
    mediump float gradient_length = max(length(gradient), 1e-6);
    mediump float distance = (radius - 1.0) / gradient_length;
    mediump vec2 direction = gradient / gradient_length;
    mediump float aa = max(length(vec2(dot(direction, uv_dx), dot(direction, uv_dy))), 1e-6);
    mediump float outer_edge = width * align * 0.5;
    mediump float inner_edge = outer_edge - width;
    mediump float outer = clamp(0.5 - (distance - outer_edge) / aa, 0.0, 1.0);
    mediump float inner = clamp(0.5 - (distance - inner_edge) / aa, 0.0, 1.0);
    return outer - inner;
}

void main()
{
    mediump vec2 uv = var_uv;
    mediump vec2 uv_dx = dFdx(uv);
    mediump vec2 uv_dy = dFdy(uv);
    mediump float mode = var_params.x;
    mediump float alpha = 1.0;

    if (mode < 0.5)
    {
        alpha = edge_coverage(uv.x, vec2(1.0, 0.0), uv_dx, uv_dy);
    }
    else if (mode < 1.5)
    {
        mediump float distance = rrect_distance(uv, var_params.y);
        mediump vec2 gradient = rrect_gradient(uv);
        alpha = edge_coverage(distance, gradient, uv_dx, uv_dy);
        if (var_params.z > 0.0)
        {
            alpha -= edge_coverage(distance + var_params.z, gradient, uv_dx, uv_dy);
        }
    }
    else if (mode < 2.5)
    {
        mediump float radius = max(length(uv), 1e-6);
        alpha = edge_coverage(radius - 1.0, uv / radius, uv_dx, uv_dy);
    }
    else
    {
        alpha = ellipse_stroke(uv, var_params.yz, var_params.w, mode - 5.0, uv_dx, uv_dy);
    }

    mediump float coverage = clamp(alpha, 0.0, 1.0) * var_color.a * texture(texture_sampler, vec2(0.5)).a;
    out_fragColor = vec4(var_color.rgb * coverage, coverage);
}
