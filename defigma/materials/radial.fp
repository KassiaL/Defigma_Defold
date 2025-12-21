#version 140
in  mediump vec2 var_texcoord0;
in  mediump vec4 var_color;

in  mediump vec2 v_normalizedPos;

out mediump vec4 out_fragColor;
uniform lowp sampler2D texture_sampler;

uniform uniforms {
	uniform mediump vec4 grad_data;
	uniform mediump vec4 grad_data2;
    uniform mediump vec4 gradient_stop0;
    uniform mediump vec4 gradient_stop1;
};

void main()
{
    mediump vec2 pos = v_normalizedPos;

	mediump vec2 center = grad_data.xy;
	mediump vec2 radius = grad_data.zw;
	mediump float rotation = grad_data2.x;

	mediump vec2 p = pos - center;

	mediump float cos_r = cos(rotation);
    mediump float sin_r = sin(rotation);
    mediump vec2 p_rot = vec2(
        p.x * cos_r - p.y * sin_r,
        p.x * sin_r + p.y * cos_r
    );
	
	mediump vec2 p_scaled = p_rot / radius;
    
    mediump float t = length(p_scaled);
    t = clamp(t, 0.0, 1.0);
    
    mediump vec4 color = mix(gradient_stop0, gradient_stop1, t);
    color.xyz *= color.w;
    
    mediump float maskA = texture(texture_sampler, var_texcoord0).a;
    out_fragColor = color * var_color * maskA;
}