# Frame mode: one surface owns the connected silhouette

**Status:** landed. Stages 0-3 here; stage 4 - popups and notifications under one pin grammar - is `frame-pin-grammar.md`.

**Goal:** the attached state reads as one piece of material, so that glassmorphism —
refraction at the edge, a specular rim, a lensing that bends what is behind it — can be
applied to the frame at all.

## 1. Why this is structural rather than a tuning job

Frame mode's premise is that the shell is one surface: a border around the screen with the
bar, the dock and eventually every other edge element as parts of it. Today that is a
premise the compositor does not share. `hyprctl layers` on a 5120x1440 screen, dock
attached:

```
level 2  slot 6   quickshell:frame   y 1438..1439
level 2  slot 8   quickshell:dock    y 1368..1442
```

Two layer surfaces, same level, the dock above, overlapping rows 1438-1439. Blur is
computed per surface against whatever is beneath it, so the dock does not share material
with the band — it refracts it.

For a flat frost that is survivable, and stage 0 below makes it look right. For glass it is
not, and the reason is what glass *is*: refraction and a specular rim are computed from the
shape's own outline. Two surfaces means two outlines, so a rim draws around the dock **and**
around the band — a bright line along precisely the join that is supposed to be invisible.
No region tuning removes it, because the region is not what draws it.

The encouraging half: `modules/common/shaders/frame_join.frag` already models the plate, the
neck and the band as ONE distance field. The primitive is right; it is drawing inside the
dock's window, which is the wrong surface.

## 2. Stage 0 — the two blur mechanisms (landed)

`Frame.qml` publishes a `WindowBlurRegion` over its band. `rules.lua` never set
`blur = false` for `quickshell:frame`, so the band fell through the catch-all
`quickshell:.*` `blur = true` at `ignore_alpha = 0.05` and was blurred WHOLE-SURFACE, while
the bar, the dock and both sidebars are blurred through a region with their own threshold.
Two mechanisms on surfaces painting the same translucent colour.

Measured over a uniform white backdrop, where blur can only change brightness and any colour
difference is compositing alone: the band and the dock's own meniscus at `(142,143,145)`
against the plate's `(82,81,84)` — a 60-level cliff exactly at the plate's rounded-rect edge,
which is the blur region's edge. Whether the band is actually blurred WITH the rule is not yet
shown: three rule-on/off A/B runs on the live session read bit-identical, because the bottom row
was flat white across the whole screen and a 2 px band over a flat backdrop cannot show blur -
and identical numbers also hint that a layer rule may apply only when the surface maps. The rule
is required by the repo's own invariant regardless; the instrument that can settle the picture is
the review sandbox with a striped wallpaper behind the band, the notification blur probe's shape.

`tests/lint_blur_region_pairing.py` fails the suite while only one half is present, which is
how this was found — it had been red since the region was added and nobody ran it. The
general rule it encodes is already in AGENT.md's layer-shell section: a region without the
layer rule changes nothing, and the layer rule without a region leaves the panel unblurred.
Both halves, or neither.

## 3. What one surface has to get right

Three precedents in this tree already host many things on one always-mapped surface, and
between them they have paid for every trap. Stage 1-4 below inherit all of it.

**`modules/imi/bar/BarPopupOverlay.qml`** — one screen-sized `Overlay` surface per screen
carrying a card that every bar popup morphs. Four properties hold it up
(d29cd6e45, b22a923a5):

1. The surface's geometry is a constant of the screen — four edges anchored, no `margins`,
   no implicit size. On a layer surface position IS `margins`, so anything animating its
   position reconfigures the surface every frame.
2. The mask follows an animating item on its own but tracks only `x`/`y`/`width`/`height`.
   Neither `scale` nor `rotation` nor `opacity` is connected: express motion as geometry.
3. An `opacity: 0` item still publishes a full-size input region. Collapse to 0x0 when idle;
   that is the only thing making a permanently-mapped screen-sized surface harmless.
4. Reuse a namespace rather than minting one. A new namespace falls through the catch-all
   `ignore_alpha = 0.05`, under which a screen-sized surface's *transparent* pixels clear
   the threshold and the compositor is asked to blur the whole screen.

**`modules/imi/editMode/`** — a screen-sized chrome surface, with the three things such a
surface must decide: input (the mask is the real rects and nothing else, or the thing
underneath stops taking clicks), blur (`quickshell:editMode` is listed at `ignore_alpha = 1`
because its bodies are opaque), keyboard (`WlrKeyboardFocus.None`, or it swallows Escape).

**`modules/common/widgets/EdgeSlide.qml`** and the persistent sidebars — what a surface that
outlives its gesture costs (c27bebd0, and the persistent-sidebar contract): an ungated `mask`
eats clicks on the edge it occupies; an unconditional `keyboardFocus: OnDemand` holds the
keyboard while showing nothing; content hides on the runner's own `shown`, never on the open
flag, which drops on frame one of the exit; the motion is an `x`, not a transform, because
the blur region and the shadow follow geometry and a transform moves neither; and a
persistent surface must name its `screen:`, or Hyprland gives it whichever monitor had focus
at creation and it never moves (#297).

Two more constraints specific to this refactor:

- **`visible: false` on a layer-shell `PanelWindow` destroys it**, so nothing here may gate a
  surface on a per-gesture flag.
- **An exclusive zone that animates belongs on a surface of its own**
  (`BarExclusiveZoneReserver`, 97689e338). Writing `exclusiveZone` at any value forces
  `exclusionMode` to `Normal`. The frame surface paints; it must not also reserve.

## 4. The staged plan

Each stage is deployable and leaves the shell working.

**Stage 1 — the frame becomes one surface per screen.** `modules/imi/frame/Frame.qml`'s four
band windows become one `PanelWindow` per screen, four edges anchored, `screen: modelData`
from a `Variants` over `Quickshell.screens`, `ExclusionMode.Ignore`, `WlrKeyboardFocus.None`,
a mask that is the drawn bands and nothing else, and a clear colour that is a literal
(`lint_window_clear_color.py`). The bands become items on it, so the existing
`frame_geometry.js` arithmetic is unchanged and the four-into-one is a layout change rather
than a geometry one. Namespace stays `quickshell:frame`, which already carries `no_anim` and
now `blur = false`.

What this buys on its own: the four bands stop being four surfaces that can disagree, and the
corner where two bands meet becomes a corner of one shape rather than an overlap two
translucent surfaces paint twice (the reason `bandMargins` currently keeps them from
crossing).

**Stage 2 — the dock's plate moves onto it (landed).** The dock keeps its own window for
input, its icons and its exclusive zone; what moves is the PAINTED plate and the neck. The
field split out of `FrameJoin` into `FrameJoinField` (the painter, reading no service), the
dock's join keeps the physics with `paintsLocally` off, and `Dock.qml` publishes what the
field needs — the plate in SCREEN coordinates (`dock_geometry.js` `surfaceOrigin` plus the
plate's place summed up the tree, so a reveal slide is followed too), its corners, the
solver's numbers and the plate's own animated colour — into `GlobalStates.frameJoins[screen]`,
the `clockDepthViewports` shape. `Frame.qml` draws the field from it and adds the field's own
OUTLINE — the rows the shader paints, evaluated by the same field in JS (`join_field.js`,
`FrameJoinField.outline`), one `Region` per rectangle from a pool of 64 the field merges down
to — to its composed blur region; the dock's own region stands down while the frame paints.

Two decisions taken while measuring it:

- **The frame paints the pill in BOTH states, at rest included** (`FrameJoin.paintsAtRest`).
  The first cut handed the plate back to the dock's Rectangle at the cut, and the hand-over
  crosses two render loops nothing orders: captured at 60 fps, one frame at the cut showed the
  icons over bare backdrop, every time. A field with no neck is a rounded box, so one painter in
  both states costs nothing and removes the frame that could be wrong. Two disjoint shapes on
  one surface are still two outlines, so a detached pill is still its own piece of glass. What it
  costs: the floating pill's 1 px `colLayer0Border` is not drawn in frame mode — the field paints
  one colour. A rim is stage-4's business anyway; noted rather than patched here.
- **Under a fullscreen window the dock paints itself.** A Top surface is buried there, so the
  frame cannot show the pill; `paintsLocally` follows `fullscreenOnThisMonitor` and the record is
  withheld. Unverified live (no fullscreen window was opened on the user's session for it).

- **The field's box stops at the band's inner edge, and the band paints whole.** The box had
  reached two pixels into the band, so inside it the field drew the band's surface too, and the
  frame's band Rectangle painted under it as well: measured on the band's row over a white
  backdrop, **81 under the plate and within 52 px either side of it, 142 beyond** — the same
  translucent colour twice, the darker run along the meniscus that was reported. The first fix
  left the band a hole under the box (`rectSubtract`); but the band's half-plane zero-crosses
  0.75 px INSIDE the band, so the field painted the band's first row at a quarter, and over a
  striped wallpaper the hole showed as a blurred, unpainted hairline 26 px long past each end of
  the fillet. Ending the box at the band's edge makes the band's rows the band's alone: the
  half-plane still shapes the field, its ramp is never rasterised, and the hole is gone (the
  bench's panes lose the same double paint for the same reason).
- **The blur region is the field's outline, not a guess around it.** The region had been the
  plate as a rounded rect plus a strip for the flare — sized first from the study's ratios (15
  of 23 px), then to climb the whole corner. Isolated in the review sandbox over red/white 4 px
  stripes, each end of the dock still carried a **14x20 px block of blurred, unpainted stripes**:
  the strip's outer corner, outside the concave fillet, which climbs 31 rows and spreads 21 px at
  the band against the strip's 17x23. No rectangles-and-radii guess follows a smooth-minimum
  fillet, so the field is evaluated on the CPU — `join_field.js`, a port of the shader that
  `tst_join_field.qml` pins to that capture within a pixel on every row — and the region is its
  rows, merged where consecutive rows match (26 rectangles for the dock). It runs on the GUI
  thread every frame the join moves, in QV4: the first cut cost 2.1 ms a call (0.07 in V8) and
  the cheatsheet's eight benched fields, each computing an outline nobody read, dropped the
  shell's frame rate — so a field computes it only for a caller that hands in a pool size
  (`outlineLimit`, 0 by default), and the port unpacks its uniforms once, solves the rows out of
  the blend's reach in closed form and bisects the rest inside a bracket seeded from the row
  before: 0.35 ms a call. After: the band's rows uniform across the screen, and the fillet's
  edge a single antialiased pixel.

- **On the frame's surface the field is the whole band strip, pinned; the plate moves inside it
  as uniforms only.** An icon arriving widened the dock's row, the record and the frame's
  `plateWidth` followed (logged), the field's window swapped 240 frames a second (a
  `FrameAnimation` counter) - and the painted plate did not change (captured at 60 fps, twice, on
  the user's session; then reproduced in the sandbox by dropping a pinned app). Split down: a
  colour uniform toggled every second repaints, and the geometry catches up with it; `x` set
  by hand does not move the paint; `width` set by hand clips it at the new right edge in the
  old place; a plain Rectangle beside it moves; a parent Item carrying it moves it. So a
  ShaderEffect directly under the frame window's content item does not get its own position
  and size changes onto the scene graph, while every uniform change lands. Rather than chase
  Qt through Quickshell's proxy window, the frame gives the field a box that never moves or
  resizes (`FrameJoinField.pinnedBox`, the band's edge by the surface's width by 160 px) and
  re-creates it through a Loader when that strip changes (screen size, band thickness). The
  dock's own window and the bench, where the field sits inside an Item tree, animate the
  computed box without trouble and keep it.
- **The frame takes the records up a beat after they are published (`Qt.callLater`).** With the
  box pinned the plate still held its old width under icons that had already moved, and snapped
  to the new one at some random later moment (four recordings on the user's 240 Hz session,
  then the sandbox: a pinned app dropped from the config, plate unchanged for ten seconds). What
  separated the changes that painted from the ones that did not was WHERE they came from: a
  colour or a `climbFraction` toggled by a Timer painted every time; anything arriving through
  `GlobalStates.frameJoins` did not. The records are published from inside the dock window's
  frame - its layout settling in polish, its spring's `FrameAnimation` tick - and under the
  threaded render loop a repaint requested for another window while one window is locked for
  its sync is only noted and taken up the next time THAT window syncs, which is the random
  snap. A `FrameAnimation` started from the same place was lost the same way. `Frame.qml` now
  copies the records into its own properties from `Qt.callLater`, after the publisher's frame:
  the field's changes ask for their repaint from the event loop, and the sandbox's plate
  followed the config change in 0.11 s.

Verified: `hyprctl layers` still one `quickshell:frame`; a detach at 60 fps has no blank frame and
no double paint, and the tab-to-pill colour rides the plate's own Behavior through the cut;
after the pinned box, a pinned app removed from the sandbox's dock narrows the painted plate
322 -> 275 px and back, fillets and band intact.

**Stage 3 — the bar (landed; superseded by the pin grammar, `frame-pin-grammar.md` the bar row:
the band on the bar's edge is a hairline like the others and the plate is a join record `"bar"`,
fused to it or lifted off by the compositor's gap - `frameBars` and `plateOnFrame`'s authority read
are gone).** Narrower than the dock's move, on purpose: only where the
bar IS the frame's edge — `barCovers`, the Hug style with a painted plate — because there the
plate is a full-width strip, which is a band. `FrameGeometry.paintsBarPlate` says when;
`Bar.qml` publishes the plate's thickness and how far its edge side sits from the screen edge
(the surface's margin plus the content's animated auto-hide margin, so the slide is followed)
into `GlobalStates.frameBars[screen]`; `Frame.qml`'s band on that edge takes them, and
`BarContent` paints no plate (`plateOnFrame`). The side bands inset by what the horizontal
edges DRAW — the plate while it is there, the band otherwise, nothing once the plate has slid
out — rather than by the authority's `bandMargins`, which knows the band's thickness and not
the plate's. So the strip and the two side bands meeting at the top corners are one shape on
one surface, which is what the corner needed. Every other bar style keeps its own plates:
they are islands inset inside the frame, not the frame, and painting them here would be
re-implementing `BarContent` on a second surface. The auto-hide slide is wired but was not
exercised live (auto-hide is off on the machine this was built on).

**Stage 4 — popups and notifications.** Only worth attempting once 1-3 hold, and it is what
the whole exercise is for: a notification that fuses with the frame's right band, a bar
widget's popup that grows out of the top one.

## 5. What is deliberately not proposed

- **Moving input onto the frame surface.** Each element keeps its own window for hit-testing
  and its own exclusive zone. A screen-sized surface that also took input would have to
  reproduce every element's mask, and the masks are the part most likely to be wrong in a way
  nothing logs.
- **A general compositing layer.** This is the frame and what attaches to it, not a new
  rendering architecture for the shell.

## 6. How any of it can be verified

Almost none of this is reachable from the suite: `qmltestrunner` cannot construct a `Region`,
and weston implements no wlr-layer-shell, so no test can see whether a region is empty,
published, or ignored. AGENT.md states it outright — every bug in that area was found by
looking at the screen, and two were misattributed first.

What can be checked: `lint_blur_region_pairing.py` (both halves present),
`test_persistent_surface_screen.py` (the surface names its screen), `lint_window_clear_color.py`
(a literal), and the geometry arithmetic in `tst_frame_geometry.qml`. What cannot is the
picture, and the instrument for that is a frame-by-frame capture (`ffmpeg -fps_mode
passthrough`) read against a control — the shape `test_clock_depth_noop.py` uses, where the
invariant is that with nothing attached the frame surface and the four bands must produce the
same frame.

A measurement that names a colour needs a backdrop that can carry it: a uniform white window
is what separated compositing from blur in stage 0, and the dark-on-dark captures taken
before it proved nothing.

220780dfb ("feat(frame): frame mode, stage 1"),
d29cd6e45 ("feat(bar): add the static overlay surface the popup card will live on"),
b22a923a5 ("refactor(bar): delete the per-popup layer surface"),
97689e338 ("feat(bar): give the bar's exclusive zone a surface of its own"),
c27bebd0 ("perf(sessionScreen): the session menu's surface outlives the gesture"),
4a1b4f850 ("fix(blur): stop the compositor frosting drop shadows").
