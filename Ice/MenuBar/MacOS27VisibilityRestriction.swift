//
//  MacOS27VisibilityRestriction.swift
//  Ice
//

import Cocoa
import OSLog

/// Asks MenuBarAgent to leave some applications' items out of the menu bar.
///
/// A spacer conceals items by pushing them into the native overflow, and a
/// display without a notch then draws the overflow control. MenuBarAgent can
/// also restrict the menu bar to a list of applications: what is not on the
/// list is not laid out at all, on any display, so nothing overflows.
///
/// The restriction is a private MenuBarClientCore interface, made for
/// assessment mode. It needs no entitlement, and it ends when this process
/// does. It only knows applications by bundle identifier, and MenuBarAgent
/// gives one to applications in `/Applications` only: anything else, Ice
/// included, counts as an ad hoc binary and can't be on the list. Callers
/// must check that Ice's own button survives and call ``giveUp()`` if not.
@MainActor
final class MacOS27VisibilityRestriction {
    private let logger = Logger(category: "MacOS27VisibilityRestriction")

    /// The active assertion, an `MBAssessmentModeAssertion`.
    private var assertion: NSObject?

    /// The bundle identifiers the active assertion leaves out.
    private(set) var hiddenBundleIdentifiers: Set<String>?

    /// The bundle identifiers the active assertion lets through.
    private var allowedBundleIdentifiers = Set<String>()

    /// Whether the restriction can't be used in this session: it turned out
    /// not to work, or Ice runs from where MenuBarAgent would hide it too.
    private(set) var isUnavailable = !Bundle.main.bundlePath.hasPrefix("/Applications/")

    var isActive: Bool { assertion != nil }

    private static let isFrameworkLoaded: Bool = {
        let path = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
        return dlopen(path, RTLD_NOW) != nil
    }()

    /// Leaves the given applications' items out of the menu bar.
    ///
    /// While a restriction is active, the applications it hides are only
    /// added to: their items are gone, so they can't be told from items
    /// that quit. Applications launched since are let through.
    func activate(hiding bundleIdentifiers: Set<String>) {
        guard !isUnavailable else { return }
        let hidden = (hiddenBundleIdentifiers ?? []).union(bundleIdentifiers)
        guard !hidden.isEmpty else {
            deactivate()
            return
        }
        let allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .subtracting(hidden)
        if assertion != nil, allowed == allowedBundleIdentifiers {
            return
        }
        guard let replacement = makeAssertion(allowing: allowed) else {
            logger.error("The menu bar visibility restriction is not available")
            isUnavailable = true
            deactivate()
            return
        }
        // The new assertion is in place before the old one ends, so the
        // hidden items don't come back in between.
        let previous = assertion
        assertion = replacement
        hiddenBundleIdentifiers = hidden
        allowedBundleIdentifiers = allowed
        logger.notice("Restricting the menu bar: hiding \(hidden.sorted().joined(separator: ", "), privacy: .public)")
        previous?.perform(NSSelectorFromString("invalidate"))
    }

    /// Lets every application's items back into the menu bar.
    func deactivate() {
        guard let assertion else { return }
        logger.notice("Ending the menu bar restriction")
        assertion.perform(NSSelectorFromString("invalidate"))
        self.assertion = nil
        hiddenBundleIdentifiers = nil
        allowedBundleIdentifiers = []
    }

    /// Ends the restriction and stops using it for this session.
    func giveUp(reason: String) {
        logger.error("Giving up on the menu bar restriction: \(reason, privacy: .public)")
        deactivate()
        isUnavailable = true
    }

    private func makeAssertion(allowing bundleIdentifiers: Set<String>) -> NSObject? {
        guard
            Self.isFrameworkLoaded,
            let configurationClass = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        else {
            return nil
        }
        let initializer = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
        let activate = NSSelectorFromString("activateWithConfiguration:completionHandler:")
        guard
            let initializerMethod = class_getInstanceMethod(configurationClass, initializer),
            let activateMethod = class_getInstanceMethod(assertionClass, activate),
            let allocated = (configurationClass as AnyObject).perform(NSSelectorFromString("alloc"))
        else {
            return nil
        }

        // Every system item stays: their identifiers are small integers.
        let systemItems = (0..<64).map { NSNumber(value: $0) } as NSArray
        typealias Initializer = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(method_getImplementation(initializerMethod), to: Initializer.self)
        // `init` consumes the allocated object and returns an owned one.
        guard let configuration = initialize(
            allocated.takeUnretainedValue(),
            initializer,
            systemItems,
            bundleIdentifiers.sorted() as NSArray
        )?.takeRetainedValue() else {
            return nil
        }

        let assertion = assertionClass.init()
        // The completion handler outlives the call, so it is passed as an
        // object: Swift would treat a closure argument here as non-escaping.
        typealias Activate = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        let activateAssertion = unsafeBitCast(method_getImplementation(activateMethod), to: Activate.self)
        let logger = logger
        let completion: @convention(block) (NSError?) -> Void = { error in
            if let error {
                logger.error("The menu bar restriction failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        activateAssertion(assertion, activate, configuration, completion as AnyObject)
        return assertion
    }
}
