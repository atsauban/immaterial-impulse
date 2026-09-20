.pragma library

// The frame join's field, on the CPU: the same rounded box, half-plane,
// tapered smooth minimum and hump that shaders/frame_join.frag draws,
// evaluated here for the one thing a shader cannot hand back - the silhouette
// it painted, as rectangles, for a compositor's blur region to follow.
//
// The region has to be the outline. A region wider than the paint frosts bare
// wallpaper beside the meniscus, and a region narrower leaves paint over a raw
// backdrop; both read as a second material along the curve. The first attempt
// approximated the flare with a strip sized from the study's ratios, and over
// a striped wallpaper in the review sandbox each end of the dock carried a
// 14x20 px block of blurred, unpainted stripes where the strip overshot the
// concave fillet (the fillet climbs 31 rows and spreads 21 px at the band; the
// strip was 17 wide and 23 tall). Measured against that same capture, this
// port's profile is within one pixel of the shader's on every row.
//
// Every function takes the shader's uniforms by their shader names, in the
// field item's own pixels: pillCenter/pillSize/bandNormal as {x, y},
// pillRadii as {x, y, z, w} (top-left, top-right, bottom-right, bottom-left),
// and the scalars bandOrigin, blend, waistHalf, waistCenter, softness, reach,
// bulge, bulgeHalf, climbFall. Keep these in step with the shader: the
// oracle for both is a capture of the rendered field (tests/tst_join_field.qml
// pins one), not either file.

function roundedBox(px, py, hx, hy, radii) {
    var right = px >= 0, bottom = py >= 0;
    var top = right ? radii.y : radii.x;
    var low = right ? radii.z : radii.w;
    var r = bottom ? low : top;
    var qx = Math.abs(px) - hx + r, qy = Math.abs(py) - hy + r;
    var mx = Math.max(qx, 0), my = Math.max(qy, 0);
    return Math.min(Math.max(qx, qy), 0) + Math.sqrt(mx * mx + my * my) - r;
}

function smoothMinimum(a, b, k) {
    if (k <= 0.001) return Math.min(a, b);
    var h = Math.max(k - Math.abs(a - b), 0) / k;
    return Math.min(a, b) - h * h * k * 0.25;
}

function along(u, px, py) {
    return px * Math.abs(u.bandNormal.y) + py * Math.abs(u.bandNormal.x);
}

function toward(u, px, py) {
    return px * u.bandNormal.x + py * u.bandNormal.y;
}

function blendAt(u, px, py) {
    var t = u.waistHalf > 0 ? (along(u, px, py) - u.waistCenter) / u.waistHalf : 2;
    var k = u.blend * Math.max(0, 1 - t * t);
    if (!(u.climbFall > 0)) return k;
    var above = Math.max(0, u.bandOrigin - toward(u, px, py));
    var fall = Math.max(0, 1 - above / u.climbFall);
    return k * fall * fall;
}

function bulgeAt(u, px, py) {
    if (!(u.bulge > 0) || !(u.bulgeHalf > 0)) return 0;
    var t = (along(u, px, py) - u.waistCenter) / u.bulgeHalf;
    var fall = Math.max(0, 1 - t * t);
    return u.bulge * fall * fall;
}

// The joined field at a point: negative inside the paint.
function field(u, px, py) {
    var half = u.reach * 0.5;
    var cx = u.pillCenter.x + u.bandNormal.x * half, cy = u.pillCenter.y + u.bandNormal.y * half;
    var hx = u.pillSize.x * 0.5 + Math.abs(u.bandNormal.x) * half;
    var hy = u.pillSize.y * 0.5 + Math.abs(u.bandNormal.y) * half;
    var pill = roundedBox(px - cx, py - cy, hx, hy, u.pillRadii);
    var band = u.bandOrigin - toward(u, px, py) - bulgeAt(u, px, py) + u.softness;
    return smoothMinimum(pill, band, blendAt(u, px, py));
}

// The painted rows of a field `width` x `height` pixels, as rectangles in the
// same pixels, merged where consecutive rows cover the same columns. Rows are
// taken across the band's normal, from the field's far side toward the band's
// inner surface; the rows INSIDE the band are left out, since the band's own
// region covers them. A row's coverage is read outward from the waist's
// centre in each direction - the field is one connected body about it while
// anything bridges the two, and at the pinch the region losing the far side
// for a frame costs nothing the eye can catch.
//
// This runs on the GUI thread once per frame while the join moves, in QV4,
// which is some thirty times slower than V8 on arithmetic like this: the
// first cut took 2.1 ms a call and eight benched fields dropped the shell's
// frame rate. So the uniforms are unpacked into locals once, a row the blend
// cannot reach (farther from the band than the blend radius) is the pill's
// own rounded box and is solved in closed form, and a row it can reach is
// bisected inside a bracket seeded from the row before it - the profile is
// continuous, and neighbouring rows differ by a few pixels at most.
//
// `maxRects` is how many rectangles the caller can carry (a pool of Regions
// declared ahead of time); past it, the closest neighbouring rows are merged
// into their bounding box, which widens the region by pixels rather than
// dropping rows.
function outline(u, width, height, maxRects) {
    var w = Math.max(0, Math.floor(Number(width) || 0)), h = Math.max(0, Math.floor(Number(height) || 0));
    var nx = u.bandNormal.x, ny = u.bandNormal.y;
    var horizontal = ny !== 0;
    var sign = nx + ny; // +1 or -1: which way along the axis the band lies
    var rows = horizontal ? h : w, span = horizontal ? w : h;
    // The pill as the field sees it (reach into the band), split into the
    // along-the-band axis (a) and the across axis (n).
    var half = u.reach * 0.5;
    var ca = horizontal ? u.pillCenter.x : u.pillCenter.y;
    var cn = (horizontal ? u.pillCenter.y : u.pillCenter.x) + sign * half;
    var ha = (horizontal ? u.pillSize.x : u.pillSize.y) * 0.5;
    var hn = (horizontal ? u.pillSize.y : u.pillSize.x) * 0.5 + half;
    // Corner radii by (side of the waist, side across): the shader's order
    // is top-left, top-right, bottom-right, bottom-left in x/y; for a side
    // band the "along" axis is y, so the roles turn with it.
    var rTL = u.pillRadii.x, rTR = u.pillRadii.y, rBR = u.pillRadii.z, rBL = u.pillRadii.w;
    var rLoNeg = rTL, rHiNeg = horizontal ? rTR : rBL; // across-negative side: along-negative, along-positive
    var rLoPos = horizontal ? rBL : rTR, rHiPos = rBR; // across-positive side
    var bandOrigin = u.bandOrigin, blend = u.blend, waistHalf = u.waistHalf, waistCenter = u.waistCenter;
    var softness = u.softness, bulge = u.bulge, bulgeHalf = u.bulgeHalf, climbFall = u.climbFall;
    var hasBulge = bulge > 0 && bulgeHalf > 0;
    var c = waistCenter;

    // roundedBox(p - pillCenter) for a point at (along a, across n).
    function pill(a, n) {
        var da = a - ca, dn = n - cn;
        var r = dn < 0 ? (da < 0 ? rLoNeg : rHiNeg) : (da < 0 ? rLoPos : rHiPos);
        var qa = Math.abs(da) - ha + r, qn = Math.abs(dn) - hn + r;
        var ma = qa > 0 ? qa : 0, mn = qn > 0 ? qn : 0;
        return Math.min(Math.max(qa, qn), 0) + Math.sqrt(ma * ma + mn * mn) - r;
    }
    // The field at (along a, across n): the pill and the band's half-plane,
    // less the hump, through the tapered smooth minimum.
    function fieldAt(a, n) {
        var toward = n * sign;
        var t = waistHalf > 0 ? (a - waistCenter) / waistHalf : 2;
        var k = blend * Math.max(0, 1 - t * t);
        if (climbFall > 0) {
            var above = Math.max(0, bandOrigin - toward);
            var fall = Math.max(0, 1 - above / climbFall);
            k *= fall * fall;
        }
        var hump = 0;
        if (hasBulge) {
            var tb = (a - waistCenter) / bulgeHalf;
            var fb = Math.max(0, 1 - tb * tb);
            hump = bulge * fb * fb;
        }
        var p = pill(a, n), b = bandOrigin - toward - hump + softness;
        if (k <= 0.001) return Math.min(p, b);
        var hh = Math.max(k - Math.abs(p - b), 0) / k;
        return Math.min(p, b) - hh * hh * k * 0.25;
    }
    // The pill's own half-extent along the band on the row across at `n`,
    // on the side `dir` (-1/+1) of its centre - the rounded box solved,
    // for rows the blend cannot reach. NaN where the row misses the pill.
    function pillReach(n, dir) {
        var dn = Math.abs(n - cn);
        if (dn > hn) return NaN;
        var r = n < cn ? (dir < 0 ? rLoNeg : rHiNeg) : (dir < 0 ? rLoPos : rHiPos);
        var into = dn - (hn - r);
        if (into <= 0 || r <= 0) return ha;
        var s = r * r - into * into;
        return ha - r + (s > 0 ? Math.sqrt(s) : 0);
    }
    // Where the paint ends on one side of the centre on this row, bisected:
    // first in a bracket around the previous row's answer, else from scratch.
    function reachOn(n, dir, seed, hi) {
        var lo = 0;
        if (seed >= 0) {
            var a = Math.max(0, seed - 3), b = Math.min(hi, seed + 6);
            if (fieldAt(c + a * dir, n) < 0 && fieldAt(c + b * dir, n) >= 0) { lo = a; hi = b; }
            else if (fieldAt(c + hi * dir, n) < 0) return hi;
        } else if (fieldAt(c + hi * dir, n) < 0) {
            return hi;
        }
        for (var i = 0; i < 6 && hi - lo > 0.2; i++) {
            var mid = (lo + hi) * 0.5;
            if (fieldAt(c + mid * dir, n) < 0) lo = mid; else hi = mid;
        }
        return lo;
    }

    var hiAll = Math.min(Math.max(c, span - c), ha + blend + bulge + 8);
    var bulgeMax = hasBulge ? bulge : 0;
    var out = [];
    var prevL = -1, prevR = -1;
    // From the far side toward the band, so each row seeds the next.
    var start = sign > 0 ? 0 : rows - 1, stop = sign > 0 ? rows : -1, step = sign > 0 ? 1 : -1;
    for (var i = start; i !== stop; i += step) {
        var n = i + 0.5;
        var toward = n * sign;
        if (toward >= bandOrigin) continue;
        var left, right;
        if (bandOrigin - toward - bulgeMax + softness > blend + 1) {
            // Out of the blend's reach: the pill alone.
            left = pillReach(n, -1); right = pillReach(n, 1);
            if (isNaN(left)) { prevL = prevR = -1; continue; }
        } else {
            if (fieldAt(c, n) >= 0) { prevL = prevR = -1; continue; }
            left = reachOn(n, -1, prevL, hiAll); right = reachOn(n, 1, prevR, hiAll);
        }
        prevL = left; prevR = right;
        var a0 = Math.max(0, Math.ceil(c - left - 0.5)), a1 = Math.min(span - 1, Math.floor(c + right - 0.5));
        if (a1 < a0) continue;
        var rect = horizontal
            ? { x: a0, y: i, width: a1 - a0 + 1, height: 1 }
            : { x: i, y: a0, width: 1, height: a1 - a0 + 1 };
        var prev = out.length ? out[out.length - 1] : null;
        if (prev && (horizontal
                ? prev.x === rect.x && prev.width === rect.width && (prev.y + prev.height === rect.y || rect.y + 1 === prev.y)
                : prev.y === rect.y && prev.height === rect.height && (prev.x + prev.width === rect.x || rect.x + 1 === prev.x))) {
            if (horizontal) { if (rect.y < prev.y) prev.y = rect.y; prev.height += 1; }
            else { if (rect.x < prev.x) prev.x = rect.x; prev.width += 1; }
        } else {
            out.push(rect);
        }
    }
    var max = Math.floor(Number(maxRects) || 0);
    if (max > 0) coalesce(out, max, horizontal);
    return out;
}

function coalesce(rects, max, horizontal) {
    while (rects.length > max && rects.length > 1) {
        var best = 0, bestCost = Infinity;
        for (var i = 0; i + 1 < rects.length; i++) {
            var a = rects[i], b = rects[i + 1];
            var cost = horizontal
                ? Math.abs(a.x - b.x) + Math.abs(a.x + a.width - b.x - b.width)
                : Math.abs(a.y - b.y) + Math.abs(a.y + a.height - b.y - b.height);
            if (cost < bestCost) { bestCost = cost; best = i; }
        }
        var p = rects[best], q = rects[best + 1];
        var x0 = Math.min(p.x, q.x), y0 = Math.min(p.y, q.y);
        var x1 = Math.max(p.x + p.width, q.x + q.width), y1 = Math.max(p.y + p.height, q.y + q.height);
        rects.splice(best, 2, { x: x0, y: y0, width: x1 - x0, height: y1 - y0 });
    }
}
