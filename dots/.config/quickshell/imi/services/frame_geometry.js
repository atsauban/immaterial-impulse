.pragma library

// Frame mode's arithmetic (docs/proposals/frame-mode.md, "a single geometry
// authority"): which edge is how thick, where each band starts and stops,
// and where the four inner fillets sit. Pure, so tests/tst_frame_geometry.qml
// can pin it; FrameGeometry.qml binds it to the config and the tokens.
//
// The frame is a border of `thickness` at the screen edge on every edge, with
// ONE exception: the bar's edge, WHEN the bar's plate covers that strip edge
// to edge - the Hug style, and only it (Float and Float Islands inset their
// plates by the gap, Islands and M3 paint no strip at all). There the bar IS
// the frame's edge: the band continues under the plate, from the plate's
// bottom to where windows start, and the frame's inner corner is the bar's
// zone plus that gap. A band placed under a bar that does NOT cover its strip
// read as a stray line below a floating bar rather than a border around it,
// which is the whole point of the mode.
//
// Every other edge is the band alone - the dock included. The dock is a pill
// in the middle of its strip, not a plate: modelling it as an occupant put a
// band above its zone (a line across the wallpaper with the dock floating
// under it), and then made the band its whole strip (a border as tall as the
// dock, mostly empty on both sides of the pill). The band stays thin and the
// dock meets it on the dock's own terms (dock_geometry.js `frameOffset`):
// sitting on the band as a tab, or floating a gap above it.

// The band's thickness: the configured pixels, or a hairline when 0. The gap
// was 0's meaning until a user read 0 as "thinnest" and got the gap's five
// pixels, which on a floating bar is a visible ledge. The gap is still what
// the bar's edge needs when the bar covers its strip (`bandExtent`), because
// there the band has to reach from the plate to the windows; nothing else has
// to reach anything.
function bandThickness(configured, gapsOut) {
    var c = Number(configured) || 0;
    return c > 0 ? c : 1;
}

// The band's thickness ON its own edge: NOTHING on a covering bar's edge,
// because there the bar's own plate is the border - it is opaque, it reaches
// both screen edges, and it is already the thickest thing on that side. A
// band under it made the frame fifty pixels thick on one edge and one pixel
// on the other three, which is not a border, and the fillet that tried to
// round that junction was the blob at each end of the bar.
function bandExtent(edge, barEdge, band, gapsOut, barCovers) {
    if (barCovers && edge === barEdge) return 0;
    return Number(band) || 0;
}

// How far the frame reaches in on each screen edge, i.e. where its inner
// corner is. A covering bar's edge is its zone plus the gap: the compositor
// reserves the zone and THEN applies the gap, so that is where windows start
// (measured: modelling it as the painted height left a gap-wide wallpaper
// stripe under the bar). Every other edge - a floating bar's included, where
// the bar sits inside the frame rather than being part of it - is the band.
// Not the dock's zone: the frame's inner corner on the dock's edge is where
// the band meets the inside, whatever hangs off the band there (a fillet
// placed at the dock's inset arced into wallpaper).
function edgeInsets(barEdge, barThickness, band, gapsOut, barCovers) {
    var insets = { top: band, left: band, right: band, bottom: band };
    if (barCovers && barEdge in insets)
        insets[barEdge] = (Number(barThickness) || 0) + (Number(gapsOut) || 0);
    return insets;
}

// There is no inner fillet any more, and no reader of the compositor's window
// rounding here. The frame's corners are the SCREEN's corners: a monitor has
// a black bezel with a radius, ScreenCorners has always drawn that bezel in
// black outside frame mode, and the frame's border simply runs into it. A
// frame-coloured fillet at an inner corner only ever made sense while one
// edge was thick enough to round, which is the model this file just left.

// A band's four margins. Every band is AT its screen edge; the two horizontal
// ones span the width and the two side ones run between them, from the top
// band's inner edge to the bottom band's, so no two bands overlap. Bands
// anchored the full screen length crossed at the corners, and the frame's
// colour is translucent: each crossing was a band-square painted twice,
// darker than the rest of the frame. A covering bar's edge has no band at
// all, so the side bands run to the screen edge there and the bar's own plate
// is the border across the top.
function bandMargins(edge, barEdge, band, gapsOut, barCovers) {
    var m = { top: 0, bottom: 0, left: 0, right: 0 };
    if (edge === "left" || edge === "right") {
        m.top = bandExtent("top", barEdge, band, gapsOut, barCovers);
        m.bottom = bandExtent("bottom", barEdge, band, gapsOut, barCovers);
    }
    return m;
}


