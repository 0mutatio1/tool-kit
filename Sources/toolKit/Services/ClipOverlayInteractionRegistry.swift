import AppKit
import Foundation

@MainActor
final class ClipOverlayInteractionRegistry {
    static let shared = ClipOverlayInteractionRegistry()

    private struct IgnoredTarget {
        weak var owner: AnyObject?
        var frame: CGRect
        var closeOnEscape: (() -> Void)?
    }

    private var ignoredTargetsByID: [ObjectIdentifier: IgnoredTarget] = [:]
    private var selectedTargetID: ObjectIdentifier?
    private var activeMouseTargetID: ObjectIdentifier?

    func setIgnoredFrame(_ frame: CGRect, for owner: AnyObject, closeOnEscape: (() -> Void)? = nil) {
        let id = ObjectIdentifier(owner)
        ignoredTargetsByID[id] = IgnoredTarget(
            owner: owner,
            frame: frame,
            closeOnEscape: closeOnEscape ?? ignoredTargetsByID[id]?.closeOnEscape
        )
    }

    func removeIgnoredFrame(for owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        ignoredTargetsByID.removeValue(forKey: id)
        if selectedTargetID == id {
            selectedTargetID = nil
        }
        if activeMouseTargetID == id {
            activeMouseTargetID = nil
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        pruneReleasedTargets()
        return ignoredTargetsByID.values.contains { $0.frame.contains(point) }
    }

    func forwardMouseEvent(_ event: NSEvent, at point: CGPoint) -> Bool {
        guard event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp else {
            return false
        }

        guard let target = target(for: event, at: point), let window = target.value.owner as? NSWindow else {
            return false
        }

        selectedTargetID = target.key
        if event.type == .leftMouseDown {
            activeMouseTargetID = target.key
        }
        window.orderFrontRegardless()
        guard let forwardedEvent = NSEvent.mouseEvent(
            with: event.type,
            location: CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY),
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) else {
            return false
        }

        window.sendEvent(forwardedEvent)
        if event.type == .leftMouseUp {
            activeMouseTargetID = nil
        }
        return true
    }

    func select(_ owner: AnyObject) {
        selectedTargetID = ObjectIdentifier(owner)
    }

    func clearSelection() {
        selectedTargetID = nil
    }

    func closeSelectedTarget() -> Bool {
        pruneReleasedTargets()
        guard
            let selectedTargetID,
            let closeOnEscape = ignoredTargetsByID[selectedTargetID]?.closeOnEscape
        else {
            return false
        }

        closeOnEscape()
        return true
    }

    private func target(for event: NSEvent, at point: CGPoint) -> (key: ObjectIdentifier, value: IgnoredTarget)? {
        pruneReleasedTargets()

        if event.type == .leftMouseDragged || event.type == .leftMouseUp,
           let activeMouseTargetID,
           let target = ignoredTargetsByID[activeMouseTargetID] {
            return (activeMouseTargetID, target)
        }

        return ignoredTargetsByID.first { $0.value.frame.contains(point) }
    }

    private func pruneReleasedTargets() {
        ignoredTargetsByID = ignoredTargetsByID.filter { $0.value.owner != nil }
    }
}
