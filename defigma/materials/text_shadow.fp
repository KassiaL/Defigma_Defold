#version 140

#include "/defigma/materials/text_shadow.glsl"

in mediump vec2 var_texcoord0;
in mediump vec4 var_face_color;
in mediump vec4 var_shadow_color;
in mediump vec4 var_sdf_params;
in mediump vec4 var_layer_mask;
in highp vec3 var_shadow_blur;

out vec4 out_fragColor;

uniform mediump sampler2D texture_sampler;

void main()
{
    mediump float distance = texture(texture_sampler, var_texcoord0).x;
    mediump float face_alpha = text_face_alpha(distance, var_sdf_params);
    mediump float shadow_alpha = 0.0;
    if (text_shadow_layer(var_layer_mask) > 0.5)
    {
        shadow_alpha = text_shadow_alpha(texture_sampler, var_texcoord0, distance, var_sdf_params, var_shadow_blur);
    }
    out_fragColor = text_layers_color(face_alpha * var_face_color, shadow_alpha * var_shadow_color, var_layer_mask, face_alpha);
}
