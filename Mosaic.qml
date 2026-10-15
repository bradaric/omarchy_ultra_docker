// The bar mosaic. One cell per container, grouped into a block of columns per
// compose stack; or one cell per stack when the detailed view does not fit the
// width budget.
//
// All the arithmetic lives in Docker.planMosaic(), which is plain JS and
// tested. This file only turns the plan into pixels.

import QtQuick
import QtQuick.Window
import qs.Commons
import "Docker.js" as Docker

Item {
  id: root

  // The object returned by Docker.planMosaic().
  property var plan: ({ cells: [], grid: { cells: [] }, cellPx: 0, gapPx: 1, blockGapPx: 0, width: 0 })
  property bool pulseRestarting: true
  // Off by default: cell colour is state, and a band is identity. The band is
  // opt-in so the mosaic stays a field of state squares for anyone who wants it.
  property bool groupColours: false
  // Passed in by the panel, which owns the rule for deriving a warning colour
  // when the theme sets `accent` equal to the foreground.
  property color okColor: Color.foreground
  property color warnColor: Color.accent
  property color badColor: Color.urgent

  // The host tooltip refuses a target without this (Bar.targetTooltipHovered),
  // so it is how the panel's showTooltip call gets through at all.
  readonly property bool tooltipHovered: blockHover.hovered && root.visible

  // Which stack the pointer is over, by name. The panel turns this into the
  // host tooltip; the loose group is translated there.
  signal blockHovered(string name)
  signal blockUnhovered()
  property string hoveredName: ""

  // The bands, not the plan: the panel rebuilds `resolved` on every state read
  // (`docker events` and the 60s poll included) even when the layout is
  // identical, so keying the clear off `plan` would hide the tooltip once a
  // minute for no reason. A container added or removed reflows the blocks and
  // changes this signature, which clears the stale name; an unchanged layout
  // leaves both alone. JSON, not delimiter-joined: the group names come from
  // compose labels, which are hostile input, so a name containing ":" or "|"
  // could otherwise serialise to the same string as a different layout and
  // swallow the clear.
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

  readonly property var cells: plan.cells || []
  readonly property var placements: plan.grid && plan.grid.cells ? plan.grid.cells : []

  implicitWidth: plan.width || 0
  implicitHeight: plan.height || 0

  // Rounding the cell to whole pixels can leave a pixel or two spare; keep the
  // rows centred in the space rather than pinned to the top.
  readonly property real topInset: Math.floor((height - (plan.height || 0)) / 2)

  // The bar places this widget on a fractional scene coordinate — measured at
  // x = 1381.296875 on the machine this was written for. Whole-pixel cells then
  // straddle pixel boundaries and rasterise at three or four pixels depending on
  // where each one lands, so a grid of identical cells renders as a grid of
  // visibly different ones.
  //
  // mapToItem is a function call, not a binding, so a correction computed from
  // it is stale by the time it matters — our own x never moves (we are first in
  // the row) and the row shifts without telling us. Walking the parent chain and
  // reading each `x` DOES bind: QML records every property read during the
  // evaluation, so this re-runs whenever any ancestor moves.
  readonly property real absoluteX: {
    var total = 0
    var item = root
    while (item) {
      total += item.x
      item = item.parent
    }
    return total
  }

  readonly property real absoluteY: {
    var total = 0
    var item = root
    while (item) {
      total += item.y
      item = item.parent
    }
    return total
  }

  // Shift the cells back onto the pixel grid.
  readonly property real snapX: absoluteX - Math.floor(absoluteX)
  readonly property real snapY: absoluteY - Math.floor(absoluteY)

  function colorFor(state) {
    if (state === "bad") return badColor
    if (state === "warn") return warnColor
    return okColor
  }

  // A container that stopped cleanly is not news. Dimming rather than hiding
  // keeps the mosaic the same shape whether or not everything is running.
  function opacityFor(state) {
    return state === "idle" ? 0.35 : 1
  }

  function restartingIn(cell) {
    var containers = cell.containers || []
    for (var i = 0; i < containers.length; i++) {
      if (containers[i].state === "restarting") return true
    }
    return false
  }

  // One handler for the whole mosaic, not one per band: moving across a band
  // boundary must not read as leaving and re-entering a target. The point is
  // mapped back into the plan's own pixel space (bands and cells share snapX),
  // and the last name is kept across the block gap rather than cleared.
  function hoverAt(x) {
    var band = Docker.bandAt(root.plan.bands, x + root.snapX)
    if (!band) return
    var name = String(band.group || "")
    if (name === "" || name === root.hoveredName) return
    root.hoveredName = name
    root.blockHovered(name)
  }

  HoverHandler {
    id: blockHover

    enabled: root.groupColours && root.visible

    onHoveredChanged: {
      if (!hovered) {
        root.hoveredName = ""
        root.blockUnhovered()
        return
      }
      root.hoverAt(point.position.x)
    }

    onPointChanged: if (hovered) root.hoverAt(point.position.x)
  }

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
      // The frame that makes a stack a chip instead of a stain. Snapped to a
      // whole DEVICE pixel: a 1-logical-pixel border is 0.85 device pixels under
      // QT_SCALE_FACTOR and rasterises as a soft half-pixel line. See the
      // device-pixel note in CLAUDE.md.
      border.width: Docker.snapToDevice(1, Screen.devicePixelRatio)
      border.color: Qt.hsla(modelData.hue / 360, 0.55, 0.55, 0.85)
      // The fill already animates; the outline has to follow it or the frame
      // snaps while the wash eases.
      Behavior on border.color { ColorAnimation { duration: 200 } }
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }

  Repeater {
    model: root.cells

    Rectangle {
      id: cellRect

      required property int index
      required property var modelData

      readonly property var placement: root.placements[index]
      readonly property bool restarting: root.pulseRestarting && root.restartingIn(modelData)

      // The extra block gap is what separates one stack from the next: cells of
      // the same stack sit adjacent, and the wider space marks the boundary.
      // Without it adjacency is not separation, and there is no way to see
      // where a stack ends.
      x: placement
        ? placement.column * (root.plan.cellPx + root.plan.gapPx)
          + placement.block * root.plan.blockGapPx - root.snapX
        : 0
      y: placement
        ? root.topInset + placement.row * (root.plan.cellPx + root.plan.gapPx)
          - root.snapY
        : 0
      width: root.plan.cellPx
      height: root.plan.cellPx
      radius: root.plan.cellPx > 6 ? 1.5 : 0

      color: root.colorFor(modelData.cell)
      opacity: root.opacityFor(modelData.cell)

      Behavior on color { ColorAnimation { duration: 200 } }
      Behavior on opacity { NumberAnimation { duration: 200 } }

      // The only movement in the widget, spent on the one state that otherwise
      // goes unnoticed for hours.
      SequentialAnimation on opacity {
        running: cellRect.restarting
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.3; duration: 1000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
      }
    }
  }
}
