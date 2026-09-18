import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Window
import "../functions/fluid.js" as Fluid

/**
 * How an element joins the frame, and how it lets go.
 *
 * Frame mode's premise is that the shell is one surface: a border around the
 * screen with the bar, the dock and eventually every other edge surface as
 * parts of it rather than islands over it. An element that can leave that
 * surface has to leave it the way a drop leaves water - holding on, thinning,
 * letting go, and ringing afterwards - and come back the same way. This is
 * that join, once, for whoever needs it.
 *
 * The consumer owns its own geometry. This owns the physics
 * (`functions/fluid.js`) and draws the neck between the two:
 *
 *     FrameJoin {
 *         id: join
 *         anchors.fill: parent      // the element's own box
 *         plate: myPlate            // the painted shape that joins the frame
 *         edge: "bottom"            // which side of the screen the band is on
 *         attached: Config...       // asked to be part of the frame
 *         travel: Appearance.sizes.hyprlandGapsOut
 *         bandInset: restOutwardMargin
 *     }
 *     // ...and the plate reads back:
 *     //   join.lift        px away from the band
 *     //   join.press       px across it: negative squashed, positive stretched
 *     //   join.cornerRound 0 square where it is joined, 1 round once free
 *     //   join.fused       whether anything still bridges the two
 */
Item {
    id: root

    // --- what the consumer sets ---------------------------------------------

    // The painted shape that joins the frame. Its geometry is read, never
    // written: the consumer positions it from `lift` and `press`.
    required property Item plate
    // Which screen edge the frame's band is on, in the dock's vocabulary.
    required property string edge
    // Asked to be part of the frame. The join takes its time about it.
    property bool attached: true
    // How far apart the detached rest is, in pixels.
    property real travel: 0
    // How far the band's inner edge is from this item's own `edge` side. The
    // element's rest outward margin, usually: the band is where the plate sits
    // when it is attached.
    property real bandInset: 0
    // The frame's colour, and whether this join is live at all.
    property color color: FrameGeometry.color
    property bool active: true
    // The flare the plate keeps where it rests, and how much blend a pixel of
    // gap needs to stay bridged.
    property real meniscus: 14
    property real blendPerPixel: 4

    // --- what the consumer reads --------------------------------------------

    readonly property real lift: root.state.gap
    readonly property real press: root.state.shape
    readonly property real cornerRound: root.active ? Fluid.cornerRound(root.state) : 1
    readonly property bool fused: root.state.neck > 0
    // True while anything is still moving, for a consumer that wants to hold
    // something steady until it stops (a blur region, a reservation).
    readonly property bool moving: !root.state.settled

    // --- the physics --------------------------------------------------------

    readonly property real target: (root.active && !root.attached) ? Math.max(0, root.travel) : 0
    property var state: Fluid.rest(0)

    onTargetChanged: {
        if (!root.active) {
            root.state = Fluid.rest(root.target);
            return;
        }
        // A target that moves wakes the stepper; the state carries its own
        // velocity through, which is what makes a reversal mid-gesture
        // continue rather than restart.
        root.state = Object.assign({}, root.state, { settled: false });
        stepper.running = true;
    }
    onActiveChanged: if (!root.active) root.state = Fluid.rest(root.target);

    FrameAnimation {
        id: stepper
        // Gated: a FrameAnimation left running is a repaint every frame for
        // the life of the shell. It runs while the join is moving and stops
        // itself the frame it settles.
        running: false
        onTriggered: {
            root.state = Fluid.step(root.state, root.target, frameTime);
            if (root.state.settled)
                stepper.running = false;
        }
    }

    Component.onCompleted: root.state = Fluid.rest(root.target)

    // --- the neck -----------------------------------------------------------

    readonly property bool vertical: root.edge === "left" || root.edge === "right"
    // The band's inner edge and the direction into the band, in this item's
    // own frame. One half-plane for the shader.
    readonly property real bandEdge: {
        if (root.edge === "top" || root.edge === "left") return root.bandInset;
        return (root.vertical ? root.width : root.height) - root.bandInset;
    }
    readonly property point bandNormal: {
        if (root.edge === "top") return Qt.point(0, -1);
        if (root.edge === "bottom") return Qt.point(0, 1);
        return root.edge === "left" ? Qt.point(-1, 0) : Qt.point(1, 0);
    }
    readonly property real plateAlong: root.vertical ? root.plate.height : root.plate.width

    ShaderEffect {
        id: neck
        // Only where a shader can draw: the software scene graph draws no
        // ShaderEffect, and one that failed to load draws nothing. There the
        // plate keeps its own Rectangle and the join has no neck.
        readonly property bool fieldAvailable: neck.GraphicsInfo.api !== GraphicsInfo.Software
            && neck.status !== ShaderEffect.Error
        readonly property bool painting: root.active && neck.fieldAvailable && root.fused && root.plate.visible
        visible: painting

        // The box: the plate, the room between it and the band, a couple of
        // pixels INSIDE the band so the coverage ramp has somewhere to land,
        // and the meniscus' reach past the plate's ends along the band - a box
        // the plate's own length draws the flare where nothing is rasterised.
        readonly property real pad: root.meniscus + 2
        readonly property real into: 2
        readonly property rect box: {
            const p = root.plate;
            const e = root.edge;
            if (e === "bottom") {
                const bottom = Math.max(p.y + p.height, root.bandEdge + into);
                return Qt.rect(p.x - pad, p.y, p.width + pad * 2, bottom - p.y);
            }
            if (e === "top") {
                const top = Math.min(p.y, root.bandEdge - into);
                return Qt.rect(p.x - pad, top, p.width + pad * 2, p.y + p.height - top);
            }
            if (e === "left") {
                const left = Math.min(p.x, root.bandEdge - into);
                return Qt.rect(left, p.y - pad, p.x + p.width - left, p.height + pad * 2);
            }
            const right = Math.max(p.x + p.width, root.bandEdge + into);
            return Qt.rect(p.x, p.y - pad, right - p.x, p.height + pad * 2);
        }
        x: box.x
        y: box.y
        width: box.width
        height: box.height

        // The field's inputs, in the box's own pixels.
        readonly property vector2d resolution: Qt.vector2d(width, height)
        readonly property color fillColor: root.color
        readonly property vector2d pillCenter: Qt.vector2d(
            root.plate.x - neck.x + root.plate.width / 2,
            root.plate.y - neck.y + root.plate.height / 2)
        readonly property vector2d pillSize: Qt.vector2d(root.plate.width, root.plate.height)
        readonly property vector4d pillRadii: Qt.vector4d(
            root.plate.topLeftRadius, root.plate.topRightRadius,
            root.plate.bottomRightRadius, root.plate.bottomLeftRadius)
        readonly property vector2d bandNormal: Qt.vector2d(root.bandNormal.x, root.bandNormal.y)
        readonly property real bandOrigin: (root.vertical ? root.bandEdge - neck.x : root.bandEdge - neck.y)
            * (root.bandNormal.x + root.bandNormal.y)
        readonly property real blend: Fluid.blend(root.state, root.meniscus, root.blendPerPixel)
        readonly property real waistHalf: Fluid.waist(root.state, root.plateAlong) / 2
        readonly property real waistCenter: root.vertical ? neck.pillCenter.y : neck.pillCenter.x
        readonly property real softness: 0.75
        // How far the plate's field reaches into the band: the first pixels of
        // a lift, before the blend can bridge them.
        readonly property real reach: Math.max(0, 2 - root.lift)
        // The WINDOW's ratio, which follows fractional scaling; the screen's is
        // the output's integer scale.
        readonly property real pixelRatio: Window.window?.devicePixelRatio ?? 1
        fragmentShader: Qt.resolvedUrl("../shaders/frame_join.frag.qsb")
    }

    // The plate hands over while the field paints it, so the two never draw
    // the same edge twice.
    readonly property bool drawsPlate: neck.painting
}
