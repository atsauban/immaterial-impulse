import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "dock_geometry.js" as DockGeometry

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    // Which edge the dock lives on. Everything positional derives from this
    // one value; nothing below names a side directly.
    readonly property string edge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")

    // One tree, not two modules. An orientation change reflows the icons in
    // place, so icon state, hover state and DockLaunchTracker's bookkeeping
    // survive it - the bar rebuilds instead, and loses all three.
    readonly property bool vertical: DockGeometry.isVertical(root.edge)

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            // The Lockscreen tab rides the lock's own teardown (spec §1.5).
            // Destroying the surface is this line's existing, deliberate cost
            // - the dock embeds no renderer - and the tab inherits it per
            // flip; holding the dock ON screen for the mode's Desktop tab
            // still goes through `reveal` below, never through this property.
            visible: !GlobalStates.screenLocked
                && !GlobalStates.editLockPreview

            property var monitor: WM.monitorFor(modelData)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            property bool reveal: {
                // The dock is edited in place (spec §4.2), so the mode holds it
                // revealed - through this expression, which is a centre offset
                // on the content, never through the surface's `visible`. First
                // in the chain so a fullscreen window cannot hide the dock out
                // from under the user arranging it.
                if (GlobalStates.editMode)
                    return true
                if (dockContextMenu.isOpen)
                    return true
                if (fullscreenOnThisMonitor)
                    return Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse
                return root.pinned
                    || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse)
                    || activeAppsArea.requestDockShow
                    || dragSlots.requestDockShow
                    || (!ToplevelManager.activeToplevel?.activated)
            }

            // Everything positional comes from one derivation
            // (dock_geometry.js), so the four places that used to spell the
            // margin pair out by hand cannot drift apart.
            readonly property real dockThickness: DockGeometry.thickness(
                Config.options?.dock.height ?? 60,
                Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut) + dockRoot.splitRoom
            readonly property var dockMargins: DockGeometry.margins(
                root.edge, Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)

            // The zone is the dock's own derivation (DockReservation.zone). In
            // frame mode a pinned dock also moves its whole surface in from
            // the screen edge to where the attached tab meets the frame's
            // band (DockReservation.frameOffset) - and the compositor adds
            // that anchored-edge margin to the zone by itself, so nothing
            // inside the surface moves. Floating is not a second surface
            // position: the pill lifts INSIDE the surface (splitLift below),
            // so the switch is drawn rather than reconfigured, and the zone
            // alone steps - reserving the union of where the pill is and
            // where it goes (splitZoneExtra below). Only while pinned:
            // an unpinned dock hides and reveals from the screen edge, and
            // its hover sliver has to stay AT the edge - moved in, the pointer
            // slammed to the edge would land on the band, which takes no input.
            readonly property bool reserves: root.pinned && !fullscreenOnThisMonitor
            exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0
            readonly property var frameMargins: DockGeometry.directedSides(
                root.edge, 0, dockRoot.reserves ? DockReservation.frameOffset : 0)
            margins {
                top: dockRoot.frameMargins.top
                bottom: dockRoot.frameMargins.bottom
                left: dockRoot.frameMargins.left
                right: dockRoot.frameMargins.right
            }
            // Attached, the pill is a tab of the band: the band's colour, no
            // border, its outward corners squared at the seam; the blur region
            // stays (the bar plate in the same colour is blurred, and the tab
            // has to read as that plate, not as unfrosted translucency).
            // Unpinned too, while the band is the gap: an unpinned dock sits a
            // gap from the edge, so on the default band a rounded, bordered
            // pill there rested on the band like a pill on a line, and as a
            // tab it comes out of the band and slides back into it. On any
            // other band an unpinned dock cannot be moved to meet it (its
            // hover sliver has to stay at the edge), so it keeps the pill.
            readonly property bool attached: DockReservation.attached && !fullscreenOnThisMonitor
                && (dockRoot.reserves || DockReservation.frameOffset === 0)

            // The attached <-> floating switch is a FRAME JOIN
            // (modules/common/widgets/FrameJoin.qml): the band is the
            // surface, the pill is what joins it, and the join owns the
            // physics - the elastic pull, the neck that thins and lets go,
            // the squash and the stretch. Everything below is read OFF it.
            // Nothing here sequences anything: what the eye reads as the
            // break is the neck's own state, not a timer.
            //
            // The target is the frame option and the PIN: pinning a floating
            // dock is a lift off the band (the travel appears), not a jump to
            // a lifted pill. Never `reserves`, which folds in the fullscreen
            // term - following it replayed the lift on every fullscreen exit;
            // fullscreen reaches the lift through the travel alone, while the
            // dock is hidden.
            readonly property bool joinAttached: !(FrameGeometry.enabled && root.pinned && !DockReservation.attached)
            // The pin, for the reservation and the frame's option to read.
            Binding { target: DockReservation; property: "pinned"; value: root.pinned }
            // The lift: the compositor's gap - the distance between "on the
            // band" and "a gap above it" - while the dock reserves its edge.
            // An unpinned dock never lifts (its hover sliver stays at the
            // edge), so at the default band it takes the look change alone.
            readonly property real splitTravel: DockGeometry.splitTravel(FrameGeometry.enabled, dockRoot.reserves, Appearance.sizes.hyprlandGapsOut)
            readonly property real splitLift: dockJoin.lift
            readonly property real splitPress: dockJoin.press
            // The pill lifts into its own inward elevation margin; a gap bigger
            // than that margin grows the strip by the shortfall (nothing at
            // the defaults) so the lifted pill stays inside its surface.
            readonly property real splitRoom: DockGeometry.splitRoom(Appearance.sizes.hyprlandGapsOut, Appearance.sizes.elevationMargin)
            // What the zone reserves beyond the attached one: the lift, while
            // the pill is up or asked to go up - a boolean that flips at the
            // start of a lift and the end of a landing, so windows are never
            // against a floating pill and the compositor re-tiles twice per
            // gesture at most, on its own animation.
            readonly property real splitZoneExtra: DockGeometry.splitZoneExtra(dockRoot.splitTravel, !dockRoot.joinAttached, dockRoot.splitLift)
            // The look is the tab's while anything still bridges the gap: the
            // colour and the border turn when the neck lets go, in both
            // directions - a drop is part of the pond until it is not. With no
            // lift the look IS the switch, on the effects tier, through a
            // scalar of its own.
            readonly property bool attachedLook: dockRoot.splitTravel > 0 ? dockJoin.fused : dockRoot.attached
            property real lookApart: dockRoot.attached ? 0 : 1
            Behavior on lookApart {
                // Read only while there is no lift; idle otherwise.
                enabled: dockRoot.splitTravel <= 0
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            // Round throughout while the join owns the motion: the neck's
            // meniscus wraps the corner, so a corner that squared itself as
            // the two fused took the body's flat flank with it and the dock
            // read as shrinking on the way out. With no lift there is no neck
            // to wrap anything, and the look scalar still squares it.
            readonly property real apart: dockRoot.splitTravel > 0 ? 1 : dockRoot.lookApart
            // The icons ride the pill: the strip is centred in the box and
            // the pill, lifted, is not.
            readonly property var liftOffset: DockGeometry.liftOffset(root.edge, dockRoot.splitRoom, dockRoot.splitLift)

            anchors {
                top: DockGeometry.anchors(root.edge).top
                bottom: DockGeometry.anchors(root.edge).bottom
                left: DockGeometry.anchors(root.edge).left
                right: DockGeometry.anchors(root.edge).right
            }
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            // The thickness lands on whichever axis the anchors left free;
            // the other one is spanned and the compositor ignores what is
            // asked for there.
            implicitWidth: root.vertical ? dockRoot.dockThickness : dockBackground.implicitWidth
            implicitHeight: root.vertical ? dockBackground.implicitHeight : dockRoot.dockThickness

            mask: Region { item: dockMouseArea }

            // Blur only the painted dock body — its surface carries an
            // elevation margin for the drop shadow, and the whole-surface
            // layerrule blur frosted that margin too (#82). Same treatment as
            // the bar/sidebars; pairs with rules.lua turning the layerrule
            // blur off for this namespace. No region when the background
            // isn't painted: blurring a transparent rect frosts bare
            // wallpaper. Per-corner radii, the bar's centre pill's pattern:
            // attached to the frame the pill squares its outward corners.
            // Published only while the pill is AT REST: Quickshell's Region
            // re-evaluates on its item's own x/y/width/height, and the dock
            // hides by offsetting an ancestor (dockMouseArea's centre offset),
            // which the pill never sees - so a hidden dock left a frosted
            // silhouette over the window where the pill rests. The frost lands
            // when the pill has arrived and lifts the instant it starts to go.
            WindowBlurRegion {
                targetWindow: dockRoot
                // ...and not while the frame's surface is painting the plate
                // (stage 2): the frost for it is the frame's region then, and
                // a second region here, over this window's own transparent
                // pixels, would blur the frame's painted plate a second time.
                region: Region {
                    item: Config.options.dock.showBackground && dockMouseArea.atRest && !dockJoin.drawsPlate ? dockVisualBackground : null
                    topLeftRadius: dockVisualBackground.topLeftRadius
                    topRightRadius: dockVisualBackground.topRightRadius
                    bottomLeftRadius: dockVisualBackground.bottomLeftRadius
                    bottomRightRadius: dockVisualBackground.bottomRightRadius
                }
            }

            DockContextMenu {
                id: dockContextMenu
            }

            MouseArea {
                id: dockMouseArea
                // The strip fills the dock's thickness across its own axis and
                // is sized by the icons along it. Across the axis that is
                // exactly the surface, so centring is the same placement the
                // reveal anchor used to give - with a membership that never
                // changes.
                readonly property var box: DockGeometry.contentBox(
                    root.edge, dockRoot.dockThickness, implicitWidth, implicitHeight)
                width: box.width
                height: box.height

                // The reveal is one number: revealed, a sliver, or one past
                // gone. Which way it travels is the edge's business.
                readonly property var revealOffsets: DockGeometry.revealOffsets(
                    dockRoot.dockThickness, Config.options?.dock.hoverRegionHeight ?? 2)
                readonly property real revealOffset: dockRoot.reveal
                    ? revealOffsets.revealed
                    : (Config.options?.dock.hoverToReveal
                        ? revealOffsets.peeking : revealOffsets.hidden)
                // Toward the screen edge the dock is on, so it travels off the
                // screen to leave. A push the other way would slide it
                // further ONTO the screen to hide.
                readonly property real revealPush: dockMouseArea.revealOffset
                    * DockGeometry.hideDirection(root.edge)

                // The strip used to anchor to its inward side and grow that
                // margin to push itself out, which means the anchor moves to
                // another side when the dock turns. During the turn the new
                // side and the old centre anchor are both live on ONE axis,
                // and Qt answers `right` + `horizontalCenter` by WRITING the
                // item's width (2 * (right - hcenter)) - measured at 5120 on
                // a surface that was already 75 wide. That write outlives the
                // binding it clobbered, because `box` has finished changing
                // by then and never re-evaluates. Centre at every edge and
                // push with an offset instead: same placement, one membership.
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.vertical ? dockMouseArea.revealPush : 0
                anchors.verticalCenterOffset: root.vertical ? 0 : dockMouseArea.revealPush

                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: dockHoverRegion.implicitHeight + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.horizontalCenterOffset {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.verticalCenterOffset {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                // The ANIMATED offsets, not revealOffset: at rest means the
                // slide has finished, for the blur region above.
                readonly property bool atRest: anchors.horizontalCenterOffset === 0 && anchors.verticalCenterOffset === 0

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight

                    Item {
                        id: dockBackground
                        // One anchor at every edge, because the turn is a
                        // change of size rather than of anchors. The body used
                        // to anchor both ends of its across axis and centre on
                        // the other, which means the SET of anchors changes
                        // when the dock turns - and Qt refuses the moment when
                        // left, right and horizontalCenter are all live rather
                        // than re-applying once the third clears. It kept both
                        // orientations' anchors and filled the surface in both
                        // axes: a full-screen pill with the icons spread over
                        // 5120px, of which a side edge shows 75.
                        anchors.centerIn: parent

                        // The dock's whole thickness across its own axis - the
                        // visual background insets the two margins out of it -
                        // and the icons plus a 5px shoulder along the strip.
                        readonly property var box: DockGeometry.contentBox(
                            root.edge, dockRoot.dockThickness,
                            dockRow.implicitWidth + 5 * 2,
                            dockRow.implicitHeight + 5 * 2)
                        implicitWidth: box.width
                        implicitHeight: box.height
                        width: box.width
                        height: box.height

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            visible: false
                        }

                        // The neck (motion-split.md §1, §6): the pill's field
                        // and the band's joined by a smooth-minimum whose
                        // radius is the neck - one shader over one box, the
                        // way the reference builds it. The bridge and its two
                        // concave flanks are the one blend, covered ONCE: a
                        // path drawn under the pill antialiased its half of a
                        // fractional boundary against the pill's half and
                        // composited to a hairline. The blend is nothing at rest, grows to the
                        // seam and holds; the waist (`neckWaist`) is where it
                        // acts, tapering along the band so the neck narrows to
                        // nothing at the pinch - a flat edge over a flat band
                        // The join with the frame: the elastic pull, the
                        // neck that thins and lets go, the squash and the
                        // stretch, and the flare the pill keeps where it
                        // rests. It owns the physics and draws the neck; the
                        // pill below reads its numbers and positions itself.
                        // While the join paints, the pill's Rectangle does not
                        // (`opacity`, no Behavior: the same silhouette in the
                        // same colour, and a translucent fill drawn twice is
                        // darker).
                        FrameJoin {
                            id: dockJoin
                            anchors.fill: parent
                            plate: dockVisualBackground
                            edge: root.edge
                            attached: dockRoot.joinAttached
                            travel: dockRoot.splitTravel
                            // The band is where the pill sits when it is
                            // attached: its own rest outward margin.
                            bandInset: DockGeometry.margins(root.edge,
                                Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)[DockGeometry.outwardSide(root.edge)]
                            // The band's own colour: the join draws the pill
                            // and the neck as one surface with it, so a second
                            // opinion about the colour here would be a seam.
                            color: FrameGeometry.color
                            active: FrameGeometry.enabled && Config.options.dock.showBackground
                            // The field is drawn on the FRAME's surface, not
                            // here (frame-one-surface.md, stage 2): this window
                            // keeps the physics and publishes what the field
                            // needs, below, so the plate and the band are one
                            // outline on one surface.
                            // ...in BOTH states, at rest included, so there is
                            // no hand-over between two surfaces' render loops
                            // (one blank frame at the cut, measured). Under a
                            // fullscreen window a Top surface is buried and the
                            // frame cannot show anything, so the dock paints
                            // itself there as it always did.
                            paintsLocally: dockRoot.fullscreenOnThisMonitor
                            paintsAtRest: true
                        }

                        // What the frame's surface draws: the plate in SCREEN
                        // coordinates - the window's origin from what the
                        // compositor was asked for plus the plate's place in
                        // it, summed up the tree so a reveal slide is followed
                        // too - the corners, and the solver's numbers. Absent
                        // while nothing is fused, so the frame paints nothing.
                        // A record per step is a small object; the map is
                        // reassigned whole by GlobalStates.publishFrameJoin,
                        // under the key "dock" (frame-pin-grammar.md §3).
                        readonly property var frameJoinRecord: {
                            if (!dockJoin.active || !dockJoin.painting || dockRoot.fullscreenOnThisMonitor || !dockRoot.screen) return null;
                            const origin = DockGeometry.surfaceOrigin(root.edge,
                                dockRoot.screen.width, dockRoot.screen.height, dockRoot.width, dockRoot.height,
                                dockRoot.frameMargins[DockGeometry.outwardSide(root.edge)]);
                            const p = dockVisualBackground;
                            return {
                                edge: root.edge,
                                plate: {
                                    x: origin.x + dockMouseArea.x + dockHoverRegion.x + dockBackground.x + p.x,
                                    y: origin.y + dockMouseArea.y + dockHoverRegion.y + dockBackground.y + p.y,
                                    width: p.width, height: p.height
                                },
                                radii: { topLeft: p.topLeftRadius, topRight: p.topRightRadius,
                                         bottomRight: p.bottomRightRadius, bottomLeft: p.bottomLeftRadius },
                                gap: dockJoin.state.gap, neck: dockJoin.state.neck, bulge: dockJoin.state.bulge,
                                meniscus: dockJoin.meniscus, blendPerPixel: dockJoin.blendPerPixel,
                                // The plate's OWN colour, which is the animated one: the
                                // tab-to-pill look change rides its Behavior.
                                climbFraction: dockJoin.climbFraction, color: p.color
                            };
                        }
                        function publishFrameJoin(record) {
                            const name = dockRoot.screen?.name ?? "";
                            if (!name) return;
                            GlobalStates.publishFrameJoin(name, "dock", record);
                        }
                        onFrameJoinRecordChanged: publishFrameJoin(frameJoinRecord)
                        Component.onCompleted: publishFrameJoin(frameJoinRecord)
                        Component.onDestruction: publishFrameJoin(null)

                        Rectangle {
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            // The pill's own margins carry the lift (outward
                            // grows, inward shrinks, the sum is the thickness),
                            // so the blur region - which tracks its item's OWN
                            // geometry - rides the motion, and the frost lands
                            // with the pill rather than a beat after it.
                            readonly property var pillMargins: DockGeometry.liftedMargins(root.edge, dockRoot.dockMargins, dockRoot.splitRoom, dockRoot.splitLift, dockRoot.splitPress)
                            anchors.fill: parent
                            anchors.topMargin:    pillMargins.top
                            anchors.bottomMargin: pillMargins.bottom
                            anchors.leftMargin:   pillMargins.left
                            anchors.rightMargin:  pillMargins.right
                            opacity: dockJoin.drawsPlate ? 0 : 1
                            color: !Config.options.dock.showBackground ? "transparent"
                                   : dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            // The border is a COLOUR change, never a width one: a
                            // width animated from 0 draws nothing until it reaches
                            // 1, which is a pop wearing a tier's name (measured).
                            // The tab's border is its own colour - a transparent
                            // ring would be a seam, since a Rectangle's fill stops
                            // at its border - and the pill's fades in from it.
                            border.width: Config.options.dock.showBackground ? Appearance.borderWidth.standard : 0
                            border.color: dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0Border
                            Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            // `large`: the tab's inward corners sit next to the
                            // fillets and the bar plate's corners in frame mode,
                            // so the pill's radius is a design value, not a sum.
                            radius: Appearance.rounding.large
                            // Round wherever a neck can reach them; see
                            // `apart` above.
                            readonly property var frameRadii: DockGeometry.cornerRadiiAt(root.edge, radius,
                                dockRoot.apart, 0, 1)
                            topLeftRadius:     frameRadii.topLeft
                            topRightRadius:    frameRadii.topRight
                            bottomLeftRadius:  frameRadii.bottomLeft
                            bottomRightRadius: frameRadii.bottomRight
                        }

                        // A GridLayout with a flow rather than a RowLayout, so
                        // the strip turns without the children being destroyed
                        // and rebuilt: one tree, per the spec's §9 Q2. Its id
                        // and its `padding` are reached by DYNAMIC SCOPE from
                        // DockSeparator and DockAppButton - renaming either
                        // yields undefined and NaN geometry, with no error.
                        GridLayout {
                            id: dockRow
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            // Same reasoning as the body above: the strip is
                            // centred at every edge and takes its size from
                            // the module, so no anchor has to appear or
                            // disappear when the dock turns.
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: dockRoot.liftOffset.x
                            anchors.verticalCenterOffset: dockRoot.liftOffset.y
                            readonly property var box: DockGeometry.contentBox(
                                root.edge, dockRoot.dockThickness,
                                implicitWidth, implicitHeight)
                            width: box.width
                            height: box.height
                            rowSpacing: Appearance.spacing.space50
                            columnSpacing: Appearance.spacing.space50
                            property real padding: Appearance.spacing.space100
                            property bool hasPinnedApps: (Config.options?.dock.pinnedApps?.length ?? 0) > 0

                            VerticalButtonGroup {
                                // space50 across the dock's thickness, the
                                // compositor's gap at both ends of the strip.
                                readonly property var pinMargins: DockGeometry.axisMargins(
                                    root.edge, Appearance.spacing.space50, 0,
                                    root.pinned
                                        ? Appearance.sizes.hyprlandGapsOut + 4
                                        : Appearance.sizes.hyprlandGapsOut)
                                Layout.topMargin: pinMargins.top
                                Layout.bottomMargin: pinMargins.bottom
                                Layout.leftMargin: pinMargins.left
                                Layout.rightMargin: pinMargins.right
                                // A layout item that does not fill defaults to
                                // AlignLeft, which at a vertical edge is the
                                // OUTWARD side: the pin hung half off the
                                // painted body. Everything else in the strip
                                // fills its cross axis and never showed it.
                                Layout.alignment: Qt.AlignCenter

                                GroupButton {
                                    baseWidth: 35; baseHeight: 35
                                    visible: Config.options.dock.showPinButton
                                    // The press stretches along the strip, so
                                    // the grown edge is the one the strip runs
                                    // in - at a side edge that is the width.
                                    clickedWidth: root.vertical ? baseWidth + 20 : baseWidth
                                    clickedHeight: root.vertical ? baseHeight : baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        verticalAlignment: Text.AlignVCenter
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned
                                               ? Appearance.m3colors.m3onPrimary
                                               : Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                            DockSeparator {
                                // dockMedia.visible, not the showMedia option:
                                // the tile is absent at a vertical edge and a
                                // separator that reads the option instead of
                                // the tile hides against nothing.
                                shown: Config.options.dock.showPinButton
                                    && (dockRow.hasPinnedApps
                                        || !(dockMedia.visible && dockMedia.hasTrack))
                            }

                            DragApps {
                                id: dragSlots
                                visible: dockRow.hasPinnedApps
                                // space25 across the thickness; the negative
                                // margin is a pull-in at the LEADING end of the
                                // strip, closing the gap an absent pin button
                                // leaves - so it is not the symmetric pair
                                // axisMargins() hands out.
                                readonly property var slotInset: DockGeometry.directedSides(
                                    root.edge, Appearance.spacing.space25, 0)
                                readonly property real slotPull: Config.options.dock.showPinButton
                                    ? 0 : -Appearance.spacing.space200
                                Layout.fillHeight: false
                                Layout.fillWidth: false
                                Layout.topMargin: root.vertical ? slotPull : slotInset.top
                                Layout.bottomMargin: root.vertical ? 0 : slotInset.bottom
                                Layout.leftMargin: root.vertical ? slotInset.left : slotPull
                                Layout.rightMargin: root.vertical ? slotInset.right : 0
                                pinnedApps:    Config.options?.dock.pinnedApps ?? []
                                contextMenu:   dockContextMenu
                                buttonPadding: dockRow.padding
                                btnSize:       46
                                btnSpacing:    1
                            }

                            DockSeparator {
                                shown: dockRow.hasPinnedApps
                                    && (activeAppsArea.activeUnpinned.length > 0
                                        || (dockMedia.visible && MprisController.activePlayer !== null))
                            }

                            Item {
                                id: activeAppsArea
                                Layout.fillHeight: !root.vertical
                                Layout.fillWidth: root.vertical
                                Layout.topMargin: 0
                                Layout.leftMargin: 0
                                property bool requestDockShow: false

                                property var activeUnpinned: {
                                    return TaskbarApps.apps.filter(
                                        a => !a.pinned
                                          && a.appId !== "SEPARATOR"
                                          && a.toplevels.length > 0
                                    )
                                }
                                property bool hasActiveUnpinned: activeUnpinned.length > 0 || dockMedia.visible

                                // The slot's length along the strip is the
                                // fluid's, not a tween's: an icon arriving or
                                // leaving, the media tile coming or going,
                                // and the pill takes the new length on the
                                // drop's own spring (FluidValue) - the plate,
                                // the meniscus and the blur outline derive
                                // from the row, so they breathe with it.
                                implicitWidth:  root.vertical ? parent.width : alongSize.value
                                implicitHeight: root.vertical ? alongSize.value : parent.height
                                FluidValue {
                                    id: alongSize
                                    target: root.vertical ? activeRow.implicitHeight : activeRow.implicitWidth
                                }
                                // The content is laid out at its final size
                                // inside a slot still opening; clipped only
                                // while it moves, so a hover scale at rest is
                                // free to leave the box.
                                clip: alongSize.moving

                                GridLayout {
                                    id: activeRow
                                    anchors.fill: parent
                                    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                    rowSpacing: -Appearance.spacing.space50
                                    columnSpacing: -Appearance.spacing.space50

                                    DockMedia {
                                        id: dockMedia
                                        // A 240x60 card has no 60x240 form.
                                        // The vertical dock omits it the way
                                        // the vertical bar omits what does not
                                        // fit; a richer vertical media tile is
                                        // its own spec (§9 Q1).
                                        visible: Config.options.dock.showMedia && !root.vertical
                                        Layout.fillHeight: true
                                        Layout.topMargin: Appearance.spacing.space150
                                        Layout.bottomMargin: Appearance.spacing.space100
                                        Layout.leftMargin: 0
                                    }

                                    Repeater {
                                        model: activeAppsArea.activeUnpinned
                                        delegate: DockAppButton {
                                            required property var modelData
                                            appToplevel: modelData
                                            appListRoot: appListBridge
                                            contextMenu: dockContextMenu
                                            crossMargin: Appearance.spacing.space25
                                            insetInward:  dockRow.padding + Appearance.spacing.space100
                                            insetOutward: dockRow.padding + Appearance.spacing.space100
                                        }
                                    }
                                }

                                QtObject {
                                    id: appListBridge
                                    property Item lastHoveredButton: null
                                    property bool buttonHovered: false
                                }
                            }

                            DockSeparator {
                                shown: Config.options.dock.showAppsButton
                            }

                            DockButton {
                                crossMargin: 0
                                visible: Config.options.dock.showAppsButton
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                insetInward:  dockRow.padding + 10
                                insetOutward: dockRow.padding + 7
                                // Centred in what is PAINTED, not in the item:
                                // the insets are asymmetric (they compensate
                                // the body's elevation-vs-gap margins), so a
                                // glyph filling the whole rect sits off-centre
                                // by half their difference. Vertically nobody
                                // saw it; at a side edge it reads as a glyph
                                // pushed sideways.
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    anchors.topMargin: parent.topInset
                                    anchors.bottomMargin: parent.bottomInset
                                    anchors.leftMargin: parent.leftInset
                                    anchors.rightMargin: parent.rightInset
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Math.min(parent.width, parent.height) / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
