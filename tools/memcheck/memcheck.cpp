#include <defigma/shape_geometry.h>

#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <atomic>
#include <memory>
#include <random>
#include <string>
#include <thread>
#include <vector>

extern "C" int DefigmaShape_Build(const char* shape, float radius_tl, float radius_tr, float radius_br, float radius_bl,
                                  const char* fills, const char* strokes, float stroke_width, const char* stroke_align,
                                  const char* effects, const char* path, const char* clip, float arc_start, float arc_sweep,
                                  float arc_ratio, float width, float height);
extern "C" void DefigmaShape_CopyVertices(float* out);

static const size_t FLOATS_PER_VERTEX = sizeof(defigma::ShapeVertex) / sizeof(float);

struct ShapeInput
{
    std::string id;
    std::string shape;
    float       radius[4];
    std::string fills;
    std::string strokes;
    float       stroke_width;
    std::string stroke_align;
    std::string effects;
    std::string path;
    std::string clip;
    float       arc[3];
    float       width;
    float       height;
};

struct BuildResult
{
    int      count;
    uint64_t hash;
};

static bool ReadLine(FILE* file, std::string& line)
{
    line.clear();
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n')
        line.push_back((char)c);
    return c != EOF || !line.empty();
}

static void ReadDump(const char* path, std::vector<ShapeInput>& shapes)
{
    FILE* file = fopen(path, "r");
    if (!file)
    {
        fprintf(stderr, "cannot open %s\n", path);
        exit(2);
    }
    std::string lines[12];
    for (;;)
    {
        if (!ReadLine(file, lines[0]) || lines[0].empty())
            break;
        for (int i = 1; i < 12; ++i)
            ReadLine(file, lines[i]);
        ShapeInput input;
        input.id = lines[0];
        input.shape = lines[1];
        sscanf(lines[2].c_str(), "%f %f %f %f", &input.radius[0], &input.radius[1], &input.radius[2], &input.radius[3]);
        input.fills = lines[3];
        input.strokes = lines[4];
        input.stroke_width = strtof(lines[5].c_str(), 0);
        input.stroke_align = lines[6];
        input.effects = lines[7];
        input.path = lines[8];
        input.clip = lines[9];
        sscanf(lines[10].c_str(), "%f %f", &input.width, &input.height);
        sscanf(lines[11].c_str(), "%f %f %f", &input.arc[0], &input.arc[1], &input.arc[2]);
        shapes.push_back(input);
    }
    fclose(file);
}

static uint64_t Hash(const void* data, size_t size)
{
    const uint8_t* bytes = (const uint8_t*)data;
    uint64_t hash = 1469598103934665603ull;
    for (size_t i = 0; i < size; ++i)
        hash = (hash ^ bytes[i]) * 1099511628211ull;
    return hash;
}

static BuildResult BuildThroughPlugin(const ShapeInput& input)
{
    BuildResult result;
    result.count = DefigmaShape_Build(input.shape.c_str(), input.radius[0], input.radius[1], input.radius[2], input.radius[3],
                                      input.fills.c_str(), input.strokes.c_str(), input.stroke_width, input.stroke_align.c_str(),
                                      input.effects.c_str(), input.path.c_str(), input.clip.c_str(), input.arc[0], input.arc[1], input.arc[2],
                                      input.width, input.height);
    result.hash = 0;
    if (result.count <= 0)
        return result;
    size_t float_count = (size_t)result.count * FLOATS_PER_VERTEX;
    std::unique_ptr<float[]> out(new float[float_count]);
    DefigmaShape_CopyVertices(out.get());
    result.hash = Hash(out.get(), float_count * sizeof(float));
    return result;
}

static bool ParseDesc(const ShapeInput& input, defigma::ShapeDesc& desc)
{
    defigma::ResetShapeDesc(desc);
    desc.kind = defigma::ParseShapeKind(input.shape.c_str());
    for (int i = 0; i < 4; ++i)
        desc.corner_radius[i] = input.radius[i];
    desc.stroke_width = input.stroke_width;
    desc.stroke_align = defigma::ParseStrokeAlign(input.stroke_align.c_str());
    desc.arc_start = input.arc[0];
    desc.arc_sweep = input.arc[1];
    desc.arc_ratio = input.arc[2];
    bool fills = defigma::ParsePaints(input.fills.c_str(), desc.fills);
    bool strokes = defigma::ParsePaints(input.strokes.c_str(), desc.strokes);
    bool effects = defigma::ParseEffects(input.effects.c_str(), desc);
    bool path = defigma::ParsePath(input.path.c_str(), desc);
    bool clip = defigma::ParseClip(input.clip.c_str(), desc);
    return fills && strokes && effects && path && clip;
}

static BuildResult BuildDirect(const ShapeInput& input, std::vector<defigma::ShapeVertex>& vertices)
{
    defigma::ShapeDesc desc;
    bool parsed = ParseDesc(input, desc);
    defigma::BuildShapeVertices(desc, input.width, input.height, vertices);
    BuildResult result;
    result.count = parsed ? (int)vertices.size() : -1;
    result.hash = vertices.empty() ? 0 : Hash(&vertices[0], vertices.size() * sizeof(defigma::ShapeVertex));
    return result;
}

static bool AllFinite(const std::vector<defigma::ShapeVertex>& vertices)
{
    for (size_t i = 0; i < vertices.size(); ++i)
    {
        const float* values = vertices[i].position;
        for (size_t k = 0; k < FLOATS_PER_VERTEX; ++k)
        {
            if (!isfinite(values[k]))
                return false;
        }
    }
    return true;
}

static void LoadDumps(int argc, char** argv, int first, std::vector<ShapeInput>& shapes)
{
    for (int i = first; i < argc; ++i)
        ReadDump(argv[i], shapes);
    if (shapes.empty())
    {
        fprintf(stderr, "no shapes in the dump files\n");
        exit(2);
    }
}

static int RunReal(int argc, char** argv, bool dump)
{
    int failures = 0;
    size_t total_shapes = 0;
    size_t total_vertices = 0;
    for (int i = 2; i < argc; ++i)
    {
        std::vector<ShapeInput> shapes;
        ReadDump(argv[i], shapes);
        size_t file_vertices = 0;
        uint64_t file_hash = 0;
        for (size_t s = 0; s < shapes.size(); ++s)
        {
            std::vector<defigma::ShapeVertex> vertices;
            BuildResult direct = BuildDirect(shapes[s], vertices);
            BuildResult plugin = BuildThroughPlugin(shapes[s]);
            if (dump)
                printf("%7d %016llx %s\n", direct.count, (unsigned long long)direct.hash, shapes[s].id.c_str());
            if (direct.count < 0)
            {
                printf("FAIL %s %s: does not parse\n", argv[i], shapes[s].id.c_str());
                ++failures;
            }
            if (direct.count != plugin.count || direct.hash != plugin.hash)
            {
                printf("FAIL %s %s: plugin %d vertices, direct %d\n", argv[i], shapes[s].id.c_str(), plugin.count, direct.count);
                ++failures;
            }
            if (vertices.size() % 3 != 0 || !AllFinite(vertices))
            {
                printf("FAIL %s %s: %zu vertices, not whole finite triangles\n", argv[i], shapes[s].id.c_str(), vertices.size());
                ++failures;
            }
            file_vertices += vertices.size();
            file_hash = file_hash * 31 + direct.hash;
        }
        if (!dump)
            printf("real %-60s %4zu shapes %7zu vertices %016llx\n", argv[i], shapes.size(), file_vertices, (unsigned long long)file_hash);
        total_shapes += shapes.size();
        total_vertices += file_vertices;
    }
    printf("real: %zu shapes, %zu vertices, %d failures\n", total_shapes, total_vertices, failures);
    return failures ? 1 : 0;
}

struct Fuzzer
{
    std::mt19937_64 rng;
    int             corruption;

    explicit Fuzzer(uint64_t seed) : rng(seed), corruption(0) {}

    int Int(int low, int high)
    {
        return std::uniform_int_distribution<int>(low, high)(rng);
    }

    bool Chance(int percent)
    {
        return Int(0, 99) < percent;
    }

    float Uniform(float low, float high)
    {
        return std::uniform_real_distribution<float>(low, high)(rng);
    }

    float SpecialFloat()
    {
        static const float values[] = { 0.0f, -0.0f, -1.0f, 1e-6f, 0.5f, 1.0f, 2.0f, 31.9f, 32.0f, 1e6f, 1e30f, -1e30f, FLT_MAX, -FLT_MAX, FLT_MIN, 1e-45f };
        switch (Int(0, 5))
        {
        case 0: return NAN;
        case 1: return Chance(50) ? INFINITY : -INFINITY;
        case 2: return values[Int(0, (int)(sizeof(values) / sizeof(values[0])) - 1)];
        default: return Uniform(-10.0f, 600.0f);
        }
    }

    float Size()
    {
        return Chance(80) ? Uniform(0.5f, 1200.0f) : SpecialFloat();
    }

    std::string NumberText(float low, float high)
    {
        static const char* specials[] = { "nan", "-nan", "inf", "-inf", "infinity", "1e999", "-1e999", "1e-999", "0", "-0", "1e38", "-1e38",
                                          "3.4e38", "0x1p3", "1e", "-", ".", "+5", "00012", "1.5.5", "true", "false", "null", "\"7\"", "[]", "{}",
                                          "[1,2]", "{\"a\":1}" };
        if (Chance(corruption))
            return specials[Int(0, (int)(sizeof(specials) / sizeof(specials[0])) - 1)];
        char buffer[64];
        snprintf(buffer, sizeof(buffer), Chance(50) ? "%.4g" : "%.9g", Uniform(low, high));
        return buffer;
    }

    std::string NumberArray(int count, float low, float high)
    {
        std::string text = "[";
        for (int i = 0; i < count; ++i)
        {
            if (i)
                text += ",";
            text += NumberText(low, high);
        }
        return text + "]";
    }

    int ArrayLength(int expected)
    {
        if (!Chance(corruption * 2))
            return expected;
        return Chance(70) ? Int(0, expected + 2) : Int(0, 40);
    }

    std::string MaybeWrongType(const std::string& value)
    {
        if (!Chance(corruption))
            return value;
        static const char* replacements[] = { "1", "\"x\"", "null", "true", "{}", "[]", "[[1,2,3,4]]", "{\"0\":1}" };
        return replacements[Int(0, (int)(sizeof(replacements) / sizeof(replacements[0])) - 1)];
    }

    std::string Field(const char* key, const std::string& value)
    {
        return std::string("\"") + key + "\":" + MaybeWrongType(value);
    }

    std::string Object(const std::vector<std::string>& fields)
    {
        std::string text = "{";
        bool first = true;
        for (size_t i = 0; i < fields.size(); ++i)
        {
            if (Chance(corruption))
                continue;
            if (!first)
                text += ",";
            text += fields[i];
            first = false;
        }
        return text + "}";
    }

    int StopCount()
    {
        int roll = Int(0, 99);
        if (roll < 3)
            return Int(500, 3000);
        if (roll < 10)
            return Int(30, 300);
        return Int(0, 6);
    }

    std::string Stops(bool radial)
    {
        int count = StopCount();
        std::string text = "[";
        float position = radial && Chance(30) ? 0.0f : Uniform(-0.2f, 0.5f);
        for (int i = 0; i < count; ++i)
        {
            if (i)
                text += ",";
            position += Chance(80) ? Uniform(0.0f, 1.5f / (float)(count + 1)) : Uniform(-0.3f, 3.0f);
            std::string stop = "[" + (Chance(95) ? std::to_string(position) : NumberText(-1e6f, 1e6f));
            int channels = ArrayLength(4);
            for (int c = 0; c < channels; ++c)
                stop += "," + NumberText(0.0f, 1.0f);
            text += stop + "]";
        }
        return text + "]";
    }

    std::string Transform()
    {
        if (Chance(50))
        {
            float angle = Uniform(0.0f, 6.2832f);
            float scale = Chance(80) ? Uniform(0.2f, 3.0f) : Uniform(1e-7f, 1e-3f);
            char buffer[256];
            snprintf(buffer, sizeof(buffer), "[%g,%g,%g,%g,%g,%g]", cosf(angle) * scale, -sinf(angle) * scale, Uniform(-1.0f, 1.0f),
                     sinf(angle) * scale, cosf(angle) * scale, Uniform(-1.0f, 1.0f));
            return buffer;
        }
        return NumberArray(ArrayLength(6), -3.0f, 3.0f);
    }

    std::string Paint()
    {
        static const char* types[] = { "solid", "linear", "radial", "angular", "", "SOLID" };
        int type = Chance(90) ? Int(0, 2) : Int(3, 5);
        std::vector<std::string> fields;
        fields.push_back(Field("type", std::string("\"") + types[type] + "\""));
        fields.push_back(Field("color", NumberArray(ArrayLength(4), 0.0f, 1.0f)));
        fields.push_back(Field("transform", Transform()));
        fields.push_back(Field("stops", Stops(type == 2)));
        return Object(fields);
    }

    std::string Paints()
    {
        int count = Chance(80) ? Int(0, 3) : Int(4, 12);
        std::string text = "[";
        for (int i = 0; i < count; ++i)
            text += (i ? "," : "") + Paint();
        return text + "]";
    }

    std::string Effect()
    {
        if (Chance(20))
            return Object({ Field("type", "\"layer_blur\""), Field("radius", NumberText(-5.0f, 200.0f)) });
        if (Chance(5))
            return Object({ Field("type", "\"inner_shadow\""), Field("radius", "4") });
        return Object({ Field("type", "\"drop_shadow\""), Field("offset", NumberArray(ArrayLength(2), -40.0f, 40.0f)),
                        Field("radius", NumberText(-5.0f, 150.0f)), Field("spread", NumberText(-60.0f, 60.0f)),
                        Field("color", NumberArray(ArrayLength(4), 0.0f, 1.0f)), Field("show_behind", Chance(50) ? "true" : "false") });
    }

    std::string Effects()
    {
        int count = Chance(85) ? Int(0, 3) : Int(4, 10);
        std::string text = "[";
        for (int i = 0; i < count; ++i)
            text += (i ? "," : "") + Effect();
        return text + "]";
    }

    int PointCount()
    {
        int roll = Int(0, 99);
        if (roll < 10)
            return Int(90, 400);
        if (roll < 20)
            return Int(0, 3);
        return Int(3, 64);
    }

    std::string RegularPolygon(int count, float width, float height)
    {
        float cx = Uniform(-0.2f, 1.2f) * width;
        float cy = Uniform(-0.2f, 1.2f) * height;
        float rx = Uniform(0.05f, 0.8f) * width;
        float ry = Uniform(0.05f, 0.8f) * height;
        float direction = Chance(50) ? 1.0f : -1.0f;
        std::string text = "[";
        for (int i = 0; i < count; ++i)
        {
            float angle = direction * 6.2831853f * (float)i / (float)count;
            char buffer[64];
            snprintf(buffer, sizeof(buffer), "%s%.3f,%.3f", i ? "," : "", cx + cosf(angle) * rx, cy + sinf(angle) * ry);
            text += buffer;
        }
        return text + "]";
    }

    std::string Polygon(float width, float height)
    {
        int count = PointCount();
        if (Chance(60) && count >= 3)
            return RegularPolygon(count, isfinite(width) ? width : 100.0f, isfinite(height) ? height : 100.0f);
        return NumberArray(ArrayLength(count * 2), -50.0f, 600.0f);
    }

    std::string Edges(float width, float height)
    {
        int count = Chance(85) ? Int(0, 80) : Int(80, 600);
        if (Chance(50))
        {
            std::string polygon = RegularPolygon(count > 2 ? count : 3, isfinite(width) ? width : 100.0f, isfinite(height) ? height : 100.0f);
            std::vector<float> points;
            for (const char* cursor = polygon.c_str() + 1; *cursor;)
            {
                char* end = 0;
                points.push_back(strtof(cursor, &end));
                cursor = *end ? end + 1 : end;
            }
            std::string text = "[";
            size_t n = points.size() / 2;
            for (size_t i = 0; i < n; ++i)
            {
                size_t j = (i + 1) % n;
                char buffer[128];
                snprintf(buffer, sizeof(buffer), "%s%g,%g,%g,%g", i ? "," : "", points[i * 2], points[i * 2 + 1], points[j * 2], points[j * 2 + 1]);
                text += buffer;
            }
            return text + "]";
        }
        return NumberArray(ArrayLength(count * 4), -50.0f, 600.0f);
    }

    std::string PathGeometry(float width, float height)
    {
        int polygons = Chance(85) ? Int(0, 6) : Int(7, 40);
        std::string list = "[";
        for (int i = 0; i < polygons; ++i)
            list += (i ? "," : "") + Polygon(width, height);
        list += "]";
        return Object({ Field("polygons", list), Field("edges", Edges(width, height)) });
    }

    std::string Path(float width, float height)
    {
        return Object({ Field("fill", PathGeometry(width, height)), Field("stroke", PathGeometry(width, height)) });
    }

    std::string Clip(float width, float height)
    {
        int count = PointCount();
        if (Chance(70) && count >= 3)
            return RegularPolygon(count, isfinite(width) ? width : 100.0f, isfinite(height) ? height : 100.0f);
        return NumberArray(ArrayLength(count * 2), -50.0f, 600.0f);
    }

    std::string Text(const std::string& valid)
    {
        return Chance(10) ? std::string() : valid;
    }

    ShapeInput Generate()
    {
        static const char* kinds[] = { "rect", "ellipse", "path", "", "circle", "RECT" };
        static const char* aligns[] = { "inside", "center", "outside", "", "middle" };
        corruption = Chance(60) ? 0 : Int(1, 8);
        ShapeInput input;
        input.id = "generated";
        input.shape = kinds[Chance(90) ? Int(0, 2) : Int(3, 5)];
        for (int i = 0; i < 4; ++i)
            input.radius[i] = Chance(70) ? Uniform(0.0f, 80.0f) : SpecialFloat();
        input.width = Size();
        input.height = Size();
        input.fills = Text(Paints());
        input.strokes = Text(Paints());
        input.stroke_width = Chance(70) ? Uniform(0.0f, 30.0f) : SpecialFloat();
        input.stroke_align = aligns[Chance(90) ? Int(0, 2) : Int(3, 4)];
        input.effects = Text(Effects());
        input.path = input.shape == "path" || Chance(10) ? Text(Path(input.width, input.height)) : std::string();
        input.clip = Chance(40) ? Text(Clip(input.width, input.height)) : std::string();
        input.arc[0] = Chance(80) ? Uniform(-720.0f, 720.0f) : SpecialFloat();
        input.arc[1] = Chance(30) ? 100.0f : (Chance(80) ? Uniform(-10.0f, 110.0f) : SpecialFloat());
        input.arc[2] = Chance(40) ? 0.0f : (Chance(80) ? Uniform(-10.0f, 110.0f) : SpecialFloat());
        return input;
    }

    void MutateText(std::string& text)
    {
        static const char alphabet[] = "[]{}\",:0123456789.-+eE \\\ttrufalsnix";
        int edits = Int(1, 6);
        for (int e = 0; e < edits; ++e)
        {
            size_t size = text.size();
            switch (Int(0, 7))
            {
            case 0:
                text.resize(size ? (size_t)Int(0, (int)size - 1) : 0);
                break;
            case 1:
                if (size)
                    text[(size_t)Int(0, (int)size - 1)] = alphabet[Int(0, (int)sizeof(alphabet) - 2)];
                break;
            case 2:
                text.insert((size_t)Int(0, (int)size), 1, alphabet[Int(0, (int)sizeof(alphabet) - 2)]);
                break;
            case 3:
                if (size)
                    text[(size_t)Int(0, (int)size - 1)] = (char)Int(1, 255);
                break;
            case 4:
                if (size)
                {
                    size_t start = (size_t)Int(0, (int)size - 1);
                    text.erase(start, (size_t)Int(1, 16));
                }
                break;
            case 5:
                if (size)
                {
                    size_t start = (size_t)Int(0, (int)size - 1);
                    std::string piece = text.substr(start, (size_t)Int(1, 64));
                    text.insert((size_t)Int(0, (int)size), piece);
                }
                break;
            case 6:
            {
                size_t start = size ? (size_t)Int(0, (int)size - 1) : 0;
                while (start < text.size() && !(text[start] >= '0' && text[start] <= '9'))
                    ++start;
                size_t end = start;
                while (end < text.size() && strchr("0123456789.e-", text[end]))
                    ++end;
                text.replace(start, end - start, NumberText(-1e4f, 1e4f));
                break;
            }
            default:
                text.insert((size_t)Int(0, (int)size), std::string((size_t)Int(1, 40), Chance(50) ? '[' : '{'));
                break;
            }
        }
    }

    ShapeInput Mutate(const ShapeInput& source)
    {
        ShapeInput input = source;
        std::string* texts[] = { &input.fills, &input.strokes, &input.effects, &input.path, &input.clip };
        for (int i = 0; i < 5; ++i)
        {
            if (Chance(35))
                MutateText(*texts[i]);
        }
        if (Chance(15))
            input.width = Size();
        if (Chance(15))
            input.height = Size();
        if (Chance(10))
            input.radius[Int(0, 3)] = SpecialFloat();
        if (Chance(10))
            input.stroke_width = SpecialFloat();
        if (Chance(5))
            input.shape = Chance(50) ? "path" : "ellipse";
        return input;
    }
};

static std::vector<std::string> EdgeCaseTexts()
{
    std::vector<std::string> texts = {
        "", "[", "]", "{", "}", "[,]", "[1,]", "{\"a\"}", "{\"a\":}", "{\"a\":1,}", "\"", "\"\\", "\\", "[\"\\", "[\"abc", "{\"type\":\"solid\"}",
        "[{}]", "[{\"type\":1}]", "[{\"type\":\"solid\"}]", "[{\"type\":\"solid\",\"color\":1}]", "[{\"type\":\"solid\",\"color\":[]}]",
        "[{\"type\":\"solid\",\"color\":[1,1,1]}]", "[{\"type\":\"linear\"}]", "[{\"type\":\"linear\",\"transform\":[1,0,0,0,1,0]}]",
        "[{\"type\":\"linear\",\"transform\":[1,0],\"stops\":[[0,1,1,1,1]]}]", "[{\"type\":\"linear\",\"transform\":[1,0,0,0,1,0],\"stops\":[[]]}]",
        "[{\"type\":\"radial\",\"transform\":[1,0,0,0,1,0],\"stops\":[1,2]}]", "[{\"type\":\"radial\",\"transform\":[1,0,0,0,1,0],\"stops\":[[0.5]]}]",
        "[{\"type\":\"radial\",\"transform\":\"x\",\"stops\":[[0,1,1,1,1]]}]", "[{\"type\":\"drop_shadow\"}]",
        "[{\"type\":\"drop_shadow\",\"offset\":[1]}]", "[{\"type\":\"drop_shadow\",\"offset\":[1,2],\"color\":[1]}]",
        "[{\"type\":\"drop_shadow\",\"offset\":[1,2],\"color\":[0,0,0,1],\"radius\":nan}]", "[{\"type\":\"layer_blur\",\"radius\":inf}]",
        "{\"fill\":1}", "{\"fill\":{\"polygons\":1,\"edges\":\"x\"}}", "{\"fill\":{\"polygons\":[1,2,[3]],\"edges\":[1,2,3]}}",
        "[nan,nan,nan,nan,nan,nan]", "[1,2,3,4,5]", "[1e999,-1e999,0,0,5,5]", "nul", "tru", "fals", "-", "1e", "0x", "\x01\x02", "\xff\xfe",
    };
    texts.push_back(std::string(1000000, '['));
    texts.push_back(std::string(1000000, '{'));
    std::string nested;
    for (int i = 0; i < 200000; ++i)
        nested += "{\"a\":[";
    texts.push_back(nested);
    texts.push_back("[" + std::string(2000000, ' ') + "1]");
    return texts;
}

static void RunCase(const ShapeInput& input, size_t& parsed, size_t& vertices)
{
    std::vector<defigma::ShapeVertex> built;
    BuildResult direct = BuildDirect(input, built);
    BuildResult plugin = BuildThroughPlugin(input);
    if (direct.count >= 0)
        ++parsed;
    vertices += built.size();
    if (built.size() % 3 != 0 || (direct.count >= 0 && (direct.count != plugin.count || direct.hash != plugin.hash)))
    {
        fprintf(stderr, "FAIL fuzz: direct %d plugin %d (%zu vertices)\n", direct.count, plugin.count, built.size());
        exit(1);
    }
}

static int RunFuzz(int argc, char** argv)
{
    int iterations = atoi(argv[2]);
    uint64_t seed = strtoull(argv[3], 0, 10);
    std::vector<ShapeInput> shapes;
    LoadDumps(argc, argv, 4, shapes);
    Fuzzer fuzzer(seed);
    size_t parsed = 0;
    size_t vertices = 0;
    size_t cases = 0;

    std::vector<std::string> edge_texts = EdgeCaseTexts();
    for (size_t t = 0; t < edge_texts.size(); ++t)
    {
        for (int field = 0; field < 5; ++field)
        {
            ShapeInput input = shapes[(t * 5 + field) % shapes.size()];
            std::string* texts[] = { &input.fills, &input.strokes, &input.effects, &input.path, &input.clip };
            *texts[field] = edge_texts[t];
            RunCase(input, parsed, vertices);
            ++cases;
        }
    }

    for (int i = 0; i < iterations; ++i)
    {
        ShapeInput input = fuzzer.Chance(50) ? fuzzer.Generate() : fuzzer.Mutate(shapes[(size_t)fuzzer.Int(0, (int)shapes.size() - 1)]);
        RunCase(input, parsed, vertices);
        ++cases;
    }
    printf("fuzz: %zu cases (seed %llu), %zu parsed, %zu vertices, 0 failures\n", cases, (unsigned long long)seed, parsed, vertices);
    return 0;
}

static int RunThreads(int argc, char** argv)
{
    int thread_count = atoi(argv[2]);
    int rounds = atoi(argv[3]);
    std::vector<ShapeInput> shapes;
    LoadDumps(argc, argv, 4, shapes);
    std::vector<BuildResult> expected(shapes.size());
    for (size_t i = 0; i < shapes.size(); ++i)
        expected[i] = BuildThroughPlugin(shapes[i]);

    std::atomic<int> mismatches(0);
    std::atomic<size_t> builds(0);
    std::vector<std::thread> threads;
    for (int t = 0; t < thread_count; ++t)
    {
        threads.emplace_back([&, t]() {
            for (int r = 0; r < rounds; ++r)
            {
                for (size_t k = 0; k < shapes.size(); ++k)
                {
                    size_t index = (k * (size_t)(2 * t + 1) + (size_t)t * 7) % shapes.size();
                    BuildResult result = BuildThroughPlugin(shapes[index]);
                    if (result.count != expected[index].count || result.hash != expected[index].hash)
                        ++mismatches;
                    ++builds;
                }
            }
        });
    }
    for (size_t t = 0; t < threads.size(); ++t)
        threads[t].join();
    printf("threads: %d threads, %zu builds, %d mismatches\n", thread_count, builds.load(), mismatches.load());
    return mismatches.load() ? 1 : 0;
}

int main(int argc, char** argv)
{
    if (argc >= 3 && strcmp(argv[1], "real") == 0)
        return RunReal(argc, argv, false);
    if (argc >= 3 && strcmp(argv[1], "dump") == 0)
        return RunReal(argc, argv, true);
    if (argc >= 5 && strcmp(argv[1], "fuzz") == 0)
        return RunFuzz(argc, argv);
    if (argc >= 5 && strcmp(argv[1], "threads") == 0)
        return RunThreads(argc, argv);
    fprintf(stderr, "usage: memcheck real <dump>... | dump <dump>... | fuzz <iterations> <seed> <dump>... | threads <threads> <rounds> <dump>...\n");
    return 2;
}
