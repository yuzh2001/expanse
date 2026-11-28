# ROWS: Rows layout

[All areas](README.md)

The Rows layout mode ("Arrange in rows"): rows of windows sharing a top and a height, x free
within a row — and every window in one, a drop anywhere joining the nearest. `RowLayout` is
pure functions exercised directly; the later cases cover it wired into the canvas, fake windows
standing in for real ones.

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

## ROWS-02 An unplaced window joins the row nearest its middle
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (28 Nov)
- **Setup:** Rowed windows plus windows in no row yet (a stranger the saved layout didn't know,
  say).
- **Steps:** Lay the set out.
- **Expected:** Each unplaced window joins the row nearest its middle — measured to the rows'
  middles, so anywhere in a row's band or the nearer half of a gap means that row. Past every
  row it joins the last; with no rows at all, row 0.
- **Automate:** unit: `layout` with row-less windows inside a lower row's band, far below every
  row, and on an empty canvas.

## ROWS-03 Laying out is stable
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Any set of items.
- **Steps:** Lay it out twice.
- **Expected:** The second layout changes nothing (`layout` is idempotent).
- **Automate:** unit: `layout(layout(x)) == layout(x)` on a mixed set of rows and unplaced windows.

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

## ROWS-05 Dropping anywhere joins the nearest row; past the ends opens a new one
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (28 Nov)
- **Setup:** Two rows and a dragged window.
- **Steps:**
  1. Let go above the first row, its middle past halfway across the gap.
  2. Let go below the last.
  3. Let go in the gap between the rows.
- **Expected:** Step 1 opens a new row 0 and pushes the others down; step 2 opens one at the
  bottom; step 3 joins whichever row its middle is nearer — there is nowhere outside the rows,
  however far right the drop is.
- **Automate:** unit: `drop` with middles before the first row, past the last, at a row's height
  far right of the rows' end, and in the gap on either side of its halfway.

## ROWS-06 Switching to Rows puts bands into rows and a stray in a row of one
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** A free layout whose windows loosely line up.
- **Steps:** Switch to Rows (`RowLayout.distribute`).
- **Expected:** Windows sorted by top group into bands — a window joins a band when its vertical
  overlap with it is at least half the smaller height. Every band becomes a row (rows ordered
  by their top, x kept) — a lone window is a row of one.
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
  (the screen less the menu bar, the Dock and the margins); a stray is a row of one. The rows'
  windows are resized for real; x is kept where nothing overlaps.
- **Automate:** unit: `rowsMode = true` on a fake canvas with two bands and a stray.

## ROWS-09 A new window opens at the right end of the row you're working in
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (28 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:** Open a window anywhere.
- **Expected:** It joins the row of the window you were working in (the same app's latest, or
  the latest at all), at that row's right end — a gap past its rightmost window — at the row's
  top and height, and the view glides there as for any window opened off screen.
- **Automate:** unit: a scan bringing a new standard window, on a rows canvas.

## ROWS-10 A canvas drop lands in the row nearest its middle
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (28 Nov)
- **Setup:** "Arrange in rows" on.
- **Steps:**
  1. Drag a window so its middle is in another row, over a window's right end.
  2. Drag one right past the rows' right end, letting go in the gap between the rows' heights.
  3. Same, letting go at a row's height.
- **Expected:** Step 1 lands it in that row after the window it overlapped, the windows to its
  right shoved on; step 2 joins whichever row the middle is nearer, at the drop's x; step 3
  extends that row where dropped. While you drag, only x snaps — y follows the pointer — and no
  built-screen drop zones appear.
- **Automate:** unit: `rowsDrop` between rows and into the gap far right of the rows.

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
- **Expected:** Windows come back in their rows, since the row is saved with the spot and
  restored with it (layouts saved before rows have no row — placed nearest their middle — and
  still load).
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
