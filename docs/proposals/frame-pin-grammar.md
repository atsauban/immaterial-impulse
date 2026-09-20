# Frame mode, stage 4: the pin grammar

**Status:** landed 2026-09-20, slices 1-4 (1ebb25a7a records map, 190d1d125 bar popups, ef5da6b11 notifications, 2bf416bab the dock's "auto") and the bar row ("feat(frame): the bar's plate is a join on its band"); what was measured landing each is in §7. Stages 0-3 are in
`frame-one-surface.md` (one surface per screen; the frame paints the dock's plate and, in the
Hug bar style, the bar's plate - 720f815f7 "release: 1.2.0").

## 1. The rule

Everything that can sit against the frame is in one of two states, and one word moves it
between them:

| state | what it looks like | how long it stays |
|---|---|---|
| **fused** | joined to the band on its edge: the band-side corners are filled by the meniscus, the plate is the frame's own material, one outline, one blur | transient: it came out of the band and goes back into it |
| **released** | its own piece of glass a gap off the band, all four corners round, its own border | persistent: it stays until closed |

**Pinned means released. Unpinned means fused.** The transitions are the split's grammar
(`motion-split.md`): releasing is the lift and the cut, fusing back is the landing and the
swallow, and a fused thing that closes *submerges* - it sinks into the band along the edge's
normal while the meniscus closes over it. The physics is `FrameJoin` (a18424982), the painter is
`FrameJoinField` (same commit), and the frame draws every fused plate itself (b730283b5) so the
join is one outline on one surface.

Both states exist for every surface. The defaults below follow how the surface was opened;
Settings > Appearance > Frame gets one row per surface to override the default.

## 2. Per surface

| surface | opened by | default | pin control | on close / unpin |
|---|---|---|---|---|
| bar widget popup | hover (`StyledPopup.hoverHeld`) | fused to the bar's band, grows out of it | clicking the widget while open = `pinnedOpen`, the card releases (lift + cut, the elevation gap appears) | unpin: lands and swallows back, then submerges; hover leaving a fused card: submerges |
| bar widget popup | click (`StyledPopup.pinnedOpen`, tray menus, Docker/Discord plugins) | released, as today | already pinned | close: swallow into the band, submerge |
| notification | arrives (`Notifications.popupList`), emerging from its band | fused to the band on its edge (`*_right`, `*_left`; the centre positions stay released) | a **Pin** button, or a drag away from the band past a threshold: releases it and cancels its timeout - it persists. Unpin (the button, or a drag back that ends nearer the band than the pinned rest) fuses it back and restarts its clock | close (the x) or timeout: a released card lands first, then slides into the band. A drag toward the band is never stopped: the join forms with the approach, past the edge the card goes under, and let go there it slides the rest of the way in and closes. Away from the band the pull is elastic to a limit and springs back short of the threshold |
| dock | reveal at the edge (unpinned) | fused: reveals out of the band and hides back into it | the dock's pin: released, reserves its edge (`DockReservation`) | unpin: lands, fuses; then hides into the band when the pointer leaves |
| bar | always on | Plate style: **Hug** (fused to the hairline band on its edge) while a window is on the monitor's active workspace - the frame is the border around the windows - and **Float** (lifted by the compositor's gap from the band's inner edge, inset from the side bands by the same, corners rounding with the lift) over an empty workspace (`FrameGeometry.barAttachedFor`; the Bar state row / `appearance.frame.bar` "auto"/"attached"/"floating"). Islands follow the same state, each on its own; M3 only floats | `bar togglePin` over IPC (`GlobalStates.barPinned`): pinned is released whatever the workspace holds; unpin returns to the workspace rule | released, the bar reserves its lift as well (the dock's flip rule: once per state change, on the compositor's own animation), so windows make room and the island has its gap on every side; bar popups fuse to the plate's inner edge wherever the lift put it; auto-hide in frame mode is still a split (out of scope, frame-one-surface.md §7) |

Two things the table changes on purpose:

- **The dock's frame option.** Today `appearance.frame.dock` ("attached" / "floating") decides
  the join and the pin decides only reservation; the user's own setup is pinned + attached. The
  grammar makes the pin decide the join, so `appearance.frame.dock` becomes an OVERRIDE with a
  third value: `"auto"` (the grammar: pinned = floating, unpinned = attached), `"attached"` (fused
  even pinned - the current setup, kept), `"floating"` (released even unpinned). Default `"auto"`
  for new configs; an existing `"attached"` keeps meaning attached.
- **The hover popup's click.** Today clicking a hover-opened widget toggles `pinnedOpen` and the
  card stays; nothing moves. Under the grammar that click is the release: the card lifts off the
  band by the elevation margin with the neck cutting - the same motion as the dock's, on the
  card's own `FrameJoin`.

## 3. Mechanics

**Records, many per screen.** `GlobalStates.frameJoins[screen]` holds ONE record (the dock's,
35f43c2b6). It becomes a map keyed by the element: `frameJoins[screen]["dock"]`,
`["barPopup"]`, `["notification:<id>"]`. The record's shape is unchanged (plate in screen
coordinates, radii, gap/neck/bulge, meniscus, colour). `Frame.qml` paints one `FrameJoinField`
per record from a Repeater, each pinned to its edge's strip and taken up from `Qt.callLater` as
now; the blur region is the union of the fields' outlines (one pool of Regions per field; the
outline is only computed for fields that paint, b6081b42a). Publishing stays the element's job:
its window keeps input, content and exclusive zone; its own plate stands down
(`FrameJoin.drawsPlate`) while the frame paints it - exactly the dock's arrangement, generalised.

**Fused geometry.** A fused plate sits ON the band's inner edge (no elevation gap), its band-side
corners are 0 in the region and filled by the meniscus in the paint, its far corners keep their
radius. For the bar popup that is the card at `y = bandEdge` instead of `barThickness +
elevationMargin`; its `openHeight` growing is the plate growing out of the band, which the field
paints at every height. For a notification it is the card's band-side edge on the band; a stack
is a column of drops on the pane, each with its own meniscus.

**Released geometry.** Today's geometry: the elevation gap, four round corners, the element's own
border colour. The element's `FrameJoin` owns the gap/neck through the transition
(`attached: !pinned`, `travel: elevationMargin`); while it is fused-or-moving the frame paints,
once it is free and settled the element may paint itself again (the neck is gone, two disjoint
shapes are two outlines anyway) - the dock keeps the frame painting at rest for the hand-over's
sake (`paintsAtRest`, frame-one-surface.md), and the popups start the same way.

**Submerge.** A new primitive next to the split: the plate's across-size (height for a top/bottom
band, width for a side band) runs to 0 on the fluid's spring (`FluidValue`, a51d12212) while the
plate stays fused, so the field paints the meniscus closing over a shrinking drop until nothing
is left but the band. Opening is the same run in reverse. No fade: a fused thing is never
translucent against the band, it is the band.

**Inputs and hit-testing** are untouched: each window's `mask` follows its own card, as now
(frame-one-surface.md §5).

## 4. Slices, each deployable

1. **Records become a map; the frame paints N fields.** Dock keyed `"dock"`, no visible change.
   Contract: `frameJoins[screen]` is a map; Frame has no single `joinField`.
2. **Bar popup: fused by hover, released by pin.** Card at the band, grows/submerges, `FrameJoin`
   on the card for the release and the landing. Settings row: *Popups opened by hover: fused /
   released*. Verified in the sandbox by a pointer moved onto a bar widget (`hl.dsp.cursor.move`)
   and a 60 fps capture of open, pin, unpin, close.
3. **Notifications: fused by default, Pin button.** Card at the band on its edge, submerge on
   timeout, Pin releases and cancels the timeout, close of a pinned card fuses back and
   submerges. Settings row: *Notifications arrive: fused / released*. Verified with `notify-send`
   in the sandbox (its own bus - deterministic).
4. **Dock: the pin decides the join; `frame.dock` gains `"auto"`.** Migration keeps an existing
   `"attached"`.
5. **Docs**: this file's status, AGENT.md's frame paragraph, motion-split.md §7 (the popup entry
   rewritten: fused-by-default, released on pin), CHANGELOG.

## 5. Not proposed

- Input on the frame surface, or a general compositing layer (frame-one-surface.md §5).
- Bar styles other than Hug joining anything: their plates are islands.
- The launcher, the modes flash, the sidebars: later slices of the same grammar, once popups
  and notifications hold.

## 6. Decisions taken at review (2026-09-20)

1. A **stack** of fused notifications: each card is fused to the band independently - a column
   of drops on the pane, each with its own meniscus.
2. A hover popup **pinned by click** releases: the lift and the cut, the elevation gap appears.
3. The dock's `appearance.frame.dock` defaults to `"auto"` in the shipped config
   (`defaults/config.json`); an existing `"attached"` or `"floating"` keeps its meaning.

## 7. What landing it taught

- **A record is withdrawn under the screen and key it was published under.** A notification
  delegate being destroyed has no list any more (no screen name) and may have no group (no app
  name); a withdrawal that recomputed either was dropped, and the frame kept painting a plate
  with no card in it. Measured twice before the fix (ef5da6b11).
- **A publisher's window has to BE the screen.** The notification popup placed itself inside
  the other surfaces' exclusive zones (`ExclusionMode.Auto`) and its window coordinates began
  40 px below the screen's; the frame painted the plate 40 px above the card. Fused, the popup
  ignores exclusion and takes `FrameGeometry.insets` as its margins.
- **The strip is per key.** A calendar popup is taller than a dock; the frame's pinned strip is
  720 px deep for `barPopup`, 480 for `notification:*`, 160 for the dock, and constant per key
  - a strip that grew with the plate would remake the field every frame.
- **Dragging** (review, rounds 3-4): away from the band the pull is elastic - `tanh` toward
  1.5x the elevation margin - and past the margin it pins. Toward the band the hand is never
  stopped: the record's neck rides the approach (whole at the band), so the meniscus grows as
  the card nears; past the band's edge the card goes under; let go there (a seventh of its
  width in) it slides the rest of the way and closes, let go nearer the band than its pinned
  rest it lands and unpins, otherwise it springs back. On release `FrameJoin.disturb` continues
  the join from the gap AND the neck the hand left, so the landing starts from what was
  already drawn. Unpinning restarts the timeout rather than dismissing.
- **A fusing popup reserves the bar's zone itself** (`roomOn`): the frame's insets count the bar
  only where it is the band, and with the Float style the card sat under the bar's icons.
- **Not driven in the sandbox:** the click that pins (the nested compositor has no
  pointer-button dispatcher). The release and the landing are verified as the fused/released
  geometry pair and by the dock's identical physics; the mid-motion look is the user's review.
- **The bar's row** (decided at review: "pin state + occupancy default"). The bar is always on,
  so its grammar needs a second input besides the pin: the workspace. Fused while the monitor's
  active workspace is empty - the frame is then the whole picture and the bar is its edge - and
  released once a window is there, the plate an island above the tiles; the pin forces released.
  Measured in the sandbox through the published record: pin 0 -> 5 px lift (the sandbox's
  compositor gap) with the side insets and the corner radius riding it, unpin back in three
  samples, a launched window releases, its close fuses back. The band on the bar's edge stays the
  hairline (`bandExtent` no longer returns 0 there; the plate covers it fused, so nothing shows
  twice). The travel is the compositor's outer gap. Holding the exclusive zone through the
  release put the island's bottom edge 1 px above the first window's top (8x crop): sides aligned
  with the window, nothing below - a bar sitting on a window, not an island. Decided at review:
  the released bar reserves its lift as well, by the dock's rule (`splitZoneExtra`: the extra
  flips at the start of a lift and the end of a landing), so the compositor re-tiles once per
  state change on its own animation and the island keeps its gap on every side. Popups were
  driven through a sandbox-only probe (the nested compositor delivers no hover): a hover popup
  fuses to the lifted plate's inner edge (`BarPopupOverlay.barLift`), a pinned one lifts its
  elevation margin off it; all five bar styles captured, the other four unchanged (islands).
- **Auto-hide** (review, live footage): the user's bar hides. Three things followed. The
  band on the bar's edge had become a permanent hairline, so a hidden bar left a straight
  gap-thick line where before only the bezel arcs remained - the band now slides out with
  the plate (`Frame.qml` Band `inset` from the bar's record), as it did when it WAS the
  plate. A fused plate whose inner edge sits AT the band's surface is two surfaces at one
  distance from every row below it, and the meniscus blended them into a strip the width
  of the screen (12 rows, measured) - the bar's neck lets go over the last meniscus of the
  slide (`slideHold` on the record). And the popup's field joined the hairline, not the
  plate: with the band 40 px thick they coincided, with a hairline the popup's plate climbed
  up through the bar to the screen edge (a black arch over the clock; a card hanging from
  nothing once the bar had hidden) - a `barPopup` record now joins the bar plate's inner
  edge (`joinBandEdgeFor`), the overlay reads the same edge off the bar's record
  (`barInner`), and the bar holds while its popup is up (`mustShow`).
- **Where the lift is measured from** (footage, a pointer held on row 0): the released plate
  sits the gap in from the band's INNER edge - as the windows do from the side bands - so the
  content's offset is band + lift and the zone grows by the same; measured from the screen
  edge, a 5 px band had the "released" plate resting straight on the band. And the auto-hide
  reveal strip has to reach the screen edge whatever the lift: begun at the lifted plate it
  left rows 0..gap outside, and a pointer there revealed the bar, fell out of the strip as the
  plate lifted, and hid it again, at 5 Hz. The sandbox did not flap with the same code
  (its default `hoverRegionWidth` is wider than 2) - a control that passes on a different
  setting is not a control.
- **One layer, one alpha** ("change the bar color/opacity to see it"). The frame's paints overlap
  by design - a popup's field fills its band side, which is the bar's plate the bar's own field
  paints too, and a fused plate reaches two rows into its band so a lift's first pixels stay
  seamless - and with a translucent frame colour every overlap doubled: the bar under an open
  popup read 22 where the popup read 37. Painted straight onto the surface there is no seamless
  translucent join between two shapes: an overlap darkens, a gap or an abutting antialiased edge
  lightens. So while the colour is translucent the bands and the fields paint OPAQUE into one
  offscreen layer (`Frame.qml paintLayer`) blended once at the colour's alpha; overlaps heal and
  a neighbour covers an edge's ramp. Measured after: both plates 37/28/28 across the junction,
  what is left lighter under the bar is its own widget-group pills. Cost: a screen-sized layer
  per frame surface, re-rendered while a join moves; a record's own alpha is not honoured inside
  it (a floating pill the frame paints at rest takes the frame's alpha).
- **Auto, the other way round; the shadow; the styles** (review of the live build). "Bar is set
  to hug but floats when there are windows - auto should be the opposite": with windows the
  frame is their border and the bar hugs it, over an empty workspace the bar is an island -
  `barAttachedFor` turned. The bar's own drop shadow lives in the bar's window, above the frame's
  surface, and fell across the frame's plate and the fused popup below it - the rest of the seam;
  it stands down with the plate. And Hug and Float are STATES now, not styles: in frame mode
  (the starter going forward; the older layouts are on their way out) the Bar style row offers
  Plate, Islands and M3, a Bar state row beside it picks Auto / Hug / Float (moved here from
  Appearance > Frame), Islands (2) is out of the row until its rework, Float (1) reads as the
  plate. The Islands style follows the same state: hugging, each island reaches up to the band's
  inner edge, band-side corners square, the frame's colour, no border; floating, as it was. The
  islands move on the tween, not the fluid spring, and the frame does not paint them yet - a
  per-island join with its own meniscus is the next slice.
- The bar popup's open and close keep their `openProgress` curve for now; the plate's growth out
  of the band and its submerge are that curve applied to a fused card (rest height 0). Moving
  the card's own scalar onto the fluid spring is a separate decision.

