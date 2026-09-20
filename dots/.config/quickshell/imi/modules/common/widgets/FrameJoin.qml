import qs.modules.common
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
 *     //   join.fused       whether anything still bridges the two
 *     //   join.drawsPlate  the field is painting the plate; the plate's own
 *     //                    Rectangle stands down
 *
 * The field itself is FrameJoinField, and it need not be drawn HERE: with
 * `paintsLocally` off the join keeps the physics and the consumer publishes
 * what the field needs to whichever surface should paint it - the frame's,
 * so the plate and the band are one outline (frame-one-surface.md, stage 2).
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
    // What the join is DRAWN IN, and whether it is live at all. The colour
    // is the caller's: a shared widget that reached into a service for it
    // could only ever draw the frame's own surfaces, and the bench and the
    // cheatsheet page both need it in a colour that can be read against their
    // own ground (tests/lint_dumb_widgets.py).
    required property color color
    property bool active: true
    // The flare the plate keeps where it rests, and how much blend a pixel of
    // gap needs to stay bridged - both scaled by the SLANT, which is how far
    // the surfaces lean out into the join. 1 is the study's 100%; the chosen
    // model is 110%.
    //
    // The meniscus is a smooth-minimum RADIUS, not the flare it draws: the
    // field's own fillet comes out a fraction of it, so 14 drew a two-pixel
    // lip where the study has a fifth of the plate's thickness (measured off
    // the live dock: 2 px of flare on a 60 px pill against the study's 8.2 on
    // 40). 45 measures 12 rows of climb and 15 px of spread, which is the
    // study's rest silhouette.
    property real meniscus: 45 * root.slant
    property real blendPerPixel: 4 * root.slant
    property real slant: 1.1
    // How far up the body the meniscus may climb, as a fraction of the blend
    // radius. 0 is the field's own answer - one radius in every direction,
    // which climbs about 1.6x as far as it spreads. Anything else caps the
    // climb without touching the spread, because the two are otherwise the
    // same number and the study this motion was chosen from has them the
    // other way round (climb 0.43 of the corner, spread 0.50).
    property real climbFraction: 0
    // Whether the field is drawn on THIS item. Off, the join is physics only
    // and `painting` says when a remote painter should be drawing the plate.
    property bool paintsLocally: true
    // Whether the field paints the plate at REST as well - free and settled,
    // no neck - rather than only while something bridges the two. Where the
    // painter is another surface this is what removes the hand-over: the plate
    // going from that surface's field to this element's own Rectangle crosses
    // two render loops nothing orders, and the frame between them showed the
    // icons over bare backdrop (measured at 60 fps: one blank frame at the
    // cut, every time). With one painter in both states there is no frame to
    // get wrong.
    property bool paintsAtRest: false

    // --- what the consumer reads --------------------------------------------

    readonly property real lift: root.state.gap
    readonly property real press: root.state.shape
    readonly property bool fused: root.state.neck > 0
    // True while anything is still moving, for a consumer that wants to hold
    // something steady until it stops (a blur region, a reservation).
    readonly property bool moving: !root.state.settled

    // --- the physics --------------------------------------------------------

    readonly property real target: (root.active && !root.attached) ? Math.max(0, root.travel) : 0
    property var state: Fluid.rest(0)

    onTargetChanged: {
        // Asked for no motion, there is none: the join is wherever it was
        // asked to be, this frame. The shell's motion policy collapses every
        // catalogued duration to zero for reduce motion, and a physics solver
        // that kept integrating through it would be the one thing still
        // moving.
        if (!root.active || Appearance.animation.scaleStep(1) <= 0) {
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
    // A hand let go: the join continues from where the hand left the plate
    // (`gap` px off the band, at rest) toward whatever `attached` now says -
    // a drag that pinned settles up to the travel, one that did not springs
    // back, and neither jumps.
    function disturb(gap: real): void {
        if (!root.active) return;
        root.state = Object.assign({}, root.state, { gap: Math.max(0, gap), speed: 0, settled: false });
        stepper.running = true;
    }

    FrameAnimation {
        id: stepper
        // Gated: a FrameAnimation left running is a repaint every frame for
        // the life of the shell. It runs while the join is moving and stops
        // itself the frame it settles.
        running: false
        onTriggered: {
            // The speed slider reaches the solver as its CLOCK: a slower shell
            // advances the physics by less of a second per frame, so the hold,
            // the cut and the settle all stretch together.
            const h = Appearance.animation.scaleStep(frameTime);
            if (h <= 0) {
                root.state = Fluid.rest(root.target);
                stepper.running = false;
                return;
            }
            root.state = Fluid.step(root.state, root.target, h);
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

    // Painted while anything still bridges the two, and while the band is
    // still ringing back from having been pulled out of shape. This is the
    // one answer for the local field and for a remote one: the plate stands
    // down on it either way.
    readonly property bool painting: root.active && neck.fieldAvailable && root.plate.visible
        && (root.paintsAtRest || root.fused || neck.bulge > 0.1)

    FrameJoinField {
        id: neck
        edge: root.edge
        plateX: root.plate.x
        plateY: root.plate.y
        plateWidth: root.plate.width
        plateHeight: root.plate.height
        radiusTopLeft: root.plate.topLeftRadius
        radiusTopRight: root.plate.topRightRadius
        radiusBottomRight: root.plate.bottomRightRadius
        radiusBottomLeft: root.plate.bottomLeftRadius
        bandEdge: root.bandEdge
        color: root.color
        gap: root.state.gap
        neck: root.state.neck
        bulgeRaw: root.state.bulge
        meniscus: root.meniscus
        blendPerPixel: root.blendPerPixel
        climbFraction: root.climbFraction
        painting: root.paintsLocally && root.painting
    }

    // The plate hands over while the field paints it, so the two never draw
    // the same edge twice.
    readonly property bool drawsPlate: root.painting
}
