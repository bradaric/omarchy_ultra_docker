# Stack-colour borders

Status: approved 2026-10-15.

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

# Part A - `Docker.js`: widen the rim, and never let bands touch

In `mosaicBands`, `half` is currently `gapPx / 2`. Change it to a full gap, but
only as far as the block gap can absorb, so two neighbouring bands can never
overlap or merge into one shape:

```js
// Half a CELL gap on each side is what makes a one-container stack visible at
// all; a full gap gives the dots a margin you can see. Capped by the block gap
// so two bands can never touch: each band may spend at most half of the space
// between them. With stackGap at its default of 3 and gapPx 2 this is 2, leaving
// 1px between neighbouring bands; with stackGap 0 it falls back to half a gap,
// which is what it was before.
var half = Math.min(gapPx, (gapPx + blockGapPx) / 2)
```

Update the function's comment: it currently says "Half a cell gap on each side
so a one-container stack is wider than its own cell" and has a per-position
paragraph. Restate both for the new rule.

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
- With `blockGapPx = 0`, `h` is `gapPx / 2`, so the geometry is what it is
  today.

Where the width is used - the `left` and `width` fields emitted per band, and
`plan.bands` in `plan()` - nothing else changes.

# Part B - `Mosaic.qml`: the border

On the band `Rectangle` (the `Repeater` over `root.plan.bands`), keep the fill
and add a border in the same hue, more opaque:

```qml
radius: Math.min(3, root.plan.cellPx / 2)
// A muted tint: the cell on top is the state, this is only the group.
color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.30)
// The frame that makes a stack a chip instead of a stain. Snapped to a whole
// DEVICE pixel: a 1-logical-pixel border is 0.85 device pixels under
// QT_SCALE_FACTOR and rasterises as a soft half-pixel line. See the device-pixel
// note in CLAUDE.md.
border.width: Docker.snapToDevice(1, Screen.devicePixelRatio)
border.color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.85)
```

`Mosaic.qml` already imports `QtQuick.Window` (for `Screen`) and `Docker.js`
(for `bandAt`), so both are in scope. `border.width` draws inside the band's
bounds, so the band's outer size does not change and Part A's table still holds.

# Part C - tests (`test_docker.js`)

- Update the per-position width assertions in
  `"band width follows the clamp, per position"` and
  `"a lone block wider than one column: both clamps bite at once"` to the new
  table: interior `S + 2`, first/last `S`, lone `S - 2` (at `cellPx 4,
  gapPx 2, blockGapPx 3`).
- Update `"a one-container stack beside others is wider than its own cell"`:
  the interior-width case is now `cellPx + 2 * gapPx` (8), not `cellPx + gapPx`.
- Keep `"a lone one-container block is exactly its own cell - accepted"` at
  `width === cellPx`; the new rule still collapses it there, and that assertion
  is the guard against someone "fixing" it.
- **Add**: with `blockGapPx = 0`, `half` falls back to `gapPx / 2`, so the band
  geometry equals the old rule and adjacent bands do not overlap. Assert on a
  two-block placement that `bands[0].left + bands[0].width <= bands[1].left`.
- **Add**: with the defaults, the same non-overlap assertion holds and the gap
  between neighbouring bands is exactly `1` (`gapPx + blockGapPx - 2 * half`).

Keep the count quoted in `CLAUDE.md` and `README.md` in step with the file.

# Part D - docs

- `README.md`: the mosaic sentence about the band should mention the frame, not
  just the tint.
- `CHANGELOG.md`: extend the existing `## Unreleased` entry for stack colours
  (no new section).
- `CLAUDE.md`: if the stack-colour note there describes the band's geometry,
  update it; otherwise nothing.

# Verification

1. `node test_docker.js` - all green; report the count.
2. `omarchy restart shell` (the shell runs what it loaded at startup).
3. **Screenshot the bar and look at it:** `hyprctl monitors -j`, then
   `grim -g "<x>,<y> <w>x30" - | magick - -scale 800% /tmp/bar.png`. Check the
   frame reads on the user's theme, that neighbouring stacks still separate
   (1px at the defaults), and that the border is a crisp whole-pixel line, not a
   grey smear. Tune `border.color`'s alpha (0.85) and, if needed, the fill alpha
   (0.30) - those two numbers are the whole visual calibration.
4. Confirm `stackGap = 0` still renders without bands touching (`omarchy bar set
   avila.ultra-docker stackGap 0`, look, then set it back).

# Risks

- **The border may read as a heavy outline** once four sides exist where there
  was only ever a horizontal rim. The alpha is the dial; drop the fill to 0.20
  if the chip looks solid.
- **1px at `QT_SCALE_FACTOR`**: snapping to a whole device pixel is why
  `snapToDevice` is used rather than a literal `1`; a fractional border is the
  same class of bug as a fractional cell edge, just far less visible.
- **Bands 1px apart at the defaults** is tighter than the current 3px. If the
  screenshot shows them merging, cap `half` at `gapPx / 2 + 0.5` instead of
  `gapPx`.
- **Vertical padding is still absent.** If the user still wants margin above and
  below the dots after seeing the frame, that is the follow-up with the three
  sources listed in Non-goals.
