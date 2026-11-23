# ROWS: Rows layout

[All areas](README.md)

The Rows layout mode ("Arrange in rows"): rows of windows sharing a top and a height, x free
within a row, plus an "inbox" to the rows' right. `RowLayout` is pure functions exercised
directly; the later cases cover it wired into the canvas, fake windows standing in for real ones.

## ROWS-01 A row shares its top and height
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Windows assigned to rows, some with heights of their own.
- **Steps:** Lay the set out (`RowLayout.layout`).
- **Expected:** Every window in a row gets the row's top and the row's window height; a window
  its app sizes (VMs) keeps its height, top-aligned. Within a row windows stay in x order with
  at least the gap between them — an overlapping one is pushed right. Empty row numbers are
  squeezed out: rows renumber to 0, 1, 2… in their previous order.
- **Automate:** unit: `layout` on rows with unsorted, overlapping frames and a sized-itself
  window, and on non-contiguous row indices.

## ROWS-02 The inbox sits right of the rows and packs on shelves
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Rowed windows plus windows in no row.
- **Steps:** Lay the set out.
- **Expected:** The unrowed windows pack left to right from a inbox gap right of the rows' right
  end, ordered by their spot's (top, left), at their own sizes, the gap between neighbours.
  Reaching the inbox's max width wraps to a new shelf under the tallest of the last; a window
  wider than a whole shelf gets one to itself.
- **Automate:** unit: `layout` with mixed sizes past `inboxMaxWidth`, checking shelf rows, and
  ordering by (minY, minX).

## ROWS-03 Laying out is stable
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Any set of items.
- **Steps:** Lay it out twice.
- **Expected:** The second layout changes nothing (`layout` is idempotent).
- **Automate:** unit: `layout(layout(x)) == layout(x)` on a mixed rows-and-inbox set.

## ROWS-04 Dropping into a row inserts and shoves right
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** A row of windows; a window dragged over it.
- **Steps:** Let go with the dragged middle inside the row (`RowLayout.drop`).
- **Expected:** Windows whose middles are left of the drop's keep their x; the drop lands right
  after the rightmost one it would overlap (gap between); everything further right is pushed on
  past it, never overlapped. Dropped over a window's left end — its middle right of that
  window's middle — it lands after it.
- **Automate:** unit: `drop` into a row's middle and over a left neighbour's end, checking the
  shoved neighbours' new x.

## ROWS-05 Dropping past the rows opens a new row; into the inbox off the rows' heights puts it back
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Two rows and a dragged window.
- **Steps:**
  1. Let go above the first row.
  2. Let go below the last.
  3. Let go with its middle right of the rows' right end, at a height no row covers.
- **Expected:** Step 1 opens a new row 0 and pushes the others down; step 2 opens one at the
  bottom; step 3 puts it back in the inbox at the inbox's packed spot, at its own size.
- **Automate:** unit: `drop` with middles before the first row, past the last, and right of
  `inboxMinX` off the rows' heights — at a row's height it extends that row instead.

## ROWS-06 Switching to Rows puts bands into rows and strays into the inbox
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** A free layout whose windows loosely line up.
- **Steps:** Switch to Rows (`RowLayout.distribute`).
- **Expected:** Windows sorted by top group into bands — a window joins a band when its vertical
  overlap with it is at least half the smaller height. A band of two or more becomes a row
  (rows ordered by their top, x kept); a lone window goes to the inbox.
- **Automate:** unit: `distribute` on an aligned trio, on two far-apart bands, and with a stray
  singleton below them.

## ROWS-07 A gap in a row collapses
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** A row with an empty stretch between windows.
- **Steps:** Close the gap at a spot in it (`RowLayout.collapseGap`), or close every gap
  (`RowLayout.collapseAll`).
- **Expected:** Every window at or right of the spot slides left till the first is one gap from
  the window before it; windows left of the spot don't move. A spot before the row's first
  window, or a gap already tight, moves nothing. `collapseAll` leaves each row gap-tight from
  its leftmost window.
- **Automate:** unit: `collapseGap` mid-row, at the row's left edge, on a tight gap; and
  `collapseAll`.

## ROWS-08 Turning Arrange in rows on lays bands out as rows
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" off, windows loosely in bands on the canvas.
- **Steps:** Turn "Arrange in rows" on in the menu bar panel.
- **Expected:** Bands become rows — every window at its row's top at the work area's height
  (the screen less the menu bar, the Dock and the margins); strays go to the inbox right of the
  rows at their own sizes. The rows' windows are resized for real; x is kept where nothing
  overlaps.
- **Automate:** unit: `rowsMode = true` on a fake canvas with two bands and a stray.

## ROWS-09 A new window opens in the inbox
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:** Open a window anywhere.
- **Expected:** It joins the unsorted inbox right of the rows at its own size (no row is made for
  it, and nothing in a row moves), and the view glides there as for any window opened off screen.
- **Automate:** unit: a scan bringing a new standard window, on a rows canvas.

## ROWS-10 A canvas drop lands in a row or back in the inbox
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:**
  1. Drag a window so its middle is in another row, over a window's right end.
  2. Drag one right past the rows' right end, letting go between the rows' heights.
  3. Same, letting go at a row's height.
- **Expected:** Step 1 lands it in that row after the window it overlapped, the windows to its
  right shoved on; step 2 puts it back in the inbox; step 3 extends that row where dropped.
  While you drag, only x snaps — y follows the pointer — and no built-screen drop zones appear.
- **Automate:** unit: `rowsDrop` between rows and into the inbox region.

## ROWS-11 A display change re-lays the rows
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:** Move to a display whose work area is a different height (a Dock shown or not).
- **Expected:** Rows re-lay at the new row height — same tops, x kept — and the windows' real
  sizes follow.
- **Automate:** unit: `refit` after a display change on a rows canvas.

## ROWS-12 A window's row survives restarts
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:** Quit Expanse and open it again; come back from minimising a window, or bring its
  next tab forward; restore a snapshot.
- **Expected:** Windows come back in their rows and the inbox, since the row is saved with the
  spot and restored with it (layouts saved before rows have no row — the inbox — and still load).
- **Automate:** unit: `savedEntry` → file → `takeSpot`, plus a tab-takeover `Departed` row.

## ROWS-13 Dragging on the canvas snaps sideways only
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" on, dragging a window on the canvas.
- **Steps:** Drag near a window's top or bottom edge.
- **Expected:** The drag snaps sideways (edges, the gap, centres) but the window's y follows the
  pointer: the row a drop lands in is where the drag's middle is, not a snap.
- **Automate:** unit: `snap` with `yToo: false` leaves minY alone and draws no y guide.

## ROWS-14 With Arrange in rows off, nothing changes
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** "Arrange in rows" off (the default).
- **Steps:** Use Expanse as ever.
- **Expected:** The free layout is exactly as before: drops note a move, snaps work both ways,
  no engine pass ever runs.
- **Automate:** unit: `rowsDrop`/`applyRows` are no-ops with the mode off; `snap`'s default still
  snaps y.

## ROWS-15 A centred row keeps the rows beside it off the screen
- **Type:** Bug fix
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Before:** Rows were a window-height plus the standard gap apart, so with a row centred at
  100% the next row's top sat a few points below the work area — inside the Dock strip but
  still on the screen — and its windows showed as slivers beside and behind the Dock.
- **Now:** Rows sit more than a viewport apart: the space between them is the out-of-view strip
  (the Dock's, say) plus a margin, at least 96pt. With a row centred in the work area, the rows
  beside it lie wholly off the screen and stay parked pictures on the backdrop.
- **Automate:** unit: with a bottom-Dock display, `focusCamera` on a row's window leaves the
  neighbouring rows' real rects off the viewport and `commitPlan` parks them.
