//
//  MacOS27NativeBoundary.swift
//  Ice
//

import CoreGraphics

/// Defers Ice-owned visibility mutations while a native drag is holding its
/// source/target scenes. Only the need to resync is retained, never old intent.
struct MacOS27NativeDragVisibilityState {
    private var dragDepth = 0
    private var hasPendingUpdate = false

    mutating func beginDrag() {
        dragDepth += 1
    }

    mutating func shouldApplyVisibilityUpdate() -> Bool {
        guard dragDepth > 0 else { return true }
        hasPendingUpdate = true
        return false
    }

    /// Returns whether the caller must reread current visibility/Layout state.
    mutating func endDrag() -> Bool {
        guard dragDepth > 0 else { return false }
        dragDepth -= 1
        guard dragDepth == 0 else { return false }
        defer { hasPendingUpdate = false }
        return hasPendingUpdate
    }
}

/// The visible Ice button, not a saved assignment or an invisible slot, is the
/// user-facing boundary. Keep these decisions independent of event handling.
enum MacOS27NativeBoundary {
    enum Side {
        case left, right
    }

    /// Conservative quick-path geometry for the native narrow handle. This
    /// is only for resizing our own item, never for targeting mouse input.
    /// Callers reject ambiguous owner variants and recheck frames. Wider gaps,
    /// custom spacing and unsettled frames use the full ordering check.
    static func canCheckImmediateHide(boundary: CGRect, control: CGRect, display: CGRect) -> Bool {
        let geometry = [
            boundary.minX, boundary.minY, boundary.width, boundary.height,
            control.minX, control.minY, control.width, control.height,
        ]
        guard
            geometry.allSatisfy(\.isFinite),
            canDrag(from: boundary, to: control, on: display),
            boundary.width <= 3,
            abs(boundary.midY - control.midY) < 0.5
        else {
            return false
        }
        let gap = control.minX - boundary.maxX
        return gap >= 0 && gap <= 6
    }

    static func side(of frame: CGRect, relativeTo control: CGRect) -> Side? {
        guard
            frame.width > 0,
            frame.height > 0,
            control.width > 0,
            abs(frame.midY - control.midY) < min(frame.height, control.height) / 2,
            frame.minX != control.minX
        else {
            return nil
        }
        // Hosted hit areas may overlap at their edges after a valid drop.
        // Left-to-right order is determined by origins, not touching edges.
        return frame.minX < control.minX ? .left : .right
    }

    /// Overflow AX elements may retain frames below the display. Never send
    /// a native drag to those coordinates or across unrelated display rows.
    static func canDrag(from source: CGRect, to target: CGRect, on display: CGRect) -> Bool {
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 40)
        return side(of: source, relativeTo: target) != nil &&
            strip.contains(source) && strip.contains(target)
    }

    /// The geometry of one display's menu bar, in global display coordinates.
    struct Display: Equatable {
        /// The display's bounds, as `CGDisplayBounds` reports them.
        var bounds: CGRect
        /// The horizontal extent of the notch, if the display has one.
        var notch: ClosedRange<CGFloat>?
        /// The right edge of the application menus on this display, if known.
        var applicationMenuMaxX: CGFloat?

        init(bounds: CGRect, notch: ClosedRange<CGFloat>? = nil, applicationMenuMaxX: CGFloat? = nil) {
            self.bounds = bounds
            self.notch = notch
            self.applicationMenuMaxX = applicationMenuMaxX
        }
    }

    /// Returns a spacer length that fills the space available to the left of
    /// the item at `controlMinX` on one display, so every item to the
    /// spacer's left overflows.
    ///
    /// On macOS 27, a status item that doesn't fit is discarded, and items
    /// that don't fit right of the notch move to its left. A spacer beside an
    /// item right of the notch must therefore be wider than the remaining gap
    /// there, so that it moves left of the notch and fills that side instead.
    static func concealingLength(controlMinX: CGFloat, on display: Display, margin: CGFloat = 32) -> CGFloat {
        // The default margin leaves room for the native overflow indicator.
        let minimumLength: CGFloat = 32
        // Accessibility reports the application menus of the main display
        // only. A frame that lies outside this display says nothing about it.
        let menusMaxX = display.applicationMenuMaxX
            .flatMap { (display.bounds.minX ... display.bounds.maxX).contains($0) ? $0 : nil }
            ?? display.bounds.minX

        guard let notch = display.notch else {
            return max(minimumLength, controlMinX - menusMaxX - margin)
        }

        let notchMinX = notch.lowerBound
        let notchMaxX = notch.upperBound
        guard controlMinX >= notchMaxX else {
            return max(minimumLength, min(controlMinX, notchMinX) - menusMaxX - margin)
        }

        let rightGap = controlMinX - notchMaxX
        let leftSegment = notchMinX - menusMaxX - margin
        if leftSegment > rightGap {
            return leftSegment
        }
        // The left side is too small to hold a spacer wider than the right
        // gap. Fill the right gap; items can still show left of the notch.
        return max(minimumLength, rightGap - margin)
    }

    /// Returns a spacer length that conceals the items left of Ice's button on
    /// every display that has a menu bar.
    ///
    /// MenuBarAgent lays out a single status bar and draws it on every
    /// display's menu bar, right-aligned: each item keeps the same distance
    /// from the right edge everywhere, and an item overflows or is discarded
    /// on every display at once. Accessibility reports Ice's button only on
    /// one display, so its position on the others is derived from that
    /// distance. The spacer has one length for all displays, and a length that
    /// does not fit the most crowded one is discarded everywhere, so the
    /// smallest of the per-display lengths is the one that works.
    ///
    /// - Parameters:
    ///   - controlFrame: The frame of the item immediately to the right of the
    ///     spacer, in global display coordinates.
    ///   - displays: The displays that draw a menu bar.
    static func concealingLength(controlFrame: CGRect, displays: [Display]) -> CGFloat? {
        let center = CGPoint(x: controlFrame.midX, y: controlFrame.midY)
        guard
            let source = displays.first(where: { $0.bounds.contains(center) })
                ?? displays.first(where: { (($0.bounds.minX)..<($0.bounds.maxX)).contains(center.x) })
        else {
            return nil
        }
        let distanceFromRight = source.bounds.maxX - controlFrame.minX
        return displays
            .map { concealingLength(controlMinX: $0.bounds.maxX - distanceFromRight, on: $0) }
            .min()
    }

    /// Returns the length of a second spacer, placed left of the first, that
    /// conceals what the first leaves visible on roomier displays.
    ///
    /// Each display decides on its own whether a spacer fits. A first spacer
    /// short enough for a notched display leaves room on a wide external one,
    /// where items left of it stay visible. A second spacer fills that room.
    /// Where it does not fit, it only overflows with the items left of it.
    ///
    /// - Parameters:
    ///   - controlFrame: The frame of the item right of the first spacer.
    ///   - displays: The displays that draw a menu bar.
    ///   - firstLength: The length of the first spacer.
    ///   - applicationMenuWidth: The width of the frontmost application's
    ///     menus, measured from the left edge of a display. Every display
    ///     draws the same menus.
    static func additionalConcealingLength(
        controlFrame: CGRect,
        displays: [Display],
        firstLength: CGFloat,
        applicationMenuWidth: CGFloat,
        margin: CGFloat = 32
    ) -> CGFloat? {
        let center = CGPoint(x: controlFrame.midX, y: controlFrame.midY)
        guard
            firstLength > 0,
            applicationMenuWidth >= 0,
            let source = displays.first(where: { $0.bounds.contains(center) })
                ?? displays.first(where: { (($0.bounds.minX)..<($0.bounds.maxX)).contains(center.x) })
        else {
            return nil
        }
        let distanceFromRight = source.bounds.maxX - controlFrame.minX
        let needed = displays.map { display in
            var display = display
            display.applicationMenuMaxX = display.bounds.minX + applicationMenuWidth
            return concealingLength(controlMinX: display.bounds.maxX - distanceFromRight, on: display, margin: margin)
        }.max() ?? 0
        let extra = needed - firstLength
        // A length the first spacer fits on every display stays within the
        // per-item limit that would get a wider spacer discarded.
        return extra >= 8 ? min(extra, firstLength) : nil
    }

    /// How a second spacer fits on one display, judged from the containers
    /// MenuBarAgent drew there.
    enum ExtraFit: Equatable {
        /// Nothing left of the spacers is drawn but, at most, the overflow
        /// control.
        case concealing
        /// Items are drawn left of the spacers, in about this much room.
        case tooShort(room: CGFloat)
        /// The second spacer did not fit and went to the overflow itself.
        case tooLong
    }

    /// Judges the second spacer on one display.
    ///
    /// MenuBarAgent draws each item in a container 16 points wider than the
    /// item. An item that does not fit keeps a container parked beside the
    /// overflow control instead of next to its right neighbor.
    ///
    /// A display without a notch keeps room for the overflow control while
    /// any item overflows: it is drawn however long the spacers are. Only
    /// a notched display, which drops what does not fit left of the notch,
    /// draws none. So only room beyond the control's own counts.
    ///
    /// - Parameters:
    ///   - ownFrames: The containers of Ice's items on the display.
    ///   - overflowFrames: The overflow controls on the display.
    ///   - firstLength: The length of the first spacer.
    ///   - extraLength: The length of the second spacer, or 0 without one.
    /// - Returns: `nil` when the first spacer is not beside Ice's button on
    ///   this display, as on a notched display that moves it left of the notch.
    static func extraFit(
        ownFrames: [CGRect],
        overflowFrames: [CGRect],
        firstLength: CGFloat,
        extraLength: CGFloat
    ) -> ExtraFit? {
        let padding: CGFloat = 16
        let tolerance: CGFloat = 2.5
        // The overflow control's container, about 25 points, plus slack.
        let overflowRoom: CGFloat = 30
        guard
            let first = ownFrames
                .filter({ abs($0.width - (firstLength + padding)) <= tolerance })
                .max(by: { $0.minX < $1.minX }),
            ownFrames.contains(where: { $0 != first && abs($0.minX - first.maxX) <= tolerance })
        else {
            return nil
        }
        var leftEdge = first.minX
        if extraLength >= 1 {
            let extra = ownFrames.first { frame in
                frame != first &&
                    abs(frame.width - (extraLength + padding)) <= tolerance &&
                    abs(frame.maxX - first.minX) <= tolerance
            }
            guard let extra else { return .tooLong }
            leftEdge = extra.minX
        }
        guard
            let overflow = overflowFrames
                .filter({ $0.maxX <= leftEdge + tolerance })
                .min(by: { $0.minX < $1.minX }),
            leftEdge - overflow.minX > overflowRoom
        else {
            return .concealing
        }
        return .tooShort(room: leftEdge - overflow.minX - overflowRoom + 8)
    }

    static func isImmediatelyBefore<Item: Equatable>(
        _ boundary: Item, _ control: Item, in order: [Item]
    ) -> Bool {
        guard
            let boundaryIndex = order.firstIndex(of: boundary),
            let controlIndex = order.firstIndex(of: control)
        else {
            return false
        }
        return boundaryIndex + 1 == controlIndex
    }
}
