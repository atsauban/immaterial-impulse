import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        // ...and while a card is still leaving: the list animates its exit
        // (a fused card slides into the band) only on a visible surface, and
        // a window that hid on the count cut it to a blink.
        visible: (Notifications.popupList.length > 0 || listview.cardItems.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        property string position: {
            const raw = Config.options.notifications.position ?? "top_right"
            if (raw === "top") return "top_right"
            if (raw === "bottom") return "bottom_right"
            return raw
        }
        property bool isTop: position.startsWith("top")
        property bool isBottom: position.startsWith("bottom")
        property bool isCenter: position.endsWith("center")
        property bool isLeft: position.endsWith("left")
        property bool isRight: position.endsWith("right")
        // The frame's band the cards fuse to (frame-pin-grammar.md, slice
        // 3): the side positions have one, the centre ones do not - a stack
        // under the top band has one card on the band and the rest on
        // nothing. Fused, the list sits ON the band's inner edge.
        readonly property string frameEdge: root.isRight ? "right" : root.isLeft ? "left" : ""
        readonly property bool frameFused: FrameGeometry.enabled && root.frameEdge !== ""
            && String(Config.options.appearance.frame.notifications ?? "auto") !== "released"

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        // Fused to the frame the window IS the screen: a card publishes its
        // plate in screen coordinates for the frame to paint, and a surface
        // placed inside the other surfaces' exclusive zones (Auto) starts
        // below the bar - measured, a plate painted 40 px above its card.
        // The frame's own insets take the bar's place in the margins below.
        exclusionMode: root.frameFused ? ExclusionMode.Ignore : ExclusionMode.Auto

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: listview.contentItem
        }

        // Every popup card already draws a StyledRectangularShadow; the
        // catch-all whole-surface blur was frosting all of them (#82, #89).
        // Scope the blur to the cards themselves - not the list's bounding
        // box, which would take in the gaps between cards and frost bare
        // wallpaper right where each shadow falls. Pairs with rules.lua
        // turning the layerrule blur off for this namespace.
        // A popup's time is up: a fused card slides into the band first, and
        // the service removes it after (or on its own fallback if this window
        // is not showing it).
        Connections {
            target: Notifications
            function onPopupExpiring(id) {
                const card = root.frameFused ? listview.cardFor(id) : null;
                if (card) card.leaveWithAnimation(root.frameEdge === "left", () => Notifications.timeoutNotification(id));
                else Notifications.timeoutNotification(id);
            }
        }

        WindowBlurRegion {
            targetWindow: root
            // ...less the cards the frame paints: their blur is the frame's
            // region, and one here would frost the wallpaper under a card
            // that has stood down.
            regionItems: listview.cardItems.filter(card => !(card.parent?.plateOnFrame ?? false))
            regionItemsRadius: Appearance.rounding.normal
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            anchors.leftMargin: root.isLeft ? (root.frameFused ? FrameGeometry.bandExtent("left") : Appearance.spacing.space50) : 0
            anchors.rightMargin: root.isRight ? (root.frameFused ? FrameGeometry.bandExtent("right") : Appearance.spacing.space50) : 0
            frameEdge: root.frameFused ? root.frameEdge : ""
            screenName: root.screen?.name ?? ""
            anchors.topMargin: (root.frameFused ? FrameGeometry.insets.top : 0) + Appearance.spacing.space50
            anchors.bottomMargin: (root.frameFused ? FrameGeometry.insets.bottom : 0) + Appearance.spacing.space50
            width: Appearance.sizes.notificationPopupWidth
            popup: true
            verticalLayoutDirection: root.isBottom ? ListView.BottomToTop : ListView.TopToBottom

            states: [
                State {
                    name: "top_left"
                    when: root.position === "top_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "top_center"
                    when: root.position === "top_center"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "top_right"
                    when: root.position === "top_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "bottom_left"
                    when: root.position === "bottom_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                },
                State {
                    name: "bottom_center"
                    when: root.position === "bottom_center"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                },
                State {
                    name: "bottom_right"
                    when: root.position === "bottom_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                }
            ]
        }
    }
}