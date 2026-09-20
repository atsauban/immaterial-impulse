import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The frame join's SHAPE, live, in the cheatsheet's Frame join tab.
 *
 * The join (modules/common/widgets/FrameJoin.qml) is how an element leaves the
 * frame's band and comes back: one solver, one distance field, and a silhouette
 * that has to read as two bodies parting rather than a box sliding. None of
 * that can be judged from a still, and the only surface that currently uses it
 * is the dock - so a change to the field was reviewed by toggling the dock and
 * watching one edge of one element at one size.
 *
 * This page is the rest of the evidence. Every surface that will have to do
 * this join is here at TRUE size, on its own edge, running the same solver at
 * the same time, so a change can be read against a 120 px pill and a 630 px
 * dock at once - the ratio of the blend radius to the body is what the eye
 * actually reads, and it is the thing that differs most between them.
 *
 * The two columns are the open question the field poses. Its blend is ONE
 * radius, so the fillet it draws climbs the body's corner about 1.6x as far as
 * it spreads along the band; `climbFraction` fades the radius with height
 * instead, which caps the climb and keeps the spread. The shell ships the
 * isotropic answer (`climbFraction: 0`); the second column is what the other
 * one would look like, kept because the question comes back every time the
 * meniscus is retuned.
 *
 * Behind Config.options.developer.enable - see Cheatsheet.qml for the tab. The
 * same page runs standalone as `qs -p <shell>/bench_frame_join.qml`, which is
 * the form to use when it has to be driven from a script.
 */
Item {
    id: root

    implicitWidth: Math.min(1460, (root.Window.window?.screen?.width ?? 1920) - 240)
    implicitHeight: Math.min(820, (root.Window.window?.screen?.height ?? 1080) - 260)

    // The silhouette is the whole subject, so the two colours are the strongest
    // pair the theme has rather than the surface colours the join wears in the
    // shell: an outline judged against the dock's own translucency is the thing
    // that made the first round of this unmeasurable.
    readonly property color ground: Appearance.colors.colLayer1
    readonly property color chrome: Appearance.colors.colOnLayer1

    property bool attached: true
    property real travel: 8
    property real slant: 1.1
    property real meniscus: 45
    property real climbFraction: 0.55
    property bool cycling: true

    // Every surface that has to join the frame, at the size it will really be.
    readonly property var surfaces: [
        { label: Translation.tr("dock"), edge: "bottom", w: 630, h: 60, r: Appearance.rounding.large },
        { label: Translation.tr("bar widget popup"), edge: "top", w: 300, h: 120, r: Appearance.rounding.normal },
        { label: Translation.tr("notification"), edge: "right", w: 330, h: 92, r: Appearance.rounding.normal },
        { label: Translation.tr("small pill"), edge: "bottom", w: 120, h: 40, r: Appearance.rounding.small }
    ]

    Timer {
        interval: 2400
        repeat: true
        running: root.cycling && root.visible
        onTriggered: root.attached = !root.attached
    }

    // One surface: a band at an edge, a plate that joins it, and the join
    // between them. The plate is positioned FROM the join - nothing here
    // sequences anything, which is the whole point of the widget.
    component Surface: Item {
        id: cell
        required property string label
        required property string edge
        required property real plateW
        required property real plateH
        required property real plateRadius
        required property real climb
        readonly property bool sideways: cell.edge === "left" || cell.edge === "right"
        readonly property real band: 2

        Rectangle {
            color: root.chrome
            width: cell.sideways ? cell.band : parent.width
            height: cell.sideways ? parent.height : cell.band
            anchors {
                top: cell.edge !== "bottom" ? parent.top : undefined
                bottom: cell.edge !== "top" ? parent.bottom : undefined
                left: cell.edge !== "right" ? parent.left : undefined
                right: cell.edge !== "left" ? parent.right : undefined
            }
        }

        Rectangle {
            id: plate
            color: root.chrome
            radius: cell.plateRadius
            // The travel axis carries the lift and the stretch; the other axis
            // is the plate's own size.
            width: cell.sideways ? cell.plateW + join.press : cell.plateW
            height: cell.sideways ? cell.plateH : cell.plateH + join.press
            x: {
                if (cell.edge === "left") return cell.band + join.lift;
                if (cell.edge === "right") return cell.width - cell.band - join.lift - width;
                return (cell.width - width) / 2;
            }
            y: {
                if (cell.edge === "top") return cell.band + join.lift;
                if (cell.edge === "bottom") return cell.height - cell.band - join.lift - height;
                return (cell.height - height) / 2;
            }
            // The field paints the plate while it has one; a translucent fill
            // drawn twice is darker than the same fill drawn once.
            opacity: join.drawsPlate ? 0 : 1
        }

        FrameJoin {
            id: join
            anchors.fill: parent
            plate: plate
            edge: cell.edge
            attached: root.attached
            travel: root.travel
            bandInset: cell.band
            color: root.chrome
            slant: root.slant
            meniscus: root.meniscus * root.slant
            climbFraction: cell.climb
        }

        // On the INWARD side, away from the band being joined, so a label
        // never crosses the outline it is labelling.
        ColumnLayout {
            x: Appearance.spacing.space100
            y: cell.edge === "top" ? cell.height - implicitHeight - Appearance.spacing.space50
                                   : Appearance.spacing.space50
            spacing: 0
            StyledText {
                text: cell.label
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                text: "lift " + join.lift.toFixed(2) + "  press " + join.press.toFixed(2)
                      + (join.fused ? "  fused" : "  free")
                color: Appearance.colors.colSubtext
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space125

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space150

            RippleButtonWithIcon {
                materialIcon: root.attached ? "arrow_upward" : "arrow_downward"
                mainText: root.attached ? Translation.tr("Detach") : Translation.tr("Attach")
                onClicked: {
                    root.cycling = false;
                    root.attached = !root.attached;
                }
            }
            ConfigSwitch {
                text: Translation.tr("Cycle")
                checked: root.cycling
                onToggleRequested: root.cycling = !root.cycling
            }
            ConfigSlider {
                text: Translation.tr("Travel")
                from: 2
                to: 24
                value: root.travel
                usePercentTooltip: false
                // ConfigSlider carries no step: it is a continuous control
                // with a Behavior on its value, and the rounding belongs to
                // whoever wants whole pixels.
                onValueModified: newValue => root.travel = Math.round(newValue)
            }
            ConfigSlider {
                text: Translation.tr("Meniscus")
                from: 5
                to: 90
                value: root.meniscus
                usePercentTooltip: false
                onValueModified: newValue => root.meniscus = Math.round(newValue)
            }
            ConfigSlider {
                text: Translation.tr("Climb")
                from: 0.15
                to: 1.5
                value: root.climbFraction
                usePercentTooltip: false
                onValueModified: newValue => root.climbFraction = Math.round(newValue * 20) / 20
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Isotropic — one radius, the climb follows the spread (shipped)")
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Anisotropic — the climb is capped, the spread is kept")
                color: Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space100

            Repeater {
                model: root.surfaces
                delegate: Item {
                    id: surfaceRow
                    required property var modelData
                    readonly property var spec: surfaceRow.modelData
                    readonly property bool sideways: spec.edge === "left" || spec.edge === "right"
                    // What one pane needs to hold this surface at TRUE size,
                    // with room for the lift and a readout.
                    readonly property real paneW: (sideways ? spec.w + root.travel + 2 : spec.w) + 48
                    readonly property real paneH: (sideways ? spec.h : spec.h + root.travel + 2) + 48
                    // Side by side while the pair fits, stacked when it does
                    // not. This page is shown in a window the compositor sizes
                    // and in a cheatsheet tab that sizes itself; a layout that
                    // only reads correctly at one width silently crops the
                    // outline it exists to show.
                    readonly property bool paired: width >= paneW * 2 + Appearance.spacing.space100

                    Layout.fillWidth: true
                    Layout.preferredHeight: paired ? paneH : paneH * 2 + Appearance.spacing.space100

                    Grid {
                        anchors.fill: parent
                        columns: surfaceRow.paired ? 2 : 1
                        spacing: Appearance.spacing.space100

                        Repeater {
                            // The spec is reached by ID rather than by counting
                            // `parent`s: a delegate inside a Grid inside a
                            // Repeater is several levels from its own model
                            // row, and that chain breaks silently the first
                            // time the layout changes.
                            model: [0, root.climbFraction]
                            delegate: Rectangle {
                                id: pane
                                required property real modelData
                                width: surfaceRow.paired
                                    ? (surfaceRow.width - Appearance.spacing.space100) / 2
                                    : surfaceRow.width
                                height: surfaceRow.paired
                                    ? surfaceRow.height
                                    : (surfaceRow.height - Appearance.spacing.space100) / 2
                                color: root.ground
                                radius: Appearance.rounding.small
                                Surface {
                                    anchors.fill: parent
                                    anchors.margins: Appearance.borderWidth.standard
                                    label: pane.modelData > 0
                                        ? surfaceRow.spec.label + "  ·  climb " + pane.modelData.toFixed(2)
                                        : surfaceRow.spec.label + "  ·  isotropic"
                                    edge: surfaceRow.spec.edge
                                    plateW: surfaceRow.spec.w
                                    plateH: surfaceRow.spec.h
                                    plateRadius: surfaceRow.spec.r
                                    climb: pane.modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
