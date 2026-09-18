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
 * - and reads `dockAttached` and `thickness` from here to do so
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
    readonly property real thickness: Geo.bandThickness(Config.options.appearance.frame.thickness)
    // How a pinned dock meets the band on its edge: on it (a tab, the
    // default) or floating a gap above it. Anything but "floating" is
    // attached, so a hand-edited value cannot leave the dock nowhere.
    readonly property bool dockAttached: String(Config.options.appearance.frame.dock ?? "attached") !== "floating"
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
    // The band's thickness on its own edge: nothing on a covering bar's edge
    // (the bar's plate is the border there), the configured thickness
    // everywhere else.
    function bandExtent(edge) {
        return Geo.bandExtent(edge, root.barEdge, root.thickness, root.gap, root.barCovers);
    }
}
