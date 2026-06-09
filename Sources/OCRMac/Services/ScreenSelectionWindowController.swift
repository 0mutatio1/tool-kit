import AppKit
import Foundation

@MainActor
final class ScreenSelectionWindowController: NSWindowController {
    private let screen: NSScreen
    private let selectionView = ScreenSelectionView()
    private weak var session: ScreenSelectionSession?

    fileprivate init(screen: NSScreen, session: ScreenSelectionSession) {
        self.screen = screen
        self.session = session

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false

        super.init(window: window)

        selectionView.screenFrame = screen.frame
        selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]

        window.contentView = selectionView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func capture(preferredScreen: NSScreen? = nil) async throws -> ScreenCaptureService.SelectionResult {
        try await ScreenSelectionSession.capture(preferredScreen: preferredScreen)
    }

    func present() {
        showWindow(nil)
        window?.setFrame(screen.frame, display: true)
        window?.orderFrontRegardless()
    }

    func makeActive() {
        window?.makeKeyAndOrderFront(nil)
    }

    func updateSelection(globalRect: CGRect?) {
        selectionView.selectionRect = globalRect
    }

    func closeWindow() {
        window?.orderOut(nil)
    }
}

@MainActor
fileprivate final class ScreenSelectionSession {
    private let continuation: CheckedContinuation<ScreenCaptureService.SelectionResult, Error>
    private let preferredScreen: NSScreen?
    private var controllers: [ScreenSelectionWindowController] = []
    private var localMonitor: Any?
    private var isCompleted = false
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    private init(
        continuation: CheckedContinuation<ScreenCaptureService.SelectionResult, Error>,
        preferredScreen: NSScreen?
    ) {
        self.continuation = continuation
        self.preferredScreen = preferredScreen
    }

    private func configureControllers() {
        controllers = NSScreen.screens.map { ScreenSelectionWindowController(screen: $0, session: self) }
    }

    static func capture(preferredScreen: NSScreen? = nil) async throws -> ScreenCaptureService.SelectionResult {
        try await withCheckedThrowingContinuation { continuation in
            let session = ScreenSelectionSession(continuation: continuation, preferredScreen: preferredScreen)
            session.configureControllers()
            ScreenSelectionSessionStore.shared.hold(session)
            session.present()
        }
    }

    func present() {
        controllers.forEach { $0.present() }
        let activeScreen = preferredScreen ?? NSScreen.screenContainingMouse ?? NSScreen.main
        if let activeScreen {
            controllers.first(where: { $0.window?.screen == activeScreen })?.makeActive()
        } else {
            controllers.first?.makeActive()
        }

        installEventMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish(with result: sending ScreenCaptureService.SelectionResult) {
        guard !isCompleted else {
            return
        }

        isCompleted = true
        let continuation = self.continuation
        closeAllWindows()
        Self.resume(continuation: continuation, with: result)
    }

    func cancel() {
        guard !isCompleted else {
            return
        }

        isCompleted = true
        closeAllWindows()
        continuation.resume(throwing: CancellationError())
    }

    private func closeAllWindows() {
        removeEventMonitor()
        controllers.forEach { $0.closeWindow() }
        controllers.removeAll()
        ScreenSelectionSessionStore.shared.release(self)
    }

    nonisolated private static func resume(
        continuation: CheckedContinuation<ScreenCaptureService.SelectionResult, Error>,
        with result: ScreenCaptureService.SelectionResult
    ) {
        continuation.resume(returning: result)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func removeEventMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 {
                cancel()
            }

        case .leftMouseDown:
            let point = globalPoint(from: event)
            startPoint = point
            currentPoint = point
            activateController(for: point)
            updateSelectionViews()

        case .leftMouseDragged:
            guard startPoint != nil else {
                return
            }

            let point = globalPoint(from: event)
            currentPoint = point
            activateController(for: point)
            updateSelectionViews()

        case .leftMouseUp:
            guard startPoint != nil else {
                cancel()
                return
            }

            currentPoint = globalPoint(from: event)
            let rect = currentSelectionRect()
            if rect.width <= 0 || rect.height <= 0 {
                cancel()
            } else {
                finish(with: ScreenCaptureService.SelectionResult(rect: rect))
            }

        default:
            break
        }
    }

    private func activateController(for point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return
        }

        controllers.first(where: { $0.window?.screen == screen })?.makeActive()
    }

    private func updateSelectionViews() {
        let rect = currentSelectionRect()
        let selectionRect = (rect.width > 0 && rect.height > 0) ? rect : nil
        controllers.forEach { $0.updateSelection(globalRect: selectionRect) }
    }

    private func currentSelectionRect() -> CGRect {
        guard let startPoint, let currentPoint else {
            return .null
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        ).integral
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        if let window = event.window {
            let localPoint = event.locationInWindow
            return CGPoint(
                x: window.frame.origin.x + localPoint.x,
                y: window.frame.origin.y + localPoint.y
            )
        }

        return NSEvent.mouseLocation
    }
}

@MainActor
fileprivate final class ScreenSelectionSessionStore {
    static let shared = ScreenSelectionSessionStore()

    private var sessions: [ObjectIdentifier: ScreenSelectionSession] = [:]

    func hold(_ session: ScreenSelectionSession) {
        sessions[ObjectIdentifier(session)] = session
    }

    func release(_ session: ScreenSelectionSession) {
        sessions.removeValue(forKey: ObjectIdentifier(session))
    }
}

private final class ScreenSelectionView: NSView {
    var screenFrame: CGRect = .zero
    var selectionRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        dirtyRect.fill()

        if let selectionRect = localSelectionRect() {
            NSColor.clear.setFill()
            selectionRect.fill(using: .copy)

            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func localSelectionRect() -> CGRect? {
        guard let selectionRect else {
            return nil
        }

        let intersection = selectionRect.intersection(screenFrame).integral
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return nil
        }

        return CGRect(
            x: intersection.origin.x - screenFrame.origin.x,
            y: intersection.origin.y - screenFrame.origin.y,
            width: intersection.width,
            height: intersection.height
        ).integral
    }
}
