#version 140
in  mediump vec2 var_texcoord0;
in  mediump vec4 var_color;

in  mediump vec2 v_normalizedPos;

out mediump vec4 out_fragColor;
uniform lowp sampler2D texture_sampler;

uniform uniforms {
	uniform mediump vec4 grad_data;
    uniform mediump vec4 gradient_stop0;
    uniform mediump vec4 gradient_stop1;
};

void main()
{
	mediump vec2 start = grad_data.xy;
    mediump vec2 end = grad_data.zw;
    
    mediump vec2 dir_vec = end - start;
    mediump float length_dir = length(dir_vec);
    
    mediump vec4 color;
    if (length_dir < 0.0001) {
        color = gradient_stop0;
    } else {
        mediump vec2 dir = normalize(dir_vec);
        mediump vec2 rel = v_normalizedPos - start;
        
        mediump float t = dot(rel, dir);
        
        mediump float t_normalized = clamp(t / length_dir, 0.0, 1.0);
        
        color = mix(gradient_stop0, gradient_stop1, t_normalized);
    }
    
    color.xyz *= color.w;
    
    mediump float maskA = texture(texture_sampler, var_texcoord0).a;
    out_fragColor = color * var_color * maskA;
}