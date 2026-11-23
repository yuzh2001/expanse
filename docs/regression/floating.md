# FLOAT: Floating windows

[All areas](README.md)

Floating windows ("float rules", Rows mode): a window matching a rule — a Settings pane, the
WeChat image viewer — opens over the window you're in, left where its app put it instead of
joining the layout. It's transient: focusing a managed window sweeps every floater into the
inbox, and so does going to the canvas. Closing one returns focus to the window you were in.
`WindowRules` is a pure match over (bundleID, title, has-sibling) exercised directly.

## FLOAT-01 A rule matches by app, then title, and non-main only with a sibling
- **Type:** Feature
- **Area:** FLOAT
- **Commits:** unreleased
- **Setup:** Rules: an app one, an app-and-title one, a non-main one, a disabled one.
- **Steps:** Match windows against them (`WindowRules.floats`).
- **Expected:** The app rule matches any window of the app's; a title pattern narrows it; a
  non-main rule matches only when the app has another window already (its first window is the
  main one); a disabled rule matches nothing.
- **Automate:** unit: `floats` on each case.

## FLOAT-02 A rule-matched new window floats where it opened
- **Type:** Feature
- **Area:** FLOAT
- **Commits:** unreleased
- **Setup:** Rows mode; windows in rows; a new window of a ruled app opening mid-screen.
- **Steps:** Let the window scan take it in.
- **Expected:** It floats: `floating` set, no row, its canvas spot the spot its app chose, the
  window you were in remembered as `returnTo`. No commit moves or parks it, no layout pass
  places it. An un-ruled window opening at the same time joins the inbox as before.
- **Automate:** unit: `arrive` on a fake scan, checking flags, spot, `returnTo` and the commit plan.

## FLOAT-03 Focusing a managed window sweeps every floater into the inbox
- **Type:** Feature
- **Area:** FLOAT
- **Commits:** unreleased
- **Setup:** Two windows floating.
- **Steps:** Focus one of them, then a managed window.
- **Expected:** Focusing a floater changes nothing — the rest stay up. Focusing a managed window
  drops every floater into the inbox in one go (packed on shelves right of the rows, at their
  own sizes).
- **Automate:** unit: `focusSettled(on:)` on a floater then a managed window.

## FLOAT-04 A floater's close gives the window you were in back its focus
- **Type:** Feature
- **Area:** FLOAT
- **Commits:** unreleased
- **Setup:** A floating window opened while you were in a managed one (`returnTo`).
- **Steps:** Close it while it has focus.
- **Expected:** The window you were in gets focus again. (If focus already went elsewhere — to
  another floater — nothing is pulled back.)
- **Automate:** unit: `remove` with the floater its app's focused window, checking the focus
  request.

## FLOAT-05 Turning Rows off frees the floaters where they are
- **Type:** Feature
- **Area:** FLOAT
- **Commits:** unreleased
- **Setup:** Rows mode with a window floating.
- **Steps:** Turn "Arrange in rows" off.
- **Expected:** The floater becomes an ordinary window where it floated — the free layout keeps
  it at its spot.
- **Automate:** unit: the `rowsMode` setter on a floating set.
