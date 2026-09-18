.pragma library

// A drop and a pond, integrated (docs/proposals/motion-split.md §4). The
// shell's split motion - a pill leaving the frame's band and landing back on
// it - is not a curve between two states. It is four things happening to each
// other, and the eye knows all four:
//
//   the ELEMENT has a position and momentum;
//   the NECK between drop and pond has a width that thins under stress and
//     runs away once thin (Rayleigh-Plateau: a thinner neck thins faster,
//     which is why a drop lets go all at once after holding on);
//   SURFACE TENSION pulls the drop back toward the pond in proportion to how
//     much neck is left, so a detachment resists, resists, and then releases,
//     and a landing is caught and sucked in;
//   the drop's SHAPE lags its motion - elongating as it pulls away, flattening
//     as it lands - and rings afterwards.
//
// Everything below is per second and in pixels, integrated semi-implicitly
// with a clamped step, so a dropped frame slows the motion rather than
// exploding it. Pure, so tests/tst_fluid.qml can pin it; Dock.qml steps it
// from a FrameAnimation and reads the state out.

// --- the constants that are the feel ---------------------------------------

// The drop's own spring toward where it has been asked to be, and its
// damping. Under-damped on purpose: the ring after a landing is the pond
// settling.
var K_POS = 110;
var C_POS = 5;

// The bridge's pull, per pixel of stretch, at full width. A RUBBER BAND, not
// a clamp: it pulls harder the further the two are pulled apart and weaker as
// the bridge thins, so the bodies separate WHILE the furrow deepens - which is
// the whole thing the eye is watching. A constant pull instead pinned the gap
// at zero until the bridge had already gone, and then the split was a jump
// with nothing between the two (measured: the bridge was down to 0.06 by the
// time the gap reached a single pixel, so there was never a visible neck).
var TENSION = 90;

// How fast a neck under stress thins, and how much faster a thin one goes.
// The runaway is the whole character of the break: at a full neck this is
// slow, and by the time it is half gone it is three times faster.
var THIN = 1.5;
var THIN_RUNAWAY = 4.0;

// How fast a neck opens once the pond has the drop, and how close the drop
// has to be for that to happen. Coalescence is much faster than separation -
// the interface is pulled open rather than torn.
var FLOOD = 22;
var CONTACT_GAP = 1.5;

// The shape oscillator: how far the drop's length leads its speed, how
// stiffly it returns, how fast that ringing dies.
var SHAPE_PER_SPEED = 0.06;
var K_SHAPE = 300;
var C_SHAPE = 6;
// How far the shape may go, either way, so a fast gesture cannot fold the
// pill through itself.
var SHAPE_LIMIT = 5;

// The FURROW. Two bodies do not part by one of them walking away: the shared
// body elongates, a constriction forms and deepens, the waist pinches, and
// both halves round up. The drag on each side is greatest when the bridge is
// HALF gone - a thin bridge pulls hardest, a whole one is not yet pulling and
// a severed one has let go - so everything the furrow drives is shaped like
// `4 * bridge * (1 - bridge)`, which is nothing at either end and one in the
// middle.
//
// `BULGE_GAIN` is how far, in pixels, the surface of the side that stays is
// drawn toward the side that leaves. `SHAPE_FURROW` is how far the leaving
// side elongates along the same axis while it is still attached.
function furrow(bridge) {
    var b = Math.max(0, Math.min(1, Number(bridge) || 0));
    return 4 * b * (1 - b);
}
var BULGE_GAIN = 3.5;
var K_BULGE = 350;
var C_BULGE = 7;
var SHAPE_FURROW = 2.2;

// The longest step to integrate in one go. A frame that took longer (a
// stall, a resume from sleep) is walked in pieces instead.
var MAX_STEP = 1 / 90;

// --- state -----------------------------------------------------------------

// Fused and still, which is where a dock that is attached starts.
function rest(gap) {
    var g = Math.max(0, Number(gap) || 0);
    return {
        gap: g,            // px between the drop and the pond
        speed: 0,          // px/s, positive away from the pond
        neck: g > 0 ? 0 : 1, // 0..1 of the bridge between the two
        shape: 0,          // px: positive stretched along the travel, negative squashed
        shapeSpeed: 0,
        bulge: 0,          // px the staying side is drawn toward the leaving one
        bulgeSpeed: 0,
        settled: true
    };
}

// True once nothing is moving enough to be worth another frame. The
// thresholds are a fifth of a pixel rather than a thousandth: a join that
// keeps stepping to chase a hundredth of a pixel is a repaint every frame for
// a motion nobody can see, and this is the only thing that stops the stepper.
function isSettled(st, target) {
    return Math.abs(st.gap - target) < 0.15
        && Math.abs(st.speed) < 1.5
        && Math.abs(st.shape) < 0.15
        && Math.abs(st.shapeSpeed) < 1.5
        && Math.abs(st.bulge) < 0.15
        && Math.abs(st.bulgeSpeed) < 1.5
        && (target > 0 ? st.neck <= 0 : st.neck >= 1);
}

// One step. `target` is the gap the drop has been asked to hold: 0 fused,
// the travel apart. Returns a NEW state; nothing here mutates its argument,
// so a caller can keep the old one to compare against.
function step(st, target, dt) {
    var t = Math.max(0, Number(target) || 0);
    var remaining = Math.max(0, Number(dt) || 0);
    var s = {
        gap: st.gap, speed: st.speed, neck: st.neck, shape: st.shape,
        shapeSpeed: st.shapeSpeed, bulge: st.bulge || 0,
        bulgeSpeed: st.bulgeSpeed || 0, settled: false
    };
    while (remaining > 0) {
        var h = Math.min(MAX_STEP, remaining);
        remaining -= h;

        // The neck. Asked to leave, it thins under stress and the thinning
        // runs away; asked to land, it stays gone until the pond can reach
        // the drop, and then floods open.
        if (t > 0) {
            if (s.neck > 0)
                s.neck = Math.max(0, s.neck - h * THIN * (1 + THIN_RUNAWAY * (1 - s.neck)));
        } else if (s.gap <= CONTACT_GAP || s.neck > 0) {
            s.neck = Math.min(1, s.neck + h * FLOOD * Math.max(0.05, 1 - s.neck));
        }

        // The element. Its spring toward where it was asked to be, its
        // damping, and surface tension pulling it at the surface for as much
        // neck as is left.
        //
        // Tension RESISTS separation; it does not press something that is
        // already resting into the surface. Applied unconditionally it kept
        // accelerating a fused, settled element downward for ever - the join
        // never came to rest, and every frame kicked the shape oscillator
        // through the floor clamp below.
        var pull = K_POS * (t - s.gap);
        var tension = (pull > 0 || s.gap > 0) ? TENSION * s.neck * s.gap : 0;
        var accel = pull - C_POS * s.speed - tension;
        s.speed += accel * h;
        s.gap += s.speed * h;
        // The pond is a floor: what is left of an undershoot becomes shape,
        // which is the drop flattening into the surface rather than through it.
        if (s.gap < 0) {
            s.shapeSpeed -= s.speed * 0.5;
            s.gap = 0;
            if (s.speed < 0) s.speed = 0;
        }

        // The furrow's drag, which both sides feel: the staying side's
        // surface is pulled toward the leaving one, and the leaving one
        // elongates along the same axis. Both peak when the bridge is half
        // gone and are nothing at either end, so both round up after the cut -
        // through their own springs, which is where the ring comes from.
        var drag = furrow(s.neck);

        // The shape lags the motion: it wants to be as long as the body is
        // fast, plus what the furrow is stretching out of it, and rings its
        // way back when both stop.
        var want = Math.max(-SHAPE_LIMIT, Math.min(SHAPE_LIMIT,
            s.speed * SHAPE_PER_SPEED + drag * SHAPE_FURROW));
        s.shapeSpeed += (K_SHAPE * (want - s.shape) - C_SHAPE * s.shapeSpeed) * h;
        s.shape += s.shapeSpeed * h;
        s.shape = Math.max(-SHAPE_LIMIT, Math.min(SHAPE_LIMIT, s.shape));

        // The staying side's own surface, on its own spring: it rises with the
        // furrow, and once the bridge lets go there is nothing holding it, so
        // it rings flat again.
        s.bulgeSpeed += (K_BULGE * (drag * BULGE_GAIN - s.bulge) - C_BULGE * s.bulgeSpeed) * h;
        s.bulge += s.bulgeSpeed * h;
    }
    s.settled = isSettled(s, t);
    return s;
}

// --- what the surfaces read ------------------------------------------------

// The neck's waist, in pixels along the band: the drop's own width while they
// are fused, nothing once it has let go. Wider than the pill at rest because
// the blend that draws it is also the meniscus, and a taper the pill's own
// width puts the flare where the two are already joined and none at the ends,
// which is the only place a flare can be seen.
function waist(st, pillAlong, restFactor) {
    var w = Number(pillAlong) || 0;
    var f = restFactor === undefined ? 2.5 : (Number(restFactor) || 0);
    return w * f * Math.max(0, Math.min(1, st.neck));
}

// The blend radius that draws it: enough to bridge the gap (a polynomial
// smooth-minimum needs about twice it), plus the meniscus the drop keeps
// where it sits, and nothing at all once the neck has gone.
function blend(st, meniscus, perPixel) {
    if (st.neck <= 0) return 0;
    var m = Number(meniscus) || 0;
    var k = perPixel === undefined ? 4 : (Number(perPixel) || 0);
    return m + k * Math.max(0, st.gap);
}

// How round the drop's outward corners are: square while a neck still bridges
// them, round once it has gone, and eased between so a corner never jumps.
function cornerRound(st) {
    return Math.max(0, Math.min(1, 1 - st.neck));
}
