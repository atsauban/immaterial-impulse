import QtQuick
import QtQuick.Window
import "../functions/fluid.js" as Fluid
import "../functions/join_field.js" as JoinField

/**
 * The frame join's FIELD: the plate, the neck between it and the band, and
 * the band's own surface, as one distance field drawn by one ShaderEffect
 * (shaders/frame_join.frag). FrameJoin owns the physics; this is the painter,
 * split out so the field can be drawn on a surface other than the one whose
 * element is moving - docs/proposals/frame-one-surface.md, stage 2: the frame
 * surface draws the dock's plate, so the whole silhouette is ONE outline on
 * one surface, which is what a blur region and later a specular rim can be
 * made to follow.
 *
 * Everything arrives in the PARENT's coordinates: the plate's rect, the
 * band's inner edge along the edge's axis, and the solver's numbers. It reads
 * no service and no singleton - a caller on the dock's surface hands it the
 * plate's own geometry, a caller on the frame's hands it a published record,
 * and the cheatsheet's bench hands it a rectangle it drew.
 */
ShaderEffect {
    id: field

    // --- what the caller sets -----------------------------------------------

    // Which screen edge the band is on, in the dock's vocabulary.
    property string edge: "bottom"
    // The plate: where it is and how round, in the parent's frame.
    property real plateX: 0
    property real plateY: 0
    property real plateWidth: 0
    property real plateHeight: 0
    property real radiusTopLeft: 0
    property real radiusTopRight: 0
    property real radiusBottomRight: 0
    property real radiusBottomLeft: 0
    // The band's inner edge, as the coordinate along the edge's axis (a y for
    // top and bottom, an x for left and right), in the parent's frame.
    property real bandEdge: 0
    // The fill, and whether the owner wants the field painted at all.
    property color color: "transparent"
    property bool painting: false
    // The solver's state (functions/fluid.js): the gap, what is left of the
    // bridge, and how far the band's surface is drawn toward the plate.
    property real gap: 0
    property real neck: 0
    property real bulgeRaw: 0
    // The blend that draws the meniscus, per FrameJoin.
    property real meniscus: 45
    property real blendPerPixel: 4
    property real climbFraction: 0

    // --- what the caller reads ----------------------------------------------

    // Only where a shader can draw: the software scene graph draws no
    // ShaderEffect, and one that failed to load draws nothing. There the
    // plate keeps its own Rectangle and the join has no neck.
    readonly property bool fieldAvailable: field.GraphicsInfo.api !== GraphicsInfo.Software
        && field.status !== ShaderEffect.Error
    visible: field.painting && field.fieldAvailable

    // --- the box ------------------------------------------------------------

    readonly property bool vertical: field.edge === "left" || field.edge === "right"
    readonly property real plateAlong: field.vertical ? field.plateHeight : field.plateWidth
    readonly property point bandNormalPoint: {
        if (field.edge === "top") return Qt.point(0, -1);
        if (field.edge === "bottom") return Qt.point(0, 1);
        return field.edge === "left" ? Qt.point(-1, 0) : Qt.point(1, 0);
    }
    // The box: the plate, the room between it and the band, and the
    // meniscus' reach past the plate's ends along the band - a box the
    // plate's own length draws the flare where nothing is rasterised. It
    // stops AT the band's inner edge. The band's rows are the band's own
    // (the frame's bands, the dock's, the bench's) and are painted once: the
    // band's half-plane still shapes the field, but its coverage ramp lands
    // 0.75 px inside a band this box never rasterises. Two rows into the band
    // it painted that first row at a quarter, and the band, standing down
    // under the box, left a blurred, unpainted hairline 26 px long past each
    // end of the fillet (measured, review sandbox, striped wallpaper).
    // Whole pixels: the box's origin is where the shader's pixel grid starts,
    // and a half-pixel origin smears every edge of the field across two device
    // pixels while the region that follows it (`outline`) is integer.
    readonly property real pad: Math.ceil(field.meniscus) + 2
    // A caller may PIN the box instead (a rect in the parent's coordinates,
    // empty to leave it to the plate). The frame does: measured on its
    // surface, a ShaderEffect whose own x/width change after creation
    // repaints with the new uniforms but at the old place, or clipped to the
    // new width at the old place - while a plain Rectangle beside it moves,
    // a parent Item carrying it moves it, and every uniform change lands. So
    // on that surface the field is the whole band strip, never moves, never
    // resizes, and the plate travels inside it as uniforms only. (The dock's
    // own window and the bench, where the field sits inside an Item tree,
    // animate the computed box without trouble.)
    property rect pinnedBox: Qt.rect(0, 0, 0, 0)
    readonly property rect box: field.pinnedBox.width > 0 && field.pinnedBox.height > 0 ? field.pinnedBox : field.plateBox
    readonly property rect plateBox: {
        const px = field.plateX, py = field.plateY, pw = field.plateWidth, ph = field.plateHeight;
        const e = field.edge;
        if (e === "bottom") {
            const bottom = Math.max(py + ph, field.bandEdge);
            return Qt.rect(px - pad, py, pw + pad * 2, bottom - py);
        }
        if (e === "top") {
            const top = Math.min(py, field.bandEdge);
            return Qt.rect(px - pad, top, pw + pad * 2, py + ph - top);
        }
        if (e === "left") {
            const left = Math.min(px, field.bandEdge);
            return Qt.rect(left, py - pad, px + pw - left, ph + pad * 2);
        }
        const right = Math.max(px + pw, field.bandEdge);
        return Qt.rect(px, py - pad, right - px, ph + pad * 2);
    }
    x: box.x
    y: box.y
    width: box.width
    height: box.height

    // --- the uniforms, in the box's own pixels --------------------------------

    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property color fillColor: field.color
    readonly property vector2d pillCenter: Qt.vector2d(
        field.plateX - field.x + field.plateWidth / 2,
        field.plateY - field.y + field.plateHeight / 2)
    readonly property vector2d pillSize: Qt.vector2d(field.plateWidth, field.plateHeight)
    readonly property vector4d pillRadii: Qt.vector4d(
        field.radiusTopLeft, field.radiusTopRight, field.radiusBottomRight, field.radiusBottomLeft)
    readonly property vector2d bandNormal: Qt.vector2d(field.bandNormalPoint.x, field.bandNormalPoint.y)
    readonly property real bandOrigin: (field.vertical ? field.bandEdge - field.x : field.bandEdge - field.y)
        * (field.bandNormalPoint.x + field.bandNormalPoint.y)
    readonly property real blend: Fluid.blend({ neck: field.neck, gap: field.gap }, field.meniscus, field.blendPerPixel)
    readonly property real waistHalf: Fluid.waist({ neck: field.neck }, field.plateAlong) / 2
    readonly property real waistCenter: field.vertical ? field.pillCenter.y : field.pillCenter.x
    // How far the band's own surface is drawn toward the plate, and how wide
    // that hump is along the band. Drawn up toward the leaving body, never
    // INTO it: the hump is on its own spring and peaks a frame or two after
    // the gap does, so unclamped it was still taller than the gap right where
    // the two were meant to be parting, and the band swallowed the body back.
    readonly property real bulge: Math.min(Math.max(0, field.bulgeRaw), Math.max(0, field.gap) * 0.4)
    readonly property real bulgeHalf: field.plateAlong * 0.4
    readonly property real climbFall: field.climbFraction > 0 ? field.blend * field.climbFraction : 0
    readonly property real softness: 0.75
    // How far the plate's field reaches into the band: the first pixels of a
    // lift, before the blend can bridge them.
    readonly property real reach: Math.max(0, 2 - field.gap)
    // Whether the band's half-plane is painted where it lies inside the box
    // (frame_join.frag `bandPaint`). Off for a field whose box crosses its
    // band - a bar popup's, whose band is the bar's plate and whose box is
    // pinned to the frame's band: on, it filled the gap between a floating
    // bar and the hairline solid across the box.
    property bool paintBand: true
    readonly property real bandPaint: field.paintBand ? 1 : 0
    // The WINDOW's ratio, which follows fractional scaling; the screen's is
    // the output's integer scale.
    readonly property real pixelRatio: Window.window?.devicePixelRatio ?? 1
    fragmentShader: Qt.resolvedUrl("../shaders/frame_join.frag.qsb")

    // --- the outline, for whatever has to follow the paint -------------------

    // How many rectangles the outline may be: a caller that follows the
    // paint keeps a pool of Regions declared ahead of time and hands its
    // size in, and the outline merges its closest rows down to fit. Zero -
    // the default - computes nothing: the outline is evaluated on the GUI
    // thread every frame the join moves, and a field nobody follows (the
    // dock under a fullscreen window, the cheatsheet's eight benched
    // fields) must not pay for it. Eight of them did: 2 ms each, in QV4.
    property int outlineLimit: 0
    // The rows this field paints, as rectangles in the PARENT's coordinates,
    // evaluated from the same field the shader draws (join_field.js) so a
    // compositor's blur region can be the silhouette rather than a guess at
    // it. Nothing while the field is not painting or nobody asked.
    readonly property var outline: {
        if (!field.visible || field.outlineLimit <= 0) return [];
        const rects = JoinField.outline({
            pillCenter: field.pillCenter, pillSize: field.pillSize, pillRadii: field.pillRadii,
            bandNormal: field.bandNormal, bandOrigin: field.bandOrigin,
            blend: field.blend, waistHalf: field.waistHalf, waistCenter: field.waistCenter,
            softness: field.softness, reach: field.reach,
            bulge: field.bulge, bulgeHalf: field.bulgeHalf, climbFall: field.climbFall,
            bandPaint: field.bandPaint
        }, field.width, field.height, field.outlineLimit);
        const ox = field.x, oy = field.y;
        return rects.map(r => ({ x: r.x + ox, y: r.y + oy, width: r.width, height: r.height }));
    }
}
