import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    // Which backend this card is drawn for. The default is the shell's own
    // freedesktop service, so a call site that says nothing is unchanged.
    property NotificationController controller: NotificationController {}
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false

    // The frame (frame-pin-grammar.md, slice 3). A popup card on the frame's
    // left or right band is FUSED to it - on the band's inner edge, its
    // band-side corners filled by the meniscus, the frame painting the plate
    // - until it is PINNED: the Pin button lifts it off (the elevation gap,
    // the neck cutting) and keeps it. Unpinning is the close: it lands and
    // swallows back into the band, then times out and slides into it. All
    // frame facts come through the controller; the edge and the screen come
    // from the list.
    readonly property string frameEdge: root.popup ? (root.ListView.view?.frameEdge ?? "") : ""
    readonly property string screenName: root.ListView.view?.screenName ?? ""
    readonly property string frameLook: root.controller.frameNotificationsLook
    readonly property bool joinsFrame: root.popup && root.controller.frameEnabled
        && root.frameEdge !== "" && root.frameLook !== "released"
    property bool pinned: false
    property bool closing: false
    readonly property bool joinAttached: root.frameLook === "fused" || !root.pinned || root.closing
    readonly property bool plateOnFrame: root.joinsFrame && cardJoin.drawsPlate
    // The card's offset off the band along the edge's normal: the lift.
    readonly property real liftOffset: root.frameEdge === "right" ? -cardJoin.lift
        : root.frameEdge === "left" ? cardJoin.lift : 0
    readonly property string joinKey: "notification:" + (root.notificationGroup?.appName ?? "")
    function pin(): void {
        root.pinned = true;
        leaveHideTimer.stop();
        root.notifications.forEach(notif => root.controller.cancelTimeout(notif));
    }
    // Unpinning is dismissal: back onto the band first where there is one,
    // then the timeout, which slides it into the band.
    function unpin(): void {
        root.pinned = false;
        if (root.joinsFrame && !cardJoin.fused) {
            root.closing = true;
            return;
        }
        root.notifications.forEach(notif => root.controller.timeout(notif));
    }
    FrameJoin {
        id: cardJoin
        anchors.fill: parent
        plate: background
        edge: root.frameEdge !== "" ? root.frameEdge : "right"
        attached: root.joinAttached
        travel: Appearance.sizes.elevationMargin
        bandInset: 0
        color: root.controller.frameColor
        active: root.joinsFrame
        paintsLocally: false
        paintsAtRest: true
        onMovingChanged: {
            if (cardJoin.moving || !root.closing) return;
            root.closing = false;
            root.notifications.forEach(notif => root.controller.timeout(notif));
        }
    }
    // The plate's colour: the band's while fused, the card's while released,
    // the change on the card's colour tier.
    property color platePaint: cardJoin.fused ? root.controller.frameColor : Appearance.colors.colBackgroundSurfaceContainer
    Behavior on platePaint { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    readonly property var frameJoinRecord: {
        if (!cardJoin.active || !cardJoin.painting || !root.screenName) return null;
        // Read so a move re-evaluates this: the card's place in the list,
        // the list's scroll, the card's own offset. mapToItem(null) is the
        // window, which is the screen for a surface anchored on every edge.
        root.x; root.y; root.width; root.height; background.x; background.y; background.width; background.height;
        root.ListView.view?.contentY; root.ListView.view?.x; root.ListView.view?.y; root.opacity;
        const at = background.mapToItem(null, 0, 0);
        return {
            edge: root.frameEdge,
            plate: { x: at.x, y: at.y, width: background.width, height: background.height },
            radii: { topLeft: background.radius, topRight: background.radius,
                     bottomRight: background.radius, bottomLeft: background.radius },
            gap: cardJoin.state.gap, neck: cardJoin.state.neck, bulge: cardJoin.state.bulge,
            meniscus: cardJoin.meniscus, blendPerPixel: cardJoin.blendPerPixel,
            climbFraction: cardJoin.climbFraction, color: root.platePaint
        };
    }
    // Withdrawn under the screen and key it was PUBLISHED under: by the time
    // a delegate is destroyed its list is gone (no screen name) and its group
    // may be (no app name), and a withdrawal that recomputed either missed -
    // the frame kept painting a plate with no card in it.
    property string publishedScreen: ""
    property string publishedKey: ""
    function publishFrameJoin(record): void {
        if (record) {
            if (!root.screenName || !root.popup) return;
            if (root.publishedScreen && (root.publishedScreen !== root.screenName || root.publishedKey !== root.joinKey))
                root.controller.publishFrameJoin(root.publishedScreen, root.publishedKey, null);
            root.controller.publishFrameJoin(root.screenName, root.joinKey, record);
            root.publishedScreen = root.screenName;
            root.publishedKey = root.joinKey;
        } else if (root.publishedScreen) {
            root.controller.publishFrameJoin(root.publishedScreen, root.publishedKey, null);
            root.publishedScreen = "";
            root.publishedKey = "";
        }
    }
    onFrameJoinRecordChanged: publishFrameJoin(frameJoinRecord)
    Component.onCompleted: publishFrameJoin(frameJoinRecord)
    Component.onDestruction: publishFrameJoin(null)
    property real padding: Appearance.spacing.space150
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true

    // Grace period before a popup starts hiding after the mouse leaves, so a
    // brief unfocus (e.g. moving the cursor onto the notification, or a 50ms
    // flicker) doesn't instantly dismiss it. Re-entering cancels the pending
    // hide. See issue #28.
    Timer {
        id: leaveHideTimer
        interval: Config.options?.notifications?.hideDelayOnLeave ?? 200
        onTriggered: {
            if (root.containsMouse) return;
            root.notifications.forEach(notif => {
                root.controller.timeout(notif);
            });
        }
    }

    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) {
            leaveHideTimer.stop();
            root.notifications.forEach(notif => {
                root.controller.cancelTimeout(notif);
            });
        } else if (!root.pinned) {
            leaveHideTimer.restart();
        }
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    root.controller.discard(notif);
                });
            });
        }
    }

    function toggleExpanded() {
        if (expanded) implicitHeightAnim.enabled = true;
        else implicitHeightAnim.enabled = false;
        root.expanded = !root.expanded;
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) 
                root.destroyWithAnimation();
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    // The painted card, published so the popup window can scope the
    // compositor's blur to the cards and leave the gaps - and the shadow
    // below - alone. See WindowBlurRegion in NotificationPopup.qml.
    readonly property Item blurItem: background

    StyledRectangularShadow {
        target: background
        visible: popup && !root.plateOnFrame
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        // Stood down while the frame paints the plate: the same silhouette
        // in the same colour, and a translucent fill drawn twice is darker.
        color: root.plateOnFrame ? "transparent"
            : popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        anchors.leftMargin: root.xOffset + root.liftOffset

        Behavior on anchors.leftMargin {
            // Off while the join moves the card: a Behavior whose target
            // moves every frame restarts every frame and never ticks.
            enabled: !dragManager.dragging && !cardJoin.moving
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        
        clip: true
        implicitHeight: root.expanded ? 
            row.implicitHeight + padding * 2 :
            Math.min(80, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: Appearance.spacing.space150

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? 
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ? 
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 
                    5 : 0) : 0
                // spacing: 00
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight)

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: pinButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Appearance.spacing.space100
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: Appearance.spacing.space150
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    // Pinned means released and kept (frame-pin-grammar.md):
                    // the card lifts off the band and stops timing out.
                    // Unpinning is the dismissal. Only for a popup card; the
                    // sidebar's list has nothing to pin.
                    RippleButton {
                        id: pinButton
                        visible: root.popup
                        anchors.right: expandButton.left
                        anchors.rightMargin: pinButton.visible ? Appearance.spacing.space50 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: expandButton.implicitHeight
                        implicitWidth: pinButton.visible ? expandButton.implicitHeight : 0
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.pinned ? Appearance.colors.colPrimaryContainer
                            : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer2Hover, 0.5)
                        colBackgroundHover: root.pinned ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: root.pinned ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                        onClicked: root.pinned ? root.unpin() : root.pin()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "keep"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.pinned ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledToolTip {
                            text: root.pinned ? Translation.tr("Unpin and dismiss") : Translation.tr("Pin: keep it here")
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? Appearance.spacing.space50 : Appearance.spacing.space50
                    // clip: true
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() : 
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        controller: root.controller
                        expanded: root.expanded
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }

            }
        }
    }
}
