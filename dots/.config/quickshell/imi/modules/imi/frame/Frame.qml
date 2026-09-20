import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../../services/frame_geometry.js" as Geo

/**
 * The frame: ONE surface per screen, drawing the four bands in the bar's
 * colour so bar, bands and the ScreenCorners bezel read as one connected
 * surface (docs/proposals/frame-one-surface.md, stage 1). The band on the
 * bar's edge sits under the bar plate; every other edge, the dock's included,
 * is the band alone - a pinned dock meets it on its own terms (Dock.qml: on it
 * as a tab, or a gap above it).
 *
 * One surface rather than four, and the reason is what a surface IS to the
 * compositor: the unit blur is computed against, and the outline a specular
 * edge will one day be drawn along. Four band surfaces were four outlines
 * meeting at four corners, each corner an overlap two translucent surfaces
 * could paint twice - which is why `bandMargins` keeps them from crossing.
 * On one surface the bands are items, the crossing arithmetic still holds
 * (an overlapping pair of translucent Rectangles double-paints too), and
 * there is one blur region for the whole border rather than four that have
 * to agree.
 *
 * What a screen-sized, always-mapped surface has to get right, each of which
 * this tree has paid for once (AGENT.md, layer-shell gotchas): its geometry
 * is a constant of the screen - four edges anchored, no margins - so nothing
 * ever reconfigures it; it takes no input (an empty mask) and no keyboard;
 * and it stays on `quickshell:frame`, whose rules.lua entry carries `no_anim`
 * and `blur = false` - a minted namespace would fall through the catch-all
 * `ignore_alpha = 0.05`, under which a screen of transparent pixels asks the
 * compositor to blur the entire output. Nothing is reserved: the bands live
 * in the outer gap windows already leave. Painted transparent, never
 * unmapped, for a fullscreen window - `visible` on a layer surface destroys
 * it.
 */
Scope {
    id: frame

    // One band. A Rectangle on the surface: the two horizontal bands span the
    // width, the two side bands run between them, so no two overlap - the
    // colour is translucent, and a crossing paints twice on one surface just
    // as it did across two. On the bar's edge, where the bar's plate covers
    // its strip, the band IS that plate (stage 3): its thickness and its
    // auto-hide slide come from what the bar publishes, and BarContent paints
    // no plate of its own. The side bands therefore inset by what is DRAWN on
    // the horizontal edges - the plate while it is there, the band otherwise,
    // nothing while the plate has slid out - rather than by the authority's
    // `bandMargins`, which knows the band's thickness and not the plate's.
    component Band: Item {
        id: band
        required property string edge // "left" | "right" | "top" | "bottom"
        required property bool hidden
        // The bar's plate, when this is the bar's edge and the frame paints it.
        property var barPlate: null
        // What the horizontal bands are drawing, for the side bands to stop at.
        property real topInset: 0
        property real bottomInset: 0
        readonly property bool vertical: band.edge === "left" || band.edge === "right"
        readonly property real extent: band.barPlate ? band.barPlate.thickness : FrameGeometry.bandExtent(band.edge)
        // How far the band's edge side sits from the screen edge: nothing for
        // a band, the bar's slide for its plate - negative on the way out.
        readonly property real inset: band.barPlate ? band.barPlate.inset : 0
        // What of it is on screen, measured from the screen edge inward.
        readonly property real visibleExtent: Math.max(0, Math.min(band.extent, band.extent + band.inset))
        // Nothing to paint where the bar's own plate is the border and the
        // frame does not paint it, and nothing for a fullscreen window:
        // transparent, never removed.
        readonly property bool painted: !band.hidden && band.extent > 0
        // The whole band, once: the join's field stops at the band's inner
        // edge (FrameJoinField's box), so nothing else paints these rows.
        Rectangle {
            anchors.fill: parent
            color: band.painted ? FrameGeometry.color : "transparent"
        }
        x: band.edge === "right" ? parent.width - band.inset - band.extent
         : band.edge === "left" ? band.inset : 0
        y: band.edge === "bottom" ? parent.height - band.inset - band.extent
         : band.edge === "top" ? band.inset : band.topInset
        width: band.vertical ? band.extent : parent.width
        height: band.vertical ? parent.height - band.topInset - band.bottomInset : band.extent
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property bool fullscreen: HyprlandData.fullscreenByMonitorName[screenScope.monitor?.name ?? ""] ?? false
            property bool specialOpen: HyprlandData.specialWorkspaceByMonitorName[screenScope.monitor?.name ?? ""] ?? false
            readonly property bool hidden: fullscreen && !specialOpen

            PanelWindow {
                id: surface
                screen: screenScope.modelData
                // Mapped for as long as frame mode is on; a fullscreen window
                // or a thickness of 0 paints the bands transparent instead.
                visible: FrameGeometry.enabled
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:frame"
                // Top. The frame is chrome, like the bezel corners on Overlay:
                // it draws over a floating window dragged into the gap. A round
                // on Bottom ("under every window, over the wallpaper") was
                // invisible on every cold start: the wallpaper is on Bottom too
                // and a level stacks by creation order.
                WlrLayershell.layer: WlrLayer.Top
                // A screen-sized surface that took the keyboard would swallow
                // whatever the user typed while showing nothing.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // A literal, and the colour on the bands: a window colour bound
                // to a transparency-derived token goes opaque once and never
                // gets its blur back (#143).
                color: "transparent"
                mask: Region {}
                anchors {
                    left: true
                    right: true
                    top: true
                    bottom: true
                }

                Band { id: topBand;    edge: "top";    hidden: screenScope.hidden
                       barPlate: surface.barPlate?.edge === "top" ? surface.barPlate : null }
                Band { id: bottomBand; edge: "bottom"; hidden: screenScope.hidden
                       barPlate: surface.barPlate?.edge === "bottom" ? surface.barPlate : null }
                Band { id: leftBand;   edge: "left";   hidden: screenScope.hidden
                       topInset: topBand.visibleExtent; bottomInset: bottomBand.visibleExtent }
                Band { id: rightBand;  edge: "right";  hidden: screenScope.hidden
                       topInset: topBand.visibleExtent; bottomInset: bottomBand.visibleExtent }

                // The joins (frame-one-surface.md stage 2, frame-pin-grammar.md
                // §3). Whatever is fused to the frame on this screen - the
                // dock, a bar popup, a notification - publishes its plate in
                // screen coordinates with the solver's numbers under its own
                // key, and a field is drawn HERE for each, so every plate,
                // neck and the band are distance fields on one surface: one
                // outline for the blur region to follow, and one for a
                // specular rim later. Each element's own plate stands down
                // while this paints (FrameJoin.drawsPlate); its window keeps
                // its content, its input and its exclusive zone.
                //
                // The records are taken up a beat AFTER they are published.
                // They are published from inside the other window's frame -
                // the dock's layout settling in its polish, its spring's
                // FrameAnimation tick - and under the threaded render loop a
                // repaint this window asks for while another window is
                // locked for its sync is only noted, and taken up the next
                // time THIS window happens to sync. Measured on a 240 Hz
                // session and then in the sandbox: the field held the old
                // plate under icons that had already moved, and snapped to
                // the new width some random moment later; a colour toggled
                // by a Timer, which fires between frames, rendered every
                // time. `Qt.callLater` runs once the publisher's frame is
                // done, so the fields' changes ask for a repaint from the
                // event loop like the Timer did.
                property var joins: ({})
                property var barPlate: null
                // The keys, as a model the painters follow: diffed rather than
                // reassigned, so a notification arriving does not rebuild the
                // dock's field beside it.
                ListModel { id: joinKeys }
                function takeRecords() {
                    const name = screenScope.modelData.name;
                    surface.joins = GlobalStates.frameJoins[name] ?? ({});
                    surface.barPlate = GlobalStates.frameBars[name] ?? null;
                    const wanted = Object.keys(surface.joins).sort();
                    for (let i = joinKeys.count - 1; i >= 0; i--)
                        if (!wanted.includes(joinKeys.get(i).key)) joinKeys.remove(i);
                    for (const key of wanted) {
                        let have = false;
                        for (let i = 0; i < joinKeys.count && !have; i++) have = joinKeys.get(i).key === key;
                        if (!have) joinKeys.append({ key });
                    }
                }
                Connections {
                    target: GlobalStates
                    function onFrameJoinsChanged() { Qt.callLater(surface.takeRecords); }
                    function onFrameBarsChanged() { Qt.callLater(surface.takeRecords); }
                }
                Component.onCompleted: surface.takeRecords()
                function bandEdgeFor(edge) {
                    const extent = edge === "left" ? leftBand.extent : edge === "right" ? rightBand.extent
                                 : edge === "top" ? topBand.extent : bottomBand.extent;
                    return Geo.joinBandEdge(edge, extent, surface.width, surface.height);
                }

                // The strip a field paints in: the band's edge, the whole
                // width, and enough depth for the plate at full lift plus
                // the meniscus - a box that never moves or resizes while the
                // plate does (FrameJoinField.pinnedBox says why). It changes
                // only with the surface or the band, and then the field is
                // made again rather than resized: a Loader keyed on it.
                // Deep enough for the tallest plate that key can publish at
                // full lift, and constant per key: a strip that grew with the
                // plate would remake the field every frame.
                function joinStripDepthFor(key) {
                    if (key === "barPopup") return 720;
                    if (String(key).startsWith("notification")) return 480;
                    return 160;
                }
                function joinStripFor(edge, key) {
                    const b = surface.bandEdgeFor(edge), d = surface.joinStripDepthFor(key);
                    if (edge === "top") return Qt.rect(0, b, surface.width, d);
                    if (edge === "left") return Qt.rect(b, 0, d, surface.height);
                    if (edge === "right") return Qt.rect(b - d, 0, d, surface.height);
                    return Qt.rect(0, b - d, surface.width, d);
                }

                // One record's painter: its field on its edge's strip, and
                // its outline as a pool of Regions for the blur region - one
                // Region per rectangle of what the field painted
                // (FrameJoinField.outline), out of a pool declared once; the
                // field merges its rows down to the pool's size. A strip
                // guessed from the study's ratios had frosted a 14x20 px block
                // of bare wallpaper at each end of the dock, outside the
                // concave fillet and inside the strip.
                component JoinPainter: Item {
                    id: painter
                    required property string key
                    readonly property var record: surface.joins[painter.key] ?? null
                    readonly property string edge: painter.record?.edge ?? "bottom"
                    readonly property rect strip: surface.joinStripFor(painter.edge, painter.key)
                    readonly property var field: fieldLoader.item
                    readonly property Instantiator pool: outlinePool
                    Loader {
                        id: fieldLoader
                        readonly property rect strip: painter.strip
                        onStripChanged: { active = false; active = true; }
                        active: true
                        sourceComponent: FrameJoinField {
                            id: joinField
                            readonly property var j: painter.record
                            painting: joinField.j !== null && !screenScope.hidden
                            edge: joinField.j?.edge ?? "bottom"
                            plateX: joinField.j?.plate.x ?? 0
                            plateY: joinField.j?.plate.y ?? 0
                            plateWidth: joinField.j?.plate.width ?? 0
                            plateHeight: joinField.j?.plate.height ?? 0
                            radiusTopLeft: joinField.j?.radii.topLeft ?? 0
                            radiusTopRight: joinField.j?.radii.topRight ?? 0
                            radiusBottomRight: joinField.j?.radii.bottomRight ?? 0
                            radiusBottomLeft: joinField.j?.radii.bottomLeft ?? 0
                            bandEdge: surface.bandEdgeFor(joinField.edge)
                            color: joinField.j?.color ?? "transparent"
                            gap: joinField.j?.gap ?? 0
                            neck: joinField.j?.neck ?? 0
                            bulgeRaw: joinField.j?.bulge ?? 0
                            meniscus: joinField.j?.meniscus ?? 45
                            blendPerPixel: joinField.j?.blendPerPixel ?? 4
                            climbFraction: joinField.j?.climbFraction ?? 0
                            outlineLimit: outlinePool.count
                            pinnedBox: fieldLoader.strip
                        }
                    }
                    Instantiator {
                        id: outlinePool
                        model: 64
                        delegate: Region {
                            required property int index
                            readonly property var r: painter.field?.outline[index] ?? null
                            x: r?.x ?? 0
                            y: r?.y ?? 0
                            width: r?.width ?? 0
                            height: r?.height ?? 0
                        }
                    }
                }
                Repeater {
                    id: joinPainters
                    model: joinKeys
                    delegate: JoinPainter {}
                }

                // One region for the whole border, composed per band and
                // gated on exactly what paints: a region over an unpainted
                // band frosts bare wallpaper. Unblurred, the band was the
                // bar's colour over RAW wallpaper while the bar was the same
                // colour over a blurred one - measured, a green-grey bar above
                // a blue band, the opposite of one connected surface.
                WindowBlurRegion {
                    targetWindow: surface
                    region: Region {
                        Region { item: leftBand.painted ? leftBand : null }
                        Region { item: rightBand.painted ? rightBand : null }
                        Region { item: topBand.painted ? topBand : null }
                        Region { item: bottomBand.painted ? bottomBand : null }
                        // ...and the joins, as the rows their fields paint:
                        // each plate, its neck and the meniscus' flanks are
                        // one outline, and these are those outlines (empty
                        // while nothing paints here).
                        Region {
                            regions: {
                                const all = [];
                                for (let p = 0; p < joinPainters.count; p++) {
                                    const pool = joinPainters.itemAt(p)?.pool ?? null;
                                    for (let i = 0; pool && i < pool.count; i++) all.push(pool.objectAt(i));
                                }
                                return all;
                            }
                        }
                    }
                }
            }
        }
    }
}
