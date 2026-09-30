#include <defigma/shape_geometry.h>

#include <algorithm>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <string>

namespace defigma
{
    static const double PI              = 3.14159265358979323846;
    static const int   MAX_POLY_POINTS  = 96;
    static const float AA_MARGIN        = 2.0f;
    static const float BLUR_EXTENT      = 3.0f;
    static const float SHADOW_SIGMA_PER_RADIUS = 0.43f;
    static const float BLUR_SIGMA_PER_RADIUS   = 0.43f;
    static const float OUTSIDE_STROKE_UNDERLAP = 0.5f;
    static const float MIN_SIGMA        = 0.3f;
    static const int   RADIAL_SECTORS   = 32;
    static const int   MIN_RADIAL_SECTORS = 12;
    static const float RADIAL_SECTOR_PIXELS = 12.0f;
    static const int   CORNER_SEGMENTS  = 8;
    static const int   HOLE_CORNER_SEGMENTS = 2;
    static const int   HOLE_SECTORS     = 12;
    static const float MIN_HOLE_AREA    = 1024.0f;
    static const float ARC_SEGMENT      = (float)(PI / 6.0);
    static const float SQRT_HALF        = 0.70710678f;
    static const float KNOCKOUT_INSET   = 1.0f;
    static const int   MAX_JSON_DEPTH   = 16;
    static const size_t MAX_GRADIENT_STOPS = 64;

    enum Mode
    {
        MODE_EDGE         = 0,
        MODE_RRECT        = 1,
        MODE_ELLIPSE      = 2,
        MODE_RRECT_BLUR   = 3,
        MODE_ELLIPSE_BLUR = 4,
        MODE_ELLIPSE_STROKE_INSIDE  = 5,
        MODE_ELLIPSE_STROKE_CENTER  = 6,
        MODE_ELLIPSE_STROKE_OUTSIDE = 7,
    };

    enum Quadrant
    {
        QUADRANT_TOP_LEFT     = 0,
        QUADRANT_TOP_RIGHT    = 1,
        QUADRANT_BOTTOM_RIGHT = 2,
        QUADRANT_BOTTOM_LEFT  = 3,
    };

    struct Vec2
    {
        float x, y;
    };

    struct Poly
    {
        int  count;
        Vec2 points[MAX_POLY_POINTS];
    };

    struct Line
    {
        float a, b, c;
    };

    struct ArcWarp
    {
        float center_x;
        float center_y;
        float half_x;
        float half_y;
        float scale;
        float middle;
        float half_sweep;
        bool  full;
        float center_radius;
        float half_width;
        float corner;
        float grow;
        float shift_x;
        float shift_y;
        float uv_scale;
    };

    struct Primitive
    {
        bool  warped = false;
        ArcWarp warp;
        bool  folded;
        float center_x;
        float center_y;
        float uv_scale_x;
        float uv_scale_y;
        float inner_x[4];
        float inner_y[4];
        Line  uv_x;
        Line  uv_y;
        float page[4];
    };

    struct Builder
    {
        std::vector<ShapeVertex>* out;
        float                     width;
        float                     height;
        bool                      clipped;
        Poly                      clip;
    };

    // ---------------------------------------------------------------- JSON

    struct JsonValue
    {
        enum Type { NIL, NUMBER, BOOLEAN, STRING, ARRAY, OBJECT };
        Type                   type;
        double                 number;
        bool                   boolean;
        std::string            string;
        std::vector<JsonValue> items;
        std::vector<std::string> keys;

        JsonValue() : type(NIL), number(0.0), boolean(false) {}

        const JsonValue* Get(const char* key) const
        {
            for (size_t i = 0; i < keys.size(); ++i)
            {
                if (keys[i] == key)
                    return &items[i];
            }
            return 0;
        }

        float Number(const char* key, float fallback) const
        {
            const JsonValue* value = Get(key);
            return value && value->type == NUMBER ? (float)value->number : fallback;
        }
    };

    struct JsonReader
    {
        const char* cursor;
        int         depth;

        void SkipSpace()
        {
            while (*cursor == ' ' || *cursor == '\n' || *cursor == '\r' || *cursor == '\t')
                ++cursor;
        }

        bool Expect(char c)
        {
            SkipSpace();
            if (*cursor != c)
                return false;
            ++cursor;
            return true;
        }

        bool ReadString(std::string& out)
        {
            if (!Expect('"'))
                return false;
            while (*cursor && *cursor != '"')
            {
                if (*cursor == '\\' && cursor[1])
                    ++cursor;
                out.push_back(*cursor);
                ++cursor;
            }
            return Expect('"');
        }

        bool ReadValue(JsonValue& value)
        {
            if (depth == MAX_JSON_DEPTH)
                return false;
            ++depth;
            bool read = ReadAny(value);
            --depth;
            return read;
        }

        bool ReadAny(JsonValue& value)
        {
            SkipSpace();
            char c = *cursor;
            if (c == '{')
            {
                ++cursor;
                value.type = JsonValue::OBJECT;
                SkipSpace();
                if (*cursor == '}')
                {
                    ++cursor;
                    return true;
                }
                for (;;)
                {
                    std::string key;
                    if (!ReadString(key) || !Expect(':'))
                        return false;
                    value.keys.push_back(key);
                    value.items.push_back(JsonValue());
                    if (!ReadValue(value.items.back()))
                        return false;
                    SkipSpace();
                    if (*cursor == ',')
                    {
                        ++cursor;
                        continue;
                    }
                    return Expect('}');
                }
            }
            if (c == '[')
            {
                ++cursor;
                value.type = JsonValue::ARRAY;
                SkipSpace();
                if (*cursor == ']')
                {
                    ++cursor;
                    return true;
                }
                for (;;)
                {
                    value.items.push_back(JsonValue());
                    if (!ReadValue(value.items.back()))
                        return false;
                    SkipSpace();
                    if (*cursor == ',')
                    {
                        ++cursor;
                        continue;
                    }
                    return Expect(']');
                }
            }
            if (c == '"')
            {
                value.type = JsonValue::STRING;
                return ReadString(value.string);
            }
            if (strncmp(cursor, "true", 4) == 0)
            {
                value.type = JsonValue::BOOLEAN;
                value.boolean = true;
                cursor += 4;
                return true;
            }
            if (strncmp(cursor, "false", 5) == 0)
            {
                value.type = JsonValue::BOOLEAN;
                cursor += 5;
                return true;
            }
            if (strncmp(cursor, "null", 4) == 0)
            {
                cursor += 4;
                return true;
            }
            char* end = 0;
            value.number = strtod(cursor, &end);
            if (end == cursor || !(fabs(value.number) <= FLT_MAX))
                return false;
            value.type = JsonValue::NUMBER;
            cursor = end;
            return true;
        }
    };

    static bool ParseJson(const char* text, JsonValue& root)
    {
        JsonReader reader;
        reader.cursor = text;
        reader.depth = 0;
        return reader.ReadValue(root);
    }

    static bool ReadFloats(const JsonValue* value, float* out, size_t count)
    {
        if (!value || value->type != JsonValue::ARRAY || value->items.size() < count)
            return false;
        for (size_t i = 0; i < count; ++i)
            out[i] = (float)value->items[i].number;
        return true;
    }

    static bool ReadColor(const JsonValue* value, Color& color)
    {
        float channels[4];
        if (!ReadFloats(value, channels, 4))
            return false;
        color.r = channels[0];
        color.g = channels[1];
        color.b = channels[2];
        color.a = channels[3];
        return true;
    }

    static bool ReadPaint(const JsonValue& value, Paint& paint)
    {
        const JsonValue* type = value.Get("type");
        if (!type || type->type != JsonValue::STRING)
            return false;
        paint.color.r = paint.color.g = paint.color.b = paint.color.a = 1.0f;
        for (int i = 0; i < 6; ++i)
            paint.transform[i] = 0.0f;
        if (type->string == "solid")
        {
            paint.type = PAINT_SOLID;
            return ReadColor(value.Get("color"), paint.color);
        }
        if (type->string == "linear")
            paint.type = PAINT_LINEAR;
        else if (type->string == "radial")
            paint.type = PAINT_RADIAL;
        else
            return false;
        if (!ReadFloats(value.Get("transform"), paint.transform, 6))
            return false;
        const JsonValue* stops = value.Get("stops");
        if (!stops || stops->type != JsonValue::ARRAY || stops->items.size() > MAX_GRADIENT_STOPS)
            return false;
        for (size_t i = 0; i < stops->items.size(); ++i)
        {
            float stop[5];
            if (!ReadFloats(&stops->items[i], stop, 5))
                return false;
            GradientStop gradient_stop = { stop[0], { stop[1], stop[2], stop[3], stop[4] } };
            paint.stops.push_back(gradient_stop);
        }
        return !paint.stops.empty();
    }

    void ResetShapeDesc(ShapeDesc& desc)
    {
        desc.kind = SHAPE_RECT;
        for (int i = 0; i < 4; ++i)
            desc.corner_radius[i] = 0.0f;
        desc.fills.clear();
        desc.strokes.clear();
        desc.stroke_width = 0.0f;
        desc.stroke_align = STROKE_INSIDE;
        desc.shadows.clear();
        desc.layer_blur = 0.0f;
        desc.fill_path.polygons.clear();
        desc.fill_path.edges.clear();
        desc.stroke_path.polygons.clear();
        desc.stroke_path.edges.clear();
        desc.clip.clear();
        desc.arc_start = 0.0f;
        desc.arc_sweep = 100.0f;
        desc.arc_ratio = 0.0f;
    }

    static void ReadNumbers(const JsonValue* value, std::vector<float>& out)
    {
        out.clear();
        if (!value)
            return;
        out.reserve(value->items.size());
        for (size_t i = 0; i < value->items.size(); ++i)
            out.push_back((float)value->items[i].number);
    }

    static void ReadPathGeometry(const JsonValue* value, PathGeometry& geometry)
    {
        if (!value)
            return;
        const JsonValue* polygons = value->Get("polygons");
        geometry.polygons.clear();
        if (polygons)
        {
            geometry.polygons.resize(polygons->items.size());
            for (size_t i = 0; i < polygons->items.size(); ++i)
                ReadNumbers(&polygons->items[i], geometry.polygons[i]);
        }
        ReadNumbers(value->Get("edges"), geometry.edges);
    }

    bool ParsePath(const char* json, ShapeDesc& desc)
    {
        if (!json || !*json)
            return true;
        JsonValue root;
        if (!ParseJson(json, root) || root.type != JsonValue::OBJECT)
            return false;
        ReadPathGeometry(root.Get("fill"), desc.fill_path);
        ReadPathGeometry(root.Get("stroke"), desc.stroke_path);
        return true;
    }

    bool ParseClip(const char* json, ShapeDesc& desc)
    {
        desc.clip.clear();
        if (!json || !*json)
            return true;
        JsonValue root;
        if (!ParseJson(json, root) || root.type != JsonValue::ARRAY)
            return false;
        ReadNumbers(&root, desc.clip);
        return true;
    }

    bool ParsePaints(const char* json, std::vector<Paint>& out)
    {
        out.clear();
        if (!json || !*json)
            return true;
        JsonValue root;
        if (!ParseJson(json, root) || root.type != JsonValue::ARRAY)
            return false;
        for (size_t i = 0; i < root.items.size(); ++i)
        {
            Paint paint;
            if (!ReadPaint(root.items[i], paint))
                return false;
            out.push_back(paint);
        }
        return true;
    }

    bool ParseEffects(const char* json, ShapeDesc& desc)
    {
        desc.shadows.clear();
        desc.layer_blur = 0.0f;
        if (!json || !*json)
            return true;
        JsonValue root;
        if (!ParseJson(json, root) || root.type != JsonValue::ARRAY)
            return false;
        for (size_t i = 0; i < root.items.size(); ++i)
        {
            const JsonValue& effect = root.items[i];
            const JsonValue* type = effect.Get("type");
            if (!type || type->type != JsonValue::STRING)
                return false;
            if (type->string == "layer_blur")
            {
                desc.layer_blur = effect.Number("radius", 0.0f);
            }
            else if (type->string == "drop_shadow")
            {
                DropShadow shadow;
                float offset[2];
                if (!ReadFloats(effect.Get("offset"), offset, 2) || !ReadColor(effect.Get("color"), shadow.color))
                    return false;
                shadow.offset_x = offset[0];
                shadow.offset_y = offset[1];
                shadow.radius = effect.Number("radius", 0.0f);
                shadow.spread = effect.Number("spread", 0.0f);
                const JsonValue* behind = effect.Get("show_behind");
                shadow.show_behind = behind && behind->boolean;
                desc.shadows.push_back(shadow);
            }
            else
            {
                return false;
            }
        }
        return true;
    }

    ShapeKind ParseShapeKind(const char* name)
    {
        if (strcmp(name, "ellipse") == 0)
            return SHAPE_ELLIPSE;
        if (strcmp(name, "path") == 0)
            return SHAPE_PATH;
        return SHAPE_RECT;
    }

    StrokeAlign ParseStrokeAlign(const char* name)
    {
        if (strcmp(name, "center") == 0)
            return STROKE_CENTER;
        if (strcmp(name, "outside") == 0)
            return STROKE_OUTSIDE;
        return STROKE_INSIDE;
    }

    // ---------------------------------------------------------------- polygons

    static void MakeRect(float x0, float y0, float x1, float y1, Poly& poly)
    {
        poly.count = 4;
        poly.points[0].x = x0; poly.points[0].y = y0;
        poly.points[1].x = x1; poly.points[1].y = y0;
        poly.points[2].x = x1; poly.points[2].y = y1;
        poly.points[3].x = x0; poly.points[3].y = y1;
    }

    static float Evaluate(const Line& line, const Vec2& p)
    {
        return line.a * p.x + line.b * p.y + line.c;
    }

    static void ClipKeepNegative(const Poly& in, const Line& line, Poly& out)
    {
        out.count = 0;
        for (int i = 0; i < in.count; ++i)
        {
            const Vec2& current = in.points[i];
            const Vec2& next = in.points[(i + 1) % in.count];
            float dc = Evaluate(line, current);
            float dn = Evaluate(line, next);
            if (dc <= 0.0f && out.count < MAX_POLY_POINTS)
                out.points[out.count++] = current;
            if ((dc < 0.0f && dn > 0.0f) || (dc > 0.0f && dn < 0.0f))
            {
                float t = dc / (dc - dn);
                if (out.count < MAX_POLY_POINTS)
                {
                    out.points[out.count].x = current.x + (next.x - current.x) * t;
                    out.points[out.count].y = current.y + (next.y - current.y) * t;
                    ++out.count;
                }
            }
        }
    }

    static Line Negate(const Line& line)
    {
        Line negated = { -line.a, -line.b, -line.c };
        return negated;
    }

    static float Area(const Poly& poly)
    {
        float area = 0.0f;
        for (int i = 0; i < poly.count; ++i)
        {
            const Vec2& a = poly.points[i];
            const Vec2& b = poly.points[(i + 1) % poly.count];
            area += a.x * b.y - b.x * a.y;
        }
        return area * 0.5f;
    }

    static bool IsUsable(const Poly& poly)
    {
        return poly.count >= 3 && fabsf(Area(poly)) > 1e-5f;
    }

    static Vec2 Centroid(const Poly& poly)
    {
        Vec2 c = { 0.0f, 0.0f };
        for (int i = 0; i < poly.count; ++i)
        {
            c.x += poly.points[i].x;
            c.y += poly.points[i].y;
        }
        c.x /= (float)poly.count;
        c.y /= (float)poly.count;
        return c;
    }

    static Line EdgeLine(const Vec2& a, const Vec2& b, float orientation)
    {
        Line line = { (b.y - a.y) * orientation, (a.x - b.x) * orientation, 0.0f };
        line.c = -(line.a * a.x + line.b * a.y);
        return line;
    }

    static void IntersectConvex(const Poly& piece, const Poly& cell, Poly& out)
    {
        float orientation = Area(cell) >= 0.0f ? 1.0f : -1.0f;
        Poly a = piece;
        Poly b;
        for (int i = 0; i < cell.count && a.count > 0; ++i)
        {
            Line edge = EdgeLine(cell.points[i], cell.points[(i + 1) % cell.count], orientation);
            ClipKeepNegative(a, edge, b);
            a = b;
        }
        out = a;
    }

    static void SubtractConvex(const Poly& piece, const Poly& hole, std::vector<Poly>& out)
    {
        float orientation = Area(hole) >= 0.0f ? 1.0f : -1.0f;
        Poly remaining = piece;
        Poly outside;
        Poly inside;
        for (int i = 0; i < hole.count && remaining.count > 0; ++i)
        {
            Line edge = EdgeLine(hole.points[i], hole.points[(i + 1) % hole.count], orientation);
            ClipKeepNegative(remaining, Negate(edge), outside);
            if (IsUsable(outside))
                out.push_back(outside);
            ClipKeepNegative(remaining, edge, inside);
            remaining = inside;
        }
    }

    static void SplitByLine(const std::vector<Poly>& in, const Line& line, std::vector<Poly>& out)
    {
        out.clear();
        Poly part;
        for (size_t i = 0; i < in.size(); ++i)
        {
            ClipKeepNegative(in[i], line, part);
            if (IsUsable(part))
                out.push_back(part);
            ClipKeepNegative(in[i], Negate(line), part);
            if (IsUsable(part))
                out.push_back(part);
        }
    }

    static void RoundedRectPolygon(float cx, float cy, float hx, float hy, const float radius[4], int corner_segments, Poly& poly)
    {
        static const float corner_x[4] = { -1.0f, 1.0f, 1.0f, -1.0f };
        static const float corner_y[4] = { 1.0f, 1.0f, -1.0f, -1.0f };
        static const int   corner_order[4] = { QUADRANT_BOTTOM_LEFT, QUADRANT_BOTTOM_RIGHT, QUADRANT_TOP_RIGHT, QUADRANT_TOP_LEFT };
        static const float start_angle[4] = { (float)PI, (float)(1.5 * PI), 0.0f, (float)(0.5 * PI) };
        poly.count = 0;
        for (int k = 0; k < 4; ++k)
        {
            int q = corner_order[k];
            float r = radius[q];
            float ox = cx + corner_x[q] * (hx - r);
            float oy = cy + corner_y[q] * (hy - r);
            int segments = r > 0.0f ? corner_segments : 0;
            for (int s = 0; s <= segments; ++s)
            {
                float angle = start_angle[k] + (float)(0.5 * PI) * (segments > 0 ? (float)s / (float)segments : 0.0f);
                poly.points[poly.count].x = ox + cosf(angle) * r;
                poly.points[poly.count].y = oy + sinf(angle) * r;
                ++poly.count;
            }
        }
    }

    static void EllipsePolygon(float cx, float cy, float hx, float hy, int sectors, Poly& poly)
    {
        poly.count = sectors;
        for (int i = 0; i < sectors; ++i)
        {
            float angle = (float)(2.0 * PI) * (float)i / (float)sectors;
            poly.points[i].x = cx + cosf(angle) * hx;
            poly.points[i].y = cy + sinf(angle) * hy;
        }
    }

    // ---------------------------------------------------------------- paints

    static Color Mix(const Color& a, const Color& b, float t)
    {
        Color c = { a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t };
        return c;
    }

    static Color SampleStops(const std::vector<GradientStop>& stops, float t)
    {
        if (t <= stops.front().position)
            return stops.front().color;
        for (size_t i = 1; i < stops.size(); ++i)
        {
            if (t <= stops[i].position)
            {
                float span = stops[i].position - stops[i - 1].position;
                float local = span > 1e-6f ? (t - stops[i - 1].position) / span : 1.0f;
                return Mix(stops[i - 1].color, stops[i].color, local);
            }
        }
        return stops.back().color;
    }

    static void GradientAxes(const Paint& paint, const Builder& builder, Line& gx, Line& gy)
    {
        const float* t = paint.transform;
        gx.a = t[0] / builder.width;
        gx.b = -t[1] / builder.height;
        gx.c = t[1] + t[2];
        gy.a = t[3] / builder.width;
        gy.b = -t[4] / builder.height;
        gy.c = t[4] + t[5];
    }

    static Color PaintColor(const Paint& paint, const Builder& builder, const Vec2& p)
    {
        if (paint.type == PAINT_SOLID)
            return paint.color;
        Line gx, gy;
        GradientAxes(paint, builder, gx, gy);
        float x = Evaluate(gx, p);
        if (paint.type == PAINT_LINEAR)
            return SampleStops(paint.stops, x);
        float y = Evaluate(gy, p);
        float ux = x * 2.0f - 1.0f;
        float uy = y * 2.0f - 1.0f;
        return SampleStops(paint.stops, sqrtf(ux * ux + uy * uy));
    }

    static void SplitLinear(const Paint& paint, const Builder& builder, std::vector<Poly>& pieces)
    {
        Line gx, gy;
        GradientAxes(paint, builder, gx, gy);
        if (fabsf(gx.a) < 1e-9f && fabsf(gx.b) < 1e-9f)
            return;
        std::vector<Poly> split;
        for (size_t i = 0; i < paint.stops.size(); ++i)
        {
            Line line = { gx.a, gx.b, gx.c - paint.stops[i].position };
            SplitByLine(pieces, line, split);
            pieces.swap(split);
        }
    }

    static void SplitRadial(const Paint& paint, const Builder& builder, std::vector<Poly>& pieces)
    {
        Line gx, gy;
        GradientAxes(paint, builder, gx, gy);
        float m00 = 2.0f * gx.a, m01 = 2.0f * gx.b, m10 = 2.0f * gy.a, m11 = 2.0f * gy.b;
        float u0 = 2.0f * gx.c - 1.0f, v0 = 2.0f * gy.c - 1.0f;
        float det = m00 * m11 - m01 * m10;
        if (fabsf(det) < 1e-12f)
            return;
        float i00 = m11 / det, i01 = -m01 / det, i10 = -m10 / det, i11 = m00 / det;

        float far_radius = 1.0f;
        for (size_t i = 0; i < pieces.size(); ++i)
        {
            for (int k = 0; k < pieces[i].count; ++k)
            {
                const Vec2& p = pieces[i].points[k];
                float u = m00 * p.x + m01 * p.y + u0;
                float v = m10 * p.x + m11 * p.y + v0;
                float r = sqrtf(u * u + v * v);
                if (r > far_radius)
                    far_radius = r;
            }
        }
        far_radius = far_radius * 1.5f + 1.0f;

        std::vector<float> rings;
        for (size_t i = 0; i < paint.stops.size(); ++i)
        {
            float r = paint.stops[i].position;
            if (r > 1e-4f && (rings.empty() || r > rings.back() + 1e-4f))
                rings.push_back(r);
        }
        rings.push_back(far_radius);

        float radius_pixels = fmaxf(sqrtf(i00 * i00 + i10 * i10), sqrtf(i01 * i01 + i11 * i11));
        int sectors = (int)fminf(fmaxf(ceilf(radius_pixels / RADIAL_SECTOR_PIXELS), (float)MIN_RADIAL_SECTORS), (float)RADIAL_SECTORS);

        std::vector<Poly> cells;
        for (int s = 0; s < sectors; ++s)
        {
            float a0 = (float)(2.0 * PI) * (float)s / (float)sectors;
            float a1 = (float)(2.0 * PI) * (float)(s + 1) / (float)sectors;
            float c0 = cosf(a0), s0 = sinf(a0), c1 = cosf(a1), s1 = sinf(a1);
            float inner = 0.0f;
            for (size_t r = 0; r < rings.size(); ++r)
            {
                float outer = rings[r];
                Poly cell;
                cell.count = 0;
                Vec2 u_points[4];
                int n = 0;
                if (inner <= 0.0f)
                {
                    u_points[n].x = 0.0f; u_points[n].y = 0.0f; ++n;
                }
                else
                {
                    u_points[n].x = c0 * inner; u_points[n].y = s0 * inner; ++n;
                }
                u_points[n].x = c0 * outer; u_points[n].y = s0 * outer; ++n;
                u_points[n].x = c1 * outer; u_points[n].y = s1 * outer; ++n;
                if (inner > 0.0f)
                {
                    u_points[n].x = c1 * inner; u_points[n].y = s1 * inner; ++n;
                }
                for (int k = 0; k < n; ++k)
                {
                    float du = u_points[k].x - u0;
                    float dv = u_points[k].y - v0;
                    cell.points[k].x = i00 * du + i01 * dv;
                    cell.points[k].y = i10 * du + i11 * dv;
                }
                cell.count = n;
                cells.push_back(cell);
                inner = outer;
            }
        }

        std::vector<Poly> result;
        Poly part;
        for (size_t i = 0; i < pieces.size(); ++i)
        {
            float min_x = 1e30f, min_y = 1e30f, max_x = -1e30f, max_y = -1e30f;
            for (int k = 0; k < pieces[i].count; ++k)
            {
                const Vec2& p = pieces[i].points[k];
                min_x = fminf(min_x, p.x); max_x = fmaxf(max_x, p.x);
                min_y = fminf(min_y, p.y); max_y = fmaxf(max_y, p.y);
            }
            for (size_t c = 0; c < cells.size(); ++c)
            {
                const Poly& cell = cells[c];
                float cmin_x = 1e30f, cmin_y = 1e30f, cmax_x = -1e30f, cmax_y = -1e30f;
                for (int k = 0; k < cell.count; ++k)
                {
                    cmin_x = fminf(cmin_x, cell.points[k].x); cmax_x = fmaxf(cmax_x, cell.points[k].x);
                    cmin_y = fminf(cmin_y, cell.points[k].y); cmax_y = fmaxf(cmax_y, cell.points[k].y);
                }
                if (cmax_x < min_x || cmin_x > max_x || cmax_y < min_y || cmin_y > max_y)
                    continue;
                IntersectConvex(pieces[i], cell, part);
                if (IsUsable(part))
                    result.push_back(part);
            }
        }
        pieces.swap(result);
    }

    static void SplitByPaint(const Paint& paint, const Builder& builder, std::vector<Poly>& pieces)
    {
        if (paint.type == PAINT_LINEAR)
            SplitLinear(paint, builder, pieces);
        else if (paint.type == PAINT_RADIAL)
            SplitRadial(paint, builder, pieces);
    }

    // ---------------------------------------------------------------- emission

    static float PackPage(int mode, uint32_t data)
    {
        uint32_t packed = (uint32_t)(mode & 3) | (data << 2);
        return mode >= 4 ? -(float)(packed + 1) : (float)packed;
    }

    static uint32_t Quantize(float value, float scale, uint32_t max)
    {
        float q = floorf(value * scale + 0.5f);
        if (!(q >= 0.0f))
            return 0;
        return q > (float)max ? max : (uint32_t)q;
    }

    static int QuadrantOf(const Primitive& primitive, const Vec2& p)
    {
        if (p.y >= primitive.center_y)
            return p.x < primitive.center_x ? QUADRANT_TOP_LEFT : QUADRANT_TOP_RIGHT;
        return p.x < primitive.center_x ? QUADRANT_BOTTOM_LEFT : QUADRANT_BOTTOM_RIGHT;
    }

    static const float WARP_FAR = -4096.0f;

    // The arc as a rounded rectangle unrolled along its centerline: x runs along the arc from its
    // middle, y across the ring from the centerline, both folded to the corner of the rectangle the
    // way the rrect modes of the shader expect them.
    static Vec2 WarpUv(const ArcWarp& warp, const Vec2& p)
    {
        float nx = (p.x - warp.shift_x - warp.center_x) / warp.half_x;
        float ny = (warp.center_y - (p.y - warp.shift_y)) / warp.half_y;
        float radius = sqrtf(nx * nx + ny * ny);
        float across = fabsf((radius - warp.center_radius) * warp.scale) - (warp.half_width + warp.grow - warp.corner);
        float along = WARP_FAR;
        if (!warp.full)
        {
            float delta = atan2f(ny, nx) - warp.middle;
            delta -= (float)(2.0 * PI) * floorf(delta / (float)(2.0 * PI) + 0.5f);
            along = warp.corner - (warp.half_sweep - fabsf(delta)) * radius * warp.scale - warp.grow;
        }
        Vec2 uv = { along * warp.uv_scale, across * warp.uv_scale };
        return uv;
    }

    static void EmitVertex(const Builder& builder, const Primitive& primitive, int quadrant, const Paint& paint, const Vec2& p)
    {
        ShapeVertex v;
        v.position[0] = p.x / builder.width;
        v.position[1] = p.y / builder.height;
        v.position[2] = 0.0f;
        if (primitive.warped)
        {
            Vec2 uv = WarpUv(primitive.warp, p);
            v.uv[0] = uv.x;
            v.uv[1] = uv.y;
        }
        else if (primitive.folded)
        {
            v.uv[0] = (fabsf(p.x - primitive.center_x) - primitive.inner_x[quadrant]) * primitive.uv_scale_x;
            v.uv[1] = (fabsf(p.y - primitive.center_y) - primitive.inner_y[quadrant]) * primitive.uv_scale_y;
        }
        else
        {
            v.uv[0] = Evaluate(primitive.uv_x, p);
            v.uv[1] = Evaluate(primitive.uv_y, p);
        }
        Color color = PaintColor(paint, builder, p);
        v.color[0] = color.r;
        v.color[1] = color.g;
        v.color[2] = color.b;
        v.color[3] = color.a;
        v.page_index = primitive.page[quadrant];
        builder.out->push_back(v);
    }

    static void ClipPieces(const Builder& builder, std::vector<Poly>& pieces)
    {
        std::vector<Poly> clipped;
        Poly part;
        for (size_t i = 0; i < pieces.size(); ++i)
        {
            IntersectConvex(pieces[i], builder.clip, part);
            if (IsUsable(part))
                clipped.push_back(part);
        }
        pieces.swap(clipped);
    }

    static void EmitPieces(const Builder& builder, const Primitive& primitive, const Paint& paint, std::vector<Poly>& pieces, bool split_paint = true)
    {
        if (builder.clipped)
            ClipPieces(builder, pieces);
        if (primitive.folded)
        {
            std::vector<Poly> split;
            Line vertical = { 1.0f, 0.0f, -primitive.center_x };
            Line horizontal = { 0.0f, 1.0f, -primitive.center_y };
            SplitByLine(pieces, vertical, split);
            SplitByLine(split, horizontal, pieces);
        }
        if (split_paint)
            SplitByPaint(paint, builder, pieces);
        for (size_t i = 0; i < pieces.size(); ++i)
        {
            const Poly& poly = pieces[i];
            int quadrant = primitive.folded ? QuadrantOf(primitive, Centroid(poly)) : 0;
            for (int k = 1; k + 1 < poly.count; ++k)
            {
                EmitVertex(builder, primitive, quadrant, paint, poly.points[0]);
                EmitVertex(builder, primitive, quadrant, paint, poly.points[k]);
                EmitVertex(builder, primitive, quadrant, paint, poly.points[k + 1]);
            }
        }
    }

    // ---------------------------------------------------------------- shapes

    struct Outline
    {
        float center_x;
        float center_y;
        float half_x;
        float half_y;
        float radius[4];
    };

    static Outline Grow(const Outline& outline, float amount)
    {
        Outline grown = outline;
        grown.half_x = fmaxf(outline.half_x + amount, 0.0f);
        grown.half_y = fmaxf(outline.half_y + amount, 0.0f);
        float limit = fminf(grown.half_x, grown.half_y);
        for (int i = 0; i < 4; ++i)
            grown.radius[i] = outline.radius[i] > 0.0f ? fminf(fmaxf(outline.radius[i] + amount, 0.0f), limit) : 0.0f;
        return grown;
    }

    static void CoverRect(const Outline& outline, float margin, std::vector<Poly>& pieces)
    {
        Poly rect;
        MakeRect(outline.center_x - outline.half_x - margin, outline.center_y - outline.half_y - margin,
                 outline.center_x + outline.half_x + margin, outline.center_y + outline.half_y + margin, rect);
        pieces.push_back(rect);
    }

    static void CoverRing(const Outline& outline, float margin, const Poly& hole, std::vector<Poly>& pieces)
    {
        Poly rect;
        MakeRect(outline.center_x - outline.half_x - margin, outline.center_y - outline.half_y - margin,
                 outline.center_x + outline.half_x + margin, outline.center_y + outline.half_y + margin, rect);
        if (hole.count < 3)
        {
            pieces.push_back(rect);
            return;
        }
        SubtractConvex(rect, hole, pieces);
    }

    static void CenteredUv(Primitive& primitive, float center_x, float center_y, float scale_x, float scale_y)
    {
        primitive.center_x = center_x;
        primitive.center_y = center_y;
        primitive.uv_x.a = scale_x;
        primitive.uv_x.b = 0.0f;
        primitive.uv_x.c = -center_x * scale_x;
        primitive.uv_y.a = 0.0f;
        primitive.uv_y.b = scale_y;
        primitive.uv_y.c = -center_y * scale_y;
    }

    static void UniformPage(Primitive& primitive, float page)
    {
        for (int q = 0; q < 4; ++q)
        {
            primitive.inner_x[q] = 0.0f;
            primitive.inner_y[q] = 0.0f;
            primitive.page[q] = page;
        }
    }

    static void RRectPrimitive(const Outline& outline, float stroke_width, Primitive& primitive)
    {
        primitive.folded = true;
        primitive.center_x = outline.center_x;
        primitive.center_y = outline.center_y;
        primitive.uv_scale_x = 1.0f;
        primitive.uv_scale_y = 1.0f;
        uint32_t width_bits = Quantize(stroke_width, 4.0f, 1023);
        for (int q = 0; q < 4; ++q)
        {
            float r = outline.radius[q];
            primitive.inner_x[q] = outline.half_x - r;
            primitive.inner_y[q] = outline.half_y - r;
            primitive.page[q] = PackPage(MODE_RRECT, Quantize(r, 4.0f, 4095) | (width_bits << 12));
        }
    }

    static void EllipsePrimitive(const Outline& outline, Primitive& primitive)
    {
        primitive.folded = false;
        CenteredUv(primitive, outline.center_x, outline.center_y,
                   outline.half_x > 0.0f ? 1.0f / outline.half_x : 0.0f,
                   outline.half_y > 0.0f ? 1.0f / outline.half_y : 0.0f);
        UniformPage(primitive, PackPage(MODE_ELLIPSE, 0));
    }

    static void EllipseStrokePrimitive(const Outline& outline, float width, StrokeAlign align, Primitive& primitive)
    {
        primitive.folded = false;
        float major = fmaxf(outline.half_x, outline.half_y);
        float minor = fminf(outline.half_x, outline.half_y);
        CenteredUv(primitive, outline.center_x, outline.center_y, 1.0f / major, 1.0f / major);
        uint32_t swap = outline.half_y > outline.half_x ? 1 : 0;
        uint32_t data = Quantize(minor / major, 2047.0f, 2047) | (swap << 11) | (Quantize(width / major, 1023.0f, 1023) << 12);
        UniformPage(primitive, PackPage(MODE_ELLIPSE_STROKE_INSIDE + (int)align, data));
    }

    static float BlurSigma(const ShapeDesc& desc, const Outline& outline, float sigma_per_radius, float radius)
    {
        float sigma = fmaxf(radius * sigma_per_radius, MIN_SIGMA);
        if (desc.kind == SHAPE_ELLIPSE)
            return fmaxf(sigma, fmaxf(outline.half_x, outline.half_y) / 255.875f);
        float max_radius = 0.0f;
        for (int q = 0; q < 4; ++q)
            max_radius = fmaxf(max_radius, outline.radius[q]);
        return fmaxf(sigma, max_radius / 63.9375f);
    }

    static void BlurPrimitive(const ShapeDesc& desc, const Outline& outline, float sigma, Primitive& primitive)
    {
        primitive.center_x = outline.center_x;
        primitive.center_y = outline.center_y;
        primitive.uv_scale_x = 1.0f / sigma;
        primitive.uv_scale_y = 1.0f / sigma;
        if (desc.kind == SHAPE_ELLIPSE)
        {
            primitive.folded = false;
            CenteredUv(primitive, outline.center_x, outline.center_y, 1.0f / sigma, 1.0f / sigma);
            UniformPage(primitive, PackPage(MODE_ELLIPSE_BLUR, Quantize(outline.half_x / sigma, 8.0f, 2047) | (Quantize(outline.half_y / sigma, 8.0f, 2047) << 11)));
            return;
        }
        primitive.folded = true;
        for (int q = 0; q < 4; ++q)
        {
            float r = outline.radius[q];
            float ax = outline.half_x - r;
            float ay = outline.half_y - r;
            primitive.inner_x[q] = ax;
            primitive.inner_y[q] = ay;
            uint32_t data = Quantize(r / sigma, 16.0f, 1023) | (Quantize(ax / sigma, 8.0f, 63) << 10) | (Quantize(ay / sigma, 8.0f, 63) << 16);
            primitive.page[q] = PackPage(MODE_RRECT_BLUR, data);
        }
    }

    static void OutlinePolygon(const ShapeDesc& desc, const Outline& outline, Poly& poly)
    {
        if (desc.kind == SHAPE_ELLIPSE)
            EllipsePolygon(outline.center_x, outline.center_y, outline.half_x, outline.half_y, RADIAL_SECTORS, poly);
        else
            RoundedRectPolygon(outline.center_x, outline.center_y, outline.half_x, outline.half_y, outline.radius, CORNER_SEGMENTS, poly);
    }

    static float StrokeOutset(const ShapeDesc& desc)
    {
        if (desc.stroke_width <= 0.0f || desc.strokes.empty())
            return 0.0f;
        if (desc.stroke_align == STROKE_OUTSIDE)
            return desc.stroke_width;
        if (desc.stroke_align == STROKE_CENTER)
            return desc.stroke_width * 0.5f;
        return 0.0f;
    }

    static void BuildShadow(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const DropShadow& shadow)
    {
        Outline cast = Grow(Grow(shape, StrokeOutset(desc)), shadow.spread);
        cast.center_x += shadow.offset_x;
        cast.center_y -= shadow.offset_y;
        float sigma = BlurSigma(desc, cast, SHADOW_SIGMA_PER_RADIUS, shadow.radius);
        Primitive primitive;
        BlurPrimitive(desc, cast, sigma, primitive);

        std::vector<Poly> pieces;
        CoverRect(cast, sigma * BLUR_EXTENT, pieces);
        if (!shadow.show_behind)
        {
            Outline hole = Grow(Grow(shape, StrokeOutset(desc)), -KNOCKOUT_INSET);
            if (hole.half_x > 0.0f && hole.half_y > 0.0f)
            {
                Poly hole_poly;
                OutlinePolygon(desc, hole, hole_poly);
                std::vector<Poly> outside;
                SubtractConvex(pieces[0], hole_poly, outside);
                pieces.swap(outside);
            }
        }
        Paint paint;
        paint.type = PAINT_SOLID;
        paint.color = shadow.color;
        EmitPieces(builder, primitive, paint, pieces);
    }

    static bool IsArc(const ShapeDesc& desc)
    {
        return desc.kind == SHAPE_ELLIPSE && (desc.arc_sweep < 100.0f || desc.arc_ratio > 0.0f);
    }

    static Vec2 ArcPoint(const Outline& shape, float angle, float radius)
    {
        Vec2 p = { shape.center_x + shape.half_x * radius * cosf(angle), shape.center_y - shape.half_y * radius * sinf(angle) };
        return p;
    }

    static void ArcCells(const Outline& shape, float from, float to, float inner, float outer, std::vector<Poly>& pieces)
    {
        int segments = (int)fmaxf(ceilf((to - from) / ARC_SEGMENT), 1.0f);
        float step = (to - from) / (float)segments;
        float grown = outer / cosf(step * 0.5f);
        for (int s = 0; s < segments; ++s)
        {
            float a0 = from + step * (float)s;
            float a1 = a0 + step;
            Poly cell;
            cell.count = 0;
            if (inner > 0.0f)
            {
                cell.points[cell.count++] = ArcPoint(shape, a0, inner);
                cell.points[cell.count++] = ArcPoint(shape, a1, inner);
            }
            else
                cell.points[cell.count++] = ArcPoint(shape, a0, 0.0f);
            cell.points[cell.count++] = ArcPoint(shape, a1, grown);
            cell.points[cell.count++] = ArcPoint(shape, a0, grown);
            pieces.push_back(cell);
        }
    }

    static void ArcFrame(const Outline& shape, float angle, bool mirror, float page, Primitive& primitive)
    {
        float rotation = (float)(0.5 * PI) + angle;
        float c = cosf(rotation);
        float s = sinf(rotation);
        float m = mirror ? -1.0f : 1.0f;
        float ix = 1.0f / shape.half_x;
        float iy = 1.0f / shape.half_y;
        primitive.folded = false;
        primitive.center_x = shape.center_x;
        primitive.center_y = shape.center_y;
        primitive.uv_x.a = m * c * ix;
        primitive.uv_x.b = -m * s * iy;
        primitive.uv_x.c = -m * (c * shape.center_x * ix - s * shape.center_y * iy);
        primitive.uv_y.a = s * ix;
        primitive.uv_y.b = c * iy;
        primitive.uv_y.c = -(s * shape.center_x * ix + c * shape.center_y * iy);
        UniformPage(primitive, page);
    }

    static void BuildArc(const Builder& builder, const ShapeDesc& desc, const Outline& outline, const Paint& paint, float grow)
    {
        Outline shape = outline;
        shape.half_x += grow;
        shape.half_y += grow;
        float minor_axis = fminf(outline.half_x, outline.half_y);
        float ratio = fminf(fmaxf(desc.arc_ratio, 0.0f), 100.0f) * 0.01f;
        if (grow > 0.0f && ratio > 0.0f)
            ratio = fmaxf((ratio * minor_axis - grow) / (minor_axis + grow), 0.0f);
        float sweep = fminf(fmaxf(desc.arc_sweep, 0.0f), 100.0f) * 0.01f * (float)(2.0 * PI);
        float start = fmodf(desc.arc_start, 360.0f) * (float)(PI / 180.0);
        float minor = fminf(shape.half_x, shape.half_y);
        if (ratio >= 1.0f || !(minor > 0.0f) || !isfinite(start))
            return;
        float half_width = 0.5f * (1.0f - ratio);
        float cap = fminf(fmaxf(desc.corner_radius[0], 0.0f) / minor, half_width);
        float margin = AA_MARGIN / minor;
        float inner = ratio - margin;
        float outer = 1.0f + margin;
        bool full = sweep >= (float)(2.0 * PI);
        uint32_t data = 1u | ((full ? 1u : 0u) << 1) | (Quantize(ratio, 1023.0f, 1023) << 2) | (Quantize(cap / half_width, 1023.0f, 1023) << 12);
        float page = PackPage(MODE_EDGE, data);
        Primitive primitive;
        std::vector<Poly> pieces;
        if (full)
        {
            ArcFrame(shape, 0.0f, false, page, primitive);
            ArcCells(shape, 0.0f, (float)(2.0 * PI), inner, outer, pieces);
            EmitPieces(builder, primitive, paint, pieces);
            return;
        }
        float reach = cap + margin;
        float overhang = fminf((float)(0.5 * PI), reach / fmaxf(ratio, reach));
        float middle = start + sweep * 0.5f;
        ArcFrame(shape, start, false, page, primitive);
        ArcCells(shape, start - overhang, middle, inner, outer, pieces);
        EmitPieces(builder, primitive, paint, pieces);
        pieces.clear();
        ArcFrame(shape, start + sweep, true, page, primitive);
        ArcCells(shape, middle, start + sweep + overhang, inner, outer, pieces);
        EmitPieces(builder, primitive, paint, pieces);
    }

    struct ArcShape
    {
        bool  valid;
        bool  full;
        float middle;
        float half_sweep;
        float scale;
        float center_radius;
        float half_width;
        float corner;
    };

    static const float BLUR_WARP_TOLERANCE = 0.5f;
    static const float EDGE_WARP_TOLERANCE = 0.2f;
    static const float WARP_MIN_STEP  = (float)(PI / 90.0);

    static ArcShape MakeArcShape(const ShapeDesc& desc, const Outline& shape)
    {
        ArcShape arc;
        float ratio = fminf(fmaxf(desc.arc_ratio, 0.0f), 100.0f) * 0.01f;
        float sweep = fminf(fmaxf(desc.arc_sweep, 0.0f), 100.0f) * 0.01f * (float)(2.0 * PI);
        float start = fmodf(desc.arc_start, 360.0f) * (float)(PI / 180.0);
        arc.scale = 0.5f * (shape.half_x + shape.half_y);
        arc.valid = ratio < 1.0f && fminf(shape.half_x, shape.half_y) > 0.0f && isfinite(start) && sweep > 0.0f;
        arc.full = sweep >= (float)(2.0 * PI);
        arc.middle = start + sweep * 0.5f;
        arc.half_sweep = sweep * 0.5f;
        arc.center_radius = 0.5f * (1.0f + ratio);
        arc.half_width = 0.5f * (1.0f - ratio) * arc.scale;
        arc.corner = fminf(fmaxf(desc.corner_radius[0], 0.0f), arc.half_width);
        return arc;
    }

    static float GrownHalfWidth(const ArcShape& arc, float grow)
    {
        return fmaxf(arc.half_width + grow, 0.0f);
    }

    static float GrownCorner(const ArcShape& arc, float grow)
    {
        return arc.corner > 0.0f ? fminf(fmaxf(arc.corner + grow, 0.0f), GrownHalfWidth(arc, grow)) : 0.0f;
    }

    static void WarpPrimitive(const Outline& shape, const ArcShape& arc, float grow, float sigma, float shift_x, float shift_y, float page, Primitive& primitive)
    {
        primitive.warped = true;
        primitive.folded = false;
        primitive.center_x = shape.center_x;
        primitive.center_y = shape.center_y;
        ArcWarp& warp = primitive.warp;
        warp.center_x = shape.center_x;
        warp.center_y = shape.center_y;
        warp.half_x = shape.half_x;
        warp.half_y = shape.half_y;
        warp.scale = arc.scale;
        warp.middle = arc.middle;
        warp.half_sweep = arc.half_sweep;
        warp.full = arc.full;
        warp.center_radius = arc.center_radius;
        warp.half_width = arc.half_width;
        warp.corner = GrownCorner(arc, grow);
        warp.grow = grow;
        warp.shift_x = shift_x;
        warp.shift_y = shift_y;
        warp.uv_scale = sigma > 0.0f ? 1.0f / sigma : 1.0f;
        UniformPage(primitive, page);
    }

    static void AddBreak(std::vector<float>& breaks, float value, float low, float high)
    {
        if (value > low && value < high)
            breaks.push_back(value);
    }

    static void AngularBreaks(float from, float to, float step, std::vector<float>& out)
    {
        int segments = (int)fmaxf(ceilf((to - from) / step), 1.0f);
        for (int i = 0; i < segments; ++i)
            out.push_back(from + (to - from) * (float)i / (float)segments);
    }

    // The radial line through the start (or the end) of the arc, moved by inset towards the middle:
    // the line is negative on the side away from the arc body.
    static Line EndLine(const Outline& shape, const ArcShape& arc, bool at_start, float inset)
    {
        float angle = at_start ? arc.middle - arc.half_sweep : arc.middle + arc.half_sweep;
        float dx = shape.half_x * cosf(angle);
        float dy = -shape.half_y * sinf(angle);
        float length = sqrtf(dx * dx + dy * dy);
        float nx = -dy / length;
        float ny = dx / length;
        Vec2 middle = ArcPoint(shape, arc.middle, arc.center_radius);
        if ((middle.x - shape.center_x) * nx + (middle.y - shape.center_y) * ny < 0.0f)
        {
            nx = -nx;
            ny = -ny;
        }
        Line line = { nx, ny, -(nx * shape.center_x + ny * shape.center_y) - inset };
        return line;
    }

    // The part of the ring the cells leave out: a rounded rectangle in the unrolled coordinates,
    // centered at `center` px from the ellipse center, `half` px across, with its ends `end_inset` px
    // inside the ends of the arc.
    struct ArcInterior
    {
        float center;
        float half;
        float corner;
        float end_inset;
    };

    static const int   MAX_CORNER_ROWS = 4;
    static const float CORNER_ROW_PIXELS = 6.0f;

    // Cells of the ring around the arc in angle and radius. The cuts at the centerline and at the
    // middle of the arc keep every cell on one side of the fold; the angular step keeps the chord of
    // a cell within `tolerance` px of the circle, so the unrolled coordinates stay exact. The cells
    // inside `interior` are cut away along the radial lines of the arc ends.
    static void WarpCells(const Outline& shape, const ArcShape& arc, float grow, float extent, float tolerance, float shift_x, float shift_y, const ArcInterior* interior, std::vector<Poly>& pieces)
    {
        float half_width = GrownHalfWidth(arc, grow);
        float corner = GrownCorner(arc, grow);
        float center = arc.center_radius * arc.scale;
        float low = fmaxf(center - half_width - extent, 0.0f) / arc.scale;
        float high = (center + half_width + extent) / arc.scale;
        std::vector<float> radii;
        radii.push_back(low);
        AddBreak(radii, arc.center_radius, low, high);
        bool cut = interior && interior->half > 0.0f;
        if (cut)
        {
            float straight = interior->half - interior->corner;
            for (int side = -1; side <= 1; side += 2)
            {
                AddBreak(radii, (interior->center + side * interior->half) / arc.scale, low, high);
                int rows = (int)fminf(ceilf(interior->corner / CORNER_ROW_PIXELS), (float)MAX_CORNER_ROWS);
                for (int j = 0; j < rows; ++j)
                    AddBreak(radii, (interior->center + side * (straight + interior->corner * (float)j / (float)rows)) / arc.scale, low, high);
            }
        }
        radii.push_back(high);
        std::sort(radii.begin(), radii.end());

        float step = fminf(fmaxf(2.0f * acosf(fmaxf(1.0f - tolerance / (high * arc.scale), -1.0f)), WARP_MIN_STEP), ARC_SEGMENT);
        std::vector<float> angles;
        float span_to;
        if (arc.full)
        {
            span_to = (float)(2.0 * PI);
            AngularBreaks(0.0f, span_to, step, angles);
        }
        else
        {
            float reach = low > 0.0f ? (extent + grow + corner) / (low * arc.scale) : (float)PI;
            float half_span = fminf(arc.half_sweep + fmaxf(reach, 0.0f), (float)PI);
            span_to = arc.middle + half_span;
            AngularBreaks(arc.middle - half_span, arc.middle, step, angles);
            AngularBreaks(arc.middle, span_to, step, angles);
        }
        angles.push_back(span_to);

        for (size_t r = 0; r + 1 < radii.size(); ++r)
        {
            float r0 = radii[r];
            float r1 = radii[r + 1];
            float u0 = fabsf(r0 * arc.scale - (cut ? interior->center : center));
            float u1 = fabsf(r1 * arc.scale - (cut ? interior->center : center));
            float across = fmaxf(u0, u1);
            bool inside = cut && u0 <= interior->half + 1e-3f && u1 <= interior->half + 1e-3f;
            float end_inset = 0.0f;
            if (inside)
            {
                float into_corner = across - (interior->half - interior->corner);
                end_inset = interior->end_inset;
                if (into_corner > 0.0f)
                    end_inset += interior->corner - sqrtf(fmaxf(interior->corner * interior->corner - into_corner * into_corner, 0.0f));
            }
            for (size_t a = 0; a + 1 < angles.size(); ++a)
            {
                float a0 = angles[a];
                float a1 = angles[a + 1];
                if (inside && arc.full)
                    continue;
                Poly cell;
                cell.count = 0;
                if (r0 > 0.0f)
                {
                    cell.points[cell.count++] = ArcPoint(shape, a0, r0);
                    cell.points[cell.count++] = ArcPoint(shape, a1, r0);
                }
                else
                    cell.points[cell.count++] = ArcPoint(shape, a0, 0.0f);
                cell.points[cell.count++] = ArcPoint(shape, a1, r1);
                cell.points[cell.count++] = ArcPoint(shape, a0, r1);
                if (inside)
                {
                    Poly outside;
                    ClipKeepNegative(cell, EndLine(shape, arc, 0.5f * (a0 + a1) < arc.middle, end_inset), outside);
                    if (!IsUsable(outside))
                        continue;
                    cell = outside;
                }
                for (int i = 0; i < cell.count; ++i)
                {
                    cell.points[i].x += shift_x;
                    cell.points[i].y += shift_y;
                }
                pieces.push_back(cell);
            }
        }
    }

    static float ArcBlurSigma(float radius, float corner)
    {
        return fmaxf(fmaxf(radius * SHADOW_SIGMA_PER_RADIUS, MIN_SIGMA), corner / 63.9375f);
    }

    static float ArcBlurPage(const ArcShape& arc, float grow, float sigma)
    {
        float half_width = GrownHalfWidth(arc, grow);
        float corner = GrownCorner(arc, grow);
        float along = arc.full ? 1e6f : fmaxf(arc.half_sweep * arc.center_radius * arc.scale + grow - corner, 0.0f);
        uint32_t data = Quantize(corner / sigma, 16.0f, 1023) | (Quantize(along / sigma, 8.0f, 63) << 10) | (Quantize((half_width - corner) / sigma, 8.0f, 63) << 16);
        return PackPage(MODE_RRECT_BLUR, data);
    }

    // Figma spreads the shadow of an arc by growing the ellipse: the ratio and the angles stay, so
    // the inner edge moves out with the outer one and the ends do not move.
    static void BuildArcShadow(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const DropShadow& shadow)
    {
        ArcShape body = MakeArcShape(desc, shape);
        Outline cast_shape = shape;
        cast_shape.half_x = fmaxf(shape.half_x + shadow.spread, 0.0f);
        cast_shape.half_y = fmaxf(shape.half_y + shadow.spread, 0.0f);
        ArcShape cast = MakeArcShape(desc, cast_shape);
        if (!body.valid || !cast.valid)
            return;
        float grow = StrokeOutset(desc);
        float sigma = ArcBlurSigma(shadow.radius, GrownCorner(cast, grow));
        float shift_x = shadow.offset_x;
        float shift_y = -shadow.offset_y;
        ArcInterior hole;
        hole.center = body.center_radius * body.scale;
        hole.half = GrownHalfWidth(body, grow) - KNOCKOUT_INSET;
        hole.corner = fmaxf(GrownCorner(body, grow) - KNOCKOUT_INSET, 0.0f);
        hole.end_inset = KNOCKOUT_INSET - grow;
        bool knockout = !shadow.show_behind && shift_x == 0.0f && shift_y == 0.0f;
        Primitive primitive;
        WarpPrimitive(cast_shape, cast, grow, sigma, shift_x, shift_y, ArcBlurPage(cast, grow, sigma), primitive);
        std::vector<Poly> pieces;
        WarpCells(cast_shape, cast, grow, sigma * BLUR_EXTENT, BLUR_WARP_TOLERANCE, shift_x, shift_y, knockout ? &hole : 0, pieces);
        Paint paint;
        paint.type = PAINT_SOLID;
        paint.color = shadow.color;
        EmitPieces(builder, primitive, paint, pieces);
    }

    static void BuildArcBlurredFill(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const Paint& paint)
    {
        ArcShape arc = MakeArcShape(desc, shape);
        if (!arc.valid)
            return;
        float sigma = ArcBlurSigma(desc.layer_blur * BLUR_SIGMA_PER_RADIUS / SHADOW_SIGMA_PER_RADIUS, arc.corner);
        Primitive primitive;
        WarpPrimitive(shape, arc, 0.0f, sigma, 0.0f, 0.0f, ArcBlurPage(arc, 0.0f, sigma), primitive);
        std::vector<Poly> pieces;
        WarpCells(shape, arc, 0.0f, sigma * BLUR_EXTENT, BLUR_WARP_TOLERANCE, 0.0f, 0.0f, 0, pieces);
        EmitPieces(builder, primitive, paint, pieces);
    }

    static void BuildArcStroke(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const Paint& paint)
    {
        ArcShape arc = MakeArcShape(desc, shape);
        if (!arc.valid)
            return;
        float grow = StrokeOutset(desc);
        float width = desc.stroke_width;
        uint32_t data = Quantize(GrownCorner(arc, grow), 4.0f, 4095) | (Quantize(width, 4.0f, 1023) << 12);
        Primitive primitive;
        WarpPrimitive(shape, arc, grow, 0.0f, 0.0f, 0.0f, PackPage(MODE_RRECT, data), primitive);
        std::vector<Poly> pieces;
        float inset = width + AA_MARGIN;
        ArcInterior hole;
        hole.center = arc.center_radius * arc.scale;
        hole.half = GrownHalfWidth(arc, grow) - inset;
        hole.corner = fmaxf(GrownCorner(arc, grow) - inset, 0.0f);
        hole.end_inset = inset - grow;
        WarpCells(shape, arc, grow, AA_MARGIN, EDGE_WARP_TOLERANCE, 0.0f, 0.0f, &hole, pieces);
        EmitPieces(builder, primitive, paint, pieces);
    }

    static const float PATH_INTERIOR = -1000.0f;

    static void EdgePrimitive(Primitive& primitive, float a, float b, float c)
    {
        primitive.folded = false;
        primitive.center_x = 0.0f;
        primitive.center_y = 0.0f;
        primitive.uv_x.a = a;
        primitive.uv_x.b = b;
        primitive.uv_x.c = c;
        primitive.uv_y.a = 0.0f;
        primitive.uv_y.b = 0.0f;
        primitive.uv_y.c = 0.0f;
        UniformPage(primitive, PackPage(MODE_EDGE, 0));
    }

    static void EmitFlat(const Builder& builder, const Paint& paint, const Poly& interior)
    {
        Primitive primitive;
        EdgePrimitive(primitive, 0.0f, 0.0f, PATH_INTERIOR);
        std::vector<Poly> pieces(1, interior);
        EmitPieces(builder, primitive, paint, pieces);
    }

    static void FilledInterior(const ShapeDesc& desc, const Outline& shape, Poly& interior)
    {
        interior.count = 0;
        float inset_x, inset_y;
        if (desc.kind == SHAPE_ELLIPSE)
        {
            inset_x = shape.half_x * (1.0f - SQRT_HALF) + AA_MARGIN;
            inset_y = shape.half_y * (1.0f - SQRT_HALF) + AA_MARGIN;
        }
        else
        {
            float radius = fmaxf(fmaxf(shape.radius[0], shape.radius[1]), fmaxf(shape.radius[2], shape.radius[3]));
            inset_x = radius + AA_MARGIN;
            inset_y = radius + AA_MARGIN;
        }
        float half_x = shape.half_x - inset_x;
        float half_y = shape.half_y - inset_y;
        if (4.0f * half_x * half_y < MIN_HOLE_AREA || half_x <= 0.0f || half_y <= 0.0f)
            return;
        MakeRect(shape.center_x - half_x, shape.center_y - half_y, shape.center_x + half_x, shape.center_y + half_y, interior);
    }

    static void BuildFill(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const Paint& paint)
    {
        std::vector<Poly> pieces;
        Primitive primitive;
        if (desc.layer_blur > 0.0f)
        {
            float sigma = BlurSigma(desc, shape, BLUR_SIGMA_PER_RADIUS, desc.layer_blur);
            BlurPrimitive(desc, shape, sigma, primitive);
            CoverRect(shape, sigma * BLUR_EXTENT, pieces);
        }
        else
        {
            if (desc.kind == SHAPE_ELLIPSE)
                EllipsePrimitive(shape, primitive);
            else
                RRectPrimitive(shape, 0.0f, primitive);
            Poly interior;
            FilledInterior(desc, shape, interior);
            if (IsUsable(interior))
            {
                CoverRing(shape, AA_MARGIN, interior, pieces);
                EmitFlat(builder, paint, interior);
            }
            else
                CoverRect(shape, AA_MARGIN, pieces);
        }
        EmitPieces(builder, primitive, paint, pieces);
    }

    static void BuildStroke(const Builder& builder, const ShapeDesc& desc, const Outline& shape, const Paint& paint)
    {
        float width = desc.stroke_width;
        Outline outer = Grow(shape, StrokeOutset(desc));
        Outline inner = Grow(outer, -(width + AA_MARGIN));
        Poly hole;
        hole.count = 0;
        std::vector<Poly> pieces;
        Primitive primitive;
        bool cut_hole = 4.0f * inner.half_x * inner.half_y >= MIN_HOLE_AREA;
        if (desc.kind == SHAPE_ELLIPSE)
        {
            EllipseStrokePrimitive(shape, width, desc.stroke_align, primitive);
            if (cut_hole)
                EllipsePolygon(inner.center_x, inner.center_y, inner.half_x, inner.half_y, HOLE_SECTORS, hole);
        }
        else
        {
            RRectPrimitive(outer, width, primitive);
            if (cut_hole)
                RoundedRectPolygon(inner.center_x, inner.center_y, inner.half_x, inner.half_y, inner.radius, HOLE_CORNER_SEGMENTS, hole);
        }
        CoverRing(outer, AA_MARGIN, hole, pieces);
        EmitPieces(builder, primitive, paint, pieces);
    }


    static Vec2 PathPoint(const Builder& builder, const std::vector<float>& values, size_t index)
    {
        Vec2 p = { values[index], builder.height - values[index + 1] };
        return p;
    }

    static Vec2 OutwardNormal(const Vec2& a, const Vec2& b)
    {
        float dx = b.x - a.x;
        float dy = b.y - a.y;
        float length = sqrtf(dx * dx + dy * dy);
        Vec2 n = { dy / length, -dx / length };
        return n;
    }

    static void EmitPolygon(const Builder& builder, const Primitive& primitive, const Paint& paint, const Vec2* points, int count, bool split_paint)
    {
        std::vector<Poly> pieces(1);
        pieces[0].count = count;
        for (int i = 0; i < count; ++i)
            pieces[0].points[i] = points[i];
        if (IsUsable(pieces[0]))
            EmitPieces(builder, primitive, paint, pieces, split_paint);
    }

    static bool SamePoint(const Vec2& a, const Vec2& b)
    {
        return fabsf(a.x - b.x) < 1e-3f && fabsf(a.y - b.y) < 1e-3f;
    }

    static void BuildPath(const Builder& builder, const PathGeometry& path, const Paint& paint)
    {
        Primitive interior;
        EdgePrimitive(interior, 0.0f, 0.0f, PATH_INTERIOR);
        for (size_t i = 0; i < path.polygons.size(); ++i)
        {
            const std::vector<float>& values = path.polygons[i];
            Vec2 points[MAX_POLY_POINTS];
            int count = 0;
            for (size_t k = 0; k + 1 < values.size() && count < MAX_POLY_POINTS; k += 2)
                points[count++] = PathPoint(builder, values, k);
            EmitPolygon(builder, interior, paint, points, count, true);
        }

        size_t edge_count = path.edges.size() / 4;
        for (size_t e = 0; e < edge_count; ++e)
        {
            Vec2 a = PathPoint(builder, path.edges, e * 4);
            Vec2 b = PathPoint(builder, path.edges, e * 4 + 2);
            if (SamePoint(a, b))
                continue;
            Vec2 n = OutwardNormal(a, b);
            Primitive fringe;
            EdgePrimitive(fringe, n.x, n.y, -(n.x * a.x + n.y * a.y));
            Vec2 quad[4] = { a, b, { b.x + n.x * AA_MARGIN, b.y + n.y * AA_MARGIN }, { a.x + n.x * AA_MARGIN, a.y + n.y * AA_MARGIN } };
            EmitPolygon(builder, fringe, paint, quad, 4, false);

            for (size_t f = 0; f < edge_count; ++f)
            {
                Vec2 next_a = PathPoint(builder, path.edges, f * 4);
                if (f == e || !SamePoint(next_a, b))
                    continue;
                Vec2 next_b = PathPoint(builder, path.edges, f * 4 + 2);
                if (SamePoint(next_a, next_b))
                    continue;
                float cross = (b.x - a.x) * (next_b.y - next_a.y) - (b.y - a.y) * (next_b.x - next_a.x);
                if (cross <= 0.0f)
                    break;
                Vec2 m = OutwardNormal(next_a, next_b);
                float det = n.x * m.y - n.y * m.x;
                if (fabsf(det) < 1e-6f)
                    break;
                float alpha_x = (m.y - n.y) / det;
                float alpha_y = (n.x - m.x) / det;
                Primitive wedge;
                EdgePrimitive(wedge, alpha_x, alpha_y, -(alpha_x * b.x + alpha_y * b.y));
                Vec2 corner[3] = { b, { b.x + n.x * AA_MARGIN, b.y + n.y * AA_MARGIN }, { b.x + m.x * AA_MARGIN, b.y + m.y * AA_MARGIN } };
                EmitPolygon(builder, wedge, paint, corner, 3, false);
                break;
            }
        }
    }

    static Outline ShapeOutline(const ShapeDesc& desc, float width, float height)
    {
        Outline outline;
        outline.center_x = width * 0.5f;
        outline.center_y = height * 0.5f;
        outline.half_x = width * 0.5f;
        outline.half_y = height * 0.5f;
        float figma_to_quadrant[4] = { desc.corner_radius[0], desc.corner_radius[1], desc.corner_radius[2], desc.corner_radius[3] };
        float scale = 1.0f;
        float top = figma_to_quadrant[0] + figma_to_quadrant[1];
        float bottom = figma_to_quadrant[3] + figma_to_quadrant[2];
        float left = figma_to_quadrant[0] + figma_to_quadrant[3];
        float right = figma_to_quadrant[1] + figma_to_quadrant[2];
        if (top > width) scale = fminf(scale, width / top);
        if (bottom > width) scale = fminf(scale, width / bottom);
        if (left > height) scale = fminf(scale, height / left);
        if (right > height) scale = fminf(scale, height / right);
        float limit = fminf(outline.half_x, outline.half_y);
        for (int q = 0; q < 4; ++q)
            outline.radius[q] = desc.kind == SHAPE_RECT ? fminf(fmaxf(figma_to_quadrant[q] * scale, 0.0f), limit) : 0.0f;
        return outline;
    }

    void BuildShapeVertices(const ShapeDesc& desc, float width, float height, std::vector<ShapeVertex>& out)
    {
        out.clear();
        if (!(width > 0.0f && height > 0.0f && isfinite(width) && isfinite(height)))
            return;
        Builder builder;
        builder.out = &out;
        builder.width = width;
        builder.height = height;
        builder.clipped = desc.clip.size() >= 6;
        builder.clip.count = 0;
        for (size_t i = 0; builder.clipped && i + 1 < desc.clip.size() && builder.clip.count < MAX_POLY_POINTS; i += 2)
        {
            builder.clip.points[builder.clip.count].x = desc.clip[i];
            builder.clip.points[builder.clip.count].y = height - desc.clip[i + 1];
            ++builder.clip.count;
        }
        if (desc.kind == SHAPE_PATH)
        {
            for (size_t i = 0; i < desc.fills.size(); ++i)
                BuildPath(builder, desc.fill_path, desc.fills[i]);
            for (size_t i = 0; i < desc.strokes.size(); ++i)
                BuildPath(builder, desc.stroke_path, desc.strokes[i]);
            return;
        }

        Outline shape = ShapeOutline(desc, width, height);
        bool outside_stroke = desc.stroke_align == STROKE_OUTSIDE && StrokeOutset(desc) > 0.0f;
        if (IsArc(desc))
        {
            for (size_t i = 0; i < desc.shadows.size(); ++i)
                BuildArcShadow(builder, desc, shape, desc.shadows[i]);
            for (size_t i = 0; i < desc.fills.size(); ++i)
            {
                if (desc.layer_blur > 0.0f)
                    BuildArcBlurredFill(builder, desc, shape, desc.fills[i]);
                else
                    BuildArc(builder, desc, shape, desc.fills[i], outside_stroke ? OUTSIDE_STROKE_UNDERLAP : 0.0f);
            }
            if (desc.stroke_width > 0.0f)
            {
                for (size_t i = 0; i < desc.strokes.size(); ++i)
                    BuildArcStroke(builder, desc, shape, desc.strokes[i]);
            }
            return;
        }

        for (size_t i = 0; i < desc.shadows.size(); ++i)
            BuildShadow(builder, desc, shape, desc.shadows[i]);
        Outline fill = outside_stroke ? Grow(shape, OUTSIDE_STROKE_UNDERLAP) : shape;
        for (size_t i = 0; i < desc.fills.size(); ++i)
            BuildFill(builder, desc, fill, desc.fills[i]);
        if (desc.stroke_width > 0.0f)
        {
            for (size_t i = 0; i < desc.strokes.size(); ++i)
                BuildStroke(builder, desc, shape, desc.strokes[i]);
        }
    }
}
