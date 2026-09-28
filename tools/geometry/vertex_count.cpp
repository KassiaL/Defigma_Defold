#include <defigma/shape_geometry.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>
#include <chrono>

static std::string read_line(FILE* f) { std::string s; int c; while ((c = fgetc(f)) != EOF && c != '\n') s.push_back((char)c); return s; }

int main(int argc, char** argv)
{
    FILE* f = fopen(argv[1], "r");
    size_t total = 0;
    double total_ms = 0;
    while (!feof(f))
    {
        std::string id = read_line(f);
        if (id.empty()) break;
        std::string shape = read_line(f), radius = read_line(f), fills = read_line(f), strokes = read_line(f), width = read_line(f), align = read_line(f), effects = read_line(f), path = read_line(f), clip = read_line(f), size = read_line(f);
        defigma::ShapeDesc desc;
        defigma::ResetShapeDesc(desc);
        desc.kind = defigma::ParseShapeKind(shape.c_str());
        sscanf(radius.c_str(), "%f %f %f %f", &desc.corner_radius[0], &desc.corner_radius[1], &desc.corner_radius[2], &desc.corner_radius[3]);
        desc.stroke_width = (float)atof(width.c_str());
        desc.stroke_align = defigma::ParseStrokeAlign(align.c_str());
        defigma::ParsePaints(fills.c_str(), desc.fills);
        defigma::ParsePaints(strokes.c_str(), desc.strokes);
        defigma::ParseEffects(effects.c_str(), desc);
        defigma::ParsePath(path.c_str(), desc);
        defigma::ParseClip(clip.c_str(), desc);
        float w, h; sscanf(size.c_str(), "%f %f", &w, &h);
        std::vector<defigma::ShapeVertex> out;
        auto t0 = std::chrono::high_resolution_clock::now();
        defigma::BuildShapeVertices(desc, w, h, out);
        double ms = std::chrono::duration<double, std::milli>(std::chrono::high_resolution_clock::now() - t0).count();
        total += out.size(); total_ms += ms;
        printf("%7zu %8.3fms %s\n", out.size(), ms, id.c_str());
    }
    printf("%7zu %8.3fms TOTAL\n", total, total_ms);
}
