#pragma once

#include <algorithm>
#include <cairo/cairo.h>
#include <hyprland/src/render/Renderer.hpp>

namespace OpenHDChrome {
inline constexpr double MARK_SPACE = 29;

// Paint at the monitor's device scale. The decoration caches the texture so
// resizing or a focus change is the only time we need to repaint the artwork.
inline auto create(int width, int height, double scale, double titleRight, bool mark, bool focused) {
    auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    auto* cr = cairo_create(surface);
    cairo_scale(cr, scale, scale);
    const double w = width / scale;
    const double h = height / scale;
    const double edge = 0.5 / scale;
    const double intensity = focused ? 1.0 : 0.46;

    // A cool inset seam under the title bar, clear of the rounded frame.
    cairo_set_line_width(cr, 1.0 / scale);
    cairo_set_source_rgba(cr, 0.20, 0.57, 0.75, 0.6 * intensity);
    cairo_move_to(cr, 12, h - edge);
    cairo_line_to(cr, w - 12, h - edge);
    cairo_stroke(cr);

    const double left = std::max(w * 0.305, titleRight + 12);
    const double right = w - 119;
    if (right - left >= 124 && h >= 34) {
        const double top = 1;
        const double bottom = std::min(h - 9, 26.0);
        const double bevel = bottom - top;
        cairo_move_to(cr, left, top);
        cairo_line_to(cr, right, top);
        cairo_line_to(cr, right - bevel, bottom);
        cairo_line_to(cr, left + bevel, bottom);
        cairo_close_path(cr);

        auto* metal = cairo_pattern_create_linear(0, top, 0, bottom);
        cairo_pattern_add_color_stop_rgba(metal, 0, 0.59, 0.69, 0.77, 0.62 * intensity);
        cairo_pattern_add_color_stop_rgba(metal, 0.27, 0.28, 0.36, 0.43, 0.66 * intensity);
        cairo_pattern_add_color_stop_rgba(metal, 1, 0.045, 0.11, 0.18, 0.94 * intensity);
        cairo_set_source(cr, metal);
        cairo_fill_preserve(cr);
        cairo_pattern_destroy(metal);

        cairo_set_source_rgba(cr, 0.62, 0.75, 0.85, 0.58 * intensity);
        cairo_stroke(cr);

        // Cyan channel and a brighter facet on the right.
        const double stripe = right - bevel;
        const double facet = std::min(112.0, (right - left - 2 * bevel) * 0.4);
        cairo_set_line_width(cr, 1.2);
        cairo_set_source_rgba(cr, 0.15, 0.80, 1.0, 0.84 * intensity);
        cairo_move_to(cr, left + bevel, bottom);
        cairo_line_to(cr, stripe, bottom);
        cairo_stroke(cr);

        cairo_set_source_rgba(cr, 0.08, 0.69, 1.0, 0.16 * intensity);
        cairo_move_to(cr, stripe - facet - 9, bottom);
        cairo_line_to(cr, stripe + 6, bottom);
        cairo_line_to(cr, stripe - 5, bottom + 8);
        cairo_line_to(cr, stripe - facet + 2, bottom + 8);
        cairo_close_path(cr);
        cairo_fill(cr);

        cairo_set_source_rgba(cr, 0.26, 0.85, 1.0, 0.92 * intensity);
        cairo_move_to(cr, stripe - facet, bottom);
        cairo_line_to(cr, stripe, bottom);
        cairo_line_to(cr, stripe - 5, bottom + 4);
        cairo_line_to(cr, stripe - facet + 5, bottom + 4);
        cairo_close_path(cr);
        cairo_fill(cr);
    }

    if (mark) {
        // A compact Albatross silhouette, centered beside the window title.
        cairo_translate(cr, 16, h / 2 - 5);
        cairo_set_source_rgba(cr, 0.88, 0.96, 1.0, focused ? 1.0 : 0.68);
        cairo_move_to(cr, 0, 0);
        cairo_curve_to(cr, 6, -1, 9, 1, 12, 4);
        cairo_curve_to(cr, 16, 1, 20, -1, 25, 0);
        cairo_curve_to(cr, 19, 1, 16, 4, 14, 7);
        cairo_line_to(cr, 12, 10);
        cairo_line_to(cr, 9, 8);
        cairo_line_to(cr, 10, 6);
        cairo_curve_to(cr, 7, 3, 4, 1, 0, 0);
        cairo_fill(cr);
    }

    cairo_destroy(cr);
    cairo_surface_flush(surface);
    auto texture = g_pHyprRenderer->createTexture(surface);
    cairo_surface_destroy(surface);
    return texture;
}
} // namespace OpenHDChrome
