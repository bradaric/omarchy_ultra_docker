# Stack colours, and the settings screen that never rendered

Status: approved 2026-10-15.

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

`Panel.qml:168-178` builds the settings field list from:

```
bar.shell.pluginRegistry.installedPlugins[pluginId].barWidget.schema
```

That path does not exist for a **third-party** bar widget on this shell:

- `../shell/plugins/bar/Bar.qml:2002` - a third-party widget's `bar` is a
  `PluginBarApi` facade, not the Bar.
- `Bar.qml:229-243` sets that facade's `shell` to
  `root.shell.pluginShellForId(...)` -> `shell.qml:676-682` ->
  `createScopedPluginShell(...)`, which returns a `PluginShellApi`.
- `services/PluginShellApi.qml` has `serviceFor`, `summon`, `hide`, `toggle`,
  `isPluginOpen`, `updateEntryInline`, `mutateShellConfig` - and **no
  `pluginRegistry`**.

So `bar.shell.pluginRegistry` is `undefined`, `settingsSchema` is `[]`,
`settingsSections` is `[]`, and the screen has nothing under its header.
`settingsError` stays blank because it is only written on a failed *write*.

The scoped registry object that *does* carry the manifest (`PluginRegistryApi`,
whose `installedPlugins` includes `barWidget.schema`) is only injected when an
entry point declares `pluginRegistry`. Bar widgets are not given it; **service
entry points are** (`shell.qml:931-932`).

The same gap breaks writes. `Panel.qml:304` calls
`pluginRegistry.setBarWidget(...)`, which for this plugin is unreachable. The
reachable call is `bar.shell.updateEntryInline(id, settings)`
(`PluginShellApi.qml:62` -> `shell.qml:1078`). It **replaces the whole entry**
with `{id, ...settings}`, so it must be handed the current settings merged with
the changed key, or every write wipes the other keys.

The `omarchy bar set` CLI still works, because it goes through the root registry
(`shell.qml:1654`), not the facade.

## Goals

- Restore the settings screen: all fields readable, and writes that persist to
  `~/.config/omarchy/shell.json` and survive restart/reboot.
- Add an opt-in per-stack colour: a tinted background band behind each stack's
  block in the bar mosaic, and a matching accent in the popup stack headers.
- Hovering the mosaic shows which stack is under the pointer, by name.

## Non-goals

- No per-container colour. Per stack only.
- No colour in the collapsed modes (one cell per stack already separates them).
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

# Part A - fix the settings screen

## A1. `Service.qml` - take the registry the shell does inject

Service entry points get a scoped `PluginRegistryApi` injected when they declare
the property (`shell.qml:932`). Add, right after `id: root`:

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
scoped view is updated in place on a rescan (`shell.qml:867`), so the binding
re-evaluates with a changed manifest.

## A2. `Panel.qml` - read the schema from the service

Replace the `settingsSchema` binding (`Panel.qml:168-178`) with:

```qml
// Built from the plugin's own manifest, read out of the shell's registry by
// the service. The bar widget cannot reach the registry itself: its
// `bar.shell` is a scoped PluginShellApi with no pluginRegistry on it.
readonly property var settingsSchema: service ? service.settingsSchema : []
```

`settingsSections` and `changedSettings` (`Panel.qml:180-182`) stay as they are;
they already derive from `root.settingsSchema`.

Keep `readonly property string pluginId` - it is still used in the read-only
message and the IPC verb.

Remove the now-dead `pluginRegistry` property (`Panel.qml:166`) **only after**
A3 replaces its two remaining uses (`canWriteSettings`, `writeSetting`).

## A3. `Panel.qml` - write through the scoped shell

`updateEntryInline` replaces the whole entry, so merge first and only write when
something actually changed (it returns `false` both for "no change" and for a
refused call, so we cannot tell them apart from its return value alone).

```qml
readonly property bool canWriteSettings:
  !!(root.bar && root.bar.shell
     && typeof root.bar.shell.updateEntryInline === "function")

function writeSetting(key, value) {
  if (!root.canWriteSettings) {
    root.settingsError = root.tr("settings.readOnly", { id: root.pluginId })
    return
  }
  var current = root.settings || ({})
  var merged = ({})
  for (var k in current) merged[k] = current[k]
  merged[String(key)] = value
  // updateEntryInline replaces the entry it finds, so the whole current
  // settings object goes back with the one change, not just the change.
  if (JSON.stringify(merged) === JSON.stringify(current)) {
    root.settingsError = ""
    return
  }
  var ok = root.bar.shell.updateEntryInline(root.pluginId, merged)
  root.settingsError = ok
    ? "" : root.tr("settings.writeFailed", { error: "updateEntryInline" })
}
```

`resetSetting` and `resetAllSettings` (`Panel.qml:309-320`) are unchanged; they
call `writeSetting`.

## A4. Verify

- `omarchy restart shell` (the shell runs the plugin it loaded at startup).
- `omarchy-shell avila.ultra-docker settings` - expect the five sections and all
  fields, no errors.
- Change one field; confirm the key lands in `~/.config/omarchy/shell.json`
  under the widget's `bar.layout.<section>[]` entry, and that the other keys
  already in that entry are still there.
- Restart the shell again and confirm the value survives.

---

# Part B - stack colours

## B1. `manifest.json`

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
column range and the full mosaic height, expanded by half a gap so that a
**single-container stack still shows a band** (otherwise the band is hidden
behind its own cell).

```js
// One background band per stack block, in the mosaic's own pixel space (the
// renderer applies the pixel snap). Half a gap on each side, so a stack with
// one container still shows a band wider than its own cell; clamped to the
// mosaic so the first and last bands do not overhang it.
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

In `plan()` (`Docker.js:705-738`), lift the row height into a local
(`var height = rows * cell + gap * (rows - 1)`, the value the return object
already has) and add to the returned object:

```js
bands: mode === "container" && grouped
  ? mosaicBands(cells, grid.cells, cell, gap, blockGap, height, width)
  : []
```

where `width` is the `mosaicWidth(...)` value the same object already computes.

`cells[i].group` is set for both `byContainer` and `byStack` cells
(`Docker.js:681-700`), and `blockLayout` gives every cell a `block` index.

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
  next to the other `look` settings (`Panel.qml:344-350`).
- Pass `groupColours: root.groupColours` to the `Mosaic` (`Panel.qml:634-645`).
- Popup stack header (`Panel.qml:1799-1850`): add a small rounded accent bar at
  the left edge of the header `Rectangle`, keeping the existing state dot
  (`Panel.qml:1841-1850`) so state and identity stay separate readings:

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

Use the host tooltip API (`PluginBarApi.showTooltip`, documented in
`../shell/plugins/bar/README.md:165`, used by first-party widgets in
`ActiveWindow.qml:61`).

- `Mosaic.qml`: a **single** `HoverHandler` on the mosaic root (not one per
  band), so moving across the block gaps does not churn enter/exit - the reason
  the previous bar tooltip was removed (commit `736a0e7`). While hovered, map
  `point.position.x` to a band via a small pure helper
  `Docker.bandAt(bands, x)` and emit:

  ```qml
  signal blockHovered(string name)
  signal blockUnhovered()
  ```

  Emit `blockHovered(name)` only when the band changes; emit
  `blockUnhovered()` when hover ends.

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

- `pt` table only (English comes from the manifest, which is the existing rule
  for `settings.label.*` / `settings.help.*`):

  ```js
  "settings.label.groupColours": "Colorir stacks",
  "settings.help.groupColours": "Uma faixa tingida atrás de cada stack do compose na barra, e um acento igual nos cabeçalhos do popup. Saudável, atenção e quebrado continuam sendo a cor da célula.",
  ```

- The tooltip reuses `group.loose`, which already exists.

## B7. Docs

- `README.md`: add a `groupColours` row to the settings table
  (`README.md:311-325`), and a sentence in the mosaic section about the stack
  band and the hover name.
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
- `mosaicBands` (or `plan.bands`):
  - container + grouped -> one band per stack, band columns match the block's
    column range, `width` follows `columns*(cell+gap) - gap + 2*(gap/2)`, and a
    single-container stack still has `width > cellPx`.
  - not emitted when `groupStacks` is false, nor in `stack`/`single` mode.
- `bandAt(bands, x)`: returns the band containing `x`, and the gap between two
  blocks resolves to one of them (or null) deterministically - lock whichever
  the implementation chooses.
- Schema/placement: the existing "every manifest key is filed into a named
  section" check covers the new key; confirm it stays green.
- I18n: the existing "Portuguese label and help for every schema field" check
  covers the new field.
- Keep the count quoted in `CLAUDE.md`/`README.md` in step with the file.

# Part D - verification

1. `node test_docker.js` - all green.
2. `omarchy restart shell`.
3. Open the settings screen; confirm fields render and the changed count works.
4. Turn **Colour stacks** on; confirm the mosaic shows bands and the popup
   headers show accents; hover a band and confirm the tooltip names the stack.
5. Screenshot the bar and check the bands are visible, not clipped, and not
   confused with the cell colour: `hyprctl monitors -j`, then
   `grim -g "<x>,<y> <w>x30" - | magick - -scale 800% /tmp/bar.png`.
6. Confirm `groupColours: true` is in `shell.json` and survives a restart.

# Risks

- **Tooltip flicker** (the reason the old bar tooltip was removed): mitigated by
  a single mosaic-level `HoverHandler` and by `metricWidthSample` having already
  fixed the widget's width. If it still flickers, drop B5 rather than ship it.
- **Band strength across themes**: fixed HSLA may read as too strong on a light
  theme. Tune saturation/alpha against a real theme and screenshot both.
- **`updateEntryInline` return value is ambiguous** (false for no-op and for
  refusal). A4's value comparison removes the ambiguity before the call.
- **Schema arrives with the service**: if the service is not loaded yet the
  settings screen is briefly empty, the same as the container list. Acceptable.
- **Write path is shell-version specific**: if `bar.shell.updateEntryInline`
  disappears, `canWriteSettings` is false and the screen says so by name
  (`settings.readOnly`), rather than looking live and doing nothing.

# Out of scope

- Per-container colours.
- A user-chooseable colour per stack.
- Any change to the mosaic's cell colour semantics or to the shell itself.
