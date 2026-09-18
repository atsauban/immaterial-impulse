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

// Surface tension's pull toward the pond, at a full neck. Bigger than the
// spring can manage across the travel, which is what makes a detachment have
// to WAIT for the neck to thin rather than simply losing a tug of war.
var TENSION = 1000;

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
        neck: g > 0 ? 0 : 1, // 0..1 of the drop's own width
        shape: 0,          // px: positive stretched along the travel, negative squashed
        shapeSpeed: 0,
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
        shapeSpeed: st.shapeSpeed, settled: false
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
        var tension = (pull > 0 || s.gap > 0) ? TENSION * s.neck : 0;
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

        // The shape lags the motion: it wants to be as long as the drop is
        // fast, and rings its way back when the drop stops.
        var want = Math.max(-SHAPE_LIMIT, Math.min(SHAPE_LIMIT, s.speed * SHAPE_PER_SPEED));
        s.shapeSpeed += (K_SHAPE * (want - s.shape) - C_SHAPE * s.shapeSpeed) * h;
        s.shape += s.shapeSpeed * h;
        s.shape = Math.max(-SHAPE_LIMIT, Math.min(SHAPE_LIMIT, s.shape));

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
