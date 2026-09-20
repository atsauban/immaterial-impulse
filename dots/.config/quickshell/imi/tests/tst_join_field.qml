import QtQuick
import QtTest
import "../modules/common/functions/join_field.js" as JoinField

// The join's field on the CPU, against the shader's paint: a capture is the
// oracle for both, and the pinned one is the dock in the review sandbox
// (2026-09-20, nested Hyprland, red/white 4 px stripes as the wallpaper) -
// plate 322x60 at rest on a 2 px bottom band, corners 23, meniscus 45 x 1.1.
TestCase {
    name: "JoinField"

    // The field's uniforms for that capture, in the field item's own pixels:
    // pad = ceil(49.5) + 2 = 52 either side, the box 426x62 with the band's
    // inner edge 60 rows down and two rows of band under it.
    function dockAtRest() {
        return {
            pillCenter: { x: 213, y: 30 }, pillSize: { x: 322, y: 60 },
            pillRadii: { x: 23, y: 23, z: 23, w: 23 },
            bandNormal: { x: 0, y: 1 }, bandOrigin: 60,
            blend: 49.5, waistHalf: 322 * 2.5 / 2, waistCenter: 213,
            softness: 0.75, reach: 2, bulge: 0, bulgeHalf: 322 * 0.4, climbFall: 0
        };
    }

    // How far past the plate's right side the paint reaches on a row.
    function rightExtent(rects, row, plateRight) {
        for (const r of rects) if (row >= r.y && row < r.y + r.height) return r.x + r.width - plateRight;
        return null;
    }

    function test_the_profile_is_the_shaders_within_a_pixel() {
        const rects = JoinField.outline(dockAtRest(), 426, 62, 64);
        // Row (of the box) -> pixels painted past the plate's side, read off
        // the capture (the plate's side at x 1120 of the screen, the box's
        // top at 1018).
        const measured = { 23: 0, 29: 1, 34: 2, 38: 3, 41: 4, 44: 5, 46: 6, 48: 7, 50: 8, 51: 9,
                           53: 10, 54: 11, 55: 13, 56: 14, 57: 16, 58: 18, 59: 21 };
        for (const row in measured) {
            const got = rightExtent(rects, Number(row), 52 + 322);
            verify(got !== null, "row " + row + " is painted");
            verify(Math.abs(got - measured[row]) <= 1, "row " + row + ": " + got + " against " + measured[row]);
        }
        // The fillet's spread at the band is what the strip undershot, and its
        // climb is what the strip's height overshot at that width.
        verify(rightExtent(rects, 59, 374) >= 20);
        compare(rightExtent(rects, 23, 374), 0);
    }

    function test_the_band_rows_are_left_to_the_band() {
        const rects = JoinField.outline(dockAtRest(), 426, 62, 64);
        for (const r of rects) verify(r.y + r.height <= 60, "no rectangle reaches into the band");
        // ...and the plate's top corners round off, so the first rows are
        // narrower than the plate.
        verify(rects[0].width < 322);
        compare(rects[0].y, 0);
    }

    function test_the_outline_is_symmetric_about_the_waist() {
        const rects = JoinField.outline(dockAtRest(), 426, 62, 64);
        for (const r of rects) compare(r.x - 52, 374 - (r.x + r.width), "row " + r.y);
    }

    function test_a_pool_that_is_too_small_widens_rather_than_drops() {
        const full = JoinField.outline(dockAtRest(), 426, 62, 0);
        verify(full.length > 8, "the dock's outline is more than eight rectangles: " + full.length);
        verify(full.length <= 64, "and fits the frame's pool: " + full.length);
        const few = JoinField.outline(dockAtRest(), 426, 62, 8);
        compare(few.length, 8);
        for (const r of full) {
            let covered = false;
            for (const c of few)
                covered = covered || (r.x >= c.x && r.y >= c.y && r.x + r.width <= c.x + c.width && r.y + r.height <= c.y + c.height);
            verify(covered, "row " + r.y + " is still under the region");
        }
    }

    function test_a_side_edge_is_the_same_shape_turned() {
        const u = dockAtRest();
        // The same plate standing against a right-hand band: axes swapped,
        // the normal pointing at the band.
        const turned = {
            pillCenter: { x: 30, y: 213 }, pillSize: { x: 60, y: 322 },
            pillRadii: u.pillRadii, bandNormal: { x: 1, y: 0 }, bandOrigin: 60,
            blend: u.blend, waistHalf: u.waistHalf, waistCenter: 213,
            softness: u.softness, reach: u.reach, bulge: 0, bulgeHalf: u.bulgeHalf, climbFall: 0
        };
        const flat = JoinField.outline(u, 426, 62, 64);
        const tall = JoinField.outline(turned, 62, 426, 64);
        compare(tall.length, flat.length);
        for (let i = 0; i < flat.length; i++) {
            compare(tall[i].x, flat[i].y, "rect " + i);
            compare(tall[i].y, flat[i].x, "rect " + i);
            compare(tall[i].width, flat[i].height, "rect " + i);
            compare(tall[i].height, flat[i].width, "rect " + i);
        }
    }

    function test_nothing_is_painted_where_the_neck_has_let_go() {
        // A lifted plate with no blend: the rows between it and the band are
        // empty, the plate's own rows are not.
        const u = dockAtRest();
        u.blend = 0;
        u.pillCenter = { x: 213, y: 20 };
        u.reach = 0;
        const rects = JoinField.outline(u, 426, 62, 64);
        for (const r of rects) verify(r.y + r.height <= 50, "row " + r.y + " is the plate's");
        verify(rects.length > 0);
    }
}
