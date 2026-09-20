import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "../../imi/dock/dock_geometry.js" as DockGeometry

Rectangle {
    id: root

    readonly property string dockEdge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    readonly property bool dockVertical: DockGeometry.isVertical(root.dockEdge)

    // The inset pair is asymmetric because the dock body's margins are: the
    // elevation margin is inward (the shadow is drawn there), the compositor's
    // gap outward. Spelled as top/bottom this was a separator that reached
    // across a bottom dock and along a left one.
    readonly property var dockMargins: DockGeometry.directedSides(
        root.dockEdge,
        Appearance.sizes.elevationMargin + dockRow.padding + Appearance.rounding.normal - 4,
        Appearance.sizes.hyprlandGapsOut + dockRow.padding + Appearance.rounding.normal)

    // Whether the separator belongs in the row. Not `visible`: a separator
    // that vanishes takes its hairline and the layout's spacing around it
    // out of the strip in one frame while the slot beside it is still
    // opening on the fluid's spring. Its own width rides the same spring
    // (FluidValue) and it fades with it, staying in the layout until it has
    // no width left.
    property bool shown: true
    readonly property real open: room.value
    FluidValue {
        id: room
        target: root.shown ? 1 : 0
    }
    visible: root.open > 0.001
    opacity: root.open
    Layout.topMargin: root.dockMargins.top
    Layout.bottomMargin: root.dockMargins.bottom
    Layout.leftMargin: root.dockMargins.left
    Layout.rightMargin: root.dockMargins.right

    // A hairline across the strip, filling the dock's depth.
    Layout.fillHeight: !root.dockVertical
    Layout.fillWidth: root.dockVertical
    implicitWidth: root.dockVertical ? 0 : root.open
    implicitHeight: root.dockVertical ? root.open : 0

    color: Appearance.colors.colOutlineVariant
}
