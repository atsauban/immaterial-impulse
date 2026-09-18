import QtQuick
import QtTest
import "../modules/common/functions/fluid.js" as Fluid

// The join's physics, without a shell (modules/common/functions/fluid.js).
// A detachment holds, thins, lets go and rings; a landing is caught and sucked
// in. Both are pinned here as SHAPE - the order of the phases and their rough
// timing - rather than as numbers a tuning pass would have to chase.
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
            frames.push({ t: (i + 1) * dt, gap: st.gap, neck: st.neck, shape: st.shape, speed: st.speed, settled: st.settled });
            if (st.settled) break;
        }
        return frames;
    }

    function test_a_detachment_holds_then_lets_go() {
        const trace = run(0, travel);
        verify(trace.length > 0);
        // It holds: the neck is still most of itself, and the pill has barely
        // moved, a tenth of a second in.
        const early = trace[Math.round(0.1 / dt) - 1];
        verify(early.neck > 0.5, "a tenth of a second in the neck is still there: " + early.neck);
        verify(early.gap < travel * 0.35, "and the pill has barely moved: " + early.gap);
        // It lets go: the neck reaches nothing, and after it does the pill is
        // moving away faster than it was while held.
        let pinch = -1;
        for (let i = 0; i < trace.length; i++)
            if (trace[i].neck <= 0) { pinch = i; break; }
        verify(pinch > 0, "the neck lets go");
        verify(trace[pinch].t > 0.12, "not before it has had to thin: " + trace[pinch].t);
        verify(trace[pinch].t < 0.6, "and not so late it reads as a stall: " + trace[pinch].t);
        // It rings: the pill goes past where it was asked to stop.
        let peak = 0;
        for (const f of trace) peak = Math.max(peak, f.gap);
        verify(peak > travel * 1.1, "an overshoot worth seeing: " + peak);
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
        for (let i = 0; i < 20; i++) st = Fluid.step(st, travel, dt);
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
}
