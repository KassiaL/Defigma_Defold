#version 140

#include "/defigma/materials/linear_text.glsl"
#include "/defigma/materials/text_shadow.glsl"

in mediump vec2 var_texcoord0;
in mediump vec4 var_face_color;
in mediump vec4 var_shadow_color;
in mediump vec4 var_sdf_params;
in mediump vec4 var_layer_mask;
in highp vec2 var_gradient_pos;
in highp vec3 var_shadow_blur;

out vec4 out_fragColor;

uniform mediump sampler2D texture_sampler;

uniform uniforms {
    mediump vec4 grad_data;
    mediump vec4 gradient_stop0;
    mediump vec4 gradient_stop1;
};

void main()
{
    mediump float distance = texture(texture_sampler, var_texcoord0).x;
    mediump float face_alpha = text_face_alpha(distance, var_sdf_params);
    mediump float shadow_alpha = 0.0;
    if (text_shadow_layer(var_layer_mask) > 0.5)
    {
        shadow_alpha = text_shadow_alpha(texture_sampler, var_texcoord0, distance, var_sdf_params, var_shadow_blur);
    }
    mediump vec4 face_color = linear_text_face_color(var_gradient_pos, grad_data, gradient_stop0, gradient_stop1, var_face_color.a);
    out_fragColor = text_layers_color(face_alpha * face_color, shadow_alpha * var_shadow_color, var_layer_mask, face_alpha);
}
