# Trackpad gestures

Four-finger swipes on the trackpad, read straight from MultitouchSupport: four fingers up open
or leave the canvas (as ⌥`), four fingers down go to the window under the mouse. Nothing is
swallowed, so macOS's own swipes for the same finger count fire too — turn them off in
Trackpad settings. The panel's "Trackpad gestures" switch turns the whole thing off; it's on
by default.

## SWIPE-01 Four fingers swipe, once per touch-down
- **Type:** Feature
- **Area:** Gestures
- **Steps:** With macOS's own four-finger swipes off, swipe four fingers up or down.
- **Expected:** Four fingers up zoom out to the canvas or back; four fingers down go to the
  window under the mouse. A swipe fires once, fingers landing a beat apart make one gesture,
  and fingers left on the pad after a swipe don't fire again.
- **Automate:** unit: `SwipeRecognizer.frame` over canned frames — a swipe's direction right,
  once per touch-down, re-armed after all fingers lift.

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

## SWIPE-05 A palm plus two fingers isn't a gesture
- **Type:** Bug
- **Area:** Gestures
- **Steps:** Rest the heel of your hand on the trackpad's near edge (as when typing) and
  scroll with two fingers.
- **Expected:** An ordinary two-finger scroll: the raw MultitouchSupport stream counts the
  palm heel as a third contact — macOS's own palm suppression sits in a layer above it —
  so contacts are filtered before the finger count is taken. A contact bigger than the
  size cap is a palm wherever it sits; one *born* inside a band in from the left, right,
  or near edge stays a palm for its whole life, while a finger born mid-pad that drifts
  to the rim still counts (the strategy Trident validated on-device; sizes in zTotal
  units, the band in mm off `MTDeviceGetSensorSurfaceDimensions`).
- **Automate:** unit: `PalmFilter` rejects oversized and rim-born contacts, keeps an
  inland-born finger that drifts to the rim, and forgets a lifted path so its index can
  be reused; `frame` counts a palm plus two fingers as two.
