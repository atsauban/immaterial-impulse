import QtQuick
import QtTest
import "../services/frame_geometry.js" as Geo

// Frame mode's arithmetic, without the shell.
TestCase {
    name: "FrameGeometry"

    function test_band_thickness_is_a_hairline_at_zero() {
        // 0 used to mean the gap, and a user read it as "thinnest" and got a
        // five-pixel ledge under a floating bar.
        compare(Geo.bandThickness(0), 1);
        compare(Geo.bandThickness(12), 12);
        compare(Geo.bandThickness("8"), 8);
        compare(Geo.bandThickness(null), 1);
        compare(Geo.bandThickness(-4), 1);
    }

    function test_only_a_covering_bars_edge_is_the_gap() {
        // Hug covers its strip, so the band under the plate has to reach the
        // windows: the gap. Every other edge, and every floating bar's edge,
        // is the configured thickness.
        compare(Geo.bandExtent("top", "top", 2, 5, true), 5);
        compare(Geo.bandExtent("top", "top", 2, 5, false), 2);
        compare(Geo.bandExtent("bottom", "top", 2, 5, true), 2);
        compare(Geo.bandExtent("left", "top", 2, 5, true), 2);
        // No gap to speak of: the thickness stands in.
        compare(Geo.bandExtent("top", "top", 2, 0, true), 2);
    }

    function test_a_covering_bars_edge_is_its_zone_plus_the_gap() {
        // The compositor reserves the bar's zone and then its outer gap:
        // windows start at zone + gap, so that is where the frame ends.
        compare(Geo.edgeInsets("top", 40, 2, 5, true), { top: 45, left: 2, right: 2, bottom: 2 });
        compare(Geo.edgeInsets("bottom", 40, 2, 5, true), { top: 2, left: 2, right: 2, bottom: 45 });
        compare(Geo.edgeInsets("top", "40", 2, 5, true), { top: 45, left: 2, right: 2, bottom: 2 });
    }

    function test_a_floating_bars_edge_is_the_band_like_any_other() {
        // The bar is inside the frame, not part of it: the border runs along
        // the screen edge on all four sides and the bar floats within it. A
        // band under a floating bar read as a stray line below it.
        const insets = Geo.edgeInsets("top", 40, 2, 5, false);
        compare(insets, { top: 2, left: 2, right: 2, bottom: 2 });
        compare(Geo.bandStart("top", "top", 40, false), 0);
        compare(Geo.bandStart("top", "top", 40, true), 40);
    }

    function test_the_dock_is_no_occupant_of_the_frame() {
        // The bar is the frame's only occupant. The dock meets the band on
        // its own terms (dock_geometry.js: on it, or a gap above it), so the
        // frame's inner corner on the dock's edge is at the band - a fillet
        // at the dock's inset arced into wallpaper, and a band as tall as
        // the dock's strip was a border with a pill lost in it.
        // The dock's edge is the band, whatever the dock is doing there: no
        // reader takes a dock zone, and the insets on the three free edges
        // are the band alone with a covering bar or without one.
        const covered = Geo.edgeInsets("top", 40, 2, 5, true);
        const floating = Geo.edgeInsets("top", 40, 2, 5, false);
        for (const edge of ["left", "right", "bottom"]) {
            compare(covered[edge], 2, edge + " is the band under a covering bar");
            compare(floating[edge], 2, edge + " is the band under a floating one");
        }
        verify(Geo.bandOffset === undefined, "no dock offset to add");
    }

    function test_each_fillet_sits_at_its_inner_corner() {
        const insets = Geo.edgeInsets("top", 40, 5, 5, true);
        compare(Geo.cornerMargins("topLeft", insets), { left: 5, top: 45, right: 0, bottom: 0 });
        compare(Geo.cornerMargins("topRight", insets), { left: 0, top: 45, right: 5, bottom: 0 });
        compare(Geo.cornerMargins("bottomLeft", insets), { left: 5, top: 0, right: 0, bottom: 5 });
        compare(Geo.cornerMargins("bottomRight", insets), { left: 0, top: 0, right: 5, bottom: 5 });
        compare(Geo.cornerMargins("nowhere", insets), { left: 0, top: 0, right: 0, bottom: 0 });
    }

    function test_the_inner_radius_is_the_window_rounding() {
        // The fillet's box sits at the inset already; its arc is concentric
        // with the window's corner only when the radii are equal.
        compare(Geo.innerRadius(12), 12);
        compare(Geo.innerRadius(0), 0);
        compare(Geo.innerRadius(null), 0);
        compare(Geo.innerRadius(-3), 0);
    }

    function test_a_band_starts_under_the_bars_plate_and_at_the_screen_edge_elsewhere() {
        compare(Geo.bandStart("top", "top", 40, true), 40);
        compare(Geo.bandStart("bottom", "top", 40, true), 0);
        compare(Geo.bandStart("bottom", "bottom", 40, true), 40);
        compare(Geo.bandStart("left", "top", 40, true), 0);
    }

    function test_the_horizontal_bands_span_the_width_and_the_side_bands_run_between_them() {
        // Covering bar on top, band 2, gap 5: the top band sits under the
        // plate and is the gap thick, the bottom band is at the screen edge
        // and 2 thick, both the full width; the side bands start where the
        // top band ends (40 + 5) and stop where the bottom band starts (2).
        compare(Geo.bandMargins("top", "top", 40, 2, 5, true), { top: 40, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("bottom", "top", 40, 2, 5, true), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "top", 40, 2, 5, true), { top: 45, bottom: 2, left: 0, right: 0 });
        compare(Geo.bandMargins("right", "top", 40, 2, 5, true), { top: 45, bottom: 2, left: 0, right: 0 });
        // Bar at the bottom: mirrored.
        compare(Geo.bandMargins("bottom", "bottom", 40, 2, 5, true), { top: 0, bottom: 40, left: 0, right: 0 });
        compare(Geo.bandMargins("top", "bottom", 40, 2, 5, true), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "bottom", 40, 2, 5, true), { top: 2, bottom: 45, left: 0, right: 0 });
        // A FLOATING bar: every band at the screen edge, every one the
        // configured thickness, so the border is uniform and the bar is
        // inside it.
        compare(Geo.bandMargins("top", "top", 40, 2, 5, false), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "top", 40, 2, 5, false), { top: 2, bottom: 2, left: 0, right: 0 });
    }

    function test_no_two_bands_overlap() {
        // The frame's colour is translucent: a corner painted by two bands
        // is darker than the frame. Lay the four bands out on a 100x80
        // screen, bar on top, band 5, and check every pair.
        const band = 2, gap = 5, W = 100, H = 80;
        const rects = ["top", "bottom", "left", "right"].map(edge => {
            const m = Geo.bandMargins(edge, "top", 40, band, gap, true);
            const extent = Geo.bandExtent(edge, "top", band, gap, true);
            const horizontal = edge === "top" || edge === "bottom";
            return {
                edge,
                x: horizontal ? m.left : (edge === "left" ? 0 : W - extent),
                y: horizontal ? (edge === "top" ? m.top : H - m.bottom - extent) : m.top,
                w: horizontal ? W - m.left - m.right : extent,
                h: horizontal ? extent : H - m.top - m.bottom,
            };
        });
        for (let i = 0; i < rects.length; i++)
            for (let j = i + 1; j < rects.length; j++) {
                const a = rects[i], b = rects[j];
                const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
                verify(!overlap, a.edge + " and " + b.edge + " overlap");
            }
        // ...and they still meet: the left band runs from the top band's
        // bottom to the bottom band's top.
        compare(rects[2].y, rects[0].y + rects[0].h);
        compare(rects[2].y + rects[2].h, rects[1].y);
    }
}
