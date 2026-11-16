// Compile together with Ice/MenuBar/MenuBarItems/MacOS27NativeBoundary.swift.
import CoreGraphics

@main
enum NativeMenuBarBoundaryTests {
    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            assertions += 1
            print("PASS: \(description)")
        }
        func frame(_ x: CGFloat, y: CGFloat = 4, width: CGFloat = 28) -> CGRect {
            CGRect(x: x, y: y, width: width, height: 24)
        }
        let ice = frame(300)
        check(MacOS27NativeBoundary.side(of: frame(270), relativeTo: ice) == .left,
              "a hidden item starts on the left of Ice")
        check(MacOS27NativeBoundary.side(of: frame(334), relativeTo: ice) == .right,
              "dragging that item to the right makes it visible")
        check(MacOS27NativeBoundary.side(of: frame(334), relativeTo: ice) == .right,
              "a visible item starts on the right of Ice")
        check(MacOS27NativeBoundary.side(of: frame(270), relativeTo: ice) == .left,
              "dragging that item left makes it hidden, including an empty Hidden section")
        check(MacOS27NativeBoundary.side(of: frame(327), relativeTo: ice) == .right,
              "overlapping AX hit areas do not change native left-to-right order")
        check(MacOS27NativeBoundary.side(of: frame(7, y: 1121), relativeTo: ice) == nil,
              "off-bar overflow frames cannot overwrite a saved section")
        check(MacOS27NativeBoundary.side(of: ice, relativeTo: ice) == nil,
              "coincident transient frames are not treated as a completed drag")
        check(MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "boundary", "ice", "visible"]),
              "an aligned boundary needs no synthetic move")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "boundary", "dropped", "ice", "visible"]),
              "a drop between the blank and Ice requires moving only the blank")
        check(MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "dropped", "boundary", "ice", "visible"]),
              "after correction every item left of Ice is also left of the hiding boundary")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "ice", "boundary", "visible"]),
              "a boundary on the wrong side of Ice cannot be accepted")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "ice", "visible"]),
              "a missing boundary cannot be accepted")
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        check(MacOS27NativeBoundary.canDrag(from: frame(270), to: ice, on: display),
              "two real menu bar endpoints can be dragged")
        check(!MacOS27NativeBoundary.canDrag(from: frame(7, y: 1121), to: ice, on: display),
              "a concealed off-display item cannot receive a synthetic drag")
        check(!MacOS27NativeBoundary.canDrag(from: frame(7, y: 1121), to: frame(37, y: 1121), on: display),
              "two retained overflow frames cannot be mistaken for a native row")
        check(!MacOS27NativeBoundary.canDrag(from: frame(270), to: ice, on: CGRect(x: -1728, y: 0, width: 1728, height: 1117)),
              "drag endpoints must belong to the same display")
        let handle = frame(291, width: 3)
        check(MacOS27NativeBoundary.canCheckImmediateHide(boundary: handle, control: ice, display: display),
              "a narrow native pair can enter live hit-test validation")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(280, width: 3), control: ice, display: display),
              "a wider gap requires complete ordering verification")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(303, width: 3), control: ice, display: display),
              "a boundary to the right cannot use immediate hiding")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(298, width: 3), control: ice, display: display),
              "overlapping transitional frames cannot use immediate hiding")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(280, width: 14), control: ice, display: display),
              "an already widened item cannot masquerade as a narrow handle")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(291, y: 6, width: 3), control: ice, display: display),
              "vertically unsettled frames require complete verification")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(291, y: 1121, width: 3), control: ice, display: display),
              "retained overflow geometry cannot enter the quick path")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: CGRect(x: CGFloat.nan, y: 4, width: 3, height: 24), control: ice, display: display),
              "non-finite geometry cannot enter the quick path")

        // Measured on macOS 27.0: a notched built-in display, and a 1920-point
        // display to its left that currently has the active menu bar.
        let builtIn = MacOS27NativeBoundary.Display(
            bounds: CGRect(x: 0, y: 0, width: 2056, height: 1329),
            notch: 918 ... 1138
        )
        let external = MacOS27NativeBoundary.Display(bounds: CGRect(x: -1920, y: 136, width: 1920, height: 1080))
        let iceOnExternal = CGRect(x: -328, y: 139.5, width: 28, height: 24)
        let iceOnBuiltIn = CGRect(x: 1728, y: 7.5, width: 28, height: 24)
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnExternal, displays: [external]) == 1560,
              "a single display fills the space left of Ice")
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnBuiltIn, displays: [builtIn]) == 886,
              "a notched display fills the larger side of the notch")
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnExternal, displays: [builtIn, external]) == 886,
              "the spacer must fit the most crowded display, not the one reporting Ice")
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnBuiltIn, displays: [builtIn, external]) == 886,
              "the result does not depend on which display has the active menu bar")
        let externalWithMainMenus = MacOS27NativeBoundary.Display(
            bounds: external.bounds,
            applicationMenuMaxX: 572
        )
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnExternal, displays: [externalWithMainMenus]) == 1560,
              "application menus reported on another display are ignored")
        let builtInWithMenus = MacOS27NativeBoundary.Display(bounds: builtIn.bounds, notch: builtIn.notch, applicationMenuMaxX: 572)
        check(MacOS27NativeBoundary.concealingLength(controlFrame: iceOnBuiltIn, displays: [builtInWithMenus, external]) == 558,
              "long application menus move the spacer right of the notch on every display")
        check(MacOS27NativeBoundary.concealingLength(controlFrame: CGRect(x: 5000, y: 4, width: 28, height: 24), displays: [builtIn]) == nil,
              "a frame on no display gives no length")
        // Measured on macOS 27.0: with Ice 365 points from the right edge and
        // iTerm2's menus ending 551 points in, an 886-point spacer leaves room
        // for an item and the overflow indicator on the external display.
        let iceAt365 = CGRect(x: -365, y: 139.5, width: 28, height: 24)
        check(MacOS27NativeBoundary.additionalConcealingLength(
            controlFrame: iceAt365, displays: [builtIn, external], firstLength: 886, applicationMenuWidth: 551
        ) == 86, "a second spacer fills what the first leaves on the external display")
        check(MacOS27NativeBoundary.additionalConcealingLength(
            controlFrame: iceAt365, displays: [builtIn], firstLength: 886, applicationMenuWidth: 551
        ) == nil, "a lone notched display needs no second spacer")
        check(MacOS27NativeBoundary.additionalConcealingLength(
            controlFrame: iceAt365, displays: [builtIn, external], firstLength: 886, applicationMenuWidth: 0
        ) == 637, "a short menu leaves the most room to fill")
        check(MacOS27NativeBoundary.additionalConcealingLength(
            controlFrame: iceAt365, displays: [builtIn, external], firstLength: 300, applicationMenuWidth: 0
        ) == 300, "the second spacer is never wider than the first")
        check(MacOS27NativeBoundary.additionalConcealingLength(
            controlFrame: iceAt365, displays: [builtIn, external], firstLength: 886, applicationMenuWidth: 640
        ) == nil, "long menus leave nothing for a second spacer")
        // MenuBarAgent containers measured on the external display, macOS 27.0.
        func box(_ x: CGFloat, _ width: CGFloat) -> CGRect { CGRect(x: x, y: 136, width: width, height: 30) }
        let iceBox = box(-364, 26)
        let firstBox = box(-1266, 902)
        let overflowBox = { (x: CGFloat) in CGRect(x: x, y: 137, width: 17.5, height: 27) }
        check(MacOS27NativeBoundary.extraFit(
            ownFrames: [box(-1535, 261), firstBox, iceBox], overflowFrames: [overflowBox(-1291)],
            firstLength: 886, extraLength: 245
        ) == .tooLong, "a second spacer parked beside the overflow control did not fit")
        check(MacOS27NativeBoundary.extraFit(
            ownFrames: [box(-1357, 91), firstBox, iceBox], overflowFrames: [overflowBox(-1501)],
            firstLength: 886, extraLength: 75
        ) == .tooShort(room: 122), "items between the overflow control and the spacers ask for more")
        check(MacOS27NativeBoundary.extraFit(
            ownFrames: [box(-1492, 226), firstBox, iceBox], overflowFrames: [overflowBox(-1517)],
            firstLength: 886, extraLength: 210
        ) == .concealing, "an overflow control alone beside the spacers is as good as it gets")
        check(MacOS27NativeBoundary.extraFit(
            ownFrames: [firstBox, iceBox], overflowFrames: [overflowBox(-1366)],
            firstLength: 886, extraLength: 0
        ) == .tooShort(room: 78), "without a second spacer the room is measured from the first")
        check(MacOS27NativeBoundary.extraFit(
            ownFrames: [box(16, 902), box(1692, 26)], overflowFrames: [],
            firstLength: 886, extraLength: 75
        ) == nil, "a display that moves the first spacer away from Ice is not judged")
        print("\(assertions) native-boundary assertions passed")
    }
}
