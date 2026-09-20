import qs.modules.common
import QtQuick
import "../functions/fluid.js" as Fluid

/**
 * One number that moves like the shell's fluid does: a slot's length, a
 * separator's room, anything a layout has to take up or give back when
 * something arrives or leaves. `target` is where it has been asked to be;
 * `value` is where it is, on the drop's own spring (fluid.js `spring`), so a
 * width that changes overshoots by a tenth and draws back rather than easing
 * to a stop - the same motion family as the join, read from the same
 * constants, driven by the same clock (the motion policy's `scaleStep`: a
 * slower shell slows the spring, reduce motion lands it at once).
 *
 * Non-visual. The stepper is a FrameAnimation gated the way FrameJoin's is:
 * it runs while the value is moving and stops itself the frame it settles,
 * so a slot at rest costs nothing per frame.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property real target: 0
    // Where the value is this frame. Starts ON the target: a slot that is
    // already there has nothing to animate.
    readonly property real value: root.state.value
    readonly property bool moving: !root.state.settled

    property var state: Fluid.springRest(0)

    onTargetChanged: {
        if (Appearance.animation.scaleStep(1) <= 0) {
            root.state = Fluid.springRest(root.target);
            return;
        }
        // The state carries its velocity through, so a target that changes
        // again mid-flight turns the value around rather than restarting it.
        root.state = Object.assign({}, root.state, { settled: false });
        stepper.running = true;
    }

    FrameAnimation {
        id: stepper
        running: false
        onTriggered: {
            const h = Appearance.animation.scaleStep(frameTime);
            if (h <= 0) {
                root.state = Fluid.springRest(root.target);
                stepper.running = false;
                return;
            }
            root.state = Fluid.spring(root.state, root.target, h);
            if (root.state.settled)
                stepper.running = false;
        }
    }

    Component.onCompleted: root.state = Fluid.springRest(root.target)
}
