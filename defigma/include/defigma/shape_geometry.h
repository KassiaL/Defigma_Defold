#pragma once

#include <stdint.h>
#include <vector>

namespace defigma
{
    struct Color
    {
        float r, g, b, a;
    };

    struct GradientStop
    {
        float position;
        Color color;
    };

    enum PaintType
    {
        PAINT_SOLID  = 0,
        PAINT_LINEAR = 1,
        PAINT_RADIAL = 2,
    };

    struct Paint
    {
        PaintType                 type;
        Color                     color;
        float                     transform[6];
        std::vector<GradientStop> stops;
    };

    enum ShapeKind
    {
        SHAPE_RECT    = 0,
        SHAPE_ELLIPSE = 1,
        SHAPE_PATH    = 2,
    };

    struct PathGeometry
    {
        std::vector<std::vector<float> > polygons;
        std::vector<float>               edges;
    };

    enum StrokeAlign
    {
        STROKE_INSIDE  = 0,
        STROKE_CENTER  = 1,
        STROKE_OUTSIDE = 2,
    };

    struct DropShadow
    {
        float offset_x;
        float offset_y;
        float radius;
        float spread;
        Color color;
        bool  show_behind;
    };

    struct ShapeDesc
    {
        ShapeKind               kind;
        float                   corner_radius[4];
        std::vector<Paint>      fills;
        std::vector<Paint>      strokes;
        float                   stroke_width;
        StrokeAlign             stroke_align;
        std::vector<DropShadow> shadows;
        float                   layer_blur;
        PathGeometry            fill_path;
        PathGeometry            stroke_path;
        std::vector<float>      clip;
    };

    struct ShapeVertex
    {
        float position[3];
        float uv[2];
        float color[4];
        float page_index;
    };

    void ResetShapeDesc(ShapeDesc& desc);
    bool ParsePaints(const char* json, std::vector<Paint>& out);
    bool ParseEffects(const char* json, ShapeDesc& desc);
    bool ParsePath(const char* json, ShapeDesc& desc);
    bool ParseClip(const char* json, ShapeDesc& desc);
    ShapeKind ParseShapeKind(const char* name);
    StrokeAlign ParseStrokeAlign(const char* name);

    void BuildShapeVertices(const ShapeDesc& desc, float width, float height, std::vector<ShapeVertex>& out);
}
