#version 140

in mediump vec2 var_texcoord0;
in mediump vec4 var_color;
in mediump vec2 v_normalizedPos;

out mediump vec4 out_fragColor;
uniform lowp sampler2D texture_sampler;

uniform uniforms {
    mediump vec4 shadow_data;
};

void main()
{
    mediump float maskA = texture(texture_sampler, var_texcoord0).a;
    out_fragColor = var_color * maskA;
}
