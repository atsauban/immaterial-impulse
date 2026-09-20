import QtQuick
import QtTest
import "../services/frame_geometry.js" as Geo

// Frame mode's arithmetic, without the shell.
TestCase {
    name: "FrameGeometry"

    function test_band_thickness_is_a_hairline_at_zero_and_never_thinner_than_draws() {
        // 0 used to mean the gap, and a user read it as "thinnest" and got a
        // five-pixel ledge under a floating bar. The floor is two pixels
        // because a one-pixel layer surface draws nothing at all here
        // (measured with the band tinted red), which is what made an attached
        // dock look like it sat a pixel above the screen's edge.
        compare(Geo.bandThickness(0), 2);
        compare(Geo.bandThickness(1), 2);
        compare(Geo.bandThickness(12), 12);
        compare(Geo.bandThickness("8"), 8);
        compare(Geo.bandThickness(null), 2);
        compare(Geo.bandThickness(-4), 2);
    }

    function test_a_covering_bars_edge_has_no_band() {
        // The bar's own plate is the border there: opaque, both screen edges,
        // and already the thickest thing on that side. A band under it made
        // the frame fifty pixels thick on one edge and one on the other three.
        compare(Geo.bandExtent("top", "top", 2, 5, true), 0);
        compare(Geo.bandExtent("bottom", "top", 2, 5, true), 2);
        compare(Geo.bandExtent("left", "top", 2, 5, true), 2);
        // A floating bar is inside the frame, so its edge is a band like the rest.
        compare(Geo.bandExtent("top", "top", 2, 5, false), 2);
        compare(Geo.bandExtent("left", "top", 2, 5, false), 2);
    }

    function test_the_insets_say_where_windows_start() {
        // A covering bar's edge: the zone the compositor reserves and then
        // its outer gap. Every other edge, a floating bar's included: the band.
        compare(Geo.edgeInsets("top", 40, 2, 5, true), { top: 45, left: 2, right: 2, bottom: 2 });
        compare(Geo.edgeInsets("bottom", 40, 2, 5, true), { top: 2, left: 2, right: 2, bottom: 45 });
        compare(Geo.edgeInsets("top", 40, 2, 5, false), { top: 2, left: 2, right: 2, bottom: 2 });
        compare(Geo.edgeInsets("top", "40", 2, 5, true), { top: 45, left: 2, right: 2, bottom: 2 });
    }

    function test_the_dock_is_no_occupant_of_the_frame() {
        // The dock's edge is the band, whatever the dock is doing there: no
        // reader takes a dock zone, and the three free edges are the band
        // alone with a covering bar or without one.
        const covered = Geo.edgeInsets("top", 40, 2, 5, true);
        const floating = Geo.edgeInsets("top", 40, 2, 5, false);
        for (const edge of ["left", "right", "bottom"]) {
            compare(covered[edge], 2, edge + " is the band under a covering bar");
            compare(floating[edge], 2, edge + " is the band under a floating one");
        }
        verify(Geo.bandOffset === undefined, "no dock offset to add");
    }

    function test_the_frame_has_no_fillet_of_its_own() {
        // The frame's corners are the SCREEN's corners - a monitor's black
        // bezel, which ScreenCorners draws in both modes - so nothing here
        // sizes or places a frame-coloured one. The fillet belonged to the
        // model where one edge was a whole bar zone thick.
        verify(Geo.innerRadius === undefined);
        verify(Geo.cornerMargins === undefined);
        verify(Geo.cornerThickness === undefined);
    }

    function test_every_band_sits_at_its_screen_edge() {
        // Covering bar on top, band 2: no top band at all, the side bands run
        // from the screen's top edge to the bottom band.
        compare(Geo.bandMargins("top", "top", 2, 5, true), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("bottom", "top", 2, 5, true), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "top", 2, 5, true), { top: 0, bottom: 2, left: 0, right: 0 });
        compare(Geo.bandMargins("right", "top", 2, 5, true), { top: 0, bottom: 2, left: 0, right: 0 });
        // Floating bar: four bands, the side ones between the horizontal ones.
        compare(Geo.bandMargins("top", "top", 2, 5, false), { top: 0, bottom: 0, left: 0, right: 0 });
        compare(Geo.bandMargins("left", "top", 2, 5, false), { top: 2, bottom: 2, left: 0, right: 0 });
        // Bar at the bottom, covering: the gap is at the bottom instead.
        compare(Geo.bandMargins("left", "bottom", 2, 5, true), { top: 2, bottom: 0, left: 0, right: 0 });
    }

    function test_no_two_bands_overlap() {
        // The frame's colour is translucent: a corner painted by two bands is
        // darker than the frame. Lay the four out on a 100x80 screen, floating
        // bar on top, band 2, and check every pair.
        const band = 2, gap = 5, W = 100, H = 80;
        const rects = ["top", "bottom", "left", "right"].map(edge => {
            const m = Geo.bandMargins(edge, "top", band, gap, false);
            const extent = Geo.bandExtent(edge, "top", band, gap, false);
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

    function test_the_join_is_drawn_against_the_bands_inner_edge() {
        // A 2 px band on a 5120x1440 screen: the dock's plate bottom lands on
        // 1438, which is where the half-plane has to be.
        compare(Geo.joinBandEdge("bottom", 2, 5120, 1440), 1438);
        compare(Geo.joinBandEdge("top", 2, 5120, 1440), 2);
        compare(Geo.joinBandEdge("left", 2, 5120, 1440), 2);
        compare(Geo.joinBandEdge("right", 2, 5120, 1440), 5118);
        // The meniscus' own outline is the field's business (join_field.js,
        // tst_join_field.qml): the frame no longer guesses a strip for it.
        verify(Geo.joinFlareRect === undefined);
    }
}
