# Stack-colour borders

Status: approved 2026-10-15.

Revision after review: the "never let bands touch" contract was wrong. The cap
in Part A guarantees **non-overlap only** - bands abut when `blockGapPx <=
gapPx` - so Part A and Part C now say non-overlap and name the abutment as
accepted. Part C also drops the `mosaicBands`-only `blockGapPx = 0` framing:
`planMosaic` coerces `0` to `3`, so that input is unreachable from the setting
and the fallback is defensive (Known issues).

Second pass, from the plan-conformance review of the first implementation: the
smallest value that actually reaches `mosaicBands` from the setting is
`blockGapPx = 1` (`stackGap 1`), not `gapPx` - `planMosaic` floors at 1 - and
that is the fractional-rim branch (`h = 1.5`, a half device pixel) the comment
warns about. Part A and Part C now say so and Part C covers it. Part D also
names README's settings table row, which was left stale while the manifest and
pt-I18n descriptions were fixed.

Third pass, from the user's screenshot: the border and the wider rim landed, but
the bands read as tall chips with the dots at the top. `mosaicBands` gave every
band the **grid's** height, so a stack with fewer containers than rows carried
empty tint below its dots. Part A2 makes the band as tall as its own cells, and
the original stack-colours plan's "the full mosaic height" is superseded with it.

Builds on `docs/plans/2026-10-15-stack-colours.md` (implemented in `20a7c4d`).
That plan's B2 width table is superseded by Part A below.

## Problem

The bands are live and identify stacks, but they read as a wash hugging the
dots: the tint shows in the 2px inter-cell gaps and as a 1px rim on the left and
right only. Vertically the band is flush to the mosaic's full height, so the
dots touch it top and bottom, and nothing delineates one stack from the next
except the tint itself. On the user's theme the bands blend into the bar.

They asked for a border, or 1-2px around the container dots.

## What changes

1. A **1px border** on each band, in the same hue as its fill but opaque enough
   to read, so each stack is a framed chip rather than a stain.
2. The **horizontal rim widens** from half a gap to a full gap where the block
   gap allows it, so there is a visible margin either side of the dots.
3. Vertical padding is **not** in this change. See Non-goals.

## Non-goals

- **No vertical padding.** A band taller than the dots has to take that height
  from the bar's slack (risking a clip), a larger mosaic area (changes the cell
  size and row count), or the dots' own size. That is a tradeoff the user has
  not chosen yet; it is a follow-up, not this change.
- **No border on individual cells.** At a 4px cell a 1px border is a quarter of
  the dot's edge, and a ring around every dot competes with the state fill,
  which is the one thing the cell colour has to keep meaning.
- **No new setting.** This rides on `groupColours`; there is no second switch.
- No change to `bandAt`, the tooltip, `bandSignature`, the popup accent, the
  cell fill, or the palette.

---

# Part A - `Docker.js`: widen the rim, and never let bands overlap

In `mosaicBands`, `half` is currently `gapPx / 2`. Change it to a full gap, as
far as the block gap can absorb:

```js
// A full CELL gap of rim on each side, so a one-container stack is not merely
// wider than its own cell but has a margin you can see. Capped by the block gap
// so two neighbouring bands can never overlap: each band may spend at most half
// of the space between them. At the defaults (gapPx 2, stackGap 3) this is 2,
// leaving 1px between neighbouring bands.
//
// The cap guarantees non-overlap, only: when the block gap is no wider than the
// cell gap the space between two bands is 0 and they abut. Accepted - the bands
// carry different hues, so an abutting pair still reads as two chips, unlike two
// cells of the same colour.
//
// blockGapPx 0 is unreachable from the setting: planMosaic's `Number(x) || 3`
// turns the falsy 0 into 3, and it floors at 1. That branch exists for direct
// callers and tests only. The smallest value that does arrive from the setting
// is 1, where the cap gives half = 1.5 - a rim on a half DEVICE pixel, which is
// the accepted case the note below is about.
var half = Math.min(gapPx, (gapPx + blockGapPx) / 2)
```

Restate `mosaicBands`'s own comment for the new rule and its per-position
paragraph; the wording above is the contract to carry across.

The two numbers to get right, and to say plainly in the comment:

- **Rim** = `half`, a full cell gap at the defaults (2px), not half of one.
- **Separation** = `gapPx + blockGapPx - 2 * half`, which is `1` at the defaults
  and `0` whenever `blockGapPx <= gapPx`.

## The width table, superseded

With `span = maxCol - minCol + 1`, `S = span * (cellPx + gapPx)`, and `h = half`
as defined above:

| Band | Clamp that bites | Width | (`cellPx 4, gapPx 2, blockGapPx 3` -> `h = 2`) |
|---|---|---|---|
| interior (not first, not last) | none | `S + 2h - gapPx` | `S + 2` |
| first block (`minCol === 0`) | `left` pinned to 0 | `S + h - gapPx` | `S` |
| last block | `right` pinned to `widthPx` | `S + h - gapPx` | `S` |
| only block (first and last) | both | `S - gapPx` | `S - 2` |

Worked numbers at the defaults, `cellPx = 4, gapPx = 2, blockGapPx = 3`:

| Case | `span` | `S` | interior | first/last | lone |
|---|---|---|---|---|---|
| two-column stack | 2 | 12 | 14 | 12 | 10 |
| one-container stack | 1 | 6 | 8 | 6 | 4 |

Two things that do **not** change:

- A **lone one-container block** is still exactly `cellPx` wide (4), because
  `S - gapPx = (4 + 2) - 2 = 4`. Still accepted, still nothing to distinguish
  it from; do not widen it, that is what the clamps exist to prevent.
- With `blockGapPx = 0` (defensive only, see Part A), `h` is `gapPx / 2`, so the
  geometry is what it was before this change.

Where the width is used - the `left` and `width` fields emitted per band, and
`plan.bands` in `plan()` - nothing else changes.

# Part A2 - `Docker.js`: the band is as tall as its own cells

`mosaicBands` currently emits `height: heightPx` for every band - the **grid's**
height, not the block's. `blockLayout` fills each block top to bottom, so a
stack with fewer containers than rows occupies only the first *n* rows, and the
rest of its band is empty tint. On the user's bar (24px reserved -> two rows at
`cellPx 4, gapPx 2`) a one-container stack is a single dot in row 0 of a
two-row band: the dot sits at the top of the chip with tint hanging below it.
That is the misalignment they reported.

Track each block's own row extent in the same loop that already tracks `min` and
`max` column:

```js
if (!spans[key]) {
  spans[key] = { min: p.column, max: p.column, maxRow: p.row, group: cells[i].group }
}
if (p.column < spans[key].min) spans[key].min = p.column
if (p.column > spans[key].max) spans[key].max = p.column
if (p.row > spans[key].maxRow) spans[key].maxRow = p.row
```

and emit the block's height instead of the grid's:

```js
height: (span.maxRow + 1) * cellPx + span.maxRow * gapPx
```

A block that fills every row therefore comes out at exactly the old height
(`rows * cellPx + (rows - 1) * gapPx`), so nothing about a full-height stack
changes. The band's own height is the cells' bounding box; the rim is applied on
top of that, below.

**Drop the now-unused `heightPx` parameter** from `mosaicBands` - the new
signature is `(cells, placements, cellPx, gapPx, blockGapPx, widthPx)`. Update
the call in `plan()`, and every call in `test_docker.js`. A dead parameter that
looks like it still controls the height is exactly the kind of thing that gets
"restored" later.

A visible rim needs vertical room too, and **the cells sit on top of the band**.
The border is drawn inside the band and under the cells, so wherever a cell
touches the band's edge the border is hidden there. With the band now exactly
the height of its cells, the top and bottom borders vanish and the four-sided
frame the user just approved becomes two side bars. So the band has to be bigger
than the cells on **all four sides**, and the vertical part has to come from
space that costs nothing:

- `mosaicBands` emits the rim it already computed - add `rim: half` to each
  band.
- `Mosaic.qml` uses as much of it as the item has spare:
  `v = Math.min(modelData.rim, root.topInset)`, then `y: root.topInset - v -
  root.snapY` and `height: modelData.height + 2 * v`.

`topInset` is the slack the plan already leaves above and below the rows,
`(itemHeight - plan.height) / 2`, so the rim is drawn inside the mosaic's own
box and never overflows the bar. At the user's bar (24px reserved, two rows of
4px with 2px gaps) `topInset` is 2 and the default rim is 2, so the rim is full
on all four sides. Where a taller bar's plan already fills the item - `topInset`
0 - the vertical rim falls back to 0, the chip loses its top and bottom lines,
and **nothing else moves**: no replanning, no lost row, no smaller cell. That is
the deliberate trade: a chip that is never clipped and never costs layout, at
the price of a config-dependent vertical rim. Do not "fix" it by planning against
a shorter area - that costs a row on any bar tall enough to have one.

Two small consequences to carry:

- The doc comment above the function should say the height is the block's own
  rows, not the mosaic's, and the "superseded" note in this plan stands for the
  original `docs/plans/2026-10-15-stack-colours.md` B2 too, which described the
  band as spanning "the full mosaic height".
- `Mosaic.qml`'s `bandSignature` (group, left, width) should gain the **height**:
  a stack losing a container changes only its height when it is one column wide,
  so without it the signature misses a real geometry change. Width-only was
  sufficient while every band was grid-height; it is not now.

# Part B - `Mosaic.qml`: the border and the rim

On the band `Rectangle` (the `Repeater` over `root.plan.bands`), the geometry
gains the vertical rim from Part A2, and the paint gains the border:

```qml
// As much of the rim as the item has spare, so the chip never overflows the
// mosaic's box. On a bar where the plan already fills the item this is 0 and
// the top and bottom lines are simply hidden under the dots (Part A2).
readonly property real rim: Math.min(modelData.rim, root.topInset)

x: modelData.left - root.snapX
y: root.topInset - rim - root.snapY
width: modelData.width
height: modelData.height + 2 * rim

radius: Math.min(3, root.plan.cellPx / 2)
// A muted tint: the cell on top is the state, this is only the group.
color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.30)
// The frame that makes a stack a chip instead of a stain. Snapped to a whole
// DEVICE pixel: a 1-logical-pixel border is 0.85 device pixels under
// QT_SCALE_FACTOR and rasterises as a soft half-pixel line. See the device-pixel
// note in CLAUDE.md.
border.width: Docker.snapToDevice(1, Screen.devicePixelRatio)
border.color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.85)
// The fill already animates on a group change; the outline has to follow it or
// the frame snaps while the wash eases.
Behavior on border.color { ColorAnimation { duration: 200 } }
```

`Mosaic.qml` already imports `QtQuick.Window` (for `Screen`) and `Docker.js`
(for `bandAt`), so both are in scope. `border.width` draws inside the band's
bounds, so the band's outer size does not change and Part A's table still holds.

The `rim` property shadows nothing, but it does mean `y` and `height` now
depend on `topInset`, which depends on `height` - both already resolve before
the delegate paints, so there is no binding loop; the rim is a `min` of two
plain values, not a feedback into the layout.

# Part C - tests (`test_docker.js`)

- Update the per-position width assertions in
  `"band width follows the clamp, per position"` and
  `"a lone block wider than one column: both clamps bite at once"` to the new
  table. With `cellPx 4, gapPx 2, blockGapPx 3`: interior `S + 2`, first/last
  `S`, lone `S - 2`. Express those from a local `h` (`S + 2 * h - gapPx`,
  `S + h - gapPx`, `S - gapPx`), not as hard-coded `+ 2` / `- 2`, so the test
  states the rule rather than one instance of it.
- Update `"a one-container stack beside others is wider than its own cell"`: the
  interior width is now `cellPx + 2 * gapPx` (8), not `cellPx + gapPx`. Express
  that from the locals too, not as a literal `4 + 2 * 2`.
- Keep `"a lone one-container block is exactly its own cell - accepted"` at
  `width === cellPx`; the new rule still collapses it there, and that assertion
  is the guard against someone "fixing" it.
- **Add** a non-overlap check for the defaults: `bands[0].left +
  bands[0].width < bands[1].left`, with the separation asserted to be exactly
  `gapPx + blockGapPx - 2 * h` (1).
- **Add** a non-overlap check at the **smallest value that reaches the helper
  from the setting**, `blockGapPx = 1` (`stackGap 1`; `planMosaic` floors at 1,
  so 0 never arrives). This is the branch the Docker.js comment warns about:
  `h = (gapPx + 1) / 2 = 1.5`, a rim on a half device pixel. The separation is
  `0`, so assert `<=` and say in the comment that the cap guarantees non-overlap
  only and abutting is accepted - do not write "never touch".
- **Add** the defensive `blockGapPx = 0` case: `h` is `gapPx / 2` and the two
  bands do not overlap. Say in the comment that this input is unreachable from
  the setting (Part A), so the check documents the helper's contract only.
- Fix the stale comment above the checked widths: it still says the band
  "expands by half a gap", which is the old rule.
- **Do not** add a `planMosaic`-level test for `blockGapPx 0`. It cannot reach
  the bands; such a test would be testing `planMosaic`'s coercion, which this
  plan does not change (see Known issues).
- **Every existing `mosaicBands(...)` call loses the `heightPx` argument** (Part
  A2's signature change). Read the call sites carefully: the argument after
  `blockGapPx` is now `widthPx`.
- **Add** the height coverage Part A2 introduces, all on hand-written
  placements at `cellPx 4, gapPx 2`:
  - a block that fills every row keeps the old height: two rows ->
    `bands[0].height === 2 * cellPx + gapPx` (10);
  - a block that uses one row of a two-row grid is `cellPx` tall (4) - the
    screenshot case, a one-container stack no longer carrying a second row of
    empty tint;
  - two blocks in the same grid get **different** heights when one of them fills
    both rows and the other does not, which is the assertion that would fail if
    the grid height leaked back in.
- **Add** the rim assertion: every band carries `rim === h`, the same `half` the
  widths use, so the renderer and the geometry cannot disagree about how thick
  the frame is. The vertical placement (`min(rim, topInset)`) is QML and stays a
  manual check.
- Confirm the popped `heightPx` argument is gone from **both** the signature and
  the `plan()` call site - a leftover argument would silently shift `widthPx`
  into the wrong slot.

Keep the count quoted in `CLAUDE.md`, `README.md` and `SPEC.md` in step with the
file.

# Part D - docs

- `README.md`: the mosaic sentence about the band should mention the frame, not
  just the tint - and so should the settings table row for `groupColours`. The
  row is the same class of description as the manifest and pt-I18n entries
  below; leaving it stale is how the three drift apart.
- `manifest.json` (`barWidget.schema` for `groupColours`) and the Portuguese
  `settings.help.groupColours` in `I18n.js`: both describe a tinted band; say it
  has a frame now, or the setting's own description is out of date with what it
  draws.
- `CHANGELOG.md`: extend the existing `## Unreleased` entry for stack colours
  (no new section).
- `CLAUDE.md`: if the stack-colour note there describes the band's geometry,
  update it; otherwise nothing.

# Verification

1. `node test_docker.js` - all green; report the count.
2. `omarchy restart shell` (the shell runs what it loaded at startup).
3. **Screenshot the bar and look at it:** on this machine the bar is the top 24px
   of each monitor (`reserved` is `[left, top, right, bottom]`), so
   `grim -g "0,0 1920x24"` on DP-1; HDMI-A-1 is at y 1080 and DP-2 at y -1080.
   Check that a **one-container stack is now a one-row chip that hugs its dot**,
   that the frame still closes on all four sides at the defaults, that
   neighbouring stacks separate (1px at the defaults), and that the border is a
   crisp whole-pixel line, not a grey smear. Tune `border.color`'s alpha (0.85)
   and, if needed, the fill alpha (0.30) - those two numbers are the whole visual
   calibration.
4. Set a **small legal** `stackGap` (`omarchy bar set avila.ultra-docker
   stackGap 1`), look, and set it back: bands must still read as separate chips
   even when they abut. Do **not** test `stackGap 0` - `planMosaic` coerces it
   to 3, so the setting has no effect at zero (see Known issues).

# Risks

- **The border may read as a heavy outline** once four sides exist where there
  was only ever a horizontal rim. The alpha is the dial; drop the fill to 0.20
  if the chip looks solid.
- **1px at `QT_SCALE_FACTOR`**: snapping to a whole device pixel is why
  `snapToDevice` is used rather than a literal `1`; a fractional border is the
  same class of bug as a fractional cell edge, just far less visible.
- **Bands 1px apart at the defaults** is tighter than the current 3px, and they
  abut outright once `stackGap` is no wider than `cellGap`. If the screenshot
  shows them merging, the remedy is to trade rim for separation - a smaller cap
  in Part A - not to widen the block gap.
- **The border may not survive `radius`** cleanly at small cell sizes, where
  `radius` is `cellPx / 2`. Look at it; if the corners wash out, cap the radius
  at 1.
- **Vertical padding is still absent.** If the user still wants margin above and
  below the dots after seeing the frame, that is the follow-up with the three
  sources listed in Non-goals.

# Known issues (not this change)

- **`stackGap = 0` is silently ignored.** The manifest offers `stackGap` with
  `min: 0`, and `coerceSetting` will store it, but `planMosaic` computes
  `blockGap = snapToDevice(Math.max(1, Number(settings.blockGapPx) || 3), dpr)`:
  the falsy `0` becomes `3`, and the floor is `1` anyway. So a control that
  looks live does nothing at `0`, and the schema advertises a value that cannot
  exist. Pre-existing, surfaced by this plan. Fixing it means deciding what `0`
  should mean (a stack boundary indistinguishable from a cell boundary) or
  changing the schema's `min` to `1` - a separate decision, not bundled here.
