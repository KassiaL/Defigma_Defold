#version 140

in highp vec2 var_uv;
in highp vec4 var_color;
in highp vec4 var_params;

out highp vec4 out_fragColor;

uniform lowp sampler2D texture_sampler;

const highp float SQRT_HALF = 0.70710678;
const highp float INV_SQRT_TWO_PI = 0.39894228;
const int BLUR_SAMPLES = 4;

highp float edge_coverage(highp float distance, highp vec2 gradient, highp vec2 uv_dx, highp vec2 uv_dy)
{
    highp float aa = length(vec2(dot(gradient, uv_dx), dot(gradient, uv_dy)));
    return clamp(0.5 - distance / max(aa, 1e-6), 0.0, 1.0);
}

highp float rrect_distance(highp vec2 q, highp float radius)
{
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

highp vec2 rrect_gradient(highp vec2 q)
{
    if (q.x > 0.0 && q.y > 0.0)
    {
        return normalize(q);
    }
    return q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
}

highp vec2 erf2(highp vec2 x)
{
    highp vec2 s = sign(x);
    highp vec2 a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    x *= x;
    return s - s / (x * x);
}

highp float gaussian(highp float x)
{
    return exp(-0.5 * x * x) * INV_SQRT_TWO_PI;
}

highp float band(highp float x, highp float extent)
{
    highp vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-extent, extent)) * SQRT_HALF);
    return integral.y - integral.x;
}

highp float rrect_blur(highp vec2 q, highp float radius, highp vec2 inner)
{
    if (q.x < -3.5 && q.y < -3.5)
    {
        return 1.0;
    }
    highp vec2 p = max(q + inner, 0.0);
    highp float half_y = inner.y + radius;
    highp float low = p.y - half_y;
    highp float high = p.y + half_y;
    highp float start = clamp(-3.0, low, high);
    highp float end = clamp(3.0, low, high);
    highp float step_size = (end - start) / float(BLUR_SAMPLES);
    highp float y = start + step_size * 0.5;
    highp float value = 0.0;
    for (int i = 0; i < BLUR_SAMPLES; i++)
    {
        highp float sample_y = abs(p.y - y);
        highp float delta = min(inner.y - sample_y, 0.0);
        highp float curved = inner.x + sqrt(max(0.0, radius * radius - delta * delta));
        value += band(p.x, curved) * gaussian(y) * step_size;
        y += step_size;
    }
    return value;
}

highp float ellipse_blur(highp vec2 uv, highp vec2 half_size)
{
    highp vec2 p = abs(uv);
    highp float low = p.y - half_size.y;
    highp float high = p.y + half_size.y;
    highp float start = clamp(-3.0, low, high);
    highp float end = clamp(3.0, low, high);
    highp float step_size = (end - start) / float(BLUR_SAMPLES);
    highp float y = start + step_size * 0.5;
    highp float value = 0.0;
    for (int i = 0; i < BLUR_SAMPLES; i++)
    {
        highp float sample_y = (p.y - y) / half_size.y;
        highp float extent = half_size.x * sqrt(max(0.0, 1.0 - sample_y * sample_y));
        value += band(p.x, extent) * gaussian(y) * step_size;
        y += step_size;
    }
    return value;
}

highp float ellipse_stroke(highp vec2 uv, highp vec2 axes, highp float width, highp float align, highp vec2 uv_dx, highp vec2 uv_dy)
{
    highp vec2 scaled = uv / axes;
    highp float radius = max(length(scaled), 1e-6);
    highp vec2 gradient = scaled / (axes * radius);
    highp float gradient_length = max(length(gradient), 1e-6);
    highp float distance = (radius - 1.0) / gradient_length;
    highp vec2 direction = gradient / gradient_length;
    highp float aa = max(length(vec2(dot(direction, uv_dx), dot(direction, uv_dy))), 1e-6);
    highp float outer_edge = width * align * 0.5;
    highp float inner_edge = outer_edge - width;
    highp float outer = clamp(0.5 - (distance - outer_edge) / aa, 0.0, 1.0);
    highp float inner = clamp(0.5 - (distance - inner_edge) / aa, 0.0, 1.0);
    return outer - inner;
}

highp float arc_distance(highp vec2 uv, highp float kind, highp float ratio, highp float cap)
{
    highp float half_width = 0.5 * (1.0 - ratio);
    highp float radius = length(uv);
    highp float distance = abs(radius - 1.0 + half_width) - half_width;
    if (kind > 1.5)
    {
        return distance;
    }
    highp float rounding = cap * half_width;
    highp float wedge = uv.y > 0.0 ? -uv.x : -radius;
    highp vec2 q = vec2(distance, wedge) + rounding;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rounding;
}

highp float fill_coverage(highp float distance)
{
    return clamp(0.5 - distance / max(length(vec2(dFdx(distance), dFdy(distance))), 1e-6), 0.0, 1.0);
}

void main()
{
    highp vec2 uv = var_uv;
    highp float mode = var_params.x;
    highp float alpha = 1.0;

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
        highp vec2 uv_dx = dFdx(uv);
        highp vec2 uv_dy = dFdy(uv);
        highp float distance = rrect_distance(uv, var_params.y);
        highp vec2 gradient = rrect_gradient(uv);
        alpha = edge_coverage(distance, gradient, uv_dx, uv_dy);
        if (var_params.z > 0.0)
        {
            alpha -= edge_coverage(distance + var_params.z, gradient, uv_dx, uv_dy);
        }
    }
    else if (mode < 2.5)
    {
        highp float radius = max(length(uv), 1e-6);
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

    highp float coverage = clamp(alpha, 0.0, 1.0) * var_color.a * texture(texture_sampler, vec2(0.5)).a;
    out_fragColor = vec4(var_color.rgb * coverage, coverage);
}
