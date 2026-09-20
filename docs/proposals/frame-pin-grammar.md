# Frame mode, stage 4: the pin grammar

**Status:** landed 2026-09-20, slices 1-4 (1ebb25a7a records map, 190d1d125 bar popups, ef5da6b11 notifications, 2bf416bab the dock's "auto"); what was measured landing each is in §7. Stages 0-3 are in
`frame-one-surface.md` (one surface per screen; the frame paints the dock's plate and, in the
Hug bar style, the bar's plate as its band - 720f815f7 "release: 1.2.0").

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
| notification | arrives (`Notifications.popupList`) | fused to the band on its edge (the right band for `top_right`/`bottom_right`, the top band for `top_center`) | a **Pin** button on the card: releases it and cancels its timeout - it persists | clear/close a pinned card: it fuses back (landing, swallow) and submerges; timeout of a fused card: submerges |
| dock | reveal at the edge (unpinned) | fused: reveals out of the band and hides back into it | the dock's pin: released, reserves its edge (`DockReservation`) | unpin: lands, fuses; then hides into the band when the pointer leaves |
| bar | always on | Hug style: the bar IS the band (fused, 26328624c); other styles: islands (released) | the style | auto-hide in frame mode is a split (out of scope here, frame-one-surface.md §7) |

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
- **Not driven in the sandbox:** the click that pins (the nested compositor has no
  pointer-button dispatcher). The release and the landing are verified as the fused/released
  geometry pair and by the dock's identical physics; the mid-motion look is the user's review.
- The bar popup's open and close keep their `openProgress` curve for now; the plate's growth out
  of the band and its submerge are that curve applied to a fused card (rest height 0). Moving
  the card's own scalar onto the fluid spring is a separate decision.

