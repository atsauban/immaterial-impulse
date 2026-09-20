#!/usr/bin/env python3
"""Frame mode, stage 1 (docs/proposals/frame-mode.md): off by default, one
geometry authority, and the surfaces that read it.

Pins: the config keys and their defaults; FrameGeometry is the only place
the insets are computed (ScreenCorners asks it for its margins, BarContent
asks it whether to square the plate, Frame draws the bands from it); the
family loads Frame only while the option is on; the bands reserve nothing and
take no input; the settings rows and the search index.
"""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
GEOMETRY = ROOT / "services/FrameGeometry.qml"
FRAME = ROOT / "modules/imi/frame/Frame.qml"
CORNERS = ROOT / "modules/imi/screenCorners/ScreenCorners.qml"
BAR = ROOT / "modules/imi/bar/BarContent.qml"
FAMILY = ROOT / "panelFamilies/ImmaterialImpulseFamily.qml"
PAGE = ROOT / "modules/imi/settings/pages/AppearanceConfig.qml"
INDEX = ROOT / "modules/imi/settings/SettingsContent.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class FrameModeContract(unittest.TestCase):
    def test_off_by_default_and_the_band_follows_the_gap(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject frame: JsonObject {"):]
        block = block[:block.index("}")]
        self.assertRegex(block, r"property bool enable:\s*false", "a look, not a fix: off by default")
        self.assertRegex(block, r"property int thickness:\s*0")
        geo = _strip(GEOMETRY.read_text())
        self.assertIn("Geo.bandThickness(Config.options.appearance.frame.thickness)", geo,
                      "the band is the configured thickness, never thinner than draws (HAIRLINE) - the gap stopped being 0's meaning")
        self.assertIn("&& !Config.options.bar.vertical", geo, "the vertical bar is not framed in stage 1")
        # The bar's edge is what the compositor reserves - ONE token, read by
        # the bar's reserver and by the authority, never a second copy.
        self.assertIn("readonly property real barThickness: Appearance.sizes.barExclusiveZone", geo)
        self.assertNotRegex(geo, r"baseBarHeight|Appearance\.sizes\.barHeight", "no hand copy of the reserver's expression")
        appearance = _strip((ROOT / "modules/common/Appearance.qml").read_text())
        frame = _strip(FRAME.read_text())
        corners = _strip(CORNERS.read_text())
        self.assertIn("property real barExclusiveZone: root.sizes.barReservedHeight", appearance)
        self.assertIn("zone: (Config?.options.bar.autoHide.enable && (!barRoot.mustShow || !Config?.options.bar.autoHide.pushWindows))\n                        ? 0 : Appearance.sizes.barReservedHeight",
                      _strip((ROOT / "modules/imi/bar/Bar.qml").read_text()))
        # No inner fillet and no inner radius: the frame's corners are the
        # SCREEN's corners, the bezel ScreenCorners draws in black.
        self.assertNotIn("innerRadius", geo)
        # The dock is NOT an occupant of the frame. The frame's inner corner
        # on the dock's edge is at the band (a fillet at the dock's inset
        # arced into wallpaper; a band as tall as the dock's strip was a
        # border with a pill lost in it), and the authority names no dock: a
        # pinned dock meets the band from its own side - DockReservation
        # reads the authority, never the other way round - so there is no
        # import cycle and no per-screen plumbing (one frame for every screen).
        self.assertNotRegex(geo, r"[Dd]ock(Reserv|Thickness|Edge|Geo)", "the authority names no dock occupant")
        self.assertNotIn("import qs.modules.imi.dock", GEOMETRY.read_text())
        self.assertNotIn("GlobalStates", GEOMETRY.read_text())
        self.assertNotRegex(geo, r"ForScreen|fullscreenOnMonitor|ByScreen", "one frame for every screen: no per-screen readers")
        self.assertIn("Geo.edgeInsets(root.barEdge, root.barThickness, root.thickness, root.gap, root.barCovers)", geo,
                      "a covering bar's edge is its zone plus the gap; every other edge is the band")
        self.assertNotRegex(appearance, r"dockExclusiveZone|dock_geometry", "Appearance is the layer everything builds on; it names no feature")
        # How a pinned dock meets the band is the frame's option, read by the
        # dock: on it as a tab (the default) or a gap above it. Anything but
        # "floating" attaches, so a hand-edited value leaves the dock somewhere.
        self.assertRegex(block, r'property string dock:\s*"attached"', "a pinned dock sits on the band by default")
        self.assertIn('readonly property bool dockAttached: String(Config.options.appearance.frame.dock ?? "attached") !== "floating"', geo)
        reservation = _strip((ROOT / "modules/imi/dock/DockReservation.qml").read_text())
        self.assertIn("readonly property real zone: DockGeometry.exclusiveZone(", reservation)
        self.assertIn("readonly property bool attached: FrameGeometry.enabled && FrameGeometry.dockAttached", reservation)
        self.assertIn("readonly property real frameOffset: DockGeometry.frameOffset(", reservation)
        self.assertIn("FrameGeometry.enabled, FrameGeometry.thickness, Appearance.sizes.hyprlandGapsOut)", reservation)
        self.assertNotIn("FrameGeometry.dockAttached, FrameGeometry.thickness", reservation,
                         "the surface sits where the attached tab needs it in BOTH states; floating is the pill's lift inside it")
        # The dock meets the band by moving its whole SURFACE (an anchored-
        # edge margin, which the compositor adds to the zone by itself), never
        # by re-deriving its inner margins - and only while pinned: an
        # unpinned dock hides and reveals from the screen edge.
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        self.assertIn("readonly property bool reserves: root.pinned && !fullscreenOnThisMonitor", dock)
        self.assertIn("exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0", dock)
        self.assertIn("fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)", dock)
        self.assertIn("root.edge, 0, dockRoot.reserves ? DockReservation.frameOffset : 0)", dock)
        for side in ("top", "bottom", "left", "right"):
            self.assertIn(f"{side}: dockRoot.frameMargins.{side}", dock, side)
        self.assertNotRegex(dock, r"dockThickness: DockGeometry\.thickness\([^)]*frame", "the dock's inner geometry knows nothing of the frame")
        # Attached, the pill is a tab of the band: its colour, no border, the
        # outward corners squared at the seam - and the blur region KEPT, per
        # corner (the bar plate in the same colour is blurred; a tab without
        # it read as unfrosted translucency on a real wallpaper). Unpinned too
        # while the band is the gap (a rounded, bordered pill on the default
        # band was a pill on a line); on any other band an unpinned dock
        # cannot be moved to meet the band, so it keeps the pill.
        self.assertIn("readonly property bool attached: DockReservation.attached && !fullscreenOnThisMonitor\n                && (dockRoot.reserves || DockReservation.frameOffset === 0)", dock)
        self.assertIn("dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0", dock)
        self.assertIn("border.width: Config.options.dock.showBackground ? Appearance.borderWidth.standard : 0", dock)
        self.assertIn("border.color: dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0Border", dock,
                      "the border is a colour change: a width from 0 draws nothing until 1, and a transparent ring is a seam")
        self.assertNotIn("regionItem:", dock, "the blur region is composed per corner, not a single-radius rect")
        # ...and published only while the pill is at rest: a Region tracks
        # its item's OWN geometry, the dock hides by offsetting an ancestor,
        # and a hidden dock left a frosted silhouette where the pill rests.
        self.assertIn("item: Config.options.dock.showBackground && dockMouseArea.atRest && !dockJoin.drawsPlate ? dockVisualBackground : null", dock,
                      "no second region over a plate the frame's surface is painting")
        self.assertIn("readonly property bool atRest: anchors.horizontalCenterOffset === 0 && anchors.verticalCenterOffset === 0", dock)
        self.assertIn("DockGeometry.cornerRadiiAt(root.edge, radius,\n                                dockRoot.apart, 0, 1)", dock,
                      "round throughout while the join owns the motion: the meniscus wraps the corner")
        for corner in ("topLeft", "topRight", "bottomLeft", "bottomRight"):
            self.assertRegex(dock, rf"{corner}Radius:\s+frameRadii\.{corner}", corner)
            self.assertIn(f"{corner}Radius: dockVisualBackground.{corner}Radius", dock, f"the blur region follows the pill's {corner}")
        # GlobalStates.dockPinned existed for the authority; nothing reads it now.
        self.assertNotIn("dockPinned", dock)
        self.assertNotIn("dockPinned", _strip((ROOT / "GlobalStates.qml").read_text()))
        # The side bands inset by what the horizontal edges DRAW (stage 3:
        # the bar's plate where the frame paints it, the band otherwise), so
        # the authority's bandMargins - the band's thickness, not the plate's
        # - is not what places them any more.
        self.assertNotIn("bandMargins", frame)
        self.assertIn("topInset: topBand.visibleExtent; bottomInset: bottomBand.visibleExtent", frame)
        self.assertIn("FrameGeometry.bandExtent(band.edge)", frame,
                      "a band's thickness on its own edge is the authority's: nothing on a covering bar's edge")
        self.assertNotRegex(frame, r"ForScreen", "one frame for every screen")
        self.assertNotIn("fullscreen: screenScope.fullscreen", frame)
        self.assertNotRegex(corners, r"cornerMargins|screen\?\.name", "the corners are the screen's bezel; they ask the authority for nothing")
        # No probe of the compositor's rounding: it sized a fillet that is
        # gone, and it spawned hyprctl on every self-inflicted reload.
        self.assertNotRegex(geo, r"hyprctl|probeArmed|configreloaded")

    def test_the_dock_switch_is_the_split(self):
        """The attached <-> floating switch is a FRAME JOIN, not a curve: a
        drop leaving a pond and landing back on it, integrated (fluid.js),
        owned once by modules/common/widgets/FrameJoin.qml. The dock keeps
        its geometry and reads the join's numbers; the field that draws the
        plate, the neck and the band is FrameJoinField, painted on the frame's
        surface (frame-one-surface.md stage 2). Pinned as SHAPE: who owns
        what, and that nothing here sequences anything with a timer."""
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        reservation = _strip((ROOT / "modules/imi/dock/DockReservation.qml").read_text())
        join = _strip((ROOT / "modules/common/widgets/FrameJoin.qml").read_text())
        field = _strip((ROOT / "modules/common/widgets/FrameJoinField.qml").read_text())
        fluid = (ROOT / "modules/common/functions/fluid.js").read_text()
        # The scalar split is gone: no progress, no seam, no latch of which
        # look the lift began as. What the eye reads as the break is the
        # neck's own state.
        self.assertNotRegex(dock, r"splitProgress|liftFromTab|splitTarget|splitNeck|Appearance\.animation\.split\b")
        # The target is the frame option and the PIN - never `attached` or
        # `reserves`, which fold in the fullscreen term and replayed a landing
        # on every fullscreen exit.
        self.assertIn("readonly property bool joinAttached: !(FrameGeometry.enabled && root.pinned && !DockReservation.attached)", dock)
        self.assertIn("FrameJoin {\n                            id: dockJoin", dock)
        self.assertIn("attached: dockRoot.joinAttached", dock)
        self.assertIn("travel: dockRoot.splitTravel", dock)
        self.assertIn("active: FrameGeometry.enabled && Config.options.dock.showBackground", dock)
        self.assertIn("color: FrameGeometry.color", dock, "the band's own colour: one surface, one opinion")
        # The dock reads the join; it does not integrate anything itself.
        self.assertIn("readonly property real splitTravel: DockGeometry.splitTravel(FrameGeometry.enabled, dockRoot.reserves, Appearance.sizes.hyprlandGapsOut)", dock)
        self.assertIn("readonly property real splitLift: dockJoin.lift", dock)
        self.assertIn("readonly property real splitPress: dockJoin.press", dock)
        self.assertIn("readonly property real splitRoom: DockGeometry.splitRoom(Appearance.sizes.hyprlandGapsOut, Appearance.sizes.elevationMargin)", dock)
        self.assertIn("DockGeometry.liftedMargins(root.edge, dockRoot.dockMargins, dockRoot.splitRoom, dockRoot.splitLift, dockRoot.splitPress)", dock,
                      "the pill moves on its OWN margins, and the stretch is the press")
        self.assertIn("DockGeometry.liftOffset(root.edge, dockRoot.splitRoom, dockRoot.splitLift)", dock)
        self.assertNotRegex(dock, r"duration:\s*\d", "no literal duration anywhere in the dock")
        # The reservation reserves the union of where the pill is and where
        # it is going, a boolean that flips, never per frame.
        self.assertIn("exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0", dock)
        self.assertIn("readonly property real splitZoneExtra: DockGeometry.splitZoneExtra(dockRoot.splitTravel, !dockRoot.joinAttached, dockRoot.splitLift)", dock)
        self.assertNotIn("splitZoneExtra", reservation)
        self.assertNotIn("dockJoin", reservation)
        # The look is the tab's while anything still bridges the two, in both
        # directions; with no lift it IS the switch, on its own effects-tier
        # scalar. The corners stay round wherever a neck can reach them.
        self.assertIn("readonly property bool attachedLook: dockRoot.splitTravel > 0 ? dockJoin.fused : dockRoot.attached", dock)
        self.assertIn("property real lookApart: dockRoot.attached ? 0 : 1", dock)
        look = dock[dock.index("Behavior on lookApart {"):]
        look = look[:look.index("}")]
        self.assertIn("enabled: dockRoot.splitTravel <= 0", look, "idle while the join is the one read")
        self.assertIn("animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)", look)
        self.assertIn("readonly property real apart: dockRoot.splitTravel > 0 ? 1 : dockRoot.lookApart", dock)
        self.assertIn("Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }", dock)
        self.assertIn("Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }", dock)
        self.assertNotIn("Behavior on border.width", dock)
        # The plate stands down while the field paints it, wherever that is.
        self.assertIn("opacity: dockJoin.drawsPlate ? 0 : 1", dock)
        # The join: physics on a gated FrameAnimation that stops itself the
        # frame it settles, stepped through the motion policy's clock (the
        # speed slider and reduce motion reach a solver that way, having no
        # duration to scale), with the field split out as its painter.
        self.assertIn("readonly property real target: (root.active && !root.attached) ? Math.max(0, root.travel) : 0", join)
        self.assertIn("FrameAnimation {", join)
        self.assertIn("running: false", join)
        self.assertIn("const h = Appearance.animation.scaleStep(frameTime);", join)
        self.assertIn("root.state = Fluid.step(root.state, root.target, h);", join)
        self.assertIn("if (root.state.settled)\n                stepper.running = false;", join)
        self.assertIn("FrameJoinField {\n        id: neck", join)
        self.assertIn("readonly property bool drawsPlate: root.painting", join)
        self.assertNotRegex(join, r"Timer\s*\{|SequentialAnimation|PauseAnimation", "nothing sequences the break; it is the neck's own state")
        # The chosen model is Cleavage: a CLAMP, not a rubber band - it holds
        # with the same force however far the two are pulled and weakens only
        # as the bridge thins, so the furrow is the event and the travel comes
        # after. Change these together or not at all.
        self.assertIn("var TENSION = 900;", fluid)
        self.assertIn("? TENSION * s.neck : 0;", fluid)
        self.assertNotIn("TENSION * s.neck * s.gap", fluid)
        self.assertNotIn("function cornerRound", fluid, "the corners are not the solver's business any more")
        # The field: one shader, the window's own pixel ratio, and a fallback
        # where no shader can draw (the software scene graph, a failed load).
        self.assertIn('fragmentShader: Qt.resolvedUrl("../shaders/frame_join.frag.qsb")', field)
        self.assertIn("readonly property bool fieldAvailable: field.GraphicsInfo.api !== GraphicsInfo.Software", field)
        self.assertIn("&& field.status !== ShaderEffect.Error", field)
        self.assertIn("readonly property real pixelRatio: Window.window?.devicePixelRatio ?? 1", field)
        self.assertNotRegex(field, r"import qs\.services|FrameGeometry|GlobalStates|Config\.", "the painter reads no service: it is handed everything")

    def test_the_split_shader_binary_is_built_from_its_source(self):
        # The shell loads frame_join.frag.qsb, never frame_join.frag: an edit to the
        # source that is not rebaked changes nothing on screen and reads as
        # a fix. frame_join.frag.qsb.bake records what the binary was baked from -
        # the source's sha256 and the qsb that baked it - so a source edit
        # without a rebake fails everywhere, CI included, whatever qsb is
        # there. Where the SAME qsb is installed the binary is also rebaked
        # and compared byte for byte (qsb's output is deterministic; another
        # version's is not, so that half skips).
        import hashlib
        shaders = ROOT / "modules/common/shaders"
        record = (shaders / "frame_join.frag.qsb.bake").read_text().split()
        digest, version = record[0], " ".join(record[2:4])
        self.assertEqual(hashlib.sha256((shaders / "frame_join.frag").read_bytes()).hexdigest(), digest,
                         "frame_join.frag changed since frame_join.frag.qsb was baked: rebake it and rewrite "
                         "frame_join.frag.qsb.bake (the command is in frame_join.frag's header)")
        qsb = shutil.which("qsb") or next((p for p in ("/usr/lib/qt6/bin/qsb", "/usr/lib64/qt6/bin/qsb")
                                           if Path(p).exists()), None)
        if qsb is None:
            self.skipTest("Qt's qsb is not installed; the source hash was checked")
        installed = subprocess.run([qsb, "--version"], capture_output=True, text=True).stdout.strip()
        if installed != version:
            self.skipTest(f"baked with {version}, {installed or 'an unknown qsb'} installed; the source hash was checked")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "frame_join.frag.qsb"
            subprocess.run([qsb, "--glsl", "100 es,120,150", "--hlsl", "50", "--msl", "12",
                            "-o", str(out), str(shaders / "frame_join.frag")], check=True, capture_output=True)
            self.assertEqual(out.read_bytes(), (shaders / "frame_join.frag.qsb").read_bytes(),
                             "frame_join.frag.qsb does not match a bake of frame_join.frag with the recorded qsb")

    def test_one_geometry_authority(self):
        corners = _strip(CORNERS.read_text())
        # The frame's corners are the SCREEN's corners: a monitor's bezel,
        # black in both modes, at the screen rounding. No frame-coloured
        # fillet, no inner radius, no margin the shape moves inward by.
        self.assertIn('color: "#000000"', corners)
        self.assertIn("implicitSize: Appearance.rounding.screenRounding", corners)
        self.assertNotRegex(corners, r"cornerMargins|frameMargins|innerRadius|FrameGeometry\.color",
                            "the bezel is not the frame's colour and takes no inset from it")
        self.assertNotRegex(corners, r"gapsOut|barHeight|decoration\.rounding", "ScreenCorners computes no inset or radius of its own")
        bar = _strip(BAR.read_text())
        self.assertEqual(bar.count("FrameGeometry.enabled ? 0 :"), 4, "the centre-only pill squares all four corners in frame mode")
        frame = _strip(FRAME.read_text())
        self.assertIn('color: band.painted ? FrameGeometry.color : "transparent"', frame, "painted or transparent, never unmapped")
        self.assertIn("visible: FrameGeometry.enabled\n", frame)
        self.assertNotIn("visible: FrameGeometry.enabled && !fullscreen", frame)
        self.assertIn("exclusionMode: ExclusionMode.Ignore", frame, "the band lives in the gap; it reserves nothing")
        self.assertIn("mask: Region {}", frame, "the band takes no input")
        # ONE surface per screen (docs/proposals/frame-one-surface.md, stage
        # 1): the four bands are items on it, so the border has one outline and
        # one blur region. A screen-sized always-mapped surface names its
        # screen (#297), anchors all four edges with no margins (a margin is a
        # position, and a position that changes reconfigures the surface),
        # and takes no keyboard.
        self.assertEqual(frame.count("PanelWindow {"), 1, "one surface per screen, not four")
        self.assertIn("screen: screenScope.modelData", frame)
        self.assertIn("WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", frame)
        self.assertRegex(frame, r"anchors \{\s*left: true\s*right: true\s*top: true\s*bottom: true\s*\}")
        self.assertNotIn("margins {", frame, "the surface's geometry is a constant of the screen")
        for edge in ("left", "right", "top", "bottom"):
            self.assertRegex(frame, rf'Band \{{ id: {edge}Band;\s+edge: "{edge}";\s+hidden: screenScope.hidden', edge)
            self.assertIn(f"Region {{ item: {edge}Band.painted ? {edge}Band : null }}", frame,
                          f"the {edge} band's frost is gated on exactly what paints it")
        # The side bands run between the horizontal ones, so no two overlap:
        # the colour is translucent.
        self.assertIn("readonly property real visibleExtent: Math.max(0, Math.min(band.extent, band.extent + band.inset))", frame)
        self.assertNotIn("bandOffsetFor", frame)
        self.assertIn("HyprlandData.specialWorkspaceByMonitorName[", frame)
        rules = (ROOT.parents[1] / "hypr/hyprland/rules.lua").read_text()
        self.assertIn('namespace = "quickshell:frame" }, no_anim = true', rules)
        # Both halves of scoped blur, or neither: the region above and the
        # layer rule. With only the region the band was blurred whole-surface
        # off the catch-all while the dock beside it was blurred through a
        # region - two mechanisms on one colour, which is the seam that made
        # an attached dock read as a separate object (lint_blur_region_pairing).
        self.assertIn('namespace = "quickshell:frame" }, blur = false', rules)
        # Stage 2: the frame paints the dock's plate. One painter in both
        # states (a hand-over across two render loops blanked a frame), the
        # dock's own region down while it does, and the dock painting itself
        # under a fullscreen window, where a Top surface is buried.
        dock = _strip((ROOT / "modules/imi/dock/Dock.qml").read_text())
        field = _strip((ROOT / "modules/common/widgets/FrameJoinField.qml").read_text())
        self.assertIn("FrameJoinField {", frame)
        self.assertIn("surface.joins = GlobalStates.frameJoins[name] ?? ({});", frame)
        # Many records per screen, one painter each (frame-pin-grammar.md §3):
        # the keys are a ListModel diffed on take-up, never reassigned, so a
        # notification arriving does not rebuild the dock's field beside it.
        self.assertIn("component JoinPainter: Item", frame)
        self.assertIn("if (!have) joinKeys.append({ key });", frame)
        self.assertIn("readonly property var record: surface.joins[painter.key] ?? null", frame)
        # The blur region IS the field's outline: the rows the shader paints,
        # evaluated by the same field in JS (join_field.js), one Region per
        # rectangle from a pool the field merges down to. A strip guessed for
        # the flare frosted a 14x20 px block of bare wallpaper at each end of
        # the dock (measured over stripes); a plate region with rounded
        # cutouts cut the corner the meniscus fills.
        self.assertIn('import "../functions/join_field.js" as JoinField', field)
        self.assertIn("readonly property var outline:", field)
        # ...and only for a caller that follows it: the outline is GUI-thread
        # JS every frame the join moves (2.1 ms a call in QV4 before it was
        # tuned; eight benched fields computing one nobody read halved the
        # shell's frame rate), so a field with no pool size computes none.
        self.assertIn("property int outlineLimit: 0", field)
        self.assertIn("if (!field.visible || field.outlineLimit <= 0) return [];", field)
        self.assertIn("outlineLimit: outlinePool.count", frame)
        self.assertIn("readonly property var r: painter.field?.outline[index] ?? null", frame)
        # The frame's field is the band strip, pinned: on this surface a
        # ShaderEffect whose own x/width change after creation paints the new
        # uniforms at the old place (measured; a Rectangle beside it moves),
        # so the plate travels inside a box that never moves, and the box is
        # re-made, not resized, when the strip changes.
        self.assertIn("pinnedBox: fieldLoader.strip", frame)
        # ...and the frame keeps its own frame clock while a record moves: a
        # window updated from another window's animation had its render
        # coalesced away until that animation stopped (the plate froze, then
        # snapped, on the user's session; a Timer-driven colour rendered).
        self.assertIn("function onFrameJoinsChanged() { Qt.callLater(surface.takeRecords); }", frame)
        self.assertIn("function onFrameBarsChanged() { Qt.callLater(surface.takeRecords); }", frame)
        self.assertNotIn("GlobalStates.frameJoins[screenScope", frame)
        self.assertIn("onStripChanged: { active = false; active = true; }", frame)
        self.assertIn("property rect pinnedBox: Qt.rect(0, 0, 0, 0)", field)
        self.assertNotIn("joinFlareRe", frame)
        self.assertNotIn("joinPlateRegion", frame)
        # The field's box stops AT the band's inner edge, so the band's rows
        # are painted once, by the band: two rows into the band, the field
        # painted the first at a quarter and the band, holed under the box,
        # left a blurred hairline past each end of the fillet.
        self.assertIn("const bottom = Math.max(py + ph, field.bandEdge);", field)
        self.assertNotIn("rectSubtract", frame)
        self.assertNotIn("joinHoleFor", frame)
        self.assertIn("paintsLocally: dockRoot.fullscreenOnThisMonitor", dock)
        self.assertIn("paintsAtRest: true", dock)
        self.assertIn("if (!dockJoin.active || !dockJoin.painting || dockRoot.fullscreenOnThisMonitor || !dockRoot.screen) return null;", dock)
        self.assertIn('GlobalStates.publishFrameJoin(name, "dock", record);', dock)
        # Stage 4, slice 2 (frame-pin-grammar.md): a bar widget's popup joins
        # the frame the way the dock does - a FrameJoin on the card owning the
        # lift and the cut, the record published under "barPopup", the card's
        # own plate stood down while the frame paints, and a fused card that
        # grows out of the band from nothing and submerges back to nothing
        # (bar_popup_unroll.js `fused`). "auto" follows how it was opened.
        overlay = _strip((ROOT / "modules/imi/bar/BarPopupOverlay.qml").read_text())
        self.assertIn('GlobalStates.publishFrameJoin(name, "barPopup", record);', overlay)
        self.assertIn("readonly property bool joinsFrame: FrameGeometry.paintsBarPlate && !overlayWindow.barVertical", overlay)
        self.assertIn('|| (overlayWindow.popupsLook === "auto" && !(overlayWindow.current?.pinnedOpen ?? false))', overlay)
        self.assertIn("readonly property bool joinAttached: !overlayWindow.joinsFrame || overlayWindow.wantsFused || overlayWindow.exiting", overlay)
        self.assertIn("card.parkedSize, overlayWindow.exiting, card.openProgress, overlayWindow.cardFused)", overlay)
        self.assertIn("readonly property bool plateOnFrame: overlayWindow.joinsFrame && cardJoin.drawsPlate", overlay)
        self.assertIn("readonly property real offBar: overlayWindow.joinsFrame ? cardJoin.lift : Appearance.sizes.elevationMargin", overlay)
        unroll = (ROOT / "modules/imi/bar/bar_popup_unroll.js").read_text()
        self.assertIn("function restHeight(openHeight, heroHeight, parkedSize, exiting, fused)", unroll)
        self.assertIn('property string popups: "auto"', _strip((ROOT / "modules/common/Config.qml").read_text()))
        self.assertIn("function publishFrameJoin(screen: string, key: string, record: var): void", _strip((ROOT / "GlobalStates.qml").read_text()))
        self.assertIn("Component.onDestruction: publishFrameJoin(null)", dock)
        # Stage 3: where the bar's plate covers its strip, the frame's band on
        # that edge IS the plate - the bar publishes thickness and slide,
        # BarContent paints no plate, and the authority says when.
        geometry = _strip(GEOMETRY.read_text())
        self.assertIn("readonly property bool paintsBarPlate: root.enabled && root.barCovers", geometry)
        self.assertIn("readonly property bool plateOnFrame: FrameGeometry.paintsBarPlate && !centerOnly", bar)
        self.assertEqual(bar.count("!root.plateOnFrame"), 2, "the plate's colour AND its region flag stand down together")
        barWindow = _strip((ROOT / "modules/imi/bar/Bar.qml").read_text())
        self.assertIn("if (!barContent.plateOnFrame || !barRoot.screen) return null;", barWindow)
        self.assertIn("inset: Appearance.sizes.barSurfaceMargin + contentInset", barWindow)
        self.assertIn("GlobalStates.frameBars = next;", barWindow)
        self.assertIn('barPlate: surface.barPlate?.edge === "top" ? surface.barPlate : null', frame)

    def test_the_family_gates_the_surface_on_the_option(self):
        fam = FAMILY.read_text()
        self.assertIn("PanelLoader { extraCondition: FrameGeometry.enabled; component: Frame {} }", fam, "the family agrees with the authority (the vertical bar is not framed)")
        self.assertIn("import qs.modules.imi.frame", fam)

    def test_settings_rows_and_index(self):
        page = _strip(PAGE.read_text())
        self.assertIn('title: Translation.tr("Frame")', page)
        self.assertIn("Config.options.appearance.frame.enable = !Config.options.appearance.frame.enable", page)
        self.assertIn("property bool rowVisible: Config.options.appearance.frame.enable", page)
        self.assertIn("Config.options.appearance.frame.thickness = newValue", page)
        # The dock row: a labelled choice, shown only while both the frame
        # and the dock are on.
        self.assertIn("Config.options.appearance.frame.dock = newValue", page)
        self.assertIn('{ "displayName": Translation.tr("Attached"), "value": "attached" }', page)
        self.assertIn('{ "displayName": Translation.tr("Floating"), "value": "floating" }', page)
        self.assertIn("property bool rowVisible: Config.options.appearance.frame.enable && (Config.options.dock.enable ?? false)", page)
        index = INDEX.read_text()
        self.assertIn('Translation.tr("Frame")', index)
        self.assertIn('Translation.tr("Floating dock")', index)


if __name__ == "__main__":
    unittest.main()
