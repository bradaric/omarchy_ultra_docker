# Stack colours, and the settings screen that never rendered

Status: approved 2026-10-15; revised twice after plan review (second pass:
G1-G3).

Revision notes (first review - F1-F5):

- **Ordering of the settings key and its Portuguese strings is now a single
  step.** The manifest key and `I18n.js`'s pt label/help must land together or
  the suite goes red the moment the key exists. See B1/B6.
- **Part C's band-width assertions are now per-position.** The `left`/`right`
  clamps mean the first, last and only blocks lose half a gap; the old
  single-formula assertion was wrong for them. See B2 and Part C.
- **`resetAllSettings` no longer loops `writeSetting`.** Each write merges from
  `root.settings`, which may not refresh synchronously, so a loop could lose
  updates. One merged write instead. See A3.
- **The tooltip's host contract and its stale-text cases are specified.**
  `Bar.showTooltip` refuses a target without `tooltipHovered`, and bands
  changing under a stationary pointer left a stale name. See B5.

Revision notes (second review - G1-G3):

- **G1: the reset check asserted the wrong end state.** `resetAllSettings`
  writes each key back at its default; it does not delete it, so `shell.json`
  still contains the keys after a correct reset. A4 and Part D step 4 now say
  "back at its default value", and name the header count as the real signal.
- **G2: the tooltip would clear on every state read.** `resolved` is rebuilt on
  every `docker events` refresh and the 60s poll even when the layout is
  unchanged, so keying the clear off `plan` would hide the tooltip once a
  minute. B5 now keys it off a band signature, and Part D step 6 checks both
  halves: stays across an unchanged refresh, clears on a real layout change.
- **G3: an unproven claim stated as fact.** A3 now says the host *may not*
  refresh `settings` synchronously; the single-write design does not depend on
  which.

Shell references: all shell paths below are absolute under
`/usr/share/omarchy/shell/` on Omarchy `4.0.0.alpha`. Any bare file name
(`Bar.qml`, `shell.qml`, `PluginShellApi.qml`, `PluginRegistryApi.qml`) is that
directory. Line numbers were correct at that version and may drift; the symbol
names are the reliable part.

## Problem

Two things, one of which turns out to be a prerequisite for the other.

1. **The settings screen renders nothing.** On Omarchy `4.0.0.alpha` the screen
   opens with its header ("All at their defaults") and its key hint, and an
   empty body. This is not a config problem and not a restart problem.

2. **The mosaic is a field of identical squares.** A cell's only identity is its
   position. The user has to memorise the layout, and loses it whenever a
   container stops, is added, or the mosaic reflows. The fix they asked for is a
   per-stack colour.

## Root cause of (1)

`Panel.qml` builds the settings field list from:

```
bar.shell.pluginRegistry.installedPlugins[pluginId].barWidget.schema
```

That path does not exist for a **third-party** bar widget on this shell:

- `plugins/bar/Bar.qml`, `injectProps` (~line 2002) - a third-party widget's
  `bar` is a `PluginBarApi` facade, not the Bar.
- `plugins/bar/Bar.qml`, `pluginBarApiFor` (~line 229) sets that facade's
  `shell` to `root.shell.pluginShellForId(...)`; `shell.qml`,
  `scopedPluginShellForId` (~line 676) returns a `PluginShellApi`.
- `services/PluginShellApi.qml` has `serviceFor`, `summon`, `hide`, `toggle`,
  `isPluginOpen`, `updateEntryInline`, `mutateShellConfig` - and **no
  `pluginRegistry`**.

So `bar.shell.pluginRegistry` is `undefined`, `settingsSchema` is `[]`,
`settingsSections` is `[]`, and the screen has nothing under its header.
`settingsError` stays blank because it is only written on a failed *write*.

The scoped registry object that *does* carry the manifest (`PluginRegistryApi`,
whose `installedPlugins` includes `barWidget.schema`) is only injected when an
entry point declares `pluginRegistry`. Bar widgets are not given it; **service
entry points are** (`shell.qml`, `ensureService`, ~line 932).

The same gap breaks writes. `Panel.qml` calls
`pluginRegistry.setBarWidget(...)`, which for this plugin is unreachable. The
reachable call is `bar.shell.updateEntryInline(id, settings)`
(`services/PluginShellApi.qml` -> `shell.qml`, `updateEntryInline`, ~line
1078). It **replaces the whole entry** with `{id, ...settings}`, so it must be
handed the current settings merged with the changed key, or every write wipes
the other keys.

The `omarchy bar set` CLI still works, because it goes through the root registry
(`shell.qml` IPC `setBarWidget`, ~line 1654), not the facade.

## Goals

- Restore the settings screen: all fields readable, and writes that persist to
  `~/.config/omarchy/shell.json` and survive restart/reboot.
- Add an opt-in per-stack colour: a tinted background band behind each stack's
  block in the bar mosaic, and a matching accent in the popup stack headers.
- Hovering the mosaic shows which stack is under the pointer, by name.

## Non-goals

- No per-container colour. Per stack only.
- No colour in the collapsed modes (one cell per stack already separates them).
- No tooltip where there are no bands: collapsed modes and `groupStacks` off.
  There is no block boundary to point at, so there is nothing to name. Stated
  here so it is a decision, not an oversight.
- Cell fill stays semantic: healthy / warning / broken. The band is background,
  the cell is figure.
- No upstream shell changes.

## Locked decisions

| # | Decision |
|---|---|
| 1 | Colour in the bar mosaic **and** the popup stack headers |
| 2 | Hues generated from the stack name, zero config |
| 3 | Feature off by default; a persistent way to turn it on |
| 4 | Tooltip shows the **group name** only, not container names |
| 5 | Per stack/group only |
| 6 | Fix the settings screen as part of this work |

---

# Note on the working tree

A first implementation run was cancelled partway and may have left uncommitted
changes (`git status` will say). If it did, **the plan is authoritative, not the
tree**. Read the changes against this revision and reconcile:

- `Service.qml`, `manifest.json`, `Docker.js` (`groupHue`, `mosaicBands`,
  `bandAt`, `plan.bands`), `Mosaic.qml` and `Panel.qml`'s schema/write path may
  already match Part A and Part B of this plan - keep what does.
- Known gaps to check for, because the first draft of this plan was wrong here:
  - `resetAllSettings` still looping `writeSetting` (A3).
  - the tooltip not clearing when `plan` changes under a stationary pointer, and
    the missing `tooltipHovered` property contract (B5).
  - band-width tests asserting one formula or using tolerances instead of the
    per-position widths, and no explicit lone-block case (Part C, B2).
  - the pt strings for `groupColours` present and `SETTINGS_SECTIONS` updated,
    or the suite is red (B1).

Run `node test_docker.js` first: it tells you immediately whether the tree is in
a coherent state or mid-edit.

---

# Part A - fix the settings screen

## A1. `Service.qml` - take the registry the shell does inject

Service entry points get a scoped `PluginRegistryApi` injected when they declare
the property (`shell.qml` `ensureService`, ~line 932). Add, right after
`id: root`:

```qml
// The shell injects a scoped, read-only registry view into service entry
// points. That view carries this plugin's own manifest, which is the single
// source of the settings field list. The bar widget is NOT given it (its
// `bar.shell` is a PluginShellApi), so the widget reads the schema from here.
property var pluginRegistry: null

readonly property var settingsSchema: {
  var registry = pluginRegistry
  if (!registry || !registry.pluginId || !registry.installedPlugins) return []
  var manifest = registry.installedPlugins[registry.pluginId]
  return manifest && manifest.barWidget ? (manifest.barWidget.schema || []) : []
}
```

`installedPlugins` is keyed by `registry.pluginId`, so nothing is hardcoded. The
scoped view is updated in place on a rescan (`shell.qml`, the rescan handler
that reassigns each `registryApi.manifest`, ~line 867), so the binding
re-evaluates with a changed manifest.

## A2. `Panel.qml` - read the schema from the service

Replace the `settingsSchema` binding (the `bar.shell.pluginRegistry` block in
the settings section of `Panel.qml`) with:

```qml
// Built from the plugin's own manifest, read out of the shell's registry by
// the service. The bar widget cannot reach the registry itself: its
// `bar.shell` is a scoped PluginShellApi with no pluginRegistry on it.
readonly property var settingsSchema: service ? service.settingsSchema : []
```

`settingsSections` and `changedSettings` stay as they are; they already derive
from `root.settingsSchema`.

Keep `readonly property string pluginId` - it is still used in the read-only
message and the IPC verb.

Remove the now-dead `pluginRegistry` property **only after** A3 replaces its two
remaining uses (`canWriteSettings`, `writeSetting`).

## A3. `Panel.qml` - write through the scoped shell

`updateEntryInline` replaces the whole entry, so every write merges first and
only calls out when something actually changed (it returns `false` both for "no
change" and for a refused call, so its return value alone cannot tell them
apart). One helper owns the write so the comparison and the error text live in
one place:

```qml
readonly property bool canWriteSettings:
  !!(root.bar && root.bar.shell
     && typeof root.bar.shell.updateEntryInline === "function")

function cloneSettings() {
  var out = ({})
  var current = root.settings || ({})
  for (var k in current) out[k] = current[k]
  return out
}

// The single write path. `updateEntryInline` replaces the widget's whole entry
// with `{id, ...merged}`, so callers hand in a COMPLETE object, never one key.
function writeSettings(merged) {
  if (!root.canWriteSettings) {
    root.settingsError = root.tr("settings.readOnly", { id: root.pluginId })
    return false
  }
  if (JSON.stringify(merged) === JSON.stringify(root.settings || ({}))) {
    root.settingsError = ""
    return true
  }
  var ok = root.bar.shell.updateEntryInline(root.pluginId, merged)
  root.settingsError = ok
    ? "" : root.tr("settings.writeFailed", { error: "updateEntryInline" })
  return ok
}

function writeSetting(key, value) {
  var merged = root.cloneSettings()
  merged[String(key)] = value
  root.writeSettings(merged)
}
```

`resetSetting(field)` is unchanged - it calls `writeSetting(field.key,
field.defaultValue)`.

**`resetAllSettings` must not loop `writeSetting`.** Each write rebuilds from
`root.settings`, and the host may not refresh `settings` synchronously between
two calls in the same tick (`shell.qml` `persistShellConfig` reassigns
`shellConfig`; `settings` reaches the widget on a later pass - the plan does not
rely on which). If it has not refreshed, the second call merges onto the stale
object and silently reverts the first, so "Reset everything" would reset one
field and lose the rest - exactly the "controls look live and do nothing"
failure this plugin warns about. One merged write removes the dependency
entirely:

```qml
function resetAllSettings() {
  var fields = root.settingsSchema
  var current = root.settings || ({})
  var merged = root.cloneSettings()
  var changed = false
  for (var i = 0; i < fields.length; i++) {
    if (Docker.settingIsDefault(current, fields[i])) continue
    merged[String(fields[i].key)] = fields[i].defaultValue
    changed = true
  }
  if (!changed) {
    root.settingsError = ""
    return
  }
  root.writeSettings(merged)
}
```

## A4. Verify

- `omarchy restart shell` (the shell runs the plugin it loaded at startup).
- `omarchy-shell avila.ultra-docker settings` - expect the five sections and all
  fields, no errors.
- Change **three or more** fields; confirm each lands in
  `~/.config/omarchy/shell.json` under the widget's `bar.layout.<section>[]`
  entry, and that the other keys already in that entry are still there.
- Press **Reset everything**; confirm the header says "All at their defaults"
  and that every changed key in `shell.json` is back at its **default value**.
  The reset writes the defaults back; it does not delete the keys, so their
  presence is not a failure. The header count is the reliable signal.
- Restart the shell again and confirm the values survive.

---

# Part B - stack colours

## B1. `manifest.json` **and `I18n.js`** - one step

These land **together, as the first step of Part B**. The moment the manifest
key exists, the suite runs the "Portuguese label and help for every schema
field" check against it and goes red until both pt strings are present. Do not
land B1 without them.

- Add to `barWidget.defaults` (next to `groupStacks`):

  ```json
  "groupColours": false
  ```

- Add to `barWidget.schema`, near the `look` fields:

  ```json
  {
    "key": "groupColours",
    "type": "boolean",
    "label": "Colour stacks",
    "description": "A tinted band behind each compose stack in the bar, and a matching accent in the popup headers. Healthy, warning and broken stay the cell colour.",
    "defaultValue": false
  }
  ```

- Add to `I18n.js`'s **pt** table, next to `settings.label.groupStacks` /
  `settings.help.groupStacks` (English comes from the manifest - that is the
  existing rule for `settings.label.*` and `settings.help.*`; do not add an en
  copy):

  ```js
  "settings.label.groupColours": "Colorir stacks",
  "settings.help.groupColours": "Uma faixa tingida atrás de cada stack do compose na barra, e um acento igual nos cabeçalhos do popup. Saudável, atenção e quebrado continuam sendo a cor da célula.",
  ```

- Add `"groupColours"` to the `look` section's `keys` in `SETTINGS_SECTIONS`
  (`Docker.js`), next to `groupStacks`. The "every manifest key is filed into a
  named section" check fails otherwise.

`node test_docker.js` must be green before moving on to B2.

## B2. `Docker.js` - the pure parts

### Hue from the stack name

Deterministic, state-independent, so a stack's colour never changes as
containers start and stop. FNV-1a for the hash, golden-ratio spread so
alphabetically adjacent stacks land far apart on the wheel.

```js
// A stable hue per stack name, so a stack keeps its colour as containers start
// and stop. FNV-1a for the hash, then the golden ratio for the spread: adjacent
// names in the mosaic's alphabetical order land far apart on the wheel.
function groupHue(name) {
  var text = String(name || "")
  var hash = 2166136261
  for (var i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 16777619) >>> 0
  }
  return Math.floor((hash * 0.618033988749895 % 1) * 360)
}
```

Returns an integer in `[0, 360)`.

### Bands behind each block

Emit the bands from `planMosaic`'s `plan()` so the geometry is testable and
`Mosaic.qml` only paints. One band per block, spanning that block's whole
column range and the full mosaic height, expanded by **half a cell gap** on each
side. The expansion is what makes a one-container stack visible at all;
clamping it to the mosaic is what stops the first and last bands overhanging the
bar. The two rules interact, so the expected width depends on the band's
position - see the table below the code.

```js
// One background band per stack block, in the mosaic's own pixel space. Half a
// cell gap on each side so a one-container stack is wider than its own cell,
// clamped to the mosaic so the outermost bands do not overhang it.
//
// cellPx and gapPx are already device-snapped, so the band lands on the device
// grid too - except for the half-gap, which is half a device pixel when gapPx is
// odd. The renderer only shifts by snapX/snapY, so a band edge can land on a
// half device pixel. That is accepted here and must NOT be "fixed" the way a
// cell is: the band is a translucent background, so a soft edge reads as a tint,
// whereas a fractional CELL edge merges two cells into one shape.
function mosaicBands(cells, placements, cellPx, gapPx, blockGapPx, heightPx, widthPx) {
  var out = []
  if (!placements || placements.length === 0) return out

  var spans = []
  for (var i = 0; i < placements.length; i++) {
    var p = placements[i]
    var key = Number(p.block) || 0
    if (!spans[key]) spans[key] = { min: p.column, max: p.column, group: cells[i].group }
    if (p.column < spans[key].min) spans[key].min = p.column
    if (p.column > spans[key].max) spans[key].max = p.column
  }

  var half = gapPx / 2
  for (var b = 0; b < spans.length; b++) {
    var span = spans[b]
    if (!span) continue
    var left = Math.max(0, span.min * (cellPx + gapPx) + b * blockGapPx - half)
    var right = span.max * (cellPx + gapPx) + b * blockGapPx + cellPx + half
    if (widthPx > 0) right = Math.min(right, widthPx)
    out.push({
      block: b,
      group: span.group,
      hue: groupHue(span.group),
      left: left,
      width: right - left,
      height: heightPx
    })
  }
  return out
}
```

Expected width, where `span = maxCol - minCol + 1` and
`S = span * (cellPx + gapPx)` (the unclamped width), `H = gapPx / 2`:

| Band | Clamp that bites | Width |
|---|---|---|
| interior (not first, not last) | none | `S` |
| first block (`minCol === 0`) | `left` pinned to 0 | `S - H` |
| last block | `right` pinned to `plan.width` | `S - H` |
| only block (first and last) | both | `S - 2H` = `S - gapPx` |

Consequences to state in the code comment and to assert in the tests:

- A one-container stack has `span = 1`, so `S = cellPx + gapPx` and its band is
  `cellPx + gapPx` wide when it is an interior block (visible on both sides),
  `cellPx + H` when it is the first or last block (visible on one side), and
  `cellPx` when it is the **only** block.
- That lone case is **accepted**: a mosaic with a single container has one band,
  exactly its own cell, and nothing to distinguish it from. Do not widen the
  formula to cover it - the extra half gap each side would push the band past
  the bar, which is the clamp's whole purpose.
- A lone block with more than one column is still visible: `S - gapPx` is the
  cells' own row span, wider than the cells leave uncovered in their internal
  gaps.

In `plan()` (the inner `plan` function of `planMosaic`), lift the row height
into a local (`var height = rows * cell + gap * (rows - 1)`, the value the
return object already has) and add to the returned object:

```js
bands: mode === "container" && grouped
  ? mosaicBands(cells, grid.cells, cell, gap, blockGap, height, width)
  : []
```

where `width` is the `mosaicWidth(...)` value the same object already computes.

`cells[i].group` is set for both `byContainer` and `byStack` cells
(`Docker.js`, `planMosaic`), and `blockLayout` gives every cell a `block`
index.

## B3. `Mosaic.qml` - paint the bands

- Add `property bool groupColours: false`.
- Add a `Repeater` over `plan.bands` **before** the cells `Repeater`, so the
  bands render behind:

```qml
Repeater {
  model: root.groupColours ? (root.plan.bands || []) : []

  Rectangle {
    required property var modelData
    x: modelData.left - root.snapX
    y: root.topInset - root.snapY
    width: modelData.width
    height: modelData.height
    radius: Math.min(3, root.plan.cellPx / 2)
    // A muted tint: the cell on top is the state, this is only the group.
    color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.30)
    Behavior on color { ColorAnimation { duration: 200 } }
  }
}
```

Bands and cells must use the same `snapX`/`snapY`.

## B4. `Panel.qml` - pass through, and the popup accent

- Add `readonly property bool groupColours: setting("groupColours", false) === true`
  next to the other `look` settings (the `readonly property bool groupStacks`
  block in `Panel.qml`).
- Pass `groupColours: root.groupColours` to the `Mosaic` in `Panel.qml`.
- Popup stack header: add a small rounded accent bar at the left edge of the
  stack header `Rectangle`, keeping the existing state dot (the small
  `Rectangle` whose colour is chosen from `stackBlock.modelData.worst`) so state
  and identity stay separate readings:

```qml
Rectangle {
  visible: root.groupColours
  anchors.left: parent.left
  anchors.verticalCenter: parent.verticalCenter
  width: Style.space(3)
  height: parent.height - Style.space(6)
  radius: width / 2
  color: Qt.hsla(Docker.groupHue(stackBlock.modelData.project) / 360,
                 0.55, 0.55, 0.95)
}
```

## B5. Tooltip - the stack name

The host tooltip is `bar.showTooltip(target, text)` / `bar.hideTooltip(target)`
(`PluginBarApi`; documented in `/usr/share/omarchy/shell/plugins/bar/README.md`;
first-party widgets use it in `plugins/bar/widgets/ActiveWindow.qml`).

**The target must expose `tooltipHovered === true`.** `Bar.showTooltip` returns
early on `!targetTooltipHovered(target)`, and `targetTooltipHovered`
(`plugins/bar/Bar.qml`, ~line 399) is
`!!target && target.visible !== false && target.opacity !== 0 &&
target.tooltipHovered === true`. A widget without that property gets a silent
no-op: the tooltip never appears and nothing errors. So `Mosaic.qml` must add:

```qml
readonly property bool tooltipHovered: blockHover.hovered && root.visible
```

- `Mosaic.qml`: a **single** `HoverHandler` on the mosaic root (not one per
  band), so moving across the block gaps does not churn enter/exit - the reason
  the previous bar tooltip was removed (commit `736a0e7`). `enabled` is
  `root.groupColours && root.visible`. While hovered, map `point.position.x`
  back into the plan's pixel space (`x + snapX`) and look up the band with the
  pure helper `Docker.bandAt(bands, x)`. Emit:

  ```qml
  signal blockHovered(string name)
  signal blockUnhovered()
  ```

  - Emit `blockHovered(name)` only when the name under the pointer changes.
  - `bandAt` is containment-only, so a point in the block gap resolves to no
    band. **Keep the last name across the gap** rather than clearing it, so the
    tooltip does not blink at every stack boundary.
  - Emit `blockUnhovered()` when hover ends.
  - Collapsed and ungrouped modes have no bands, so `bandAt` always misses and
    no tooltip is shown (see Non-goals).

- **Clear the tooltip when what it names goes away, and only then.** Reset the
  tracked name and emit `blockUnhovered()` when either:
  - `groupColours` turns false while hovered - the handler is disabled, which
    fires `onHoveredChanged` with `hovered === false`, or
  - the **bands** actually change. Do not key this off `plan` itself: the panel
    rebuilds `resolved` on every state read - `docker events` activity and the
    60s safety poll included - even when the layout is identical, so
    `onPlanChanged` would hide the tooltip once a minute for no reason. That is
    the same class of unexplained disappearance that removed the first tooltip.
    Key it off a band signature instead:

    ```qml
    // The bands, not the plan: a state refresh that leaves the layout alone
    // must not hide the tooltip under a stationary pointer. Built as JSON,
    // never delimiter-joined: group names come from compose labels, which are
    // hostile input, and a name containing ":" or "|" could otherwise
    // serialise to the same string as a different layout and swallow the
    // clear.
    readonly property string bandSignature: {
      var bands = root.plan.bands || []
      var parts = []
      for (var i = 0; i < bands.length; i++)
        parts.push([bands[i].group, bands[i].left, bands[i].width])
      return JSON.stringify(parts)
    }

    onBandSignatureChanged: {
      root.hoveredName = ""
      root.blockUnhovered()
    }
    ```

    A container added or removed reflows the blocks, which changes the
    signature, which clears the stale name. An unchanged layout leaves the
    signature alone and the tooltip stays.

- `Panel.qml`: connect them to the host tooltip, translating the loose group:

  ```qml
  onBlockHovered: function(name) {
    if (root.bar && root.bar.showTooltip)
      root.bar.showTooltip(mosaic, name === Docker.LOOSE ? root.tr("group.loose") : name)
  }
  onBlockUnhovered: function() {
    if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(mosaic)
  }
  ```

Gate both signals on `groupColours`, so one switch turns the whole feature on.

## B6. `I18n.js`

Moved into B1: the pt label and help land with the manifest key, in the same
step, because the suite is red in between. Nothing else is needed here - the
tooltip reuses `group.loose`, which already exists in both tables.

## B7. Docs

- `README.md`: add a `groupColours` row to the settings table, and a sentence in
  the mosaic section about the stack band and the hover name.
- `CHANGELOG.md`: add an `## Unreleased` section above `## 1.1.0` with an
  **Added** entry for stack colours and a **Fixed** entry for the settings
  screen (state the shell incompatibility plainly).
- `CLAUDE.md`: note the shell-injection fact - a third-party bar widget's
  `bar.shell` is a scoped `PluginShellApi` with no `pluginRegistry`, the schema
  arrives through the service, and writes go through `updateEntryInline`. Update
  the check count if the README or CLAUDE.md quotes it.

---

# Part C - tests (`test_docker.js`)

Add checks; the file is plain node, `node test_docker.js`.

- `groupHue`: same name -> same hue; `[0, 360)` and integer; two different
  fixture stack names differ.
- `mosaicBands` / `plan.bands`:
  - container + grouped -> one band per stack, in `stableGroupOrder` order, each
    covering its block's whole column range.
  - Width is per-position, not one formula (B2's table). Build the assertion
    from hand-written placements so it does not depend on the fixture's stack
    count. With `cellPx = 4, gapPx = 2`:
    - interior block -> `span * (cellPx + gapPx)`
    - first block -> that minus `gapPx / 2`
    - last block -> that minus `gapPx / 2`
    - only block -> that minus `gapPx`
  - a one-container stack that is not the only block has `width > cellPx`; a
    lone one-container block has `width === cellPx` - assert the equality, so
    the accepted case (B2) is explicit rather than accidental.
  - not emitted when `groupStacks` is false, nor in `stack`/`single` mode.
- `bandAt(bands, x)`: containment only. A point inside a band returns it; a
  point in the block gap returns `null` (assert the null - the tooltip relies on
  keeping the last name across the gap, so a "helpful" neighbour guess would
  reintroduce blinking); past the last band returns `null`; empty and `null`
  band lists return `null`.
- Schema/placement: the existing "every manifest key is filed into a named
  section" check covers the new key; confirm it stays green.
- I18n: the existing "Portuguese label and help for every schema field" check
  covers the new field.
- Keep the count quoted in `CLAUDE.md`/`README.md` in step with the file.

# Part D - verification

1. `node test_docker.js` - all green.
2. `omarchy restart shell`.
3. Open the settings screen; confirm fields render and the changed count works.
4. Change three or more settings, then press **Reset everything**; confirm the
   header returns to "All at their defaults" and each changed key in
   `shell.json` is back at its default value. The keys stay present; their
   presence is not a failure (A4).
5. Turn **Colour stacks** on; confirm the mosaic shows bands and the popup
   headers show accents; hover a band and confirm the tooltip names the stack.
   Then move the pointer straight from one band to the next: the name must
   change to the new stack. The host clears and re-arms its tooltip on every
   `showTooltip` (it has a short show delay), so a brief gap on the move is
   expected; if the name does not change, or the gap is worse than a gap, drop
   B5 rather than ship it.
6. The tooltip does not clear on its own. Hold the pointer still over a band:
   - across a state refresh that leaves the layout unchanged (a `docker events`
     burst elsewhere on the machine, or the 60s safety poll) the name must
     **stay**;
   - then change the layout (start or stop a container in that stack) and it
     must **clear**, rather than name a stack that is no longer under the
     pointer.
7. Screenshot the bar and check the bands are visible, not clipped, and not
   confused with the cell colour: `hyprctl monitors -j`, then
   `grim -g "<x>,<y> <w>x30" - | magick - -scale 800% /tmp/bar.png`.
8. Confirm `groupColours: true` is in `shell.json` and survives a restart.

# Risks

- **Tooltip flicker** (the reason the old bar tooltip was removed): mitigated by
  a single mosaic-level `HoverHandler`, keeping the last name across the block
  gap, clearing only on a band-signature change rather than on every state read,
  and `metricWidthSample` having already fixed the widget's width. If it still
  flickers, drop B5 rather than ship it.
- **Band strength across themes**: fixed HSLA may read as too strong on a light
  theme. Tune saturation/alpha against a real theme and screenshot both.
- **`updateEntryInline` return value is ambiguous** (false for no-op and for
  refusal). A3's `writeSettings` comparison removes the ambiguity before the
  call.
- **Reset-everything lost updates**: A3 writes once instead of looping; A4 and
  Part D step 4 are the checks.
- **Schema arrives with the service**: if the service is not loaded yet the
  settings screen is briefly empty, the same as the container list. Acceptable.
- **Write path is shell-version specific**: if `bar.shell.updateEntryInline`
  disappears, `canWriteSettings` is false and the screen says so by name
  (`settings.readOnly`), rather than looking live and doing nothing.
- **`tooltipHovered` is load-bearing**: without it `Bar.showTooltip` is a silent
  no-op. B5 states it; the manual step 5 is the check.

# Review findings and disposition

After the first implementation pass, the code reviewers raised no blockers. Four
items were settled by reading `/usr/share/omarchy/shell/` directly (no code
change); two were accepted and are reflected above.

Settled from the shell source, no change needed:

- **Schema reactivity after a rescan (raised as a major) - rejected.**
  `PluginRegistryApi.installedPlugins` is a binding over its own `manifest`
  property, and `syncPluginApis` (`shell.qml`, ~line 861) reassigns
  `registryApi.manifest` on `pluginRegistry.pluginsChanged()`, which a rescan
  emits. So `installedPlugins` re-evaluates and `Service.settingsSchema` with
  it. The old `registryRevision` read is not what provides this.
- **Tooltip markup from a label-derived name - rejected.**
  The host's tooltip label sets `textFormat: Text.PlainText`
  (`plugins/bar/Bar.qml`, the tooltip bubble's `Text`), so a crafted
  `com.docker.compose.project` cannot inject markup.
- **Cross-band retarget - rejected.** `Bar.showTooltip` calls `clearTooltip()`
  first, so a repeat call for the same target replaces the text, and the plugin
  only calls it when the name changes. Part D step 5 now exercises the
  transition.
- **`gridHeight`/`gridWidth` instead of the plan's `height` - accepted as
  better**; it avoids shadowing the `settings.heightPx` local.
- **Band delegates rebuilt on every state read - accepted, no action.** Cheap
  at desktop stack counts, and the tooltip no longer keys off `plan`.

Accepted and reflected in the plan:

- **Band-signature collision (raised as a minor) - fixed in B5.** The signature
  is built with `JSON.stringify`, not delimiter concatenation, because group
  names come from compose labels and are hostile input.
- **Band edges are not device-snapped (raised as a minor) - documented, not
  fixed.** B2 now says the half-gap can land on a half device pixel and that
  this is accepted for a translucent band, unlike a cell edge.

Third review (plan conformance, of the implementation): CONFORMS WITH NOTED
DEVIATIONS. No blockers, no majors.

- **A multi-column lone block was tested only at span 1.** The only-block width
  `S - gapPx` was asserted only where it collapses to `cellPx`. Part C already
  lists the case; only the test was short. A follow-up adds one assertion for a
  two-column lone block (`cellPx = 4, gapPx = 2` -> `width === 10`).
- **`bandSignature` uses `JSON.stringify`** - that is what this plan now
  specifies (B5), for the collision reason above, so it is not a deviation from
  the current plan.
- **Undocumented but harmless additions** accepted: lifting `gridWidth` and
  `blockGapHere` in `plan()` alongside the row height, the half-device-pixel
  band-edge comment, and the rewritten bar-button comment. None change
  behaviour.
- **`onBandSignatureChanged` emits `blockUnhovered()` with Colour stacks off**
  (the plan says to gate the signals on the switch). Accepted, no change: the
  host's `hideTooltip` returns early when the target is neither the shown nor
  the pending tooltip target (`plugins/bar/Bar.qml`, `hideTooltip`), and nothing
  else in the panel uses the mosaic as a tooltip target, so the call is a no-op.
  Gating it would be tidier and buys nothing.

# Out of scope

- Per-container colours.
- A user-chooseable colour per stack.
- Any change to the mosaic's cell colour semantics or to the shell itself.
