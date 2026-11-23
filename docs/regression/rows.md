# ROWS: Rows layout

[All areas](README.md)

The Rows layout mode's engine: rows of windows sharing a top and a height, x free within a row,
plus an "unsorted grid" to the rows' right. Pure functions (`RowLayout`), exercised directly by
the unit tests — no canvas, controller or screen involved yet.

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

## ROWS-02 The grid sits right of the rows and packs on shelves
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Rowed windows plus windows in no row.
- **Steps:** Lay the set out.
- **Expected:** The unrowed windows pack left to right from a grid gap right of the rows' right
  end, ordered by their spot's (top, left), at their own sizes, the gap between neighbours.
  Reaching the grid's max width wraps to a new shelf under the tallest of the last; a window
  wider than a whole shelf gets one to itself.
- **Automate:** unit: `layout` with mixed sizes past `gridMaxWidth`, checking shelf rows, and
  ordering by (minY, minX).

## ROWS-03 Laying out is stable
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Any set of items.
- **Steps:** Lay it out twice.
- **Expected:** The second layout changes nothing (`layout` is idempotent).
- **Automate:** unit: `layout(layout(x)) == layout(x)` on a mixed rows-and-grid set.

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

## ROWS-05 Dropping past the rows opens a new row; into the grid puts it back
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** Two rows and a dragged window.
- **Steps:**
  1. Let go above the first row.
  2. Let go below the last.
  3. Let go with its middle right of the rows' right end.
- **Expected:** Step 1 opens a new row 0 and pushes the others down; step 2 opens one at the
  bottom; step 3 puts it back in the grid at the grid's packed spot, at its own size.
- **Automate:** unit: `drop` with middles before the first row, past the last, and right of
  `gridMinX`.

## ROWS-06 Switching to Rows puts bands into rows and strays into the grid
- **Type:** Feature
- **Area:** ROWS
- **Commits:** unreleased (23 Nov)
- **Setup:** A free layout whose windows loosely line up.
- **Steps:** Switch to Rows (`RowLayout.distribute`).
- **Expected:** Windows sorted by top group into bands — a window joins a band when its vertical
  overlap with it is at least half the smaller height. A band of two or more becomes a row
  (rows ordered by their top, x kept); a lone window goes to the grid.
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
