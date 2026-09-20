pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.dropShelf
import "../dock/dock_geometry.js" as DockGeometry

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            // The Lockscreen tab takes the bar down exactly as the real lock
            // does, through the same gate (spec §1.5) - a teardown/rebuild per
            // tab flip, same as per lock/unlock.
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
                && !GlobalStates.editLockPreview
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                // Stay shown while a bar popup is open so it isn't orphaned above
                // a hidden bar; the popup closes itself on pointer-leave, then the
                // bar hides. See issues #30, #31.
                //
                // Edit Mode is a term here and NEVER a write to `visible`: the
                // bar is edited in place at full size (spec §4.2), so an
                // auto-hidden bar has to stay on screen for the mode - and
                // `visible: false` on a layer surface destroys the surface
                // rather than hiding it. The mode's viewport reservation does
                // not read this (EditModeInsets is configuration-only), so
                // holding the bar out changes nothing about the shrunk desktop.
                property bool mustShow: hoverRegion.containsMouse || superShow
                    || GlobalStates.editMode
                    || ((GlobalStates.mediaControlsOpen || GlobalStates.sysTrayOverflowOpen) && Config?.options.bar.autoHide.dismissPopups)
                    // A widget's popup is fused to this bar's plate (the pin
                    // grammar): the bar cannot leave while its card is up.
                    || ((GlobalStates.activeBarPopup?.popupVisible ?? false) && Config?.options.bar.autoHide.dismissPopups)
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                // The zone lives on barSpaceReserver below, so this surface
                // never reconfigures for it. Do not put an `exclusiveZone`
                // back here, not even 0: writing that property at all forces
                // exclusionMode to Normal, and a Normal-mode surface is placed
                // inside the area other surfaces reserve - so the bar would be
                // pushed off the screen edge by its own reserver.
                exclusionMode: ExclusionMode.Ignore
                // A second window, not something in the bar's item tree, which
                // is why it is a property rather than a child.
                property QtObject barSpaceReserver: BarExclusiveZoneReserver {
                    screen: barLoader.modelData
                    barNamespace: "quickshell:bar"
                    farEdge: Config.options.bar.bottom
                    edgeMargin: Config.options.bar.bottom
                        ? Appearance.sizes.barBottomMargin : Appearance.sizes.barDetachMargin
                    zone: (Config?.options.bar.autoHide.enable && (!barRoot.mustShow || !Config?.options.bar.autoHide.pushWindows))
                        ? 0 : Appearance.sizes.barReservedHeight + barRoot.releaseZoneExtra
                }
                WlrLayershell.namespace: "quickshell:bar"
                // Overlay layer only while special workspace sits on top of a fullscreen window on this monitor,
                // else Top layer so fullscreen apps cover the bar as normal (Hyprland buries Top layer under fullscreen+special).
                WlrLayershell.layer: (monitorHasFullscreen && monitorHasSpecialOpen) ? WlrLayer.Overlay : WlrLayer.Top
                // A detached bar style (cornerStyle 3) holds the surface off the
                // screen edge by barDetachMargin. That gap is not part of the
                // surface, so with auto-hide on it is a band the pointer can
                // never reach: the reveal strip lives *inside* the window, and
                // hovering the gap reaches whatever is behind it instead. It
                // also made hiding look wrong - the bar slid up inside a
                // surface that already started below the edge, so the gap above
                // it never moved.
                //
                // While auto-hide is on the surface takes the edge and the
                // content carries the gap instead, which looks identical and
                // costs no surface reconfiguration.
                readonly property real detachInset: Appearance.sizes.barDetachInset
                // The sum lives in Appearance because Edit Mode has to know how
                // much of the screen this surface occupies and cannot measure
                // it - the two are on different layer surfaces, in different
                // scene graphs.
                implicitHeight: Appearance.sizes.barSurfaceHeight
                // When Overlay-layer, bar shares a layer with the screen-corner click zones (ScreenCorners.qml)
                // and same-layer overlap is resolved by stacking, not layer priority - bar was winning and
                // swallowing the tiny corner-open hit rects. Carve them out of the bar's own mask so clicks
                // reach the corners underneath. Only relevant on the edge the bar and corners share.
                property bool cutOutCornerOpenZones: (monitorHasFullscreen && monitorHasSpecialOpen) && (Config.options.bar.bottom === Config.options.sidebar.cornerOpen.bottom)
                property int cornerOpenCutWidth: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
                property int cornerOpenCutHeight: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
                mask: Region {
                    item: hoverMaskRegion
                    Region {
                        intersection: Intersection.Subtract
                        x: 0
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: barRoot.width - barRoot.cornerOpenCutWidth
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                }
                color: "transparent"

                // Blur only the painted body shapes. The bar's drop shadow and
                // the screen-rounding margin live outside these rects, so the
                // compositor's blur can't frost them (#82) — same treatment as
                // the sidebars. Pairs with rules.lua turning the whole-surface
                // layerrule blur off for this namespace. The RoundCorner
                // decorators and the Islands pills are left out: a region is a
                // plain rect, so covering their transparent parts would frost
                // bare wallpaper; they are opaque by default and merely read as
                // unblurred translucency under transparency mode. The M3
                // wrappers ARE covered (dc4e0662c) - under that style they are
                // the only painted shapes, so leaving them out meant an empty
                // region and no blur at all.
                WindowBlurRegion {
                    targetWindow: barRoot
                    region: Region {
                        Region {
                            item: barContent.backgroundPainted ? barContent.backgroundItem : null
                            radius: barContent.backgroundItem.radius
                        }
                        Region {
                            item: barContent.centerPillPainted ? barContent.centerPillItem : null
                            topLeftRadius: barContent.centerPillItem.topLeftRadius
                            topRightRadius: barContent.centerPillItem.topRightRadius
                            bottomLeftRadius: barContent.centerPillItem.bottomLeftRadius
                            bottomRightRadius: barContent.centerPillItem.bottomRightRadius
                        }
                        // The M3 wrappers. Their own radius is `full` (9999),
                        // which is a "round me completely" sentinel rather than
                        // a length, so it is resolved to the real pill radius
                        // here - a region is a plain rounded rect and would
                        // otherwise be squared off against the painted shape.
                        Region {
                            item: barContent.materialPillsPainted ? barContent.leftMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.leftMaterialPillItem.width, barContent.leftMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.centerMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.centerMaterialPillItem.width, barContent.centerMaterialPillItem.height) / 2)
                        }
                        Region {
                            item: barContent.materialPillsPainted ? barContent.rightMaterialPillItem : null
                            radius: Math.round(Math.min(barContent.rightMaterialPillItem.width, barContent.rightMaterialPillItem.height) / 2)
                        }
                        // Float Islands' three plates - the only painted shapes
                        // in that style, each at the window rounding.
                        Region {
                            item: barContent.leftIslandPainted ? barContent.leftIslandItem : null
                            radius: barContent.leftIslandItem.radius
                        }
                        Region {
                            item: barContent.centerIslandPainted ? barContent.centerIslandItem : null
                            radius: barContent.centerIslandItem.radius
                        }
                        Region {
                            item: barContent.rightIslandPainted ? barContent.rightIslandItem : null
                            radius: barContent.rightIslandItem.radius
                        }
                    }
                }

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                // The dead row is on the right and bottom screen edges only, so
                // a top-anchored bar has nothing to overhang. See the tokens'
                // own comment in Appearance for what these two terms are and
                // why the bottom one used to come out +5 instead of -1.
                margins {
                    top: Appearance.sizes.barDetachMargin
                    right: Appearance.sizes.barDeadPixelOverhang
                    bottom: Appearance.sizes.barBottomMargin
                }

                // The bar and the frame (frame-pin-grammar.md, the bar row).
                // Where the bar is the frame's edge (Hug) its plate is a JOIN
                // on the band on that edge: FUSED - on the hairline, one
                // colour with it, the icons where they are - or RELEASED, the
                // plate lifted off by the compositor's gap, drawn in from the
                // side bands by the same, its corners rounding with the lift:
                // an island. "auto" follows the workspace and the pin: fused
                // while nothing is on the workspace and nothing pins it. The
                // frame paints the plate in both states (published under
                // "bar" like the dock's); BarContent stands its own plate
                // down while it does. Released, the bar reserves its lift as
                // well (releaseZoneExtra, on the reserver): a plate lifted
                // by the gap with the zone held would sit ON the first
                // window's edge, and an island touching a window is not an
                // island (measured, 8x). The extra flips at the start of a
                // lift and the end of a landing - the dock's rule - so the
                // compositor re-tiles once per state change, on its own
                // animation.
                readonly property bool barOccupied: HyprlandData.occupiedByMonitorName[barRoot.screen?.name ?? ""] ?? false
                readonly property bool joinAttached: FrameGeometry.barAttachedFor(GlobalStates.barPinned, barRoot.barOccupied)
                // The band's inner edge in this window's frame: the surface
                // sits at the screen edge less its own margin.
                readonly property real bandInsetHere: FrameGeometry.bandExtent(FrameGeometry.barEdge) - Appearance.sizes.barSurfaceMargin
                FrameJoin {
                    id: barJoin
                    anchors.fill: parent
                    plate: barContent.backgroundItem
                    edge: FrameGeometry.barEdge
                    attached: barRoot.joinAttached
                    travel: Appearance.sizes.hyprlandGapsOut
                    bandInset: barRoot.bandInsetHere
                    color: FrameGeometry.color
                    // The plate (Hug) or the islands: the same join, the
                    // islands being pieces of the plate (frame-pin-grammar.md).
                    active: FrameGeometry.enabled && (FrameGeometry.barCovers || FrameGeometry.barIslands)
                        && Config.options.bar.showBackground && !barContent.centerOnly
                    paintsLocally: false
                    paintsAtRest: true
                }
                // What the content carries for the join. Fused, the plate
                // starts at the screen edge and covers the band; released,
                // it sits the gap in from the band's INNER edge, like the
                // windows do from the side bands - so the content's offset
                // is the band plus the lift, scaled along the lift so the
                // motion is one run (a 5 px band put a plate lifted 5 px
                // straight onto the band, no gap - seen live). The side
                // insets measure from the screen edge already.
                readonly property real plateLift: barJoin.active && barJoin.travel > 0
                    ? barJoin.lift * (1 + Math.max(0, barRoot.bandInsetHere) / barJoin.travel) : 0
                readonly property real plateSideInset: barJoin.active ? FrameGeometry.bandExtent("left") + barJoin.lift : 0
                readonly property real plateRadius: barJoin.active && barJoin.travel > 0
                    ? Appearance.rounding.windowRounding * Math.min(1, barJoin.lift / barJoin.travel) : 0
                readonly property real releaseZoneExtra: barJoin.active
                    ? DockGeometry.splitZoneExtra(barJoin.travel + Math.max(0, barRoot.bandInsetHere), !barRoot.joinAttached, barJoin.lift) : 0
                // How far a plate reaches past the band's inner edge, and
                // the neck it may carry for it (see slideHold below).
                function plateReach(at, height) {
                    return Config.options.bar.bottom
                        ? (barRoot.height - barRoot.bandInsetHere) - at.y
                        : at.y + height - barRoot.bandInsetHere;
                }
                // The last stretch of the slide over which the neck lets go:
                // the strip a plate AT the band's surface blended into was a
                // dozen rows (the blend radius over four), so sixteen covers
                // it - and a plate at rest reaches further than that past the
                // band (a bar 40 tall, a band 2: 38), which is what keeps the
                // neck whole at rest. Measured against the meniscus (49) it
                // never was.
                readonly property real slideHoldReach: 16
                function screenOriginY() {
                    return Config.options.bar.bottom
                        ? barRoot.screen.height - barRoot.height - Appearance.sizes.barSurfaceMargin
                        : Appearance.sizes.barSurfaceMargin;
                }
                readonly property var frameJoinRecord: {
                    if (!barJoin.active || !barJoin.painting || !barRoot.screen || !FrameGeometry.barCovers) return null;
                    const p = barContent.backgroundItem;
                    // Read so a move re-evaluates this: the content's place in
                    // the window (the slide, the lift, the side insets) and
                    // the plate's own rect. mapToItem(null) is the window; the
                    // window sits at the screen's edge less its own margin.
                    barContent.x; barContent.y; barContent.width; barContent.height; p.x; p.y; p.width; p.height;
                    const at = p.mapToItem(null, 0, 0);
                    const bottom = Config.options.bar.bottom;
                    const oy = bottom
                        ? barRoot.screen.height - barRoot.height - Appearance.sizes.barSurfaceMargin
                        : Appearance.sizes.barSurfaceMargin;
                    // How far the plate reaches past the band's inner edge.
                    // Auto-hide slides the plate out through the band, and a
                    // fused plate whose inner edge sits AT the band's surface
                    // is two surfaces at one distance from every row below:
                    // the meniscus blends them into a strip the width of the
                    // screen (measured, 12 rows under a hidden bar). So the
                    // neck lets go over the last meniscus of the slide, and a
                    // plate past the band carries none.
                    const reach = bottom
                        ? (barRoot.height - barRoot.bandInsetHere) - at.y
                        : at.y + p.height - barRoot.bandInsetHere;
                    const slideHold = Math.max(0, Math.min(1, reach / barRoot.slideHoldReach));
                    return {
                        edge: FrameGeometry.barEdge,
                        plate: { x: at.x, y: at.y + oy, width: p.width, height: p.height },
                        radii: { topLeft: p.radius, topRight: p.radius, bottomRight: p.radius, bottomLeft: p.radius },
                        gap: barJoin.state.gap, neck: barJoin.state.neck * slideHold, bulge: barJoin.state.bulge * slideHold,
                        meniscus: barJoin.meniscus, blendPerPixel: barJoin.blendPerPixel,
                        climbFraction: barJoin.climbFraction, color: FrameGeometry.color,
                        // What the bar reserves beyond its settled zone while
                        // released, for whoever keeps clear of the bar's edge.
                        zoneExtra: barRoot.releaseZoneExtra
                    };
                }
                function publishFrameJoin(record) {
                    const name = barRoot.screen?.name ?? "";
                    if (!name) return;
                    GlobalStates.publishFrameJoin(name, "bar", record);
                }
                onFrameJoinRecordChanged: publishFrameJoin(frameJoinRecord)
                // The islands (frame-pin-grammar.md, the bar row): each a piece
                // of the plate on the same join, published as its own record
                // so the frame paints it fused to the band with its meniscus or
                // lifted off it. Hugging, the outer islands hug their corner
                // too: the left one runs from the screen's left edge, the right
                // one to the right edge, and the corner on the side is square
                // like the plate's; the inner corners stay round. The radius of
                // a band-side or side corner rounds with the lift as the
                // plate's does.
                readonly property var frameIslandRecords: {
                    const out = { "barIsland:left": null, "barIsland:center": null, "barIsland:right": null };
                    if (!barJoin.active || !barJoin.painting || !barRoot.screen || !FrameGeometry.barIslands) return out;
                    barContent.x; barContent.y; barContent.width; barContent.height;
                    const bottom = Config.options.bar.bottom;
                    const oy = barRoot.screenOriginY();
                    const R = Appearance.rounding.windowRounding, r = barRoot.plateRadius;
                    // A card wider than its island: the island stands on it
                    // as a tab, and its corners on the card square off by the
                    // hold (GlobalStates.barPopupTab, from the overlay).
                    const tab = GlobalStates.barPopupTab;
                    const tabScreen = tab && tab.screen === (barRoot.screen?.name ?? "") ? tab : null;
                    for (const isl of barContent.frameIslandItems) {
                        if (!isl || !isl.visible) continue;
                        isl.x; isl.y; isl.width; isl.height;
                        const at = isl.mapToItem(null, 0, 0);
                        const section = isl.sectionName;
                        const slideHold = Math.max(0, Math.min(1, barRoot.plateReach(at, isl.height) / barRoot.slideHoldReach));
                        const onCard = tabScreen && tabScreen.section === section ? tabScreen : null;
                        const sideL = (section === "left" ? r : R) * (1 - (onCard?.left ?? 0));
                        const sideR = (section === "right" ? r : R) * (1 - (onCard?.right ?? 0));
                        out["barIsland:" + section] = {
                            edge: FrameGeometry.barEdge,
                            section: section,
                            plate: { x: at.x, y: at.y + oy, width: isl.width, height: isl.height },
                            radii: bottom
                                ? { topLeft: sideL, topRight: sideR, bottomRight: r, bottomLeft: r }
                                : { topLeft: r, topRight: r, bottomRight: sideR, bottomLeft: sideL },
                            gap: barJoin.state.gap, neck: barJoin.state.neck * slideHold, bulge: barJoin.state.bulge * slideHold,
                            meniscus: barJoin.meniscus, blendPerPixel: barJoin.blendPerPixel,
                            climbFraction: barJoin.climbFraction, color: FrameGeometry.color,
                            zoneExtra: barRoot.releaseZoneExtra
                        };
                    }
                    return out;
                }
                function publishFrameIslands(records) {
                    const name = barRoot.screen?.name ?? "";
                    if (!name) return;
                    for (const key in records) GlobalStates.publishFrameJoin(name, key, records[key]);
                }
                onFrameIslandRecordsChanged: publishFrameIslands(frameIslandRecords)

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                    publishFrameJoin(frameJoinRecord);
                    publishFrameIslands(frameIslandRecords);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                    publishFrameJoin(null);
                    publishFrameIslands({ "barIsland:left": null, "barIsland:center": null, "barIsland:right": null });
                }

                // Drag files over the bar to pop the drop shelf out below it -
                // the Wayland-native drop shelf summon (a DropArea learns of a
                // drag the moment it crosses this surface; nothing else can).
                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onEntered: drag => {
                        if (!Config.options.dropShelf.dragToBarReveal || !drag.hasUrls) {
                            drag.accepted = false
                            return
                        }
                        drag.accepted = true
                        if (!GlobalStates.dropShelfOpen) {
                            GlobalStates.dropShelfX = drag.x
                            GlobalStates.dropShelfAnchorBelow = !Config.options.bar.bottom
                            GlobalStates.dropShelfY = Config.options.bar.bottom
                                ? barRoot.screen.height - Appearance.sizes.barHeight - 10
                                : Appearance.sizes.barHeight
                            GlobalStates.dropShelfOpen = true
                            DropShelf.armAutoDismiss()
                        }
                    }
                    onDropped: drop => {
                        if (!drop.hasUrls) {
                            drop.accepted = false
                            return
                        }
                        DropShelf.addItems(drop.urls)
                        drop.accept()
                    }
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    // The window's input region, and the only thing that can
                    // reveal an auto-hidden bar: the pointer has to land inside
                    // it for hoverRegion to see anything at all.
                    //
                    // Kept inside the surface on purpose. Anchoring this to
                    // barContent with negative margins was the obvious way to
                    // write it, but while the bar is hidden barContent sits at
                    // y = -barHeight, so the published rect began roughly a
                    // whole bar height *above* the surface and the compositor
                    // was left to clamp it. The reveal strip is only
                    // hoverRegionWidth (2px by default) tall once clamped, so
                    // an off-by-one there costs half of it - and the row that
                    // goes missing is y = 0, the screen edge, which is exactly
                    // where a pointer thrown at the top of the screen lands.
                    Item {
                        id: hoverMaskRegion
                        readonly property real reveal: Config.options.bar.autoHide.hoverRegionWidth
                        // The detach inset counts as the bar's own space, not a
                        // gap outside it. Leaving it out made the strip start
                        // below the edge whenever the bar was *shown*, so a
                        // pointer resting on row 0 revealed the bar, fell
                        // outside the strip the moment it appeared, and hid it
                        // again - a reveal/hide oscillation for as long as the
                        // pointer stayed on the edge.
                        //
                        // The lift counts the same way: a released plate sits
                        // a gap in from the edge, and a strip that began at the
                        // plate left rows 0..gap outside - a pointer held at the
                        // very top revealed the bar, fell out of the strip as the
                        // plate lifted, and hid it again, at 5 Hz (footage).
                        readonly property real rawTop: barContent.y - reveal - Appearance.sizes.barDetachInset - barRoot.plateLift
                        readonly property real rawBottom: barContent.y + barContent.height + reveal + barRoot.plateLift

                        x: 0
                        width: parent.width
                        y: Math.max(0, rawTop)
                        height: Math.max(0, Math.min(parent.height, rawBottom) - y)
                    }

                    RoundCorner {
                        id: leftPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        x: barContent.centerPillX - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.TopRight

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: leftPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: leftPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: leftPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }

                    BarContent {
                        id: barContent

                        implicitHeight: Appearance.sizes.barHeight
                        plateOnFrame: barJoin.drawsPlate && !barContent.centerOnly && Config.options.bar.showBackground
                        plateRadius: barRoot.plateRadius
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: ((Config?.options.bar.autoHide.enable && !mustShow)
                                ? -Appearance.sizes.barHeight : barRoot.detachInset) + barRoot.plateLift
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            leftMargin: barRoot.plateSideInset
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1 + barRoot.plateSideInset
                        }
                        // Off while the join moves the plate: a Behavior whose
                        // target moves every frame restarts every frame.
                        Behavior on anchors.topMargin {
                            enabled: !barJoin.moving
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            enabled: !barJoin.moving
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: ((Config?.options.bar.autoHide.enable && !mustShow)
                                    ? -Appearance.sizes.barHeight : barRoot.detachInset) + barRoot.plateLift
                            }
                        }
                    }

                    RoundCorner {
                        id: rightPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0
                        x: barContent.centerPillX + barContent.centerPillWidth
                        implicitSize: Appearance.rounding.screenRounding
                        color: Appearance.colors.colBarBackground
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: rightPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: rightPillCorner
                                corner: RoundCorner.CornerEnum.BottomLeft
                            }
                        }
                        AnchorChanges {
                            target: rightPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }
                    
                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        // Hug - and the frame's islands, whose outer islands hug
                        // their corner the same way (each fillet only under a
                        // populated island).
                        active: showBarBackground && !barContent.centerOnly
                            && (Config.options.bar.cornerStyle === 0 || (FrameGeometry.enabled && FrameGeometry.barIslands))
                        // The hug is the FUSED look: these fillets bridge the
                        // plate into the screen's sides. They ride the content
                        // down with the lift and would sit in the island's gap
                        // at the screen edge (seen live), so they fade with the
                        // lift and are gone by the time the plate is free.
                        opacity: barJoin.active && barJoin.travel > 0
                            ? 1 - Math.min(1, barJoin.lift / barJoin.travel) : 1
                        visible: opacity > 0

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                visible: !FrameGeometry.barIslands || (barContent.frameIslandItems[0]?.visible ?? false)
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                visible: !FrameGeometry.barIslands || (barContent.frameIslandItems[2]?.visible ?? false)
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }
        // The pin (frame-pin-grammar.md): pinned, the bar floats off the
        // frame's band whatever the workspace holds.
        function pin(): void {
            GlobalStates.barPinned = true
        }
        function unpin(): void {
            GlobalStates.barPinned = false
        }
        function togglePin(): void {
            GlobalStates.barPinned = !GlobalStates.barPinned
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
