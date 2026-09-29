#version 140

in mediump vec2 var_uv;
in mediump vec4 var_color;
in mediump vec4 var_params;

out mediump vec4 out_fragColor;

uniform lowp sampler2D texture_sampler;

const mediump float SQRT_HALF = 0.70710678;
const mediump float INV_SQRT_TWO_PI = 0.39894228;
const int BLUR_SAMPLES = 4;

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

mediump vec2 erf2(mediump vec2 x)
{
    mediump vec2 s = sign(x);
    mediump vec2 a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    x *= x;
    return s - s / (x * x);
}

mediump float gaussian(mediump float x)
{
    return exp(-0.5 * x * x) * INV_SQRT_TWO_PI;
}

mediump float band(mediump float x, mediump float extent)
{
    mediump vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-extent, extent)) * SQRT_HALF);
    return integral.y - integral.x;
}

mediump float rrect_blur(mediump vec2 q, mediump float radius, mediump vec2 inner)
{
    if (q.x < -3.5 && q.y < -3.5)
    {
        return 1.0;
    }
    mediump vec2 p = max(q + inner, 0.0);
    mediump float half_y = inner.y + radius;
    mediump float low = p.y - half_y;
    mediump float high = p.y + half_y;
    mediump float start = clamp(-3.0, low, high);
    mediump float end = clamp(3.0, low, high);
    mediump float step_size = (end - start) / float(BLUR_SAMPLES);
    mediump float y = start + step_size * 0.5;
    mediump float value = 0.0;
    for (int i = 0; i < BLUR_SAMPLES; i++)
    {
        mediump float sample_y = abs(p.y - y);
        mediump float delta = min(inner.y - sample_y, 0.0);
        mediump float curved = inner.x + sqrt(max(0.0, radius * radius - delta * delta));
        value += band(p.x, curved) * gaussian(y) * step_size;
        y += step_size;
    }
    return value;
}

mediump float ellipse_blur(mediump vec2 uv, mediump vec2 half_size)
{
    mediump vec2 p = abs(uv);
    mediump float low = p.y - half_size.y;
    mediump float high = p.y + half_size.y;
    mediump float start = clamp(-3.0, low, high);
    mediump float end = clamp(3.0, low, high);
    mediump float step_size = (end - start) / float(BLUR_SAMPLES);
    mediump float y = start + step_size * 0.5;
    mediump float value = 0.0;
    for (int i = 0; i < BLUR_SAMPLES; i++)
    {
        mediump float sample_y = (p.y - y) / half_size.y;
        mediump float extent = half_size.x * sqrt(max(0.0, 1.0 - sample_y * sample_y));
        value += band(p.x, extent) * gaussian(y) * step_size;
        y += step_size;
    }
    return value;
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

mediump float arc_distance(mediump vec2 uv, mediump float kind, mediump float ratio, mediump float cap)
{
    mediump float half_width = 0.5 * (1.0 - ratio);
    mediump float radius = length(uv);
    mediump float distance = abs(radius - 1.0 + half_width) - half_width;
    if (kind > 1.5)
    {
        return distance;
    }
    mediump float rounding = cap * half_width;
    mediump float wedge = uv.y > 0.0 ? -uv.x : -radius;
    mediump vec2 q = vec2(distance, wedge) + rounding;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rounding;
}

mediump float fill_coverage(mediump float distance)
{
    return clamp(0.5 - distance / max(length(vec2(dFdx(distance), dFdy(distance))), 1e-6), 0.0, 1.0);
}

void main()
{
    mediump vec2 uv = var_uv;
    mediump float mode = var_params.x;
    mediump float alpha = 1.0;

    if (mode < 0.5)
    {
        if (var_params.y > 0.5)
        {
            alpha = fill_coverage(arc_distance(uv, var_params.y, var_params.z, var_params.w));
        }
        else if (uv.x > -500.0)
        {
            alpha = edge_coverage(uv.x, vec2(1.0, 0.0), dFdx(uv), dFdy(uv));
        }
    }
    else if (mode < 1.5)
    {
        mediump vec2 uv_dx = dFdx(uv);
        mediump vec2 uv_dy = dFdy(uv);
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
        alpha = edge_coverage(radius - 1.0, uv / radius, dFdx(uv), dFdy(uv));
    }
    else if (mode < 3.5)
    {
        alpha = rrect_blur(uv, var_params.y, var_params.zw);
    }
    else if (mode < 4.5)
    {
        alpha = ellipse_blur(uv, var_params.yz);
    }
    else
    {
        alpha = ellipse_stroke(uv, var_params.yz, var_params.w, mode - 5.0, dFdx(uv), dFdy(uv));
    }

    mediump float coverage = clamp(alpha, 0.0, 1.0) * var_color.a * texture(texture_sampler, vec2(0.5)).a;
    out_fragColor = vec4(var_color.rgb * coverage, coverage);
}
