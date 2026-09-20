import QtQuick
import QtTest
import "../modules/common/functions/fluid.js" as Fluid

// The join's physics, without a shell (modules/common/functions/fluid.js).
// The model is CLEAVAGE: the two are held while a ring cuts inward to a
// thread, and they part when it lets go - the pinch is the event, not the
// travel. A landing is caught and sucked in. Both are pinned here as SHAPE -
// the order of the phases and their rough timing - rather than as numbers a
// tuning pass would have to chase.
TestCase {
    name: "Fluid"

    readonly property real travel: 5
    readonly property real dt: 1 / 60

    // Steps until settled (or the guard trips) and returns the trace.
    function run(from, target, guardSeconds) {
        let st = Fluid.rest(from);
        if (from === 0) st.neck = 1;
        const frames = [];
        const guard = Math.round((guardSeconds ?? 4) / dt);
        for (let i = 0; i < guard; i++) {
            st = Fluid.step(st, target, dt);
            frames.push({ t: (i + 1) * dt, gap: st.gap, neck: st.neck, shape: st.shape,
                          bulge: st.bulge, speed: st.speed, settled: st.settled });
            if (st.settled) break;
        }
        return frames;
    }

    function test_a_detachment_is_held_until_the_bridge_lets_go() {
        const trace = run(0, travel);
        verify(trace.length > 0);
        // The bridge HOLDS. A clamp pulls with the same force however far the
        // two are pulled, so at this travel the gap cannot open until the
        // bridge has thinned enough for the spring to beat it: the furrow is
        // what the eye is watching, and the travel comes after. (The other
        // reading - a rubber band, weaker as the bridge thins - separates the
        // whole way down and is a different model, not a tuning of this one.)
        const early = trace[Math.round(0.1 / dt) - 1];
        verify(early.neck > 0.5, "a tenth of a second in the bridge is still most of itself: " + early.neck);
        verify(early.gap < travel * 0.1, "and the two have barely moved: " + early.gap);
        // Both sides are pulled out of shape while it lasts: the leaving side
        // elongates, the staying side is drawn after it.
        let maxShape = 0, maxBulge = 0;
        for (const f of trace) { maxShape = Math.max(maxShape, f.shape); maxBulge = Math.max(maxBulge, f.bulge); }
        verify(maxShape > 1, "the leaving side elongates: " + maxShape);
        verify(maxBulge > 1, "the staying side is drawn after it: " + maxBulge);
        // It lets go: the bridge reaches nothing.
        let pinch = -1;
        for (let i = 0; i < trace.length; i++)
            if (trace[i].neck <= 0) { pinch = i; break; }
        verify(pinch > 0, "the neck lets go");
        verify(trace[pinch].t > 0.12, "not before it has had to thin: " + trace[pinch].t);
        verify(trace[pinch].t < 0.6, "and not so late it reads as a stall: " + trace[pinch].t);
        // Both round up afterwards, and STOP there. The chosen model carries
        // no wobble: the shapes come back to rest without ringing through it,
        // so a bounce here is the damping having drifted, not a nicety.
        let minShape = 0, minBulge = 0;
        for (let i = pinch; i < trace.length; i++) {
            minShape = Math.min(minShape, trace[i].shape);
            minBulge = Math.min(minBulge, trace[i].bulge);
        }
        verify(minShape > -0.6, "the leaving side does not ring past its rest: " + minShape);
        verify(minBulge > -0.6, "nor does the staying side: " + minBulge);
        const end = trace[trace.length - 1];
        verify(Math.abs(end.shape) < 0.15 && Math.abs(end.bulge) < 0.15,
               "and both are back at rest: " + end.shape + ", " + end.bulge);
        // ...and it stops, near the target.
        const last = trace[trace.length - 1];
        verify(last.settled, "it settles");
        verify(Math.abs(last.gap - travel) < 0.5, "at the travel: " + last.gap);
        verify(last.t < 2.5, "inside a gesture's worth of time: " + last.t);
    }

    function test_a_landing_is_caught_and_sucked_in() {
        const trace = run(travel, 0);
        let contact = -1;
        for (let i = 0; i < trace.length; i++)
            if (trace[i].neck > 0) { contact = i; break; }
        verify(contact > 0, "the surface takes it");
        // The neck opens far faster than it thinned: a landing coalesces.
        let opened = -1;
        for (let i = contact; i < trace.length; i++)
            if (trace[i].neck > 0.9) { opened = i; break; }
        verify(opened > 0 && (trace[opened].t - trace[contact].t) < 0.2,
               "the neck floods: " + (opened > 0 ? trace[opened].t - trace[contact].t : -1));
        // It flattens as it lands: the shape goes negative (squashed).
        let squash = 0;
        for (const f of trace) squash = Math.min(squash, f.shape);
        verify(squash < -0.4, "it flattens on contact: " + squash);
        const last = trace[trace.length - 1];
        verify(last.settled && last.gap < 0.1, "and ends fused: " + last.gap);
    }

    function test_a_reversal_carries_its_speed_through() {
        // Half way out, asked back: the state keeps its velocity, so the
        // return starts from where and how fast it was going.
        let st = Fluid.rest(0);
        st.neck = 1;
        // Far enough in that the bridge has let go and the body is moving:
        // under a clamp the first frames are all furrow and no travel, so a
        // reversal sampled there would be testing nothing.
        for (let i = 0; i < 16; i++) st = Fluid.step(st, travel, dt);
        const mid = { gap: st.gap, speed: st.speed };
        verify(mid.gap > 0, "it did move");
        const back = Fluid.step(st, 0, dt);
        // Velocity carries: the frame after the reversal is still travelling
        // the way it was, slowed by one frame of the new pull rather than
        // restarted from a standstill (which is what a re-targeted curve
        // does, and why it needed a proportional duration to look sane).
        verify(mid.speed > 0, "it was on its way out: " + mid.speed);
        verify(back.gap > mid.gap, "and the next frame is still outbound: " + back.gap + " from " + mid.gap);
        verify(back.speed < mid.speed, "but slower: " + back.speed + " from " + mid.speed);
    }

    function test_a_long_frame_is_walked_in_pieces() {
        // A stall must slow the motion, never explode it.
        let st = Fluid.rest(0);
        st.neck = 1;
        const big = Fluid.step(st, travel, 0.5);
        verify(isFinite(big.gap) && Math.abs(big.gap) < travel * 3, "a half-second frame stays sane: " + big.gap);
        verify(isFinite(big.shape) && Math.abs(big.shape) <= 5.001);
    }

    // --- the slot spring -----------------------------------------------------

    function springRun(from, to, seconds) {
        let st = Fluid.springRest(from);
        const frames = [];
        for (let i = 0; i < Math.round(seconds / dt); i++) {
            st = Fluid.spring(st, to, dt);
            frames.push({ t: (i + 1) * dt, value: st.value, settled: st.settled });
            if (st.settled) break;
        }
        return frames;
    }

    function test_a_slot_opens_with_the_drops_own_overshoot_and_lands_on_its_target() {
        // A 46 px icon slot opening: past the target once, by less than a
        // fifth of the step, then settled ON the target within a second.
        const frames = springRun(0, 46, 2);
        const peak = Math.max(...frames.map(f => f.value));
        verify(peak > 46.5, "overshoots: " + peak);
        verify(peak < 46 * 1.2, "by less than a fifth: " + peak);
        const last = frames[frames.length - 1];
        verify(last.settled, "settles");
        compare(last.value, 46);
        verify(last.t < 1.0, "within a second: " + last.t);
        // ...and it is most of the way there quickly enough to read as a
        // response rather than a drift.
        const half = frames.find(f => f.value >= 23);
        verify(half.t < 0.15, "half way by " + half.t);
    }

    function test_a_slot_closing_is_the_same_motion_reversed() {
        const open = springRun(0, 46, 2).map(f => f.value);
        const close = springRun(46, 0, 2).map(f => 46 - f.value);
        compare(close.length, open.length);
        for (let i = 0; i < open.length; i += 7)
            fuzzyCompare(close[i], open[i], 0.01);
    }

    function test_a_retarget_mid_flight_keeps_its_velocity() {
        // An icon that leaves while its slot is still opening: the spring
        // turns around from where it is, at the speed it has, rather than
        // restarting - no jump in either value or direction on the frame of
        // the change.
        let st = Fluid.springRest(0);
        for (let i = 0; i < 6; i++) st = Fluid.spring(st, 46, dt);
        const before = st.value, speedBefore = st.speed;
        st = Fluid.spring(st, 0, dt);
        verify(st.value > before, "still travelling outward on the frame of the retarget");
        verify(st.speed < speedBefore, "and already slowing");
        verify(!st.settled);
    }

    function test_a_slots_long_frame_is_walked_in_pieces() {
        const fine = springRun(0, 46, 0.5);
        let coarse = Fluid.springRest(0);
        for (let i = 0; i < 5; i++) coarse = Fluid.spring(coarse, 46, 0.1);
        const fineAtHalf = fine.find(f => f.t >= 0.5 - 1e-6) ?? fine[fine.length - 1];
        fuzzyCompare(coarse.value, fineAtHalf.value, 0.5);
    }
}
