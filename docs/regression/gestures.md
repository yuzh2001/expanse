# Trackpad gestures

Three- and four-finger swipes on the trackpad, read straight from MultitouchSupport: three
fingers hop to the next window that way (as ⌃ + arrow), four fingers up open or leave the
canvas (as ⌥`). Nothing is swallowed, so macOS's own swipes for the same finger counts fire
too — turn them off in Trackpad settings. The panel's "Trackpad gestures" switch turns the
whole thing off; it's on by default.

## SWIPE-01 A swipe fires once per touch-down
- **Type:** Feature
- **Area:** Gestures
- **Steps:** With macOS's own three- and four-finger swipes off, swipe three fingers sideways,
  or four fingers up.
- **Expected:** A three-finger swipe hops to the next window in that direction, like ⌃ +
  arrow; four fingers up zooms out to the canvas, or back from it. One swipe fires once, and
  fingers landing a beat apart still make one gesture of the final count.
- **Automate:** unit: `SwipeRecognizer.frame` over canned frames — one event, direction and
  finger count right, re-armed after all fingers lift.

## SWIPE-02 Other touches never fire
- **Type:** Feature
- **Area:** Gestures
- **Steps:** Scroll with two fingers, rest a palm while typing, use Three-Finger Drag.
- **Expected:** Nothing: only three or four fingers count, the movement has to be decisive
  (far enough, one axis clearly dominant), and a finger lifting early aborts the gesture.
- **Automate:** unit: two- and five-finger frames, drifts and diagonals, early lifts.

## SWIPE-03 The panel switch turns gestures off
- **Type:** Feature
- **Area:** UI
- **Steps:** Turn off "Trackpad gestures" in the menu bar panel, then swipe.
- **Expected:** The swipe does nothing. Frames are dropped whole (a gesture under way is
  forgotten, so turning it back on mid-touch can't fire).
- **Automate:** unit: `Action.gestures` leaves the panel open; the recognizer gate.

## SWIPE-04 A swipe's fingers finishing their arc aren't scrolls
- **Type:** Bug
- **Area:** Gestures
- **Steps:** Four-finger swipe up to open the canvas, and without lifting, keep the fingers
  moving a moment before lifting them.
- **Expected:** Nothing more happens: the same touch's continued movement isn't a scroll —
  some fingers lifting leaves the rest still not scrolling — so the canvas the swipe just
  opened doesn't pan, a fast flick's lift and momentum tail don't either, and at 100% a
  desktop scroll can't open it before the swipe's own toggle.
- **Automate:** unit: `suppressesScrolls` stays on while the swipe's touch lasts, however few
  fingers remain, `firedWithin` holds through the gap to the swipe's delivery, and both are
  off again for a fresh two-finger scroll.
