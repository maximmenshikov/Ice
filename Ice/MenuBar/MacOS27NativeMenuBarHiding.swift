//
//  MacOS27NativeMenuBarHiding.swift
//  Ice
//

import Cocoa
import OSLog
@preconcurrency import AXSwift

/// Hides a contiguous section by resizing an Ice-owned blank status item.
/// macOS lays out and handles every other item, including overflow and clicks.
@MainActor
final class MacOS27NativeMenuBarHiding {
    private struct Spacer {
        let item: NSStatusItem
    }

    private let logger = Logger(category: "MacOS27NativeMenuBarHiding")


    private var spacers = [MenuBarSection.Name: Spacer]()

    /// Second spacers, left of the first ones, that fill the room the first
    /// leave on displays wider than the most crowded one.
    private var extraSpacers = [MenuBarSection.Name: Spacer]()

    isolated deinit {
        removeAll()
    }

    /// A short description of a section's spacer, for logging.
    func debugDescription(for section: MenuBarSection.Name) -> String {
        guard let spacer = spacers[section] else { return "no spacer" }
        var description = "spacer visible=\(spacer.item.isVisible) length=\(spacer.item.length)"
        if let extra = extraSpacers[section], extra.item.isVisible {
            description += " extra=\(extra.item.length)"
        }
        return description
    }

    func isConcealing(_ section: MenuBarSection.Name) -> Bool {
        guard let spacer = spacers[section] else { return false }
        return spacer.item.isVisible && spacer.item.length > 1
    }

    func prepare(section: MenuBarSection.Name, anchorPosition: CGFloat) {
        guard spacers[section] == nil else { return }
        let name = "Ice.NativeBoundary.\(section.rawValue).v2"
        // Equal preferred positions have unstable ordering after a relaunch.
        // The spacer must sort strictly to the left of the visible Ice item.
        let key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(anchorPosition + 1, forKey: key)
        }
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = name
        item.button?.title = ""
        item.button?.image = nil
        item.button?.isEnabled = false
        item.button?.setAccessibilityIdentifier(name)
        spacers[section] = Spacer(item: item)
        withdraw(item)
    }

    /// AppKit reserves a real slot even for a one-point item. Publish the
    /// narrow boundary only while an explicit operation needs a drag handle.
    func prepareForHiding(anchorPosition: CGFloat) {
        prepare(section: .hidden, anchorPosition: anchorPosition)
        withdrawExtra(section: .hidden)
        if let spacer = spacers[.hidden] { showNarrow(spacer.item) }
    }

    func showForLayout(anchorPosition: CGFloat, alwaysHiddenAnchor: CGFloat?) {
        prepare(section: .hidden, anchorPosition: anchorPosition)
        if let alwaysHiddenAnchor {
            prepare(section: .alwaysHidden, anchorPosition: alwaysHiddenAnchor)
        }
        for section in extraSpacers.keys {
            withdrawExtra(section: section)
        }
        for (section, spacer) in spacers {
            if section == .hidden || alwaysHiddenAnchor != nil {
                showNarrow(spacer.item)
            } else {
                withdraw(spacer.item)
            }
        }
    }

    private func showNarrow(_ item: NSStatusItem) {
        if item.length != 1 { item.length = 1 }
        if item.button?.isEnabled == false { item.button?.isEnabled = true }
        if !item.isVisible { item.isVisible = true }
    }

    private func withdraw(_ item: NSStatusItem) {
        guard item.isVisible else { return }
        logger.notice("Withdrawing \(item.autosaveName ?? "spacer", privacy: .public) (length \(item.length))")
        // Hiding an NSStatusItem clears its saved position. Preserve only our
        // own position; the pre-hide check reconciles native user reordering.
        let key = "NSStatusItem Preferred Position \(item.autosaveName ?? "")"
        let position = UserDefaults.standard.object(forKey: key)
        item.isVisible = false
        if let position { UserDefaults.standard.set(position, forKey: key) }
        if item.button?.isEnabled == true { item.button?.isEnabled = false }
    }

    /// Sets whether a section's spacer conceals the items to its left.
    ///
    /// - Parameter controlFrame: The current frame of the item immediately to
    ///   the right of the spacer, in global display coordinates. When known,
    ///   the spacer is sized to the space actually available to its left.
    @available(macOS 27.0, *)
    func setHidden(
        _ hidden: Bool,
        section: MenuBarSection.Name,
        anchorPosition: CGFloat,
        screen: NSScreen,
        controlFrame: CGRect? = nil
    ) {
        guard hidden else {
            withdrawExtra(section: section)
            guard let spacer = spacers[section] else { return }
            // Keep the boundary published instead of withdrawing it. Removing
            // it means the next hide has to insert it again, and AppKit
            // reserves its slot the moment it appears: the whole bar shifts a
            // couple of points left, and only after the alignment check does
            // the spacer widen and the items actually hide. That two-stage
            // move is visible as a jump followed by the hide whenever the
            // check is not instant. A boundary that never leaves also stays in
            // Ice's own accessibility tree, so the fast path stops missing.
            // The cost is a permanent gap of a few points beside Ice's icon.
            showNarrow(spacer.item)
            return
        }

        prepare(section: section, anchorPosition: anchorPosition)
        guard let spacer = spacers[section] else { return }

        let length: CGFloat
        if
            let controlFrame,
            let fitted = MacOS27NativeBoundary.concealingLength(
                controlFrame: controlFrame,
                displays: Self.menuBarDisplays(fallback: screen)
            )
        {
            length = fitted
        } else if spacer.item.isVisible, spacer.item.length > 1 {
            // Without a fresh frame, keep the length that is already concealing.
            length = spacer.item.length
        } else {
            // An item wider than the entire native status region is discarded on
            // macOS 27. A width within that region makes its left neighbors overflow.
            // The region is shared by every display, so the narrowest one decides.
            let regionWidth = Self.menuBarScreens(fallback: screen).map { screen in
                screen.auxiliaryTopRightArea?.width
                    ?? (screen.frame.width - (screen.getApplicationMenuFrame()?.width ?? 300))
            }.min() ?? 300
            length = max(32, regionWidth - 32)
        }

        if spacer.item.button?.isEnabled == true { spacer.item.button?.isEnabled = false }
        if spacer.item.length != length {
            logger.notice("Sizing \(section.rawValue, privacy: .public) spacer to \(length) (control frame: \(controlFrame?.debugDescription ?? "unknown", privacy: .public))")
            spacer.item.length = length
        }
        if !spacer.item.isVisible { spacer.item.isVisible = true }
        updateExtra(section: section, screen: screen, controlFrame: controlFrame)
    }

    /// Whether a second spacer may be used. With the visibility restriction
    /// nothing is left for it to conceal, and it would overflow itself,
    /// which draws the overflow control.
    var allowsExtraSpacer = false {
        didSet {
            if !allowsExtraSpacer {
                withdrawExtra(section: .hidden)
            }
        }
    }

    /// Shows the second spacer of a concealing section at its last length, or
    /// at an estimate when it has none. ``setExtraLength(_:section:)`` then
    /// corrects it from what MenuBarAgent actually draws.
    ///
    /// - Parameter controlFrame: The current frame of the item immediately to
    ///   the right of the first spacer. Without it, the second keeps its state.
    @available(macOS 27.0, *)
    func updateExtra(section: MenuBarSection.Name, screen: NSScreen, controlFrame: CGRect?) {
        guard allowsExtraSpacer else {
            withdrawExtra(section: section)
            return
        }
        guard let spacer = spacers[section], spacer.item.isVisible, spacer.item.length > 1 else {
            withdrawExtra(section: section)
            return
        }
        if let extra = extraSpacers[section], extra.item.isVisible || extra.item.length > 1 {
            setExtraLength(min(extra.item.length, spacer.item.length), section: section)
            return
        }
        guard let controlFrame else { return }
        // The frontmost application's menus are drawn on the active display
        // only. Other displays draw their own Space's application, so this is
        // only a starting point.
        let length = Self.frontmostApplicationMenuWidth().flatMap { menuWidth in
            MacOS27NativeBoundary.additionalConcealingLength(
                controlFrame: controlFrame,
                displays: Self.menuBarDisplays(fallback: screen),
                firstLength: spacer.item.length,
                applicationMenuWidth: menuWidth
            )
        }
        setExtraLength(length, section: section)
    }

    /// The length of a section's second spacer, or `nil` while it is withdrawn.
    func extraLength(for section: MenuBarSection.Name) -> CGFloat? {
        guard let extra = extraSpacers[section], extra.item.isVisible else { return nil }
        return extra.item.length
    }

    /// Shows a concealing section's second spacer at a length, or withdraws it.
    func setExtraLength(_ length: CGFloat?, section: MenuBarSection.Name) {
        let length = allowsExtraSpacer ? length : nil
        guard
            let spacer = spacers[section],
            spacer.item.isVisible,
            spacer.item.length > 1,
            let length,
            length >= 1
        else {
            withdrawExtra(section: section)
            return
        }
        let extra = prepareExtra(section: section, after: spacer)
        if extra.item.length != length {
            logger.notice("Sizing \(section.rawValue, privacy: .public) extra spacer to \(length)")
            extra.item.length = length
        }
        if !extra.item.isVisible {
            // Sort strictly between the first spacer and the items it conceals.
            let firstKey = "NSStatusItem Preferred Position \(spacer.item.autosaveName ?? "")"
            if let first = UserDefaults.standard.object(forKey: firstKey) as? Double {
                UserDefaults.standard.set(
                    first + 0.5,
                    forKey: "NSStatusItem Preferred Position \(extra.item.autosaveName ?? "")"
                )
            }
            extra.item.isVisible = true
        }
    }

    private func prepareExtra(section: MenuBarSection.Name, after spacer: Spacer) -> Spacer {
        if let extra = extraSpacers[section] { return extra }
        let name = "Ice.NativeBoundary.\(section.rawValue).extra.v2"
        let key = "NSStatusItem Preferred Position \(name)"
        let firstKey = "NSStatusItem Preferred Position \(spacer.item.autosaveName ?? "")"
        let position = (UserDefaults.standard.object(forKey: firstKey) as? Double).map { $0 + 0.5 }
        if let position { UserDefaults.standard.set(position, forKey: key) }
        // Created hidden: an item AppKit shows at once is laid out before it
        // has its length, and the whole bar would reflow twice.
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = name
        // Hiding an item clears its saved position.
        item.isVisible = false
        if let position { UserDefaults.standard.set(position, forKey: key) }
        item.button?.title = ""
        item.button?.image = nil
        item.button?.isEnabled = false
        item.button?.setAccessibilityIdentifier(name)
        let extra = Spacer(item: item)
        extraSpacers[section] = extra
        return extra
    }

    private func withdrawExtra(section: MenuBarSection.Name) {
        guard let extra = extraSpacers[section], extra.item.isVisible else { return }
        logger.notice("Withdrawing \(section.rawValue, privacy: .public) extra spacer")
        extra.item.isVisible = false
    }

    /// The width of the frontmost application's menus, measured from the left
    /// edge of a display.
    ///
    /// Accessibility reports the menus on the display with the active menu
    /// bar only, but every display draws the same menus from its left edge.
    static func frontmostApplicationMenuWidth() -> CGFloat? {
        guard
            // Not the frontmost application: Ice itself can be frontmost
            // without drawing any menus.
            let app = NSWorkspace.shared.menuBarOwningApplication,
            let application = AXHelpers.application(for: app),
            let menuBar: UIElement = AXHelpers.performOnMain({ try? application.attribute(.menuBar) })
        else {
            return nil
        }
        let frame = AXHelpers.children(for: menuBar).reduce(into: CGRect.null) { result, child in
            if AXHelpers.isEnabled(child), let childFrame = AXHelpers.frame(for: child) {
                result = result.union(childFrame)
            }
        }
        guard !frame.isNull, frame.width > 0 else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let bounds = NSScreen.screens.lazy
            .map { CGDisplayBounds($0.displayID) }
            .first { $0.contains(center) } ?? CGDisplayBounds(CGMainDisplayID())
        guard frame.maxX > bounds.minX else { return nil }
        return frame.maxX - bounds.minX
    }

    /// The current length of a section's spacer, if it has one.
    func spacerLength(for section: MenuBarSection.Name) -> CGFloat? {
        spacers[section]?.item.length
    }

    /// Sets a section's spacer to an explicit length.
    ///
    /// The photo pass uses this to give back the menu bar space a few items at
    /// a time, so macOS draws them long enough to be photographed.
    @available(macOS 27.0, *)
    func setConcealingLength(_ length: CGFloat, section: MenuBarSection.Name, anchorPosition: CGFloat) {
        prepare(section: section, anchorPosition: anchorPosition)
        guard let spacer = spacers[section] else { return }
        withdrawExtra(section: section)
        let clamped = max(1, length)
        if spacer.item.length != clamped {
            spacer.item.length = clamped
        }
        if !spacer.item.isVisible {
            spacer.item.isVisible = true
        }
    }

    /// The screens that draw a menu bar, and so a copy of the status items.
    ///
    /// With "Displays have separate Spaces" turned off, only the primary
    /// display has a menu bar.
    static func menuBarScreens(fallback: NSScreen) -> [NSScreen] {
        guard NSScreen.screensHaveSeparateSpaces else {
            return [NSScreen.screens.first ?? fallback]
        }
        let screens = NSScreen.screens
        return screens.isEmpty ? [fallback] : screens
    }

    /// The menu bar geometry of every screen that draws the status items.
    static func menuBarDisplays(fallback: NSScreen) -> [MacOS27NativeBoundary.Display] {
        menuBarScreens(fallback: fallback).map { screen in
            let notch: ClosedRange<CGFloat>? = if
                let left = screen.auxiliaryTopLeftArea,
                let right = screen.auxiliaryTopRightArea,
                left.maxX <= right.minX
            {
                left.maxX ... right.minX
            } else {
                nil
            }
            return MacOS27NativeBoundary.Display(
                bounds: CGDisplayBounds(screen.displayID),
                notch: notch,
                applicationMenuMaxX: screen.getApplicationMenuFrame()?.maxX
            )
        }
    }

    func removeAll() {
        for spacer in Array(spacers.values) + Array(extraSpacers.values) {
            spacer.item.isVisible = false
            NSStatusBar.system.removeStatusItem(spacer.item)
        }
        spacers.removeAll()
        extraSpacers.removeAll()
    }
}
