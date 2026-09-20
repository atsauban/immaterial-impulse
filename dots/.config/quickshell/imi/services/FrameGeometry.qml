pragma Singleton
import QtQuick
import Quickshell

import qs.modules.common
import "frame_geometry.js" as Geo

/**
 * Frame mode's geometry authority (docs/proposals/frame-mode.md): the shell's
 * edge surfaces read where the frame is from here instead of each deciding
 * for itself. Stage 1: one frame for every screen, the bar's edge is the
 * bar, the other three edges are a band as thick as the compositor's outer
 * gap (or `appearance.frame.thickness`), and the four inner corners carry
 * the screen-rounding fillet in the frame's colour. The dock is not part of
 * the frame: a pinned dock meets the band on its own edge - sitting on it as
 * a tab (`appearance.frame.dock` "attached") or a gap above it ("floating")
 * - and reads `dockAttachedFor(pinned)` and `thickness` from here to do so
 * (modules/imi/dock/DockReservation.qml). Off by default; a vertical bar is
 * not framed yet.
 */
Singleton {
    id: root
    readonly property bool enabled: (Config.options.appearance.frame.enable ?? false) && !Config.options.bar.vertical
    readonly property string barEdge: Config.options.bar.bottom ? "bottom" : "top"
    // What the compositor reserves for the bar - the settled exclusive zone
    // Bar.qml's reserver asks for, one token in Appearance for both. Known
    // stage-1 limits: the bar's per-screen list and auto-hide are not
    // modelled - one frame, the bar assumed present at its full zone on
    // every screen.
    readonly property real barThickness: Appearance.sizes.barExclusiveZone
    // Whether the bar's plate covers its strip edge to edge, which is what
    // makes the bar part of the frame rather than something floating inside
    // it. Hug (cornerStyle 0) with a painted background, and only it: Float
    // and Float Islands inset their plates by the gap, Islands and M3 paint
    // no strip at all. One expression, here, rather than a second copy of
    // BarContent's `backgroundPainted` - the authority owns the question.
    readonly property bool barCovers: (Config.options.bar.cornerStyle ?? 0) === 0
        && (Config.options.bar.showBackground ?? true)
    readonly property real gap: Appearance.sizes.hyprlandGapsOut
    // Whether the FRAME's surface paints the bar's plate (frame-one-surface.md
    // stage 3, frame-pin-grammar.md the bar row): only where the bar is the
    // frame's edge - a covering plate - because there the plate is a
    // full-width strip on the band. The bar publishes it as a join record
    // (the shell's ephemeral join map, under "bar"; the authority itself reads
    // none of it - an occupant read through it was inert for a whole review
    // round), and Frame.qml paints it fused to the hairline or
    // lifted off it, while BarContent paints no plate of its own, so the
    // plate and the side bands are one shape on one surface rather than two
    // surfaces crossing. Every other style keeps its own plates: they are
    // inset islands inside the frame, not the frame.
    readonly property bool paintsBarPlate: root.enabled && root.barCovers
    // How the bar meets its band (frame-pin-grammar.md, the bar row): "auto"
    // follows the workspace and the pin - fused (Hug) while a window is on
    // the workspace and nothing pins the bar, since the frame is then the
    // border around the windows; released (Float, an island a gap off the
    // band) over an empty workspace or when pinned. Decided at review the
    // other way round first and turned: "bar is set to hug but floats when
    // there are windows - auto should be the opposite". "attached" and
    // "floating" force one look. The pin and the occupancy are the bar's
    // facts, handed in.
    readonly property string barLook: String(Config.options.appearance.frame.bar ?? "auto")
    function barAttachedFor(pinned: bool, occupied: bool): bool {
        if (root.barLook === "floating") return false;
        if (root.barLook === "attached") return true;
        return !pinned && occupied;
    }
    readonly property real thickness: Geo.bandThickness(Config.options.appearance.frame.thickness)
    // How the dock meets the band on its edge, given its pin
    // (frame-pin-grammar.md: pinned means released, unpinned means fused).
    // "auto" follows the pin; "attached" and "floating" force one look.
    // Anything else attaches, so a hand-edited value cannot leave the dock
    // nowhere. The pin itself lives with the dock (DockReservation.pinned);
    // this authority reads no occupant.
    readonly property string dockLook: String(Config.options.appearance.frame.dock ?? "auto")
    function dockAttachedFor(pinned: bool): bool {
        if (root.dockLook === "floating") return false;
        if (root.dockLook === "auto") return !pinned;
        return true;
    }
    // Where windows start on each edge, which is the frame's own reach: a
    // covering bar's zone plus the compositor's gap on its edge, the band on
    // the other three.
    readonly property var insets: Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.gap, root.barCovers)
    readonly property color color: Appearance.colors.colBarBackground

    // No rounding probe any more, and no fillet to size with it: the frame's
    // corners are the SCREEN's corners, which ScreenCorners draws in black as
    // a monitor's bezel, in frame mode and out of it. The probe existed only
    // to size a frame-coloured fillet at an inner corner, and the inner
    // corner went with the model that made one edge thick.

    // The readers. One frame for every screen, so neither takes a screen:
    // an earlier cut framed a pinned dock per screen (its zone drops on a
    // fullscreen monitor) and the per-screen plumbing went with the dock.
    function bandMargins(edge) {
        return Geo.bandMargins(edge, root.barEdge, root.thickness, root.gap, root.barCovers);
    }
    // The band's thickness on its own edge: the configured thickness on every
    // edge, the covering bar's included - its plate is a join on that band.
    function bandExtent(edge) {
        return Geo.bandExtent(edge, root.barEdge, root.thickness, root.gap, root.barCovers);
    }
}
