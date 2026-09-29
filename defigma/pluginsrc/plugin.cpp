#include <string.h>
#include <vector>

#include <dmsdk/sdk.h>
#include <defigma/shape_geometry.h>

static thread_local std::vector<defigma::ShapeVertex> g_Vertices;

extern "C" DM_DLLEXPORT int DefigmaShape_Build(const char* shape, float radius_tl, float radius_tr, float radius_br, float radius_bl,
                                               const char* fills, const char* strokes, float stroke_width, const char* stroke_align,
                                               const char* effects, const char* path, const char* clip, float arc_start, float arc_sweep,
                                               float arc_ratio, float width, float height)
{
    defigma::ShapeDesc desc;
    defigma::ResetShapeDesc(desc);
    desc.kind = defigma::ParseShapeKind(shape);
    desc.corner_radius[0] = radius_tl;
    desc.corner_radius[1] = radius_tr;
    desc.corner_radius[2] = radius_br;
    desc.corner_radius[3] = radius_bl;
    desc.stroke_width = stroke_width;
    desc.stroke_align = defigma::ParseStrokeAlign(stroke_align);
    desc.arc_start = arc_start;
    desc.arc_sweep = arc_sweep;
    desc.arc_ratio = arc_ratio;
    if (!defigma::ParsePaints(fills, desc.fills) || !defigma::ParsePaints(strokes, desc.strokes) ||
        !defigma::ParseEffects(effects, desc) || !defigma::ParsePath(path, desc) || !defigma::ParseClip(clip, desc))
    {
        g_Vertices.clear();
        return -1;
    }
    defigma::BuildShapeVertices(desc, width, height, g_Vertices);
    return (int)g_Vertices.size();
}

extern "C" DM_DLLEXPORT void DefigmaShape_CopyVertices(float* out)
{
    if (!g_Vertices.empty())
        memcpy(out, &g_Vertices[0], g_Vertices.size() * sizeof(defigma::ShapeVertex));
}
