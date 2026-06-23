import AppKit
import Foundation
import UniformTypeIdentifiers

fileprivate enum SelectionResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

enum ClipOverlayTool: CaseIterable {
    case move
    case rectangle
    case arrow
    case pencil
    case marker
    case privacy
    case text
    case eraser

    var label: String {
        switch self {
        case .move: return "⌖"
        case .rectangle: return "▭"
        case .arrow: return "↗"
        case .pencil: return "✎"
        case .marker: return "▰"
        case .privacy: return "◫"
        case .text: return "T"
        case .eraser: return "⌫"
        }
    }

    var symbolName: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .privacy: return "checkerboard.rectangle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }
}

enum PrivacyEffect: CaseIterable {
    case blur
    case mosaic

    var title: String {
        switch self {
        case .blur: return "Blur"
        case .mosaic: return "Mosaic"
        }
    }

    var annotationKind: ClipOverlayAnnotation.Kind {
        switch self {
        case .blur: return .blur
        case .mosaic: return .mosaic
        }
    }

    var style: ClipOverlayAnnotation.Style {
        switch self {
        case .blur: return .blur
        case .mosaic: return .mosaic
        }
    }
}

enum PrivacyTrackSize: CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 40
        case .large: return 64
        }
    }
}

enum AnnotationStyleColor: CaseIterable {
    case red
    case blue
    case yellow
    case green

    var label: String {
        switch self {
        case .red: return "●"
        case .blue: return "●"
        case .yellow: return "●"
        case .green: return "●"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        }
    }

    func style(for tool: ClipOverlayTool, lineWidth: CGFloat) -> ClipOverlayAnnotation.Style {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        let alpha: Double = tool == .marker ? 0.45 : 1
        let width = tool == .marker ? max(lineWidth * 4, 12) : lineWidth
        return ClipOverlayAnnotation.Style(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: alpha,
            lineWidth: width
        )
    }

    func matches(_ style: ClipOverlayAnnotation.Style) -> Bool {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        return abs(Double(color.redComponent) - style.red) < 0.02
            && abs(Double(color.greenComponent) - style.green) < 0.02
            && abs(Double(color.blueComponent) - style.blue) < 0.02
    }
}

@MainActor
final class ScreenSelectionWindowController: NSWindowController {
    private let screen: NSScreen
    private let selectionView = ScreenSelectionView()
    private weak var session: ScreenSelectionSession?

    fileprivate init(screen: NSScreen, session: ScreenSelectionSession) {
        self.screen = screen
        self.session = session

        let window = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.sharingType = .none

        super.init(window: window)

        selectionView.screenFrame = screen.frame
        selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]

        window.contentView = selectionView
        selectionView.onCancel = { [weak session] in
            session?.cancel()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func capture(preferredScreen: NSScreen? = nil) async throws -> ScreenCaptureService.SelectionResult {
        try await ScreenSelectionSession.capture(preferredScreen: preferredScreen)
    }

    static func capture(
        preferredScreen: NSScreen? = nil,
        defaultSaveDirectory: URL? = nil,
        captureInPlace: @escaping @MainActor (ScreenCaptureService.SelectionResult) async throws -> ScreenCaptureService.CapturedRegion,
        handleInPlaceResult: @escaping @MainActor (ScreenCaptureService.CapturedRegion) async -> Void
    ) async throws -> ScreenCaptureService.SelectionResult {
        try await ScreenSelectionSession.capture(
            preferredScreen: preferredScreen,
            defaultSaveDirectory: defaultSaveDirectory,
            captureInPlace: captureInPlace,
            handleInPlaceResult: handleInPlaceResult
        )
    }

    func present() {
        showWindow(nil)
        window?.setFrame(screen.frame, display: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func makeActive() {
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func updateSelection(
        globalRect: CGRect?,
        mousePoint: CGPoint?,
        isEditing: Bool,
        annotations: [ClipOverlayAnnotation],
        draftAnnotation: ClipOverlayAnnotation?,
        activeTool: ClipOverlayTool,
        selectedAnnotationIndex: Int?,
        editingTextAnnotationIndex: Int?,
        editingText: String,
        currentPrivacyEffect: PrivacyEffect,
        currentPrivacyTrackSize: PrivacyTrackSize,
        currentColor: AnnotationStyleColor,
        currentLineWidth: CGFloat,
        privacyPreviewBaseImage: NSImage?,
        privacyPreviewOverlayImage: NSImage?,
        privacyPreviewRect: CGRect?
    ) {
        selectionView.selectionRect = globalRect
        selectionView.mousePoint = mousePoint
        selectionView.isEditing = isEditing
        selectionView.annotations = annotations
        selectionView.draftAnnotation = draftAnnotation
        selectionView.activeTool = activeTool
        selectionView.selectedAnnotationIndex = selectedAnnotationIndex
        selectionView.editingTextAnnotationIndex = editingTextAnnotationIndex
        selectionView.editingText = editingText
        selectionView.currentPrivacyEffect = currentPrivacyEffect
        selectionView.currentPrivacyTrackSize = currentPrivacyTrackSize
        selectionView.currentColor = currentColor
        selectionView.currentLineWidth = currentLineWidth
        selectionView.privacyPreviewBaseImage = privacyPreviewBaseImage
        selectionView.privacyPreviewOverlayImage = privacyPreviewOverlayImage
        selectionView.privacyPreviewRect = privacyPreviewRect
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    func hideForCapture() {
        window?.sharingType = .none
    }

    func restoreAfterCapture() {
        window?.sharingType = .none
        window?.orderFrontRegardless()
        window?.makeKey()
    }

}

@MainActor
fileprivate final class ScreenSelectionSession {
    private enum InteractionMode {
        case idle
        case drawing
        case moving
        case resizing(SelectionResizeHandle)
        case annotating
        case erasing
        case movingAnnotation(Int)
        case resizingAnnotation(Int, SelectionResizeHandle)
    }

    private enum ToolbarAction {
        case tool(ClipOverlayTool)
        case undo
        case redo
        case delete
        case pin
        case save
        case ocr
        case cancel
        case capture
    }

    private let continuation: CheckedContinuation<ScreenCaptureService.SelectionResult, Error>
    private let preferredScreen: NSScreen?
    private let defaultSaveDirectory: URL?
    private let captureInPlace: (@MainActor (ScreenCaptureService.SelectionResult) async throws -> ScreenCaptureService.CapturedRegion)?
    private let handleInPlaceResult: (@MainActor (ScreenCaptureService.CapturedRegion) async -> Void)?
    private var controllers: [ScreenSelectionWindowController] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isCompleted = false
    private var isPerformingInPlaceAction = false
    private var interactionMode: InteractionMode = .idle
    private var selectionRect: CGRect?
    private var dragStartPoint: CGPoint?
    private var dragStartRect: CGRect?
    private var dragStartAnnotations: [ClipOverlayAnnotation] = []
    private var mousePoint: CGPoint?
    private var activeTool: ClipOverlayTool = .move
    private var annotations: [ClipOverlayAnnotation] = []
    private var draftAnnotation: ClipOverlayAnnotation?
    private var selectedAnnotationIndex: Int?
    private var undoStack: [[ClipOverlayAnnotation]] = []
    private var redoStack: [[ClipOverlayAnnotation]] = []
    private var currentColor: AnnotationStyleColor = .red
    private var currentLineWidth: CGFloat = 4
    private var currentPrivacyEffect: PrivacyEffect = .blur
    private var currentPrivacyTrackSize: PrivacyTrackSize = .medium
    private var isEditingText = false
    private var editingTextAnnotationIndex: Int?
    private var editingTextDraft = ""
    private var privacyPreviewBaseImage: NSImage?
    private var privacyPreviewOverlayImage: NSImage?
    private var privacyPreviewRect: CGRect?
    private var privacyPreviewGeneration = 0
    private var isPrivacyPreviewOverlayRenderScheduled = false
    private var isCapturingPrivacyPreview = false
    private var needsPrivacyPreviewRefreshAfterCapture = false

    private init(
        continuation: CheckedContinuation<ScreenCaptureService.SelectionResult, Error>,
        preferredScreen: NSScreen?,
        defaultSaveDirectory: URL?,
        captureInPlace: (@MainActor (ScreenCaptureService.SelectionResult) async throws -> ScreenCaptureService.CapturedRegion)?,
        handleInPlaceResult: (@MainActor (ScreenCaptureService.CapturedRegion) async -> Void)?
    ) {
        self.continuation = continuation
        self.preferredScreen = preferredScreen
        self.defaultSaveDirectory = defaultSaveDirectory
        self.captureInPlace = captureInPlace
        self.handleInPlaceResult = handleInPlaceResult
    }

    private func configureControllers() {
        controllers = NSScreen.screens.map { ScreenSelectionWindowController(screen: $0, session: self) }
    }

    static func capture(preferredScreen: NSScreen? = nil) async throws -> ScreenCaptureService.SelectionResult {
        try await capture(preferredScreen: preferredScreen, defaultSaveDirectory: nil, captureInPlace: nil, handleInPlaceResult: nil)
    }

    static func capture(
        preferredScreen: NSScreen? = nil,
        defaultSaveDirectory: URL? = nil,
        captureInPlace: (@MainActor (ScreenCaptureService.SelectionResult) async throws -> ScreenCaptureService.CapturedRegion)?,
        handleInPlaceResult: (@MainActor (ScreenCaptureService.CapturedRegion) async -> Void)?
    ) async throws -> ScreenCaptureService.SelectionResult {
        try await withCheckedThrowingContinuation { continuation in
            let session = ScreenSelectionSession(
                continuation: continuation,
                preferredScreen: preferredScreen,
                defaultSaveDirectory: defaultSaveDirectory,
                captureInPlace: captureInPlace,
                handleInPlaceResult: handleInPlaceResult
            )
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
            self?.handle(event) == true ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    private func removeEventMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    @discardableResult
    fileprivate func handle(_ event: NSEvent) -> Bool {
        guard !isPerformingInPlaceAction else {
            return false
        }
        if let eventWindow = event.window, !isSelectionWindow(eventWindow) {
            return false
        }
        let eventPoint = globalPoint(from: event)
        if ClipOverlayInteractionRegistry.shared.forwardMouseEvent(event, at: eventPoint) {
            return true
        }
        if ClipOverlayInteractionRegistry.shared.contains(eventPoint) {
            mousePoint = nil
            updateSelectionViews()
            return false
        }

        switch event.type {
        case .keyDown:
            if isEditingText {
                handleTextEditingKey(event)
                return true
            }
            if event.keyCode == 53 {
                if ClipOverlayInteractionRegistry.shared.closeSelectedTarget() {
                    return true
                }
                cancel()
                return true
            } else if event.keyCode == 51 || event.keyCode == 117 {
                deleteSelectedAnnotation()
                return true
            } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
                if event.modifierFlags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return true
            } else if event.keyCode == 36 || event.keyCode == 76 {
                finishCurrentSelection(action: .capture)
                return true
            }
            return false

        case .leftMouseDown:
            if isEditingText {
                commitTextEditing()
                updateSelectionViews()
                return true
            }
            let point = eventPoint
            mousePoint = point
            ClipOverlayInteractionRegistry.shared.clearSelection()
            beginInteraction(at: point, clickCount: event.clickCount)
            updateSelectionViews()
            return true

        case .leftMouseDragged:
            if isEditingText {
                return true
            }
            let point = eventPoint
            mousePoint = point
            continueInteraction(to: point)
            updateSelectionViews()
            return true

        case .leftMouseUp:
            if isEditingText {
                return true
            }
            mousePoint = eventPoint
            endInteraction()
            updateSelectionViews()
            return true

        default:
            return false
        }
    }

    private func isSelectionWindow(_ window: NSWindow) -> Bool {
        controllers.contains { $0.window === window }
    }

    private func updateSelectionViews() {
        let hasPreview = privacyPreviewRect == selectionRect?.integral
        controllers.forEach {
            $0.updateSelection(
                globalRect: selectionRect,
                mousePoint: mousePoint,
                isEditing: selectionRect != nil && !isDrawing,
                annotations: annotations,
                draftAnnotation: draftAnnotation,
                activeTool: activeTool,
                selectedAnnotationIndex: selectedAnnotationIndex,
                editingTextAnnotationIndex: editingTextAnnotationIndex,
                editingText: editingTextDraft,
                currentPrivacyEffect: currentPrivacyEffect,
                currentPrivacyTrackSize: currentPrivacyTrackSize,
                currentColor: currentColor,
                currentLineWidth: currentLineWidth,
                privacyPreviewBaseImage: hasPreview ? privacyPreviewBaseImage : nil,
                privacyPreviewOverlayImage: hasPreview ? privacyPreviewOverlayImage : nil,
                privacyPreviewRect: hasPreview ? privacyPreviewRect : nil
            )
        }
    }

    private func currentPrivacyAnnotations() -> [ClipOverlayAnnotation] {
        var privacyAnnotations = annotations.filter { $0.kind == .blur || $0.kind == .mosaic }
        if let draftAnnotation, draftAnnotation.kind == .blur || draftAnnotation.kind == .mosaic {
            privacyAnnotations.append(draftAnnotation)
        }
        return privacyAnnotations
    }

    private var isDrawing: Bool {
        if case .drawing = interactionMode {
            return true
        }
        return false
    }

    private func beginInteraction(at point: CGPoint, clickCount: Int) {
        if let selectionRect {
            if let action = toolbarAction(at: point, for: selectionRect) {
                switch action {
                case .tool(let tool):
                    activeTool = tool
                    draftAnnotation = nil
                    selectedAnnotationIndex = nil
                    preparePrivacyPreviewIfNeeded()
                case .undo:
                    undo()
                case .redo:
                    redo()
                case .delete:
                    deleteSelectedAnnotation()
                case .ocr:
                    performInPlaceAction(.ocr)
                case .cancel:
                    cancel()
                case .pin:
                    performInPlaceAction(.pin)
                case .save:
                    performSaveAction()
                case .capture:
                    finishCurrentSelection(action: .capture)
                }
                return
            }

            if let privacyEffect = privacyEffect(at: point, for: selectionRect) {
                currentPrivacyEffect = privacyEffect
                activeTool = .privacy
                selectedAnnotationIndex = nil
                preparePrivacyPreviewIfNeeded()
                return
            }

            if let trackSize = privacyTrackSize(at: point, for: selectionRect) {
                currentPrivacyTrackSize = trackSize
                activeTool = .privacy
                selectedAnnotationIndex = nil
                preparePrivacyPreviewIfNeeded()
                return
            }

            if let color = stylePaletteColor(at: point) {
                currentColor = color
                updateSelectedAnnotationStyle()
                return
            }

            if activeTool == .move, let selectedAnnotationIndex {
                if let handle = resizeHandle(at: point, in: annotations[selectedAnnotationIndex].bounds),
                   canResize(annotations[selectedAnnotationIndex]) {
                    pushUndo()
                    interactionMode = .resizingAnnotation(selectedAnnotationIndex, handle)
                    dragStartPoint = point
                    dragStartAnnotations = annotations
                    return
                }
            }

            if activeTool == .move, let annotationIndex = annotationIndex(at: point) {
                selectedAnnotationIndex = annotationIndex
                if clickCount > 1, annotations[annotationIndex].kind == .text {
                    editTextAnnotation(at: annotationIndex)
                    return
                }

                pushUndo()
                interactionMode = .movingAnnotation(annotationIndex)
                dragStartPoint = point
                dragStartAnnotations = annotations
                return
            }

            if clickCount > 1 && selectionRect.contains(point), activeTool == .move {
                finishCurrentSelection(action: .capture)
                return
            }

            if activeTool != .move, selectionRect.contains(point) {
                if activeTool == .eraser {
                    beginErasing(at: point)
                    return
                }
                beginAnnotation(at: clamp(point, to: selectionRect))
                return
            }

            if activeTool == .move, let handle = resizeHandle(at: point, in: selectionRect) {
                interactionMode = .resizing(handle)
                dragStartPoint = point
                dragStartRect = selectionRect
                return
            }

            if activeTool == .move, selectionRect.contains(point) {
                selectedAnnotationIndex = nil
                interactionMode = .moving
                dragStartPoint = point
                dragStartRect = selectionRect
                dragStartAnnotations = annotations
                return
            }
        }

        interactionMode = .drawing
        dragStartPoint = point
        dragStartRect = nil
        dragStartAnnotations = []
        annotations = []
        draftAnnotation = nil
        selectedAnnotationIndex = nil
        invalidatePrivacyPreview()
        selectionRect = CGRect(origin: point, size: .zero)
    }

    private func continueInteraction(to point: CGPoint) {
        guard let dragStartPoint else {
            return
        }

        switch interactionMode {
        case .idle:
            break
        case .drawing:
            selectionRect = normalizedRect(from: dragStartPoint, to: clampToDisplayBounds(point))
        case .moving:
            guard let dragStartRect else {
                return
            }
            let constrainedRect = constrain(
                dragStartRect.offsetBy(dx: point.x - dragStartPoint.x, dy: point.y - dragStartPoint.y),
                near: point
            ).integral
            if constrainedRect != selectionRect {
                invalidatePrivacyPreview()
            }
            selectionRect = constrainedRect
            annotations = dragStartAnnotations.map {
                translate($0, dx: constrainedRect.minX - dragStartRect.minX, dy: constrainedRect.minY - dragStartRect.minY)
            }
        case .resizing(let handle):
            guard let dragStartRect else {
                return
            }
            let resizedRect = resize(dragStartRect, handle: handle, to: clampToDisplayBounds(point)).integral
            if resizedRect != selectionRect {
                invalidatePrivacyPreview()
            }
            selectionRect = resizedRect
        case .annotating:
            guard let selectionRect else {
                return
            }
            continueAnnotation(to: clamp(point, to: selectionRect))
        case .erasing:
            guard let selectionRect else {
                return
            }
            eraseAnnotation(at: clamp(point, to: selectionRect))
        case .movingAnnotation(let index):
            guard dragStartAnnotations.indices.contains(index) else {
                return
            }
            annotations = dragStartAnnotations
            annotations[index] = translate(
                dragStartAnnotations[index],
                dx: point.x - dragStartPoint.x,
                dy: point.y - dragStartPoint.y
            )
        case .resizingAnnotation(let index, let handle):
            guard dragStartAnnotations.indices.contains(index) else {
                return
            }
            annotations = dragStartAnnotations
            annotations[index] = resize(dragStartAnnotations[index], handle: handle, to: point)
        }
    }

    private func endInteraction() {
        if case .drawing = interactionMode, let selectionRect, !isValidSelection(selectionRect) {
            self.selectionRect = nil
        }
        let shouldRefreshPreviewBase = shouldRefreshPrivacyPreviewBaseWhenInteractionEnds
        if case .annotating = interactionMode {
            finishAnnotation()
        }
        if case .erasing = interactionMode, annotations != dragStartAnnotations {
            undoStack.append(dragStartAnnotations)
            redoStack.removeAll()
            selectedAnnotationIndex = nil
        }
        if case .movingAnnotation = interactionMode, annotations == dragStartAnnotations {
            _ = undoStack.popLast()
        }
        if case .resizingAnnotation = interactionMode, annotations == dragStartAnnotations {
            _ = undoStack.popLast()
        }

        interactionMode = .idle
        dragStartPoint = nil
        dragStartRect = nil
        dragStartAnnotations = []

        if shouldRefreshPreviewBase {
            requestPrivacyPreviewCaptureIfNeeded()
        }
    }

    private var shouldRefreshPrivacyPreviewBaseWhenInteractionEnds: Bool {
        guard isValidSelection(selectionRect ?? .zero) else {
            return false
        }

        switch interactionMode {
        case .drawing, .moving, .resizing:
            return true
        case .idle, .annotating, .erasing, .movingAnnotation, .resizingAnnotation:
            return false
        }
    }

    private func finishCurrentSelection(action: ClipCaptureAction) {
        guard let selectionRect, isValidSelection(selectionRect) else {
            return
        }

        if captureInPlace != nil, handleInPlaceResult != nil {
            performInPlaceAction(action, saveURL: nil, selectionRect: selectionRect)
            return
        }

        finish(with: ScreenCaptureService.SelectionResult(
            rect: selectionRect.integral,
            annotations: annotations,
            action: action,
            saveURL: nil
        ))
    }

    private func performInPlaceAction(_ action: ClipCaptureAction) {
        guard
            let selectionRect,
            isValidSelection(selectionRect)
        else {
            return
        }

        performInPlaceAction(action, saveURL: nil, selectionRect: selectionRect)
    }

    private func performSaveAction() {
        guard let selectionRect, isValidSelection(selectionRect) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultClipImageName()
        panel.directoryURL = defaultSaveDirectory
        guard panel.runModal() == .OK, let saveURL = panel.url else {
            return
        }

        performInPlaceAction(.save, saveURL: saveURL, selectionRect: selectionRect)
    }

    private func performInPlaceAction(_ action: ClipCaptureAction, saveURL: URL?, selectionRect: CGRect) {
        guard
            isValidSelection(selectionRect),
            let captureInPlace,
            let handleInPlaceResult
        else {
            return
        }

        isPerformingInPlaceAction = true
        draftAnnotation = nil
        updateSelectionViews()

        let selection = ScreenCaptureService.SelectionResult(
            rect: selectionRect.integral,
            annotations: annotations,
            action: action,
            saveURL: saveURL
        )

        Task { @MainActor in
            do {
                hideOverlayPanelsForCapture()
                await Task.yield()
                let capturedRegion = try await captureInPlace(selection)
                restoreOverlayPanelsAfterCapture()
                await handleInPlaceResult(capturedRegion)
                if keepsSelectionOpenAfterInPlaceAction(action) {
                    isPerformingInPlaceAction = false
                    updateSelectionViews()
                } else {
                    finishHandledInPlaceAction()
                }
            } catch {
                restoreOverlayPanelsAfterCapture()
                isPerformingInPlaceAction = false
                updateSelectionViews()
            }
        }
    }

    private func keepsSelectionOpenAfterInPlaceAction(_ action: ClipCaptureAction) -> Bool {
        action == .pin || action == .ocr
    }

    private func finishHandledInPlaceAction() {
        guard !isCompleted else {
            return
        }

        isPerformingInPlaceAction = false
        isCompleted = true
        closeAllWindows()
        continuation.resume(throwing: CancellationError())
    }

    private func defaultClipImageName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Clip \(formatter.string(from: Date())).png"
    }

    private func requestPrivacyPreviewCaptureIfNeeded() {
        guard
            let selectionRect,
            isValidSelection(selectionRect),
            let captureInPlace
        else {
            return
        }

        let previewRect = selectionRect.integral
        if privacyPreviewBaseImage != nil, privacyPreviewRect == previewRect {
            return
        }

        if isCapturingPrivacyPreview {
            needsPrivacyPreviewRefreshAfterCapture = true
            return
        }

        privacyPreviewGeneration += 1
        let generation = privacyPreviewGeneration
        isCapturingPrivacyPreview = true
        needsPrivacyPreviewRefreshAfterCapture = false
        let selection = ScreenCaptureService.SelectionResult(
            rect: previewRect,
            annotations: [],
            action: .capture,
            saveURL: nil
        )

        Task { @MainActor in
            do {
                hideOverlayPanelsForCapture()
                await Task.yield()
                let capturedRegion = try await captureInPlace(selection)
                restoreOverlayPanelsAfterCapture()
                if generation == privacyPreviewGeneration {
                    privacyPreviewBaseImage = capturedRegion.image
                    privacyPreviewRect = previewRect
                    schedulePrivacyPreviewOverlayUpdate()
                }
            } catch {
                restoreOverlayPanelsAfterCapture()
                if generation == privacyPreviewGeneration {
                    privacyPreviewBaseImage = nil
                    privacyPreviewOverlayImage = nil
                    privacyPreviewRect = nil
                }
            }
            isCapturingPrivacyPreview = false
            updateSelectionViews()
            if needsPrivacyPreviewRefreshAfterCapture {
                needsPrivacyPreviewRefreshAfterCapture = false
                requestPrivacyPreviewCaptureIfNeeded()
            }
        }
    }

    private func preparePrivacyPreviewIfNeeded() {
        guard activeTool == .privacy || !currentPrivacyAnnotations().isEmpty else {
            return
        }

        requestPrivacyPreviewCaptureIfNeeded()
    }

    private func invalidatePrivacyPreview() {
        privacyPreviewGeneration += 1
        needsPrivacyPreviewRefreshAfterCapture = isCapturingPrivacyPreview
        privacyPreviewBaseImage = nil
        privacyPreviewOverlayImage = nil
        privacyPreviewRect = nil
    }

    private func schedulePrivacyPreviewOverlayUpdate() {
        guard
            let privacyPreviewBaseImage,
            let privacyPreviewRect,
            privacyPreviewRect == selectionRect?.integral
        else {
            privacyPreviewOverlayImage = nil
            return
        }

        guard !currentPrivacyAnnotations().isEmpty else {
            privacyPreviewOverlayImage = nil
            return
        }

        guard !isPrivacyPreviewOverlayRenderScheduled else {
            return
        }

        isPrivacyPreviewOverlayRenderScheduled = true
        let generation = privacyPreviewGeneration
        Task { @MainActor in
            await Task.yield()
            isPrivacyPreviewOverlayRenderScheduled = false
            guard generation == privacyPreviewGeneration else {
                privacyPreviewOverlayImage = nil
                updateSelectionViews()
                return
            }
            renderPrivacyPreviewOverlay(baseImage: privacyPreviewBaseImage, previewRect: privacyPreviewRect)
            updateSelectionViews()
        }
    }

    private func renderPrivacyPreviewOverlay(baseImage: NSImage, previewRect: CGRect) {
        guard previewRect == selectionRect?.integral else {
            privacyPreviewOverlayImage = nil
            return
        }

        let privacyAnnotations = currentPrivacyAnnotations()
        privacyPreviewOverlayImage = ClipAnnotationRenderer.renderPrivacyOverlay(
            baseImage: baseImage,
            annotations: privacyAnnotations,
            in: previewRect
        )
    }

    private func hideOverlayPanelsForCapture() {
        controllers.forEach { $0.hideForCapture() }
    }

    private func restoreOverlayPanelsAfterCapture() {
        controllers.forEach { $0.restoreAfterCapture() }
    }

    private func normalizedRect(from startPoint: CGPoint, to currentPoint: CGPoint) -> CGRect {
        CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        ).integral
    }

    private func isValidSelection(_ rect: CGRect) -> Bool {
        rect.width > 4 && rect.height > 4
    }

    private func beginAnnotation(at point: CGPoint) {
        dragStartPoint = point
        interactionMode = .annotating

        switch activeTool {
        case .move:
            break
        case .text:
            pushUndo()
            annotations.append(ClipOverlayAnnotation(
                kind: .text,
                rect: CGRect(x: point.x, y: point.y - 36, width: 120, height: 42),
                points: [],
                text: "",
                style: currentColor.style(for: .text, lineWidth: currentLineWidth)
            ))
            selectedAnnotationIndex = annotations.indices.last
            interactionMode = .idle
            dragStartPoint = nil
            if let selectedAnnotationIndex {
                editTextAnnotation(at: selectedAnnotationIndex)
            }
        case .rectangle:
            draftAnnotation = ClipOverlayAnnotation(
                kind: .rectangle,
                rect: CGRect(origin: point, size: .zero),
                points: [],
                text: "",
                style: currentColor.style(for: activeTool, lineWidth: currentLineWidth)
            )
        case .privacy:
            requestPrivacyPreviewCaptureIfNeeded()
            var privacyStyle = currentPrivacyEffect.style
            privacyStyle.lineWidth = currentPrivacyTrackSize.lineWidth
            draftAnnotation = ClipOverlayAnnotation(
                kind: currentPrivacyEffect.annotationKind,
                rect: .zero,
                points: [point],
                text: "",
                style: privacyStyle
            )
            schedulePrivacyPreviewOverlayUpdate()
        case .eraser:
            beginErasing(at: point)
        case .arrow:
            draftAnnotation = ClipOverlayAnnotation(kind: .arrow, rect: .zero, points: [point, point], text: "", style: currentColor.style(for: .arrow, lineWidth: currentLineWidth))
        case .pencil:
            draftAnnotation = ClipOverlayAnnotation(kind: .pencil, rect: .zero, points: [point], text: "", style: currentColor.style(for: .pencil, lineWidth: currentLineWidth))
        case .marker:
            draftAnnotation = ClipOverlayAnnotation(kind: .marker, rect: .zero, points: [point], text: "", style: currentColor.style(for: .marker, lineWidth: currentLineWidth))
        }
    }

    private func beginErasing(at point: CGPoint) {
        interactionMode = .erasing
        dragStartPoint = point
        dragStartAnnotations = annotations
        draftAnnotation = nil
        selectedAnnotationIndex = nil
        eraseAnnotation(at: point)
    }

    private func continueAnnotation(to point: CGPoint) {
        guard let dragStartPoint, var draftAnnotation else {
            return
        }

        switch draftAnnotation.kind {
        case .rectangle:
            draftAnnotation.rect = normalizedRect(from: dragStartPoint, to: point)
        case .arrow:
            draftAnnotation.points = [dragStartPoint, point]
        case .pencil, .marker, .mosaic, .blur:
            if shouldAppend(point, to: draftAnnotation.points) {
                draftAnnotation.points.append(point)
            }
        case .text:
            break
        }

        self.draftAnnotation = draftAnnotation
        if isPrivacyAnnotation(draftAnnotation) {
            schedulePrivacyPreviewOverlayUpdate()
        }
    }

    private func finishAnnotation() {
        guard let draftAnnotation, isRenderable(draftAnnotation) else {
            self.draftAnnotation = nil
            return
        }

        pushUndo()
        annotations.append(draftAnnotation)
        selectedAnnotationIndex = isPrivacyAnnotation(draftAnnotation) ? nil : annotations.indices.last
        self.draftAnnotation = nil
        if isPrivacyAnnotation(draftAnnotation) {
            schedulePrivacyPreviewOverlayUpdate()
        }
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else {
            return
        }
        redoStack.append(annotations)
        annotations = snapshot
        selectedAnnotationIndex = nil
        schedulePrivacyPreviewOverlayUpdate()
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else {
            return
        }
        undoStack.append(annotations)
        annotations = snapshot
        selectedAnnotationIndex = nil
        schedulePrivacyPreviewOverlayUpdate()
    }

    private func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    private func isRenderable(_ annotation: ClipOverlayAnnotation) -> Bool {
        switch annotation.kind {
        case .rectangle:
            return annotation.rect.width > 4 && annotation.rect.height > 4
        case .mosaic, .blur:
            return !annotation.points.isEmpty || annotation.rect.width > 4 && annotation.rect.height > 4
        case .arrow:
            return annotation.points.count >= 2 && distance(annotation.points[0], annotation.points[1]) > 4
        case .pencil, .marker:
            return annotation.points.count > 1
        case .text:
            return !annotation.text.isEmpty
        }
    }

    private func deleteSelectedAnnotation() {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return
        }

        pushUndo()
        annotations.remove(at: selectedAnnotationIndex)
        self.selectedAnnotationIndex = nil
        schedulePrivacyPreviewOverlayUpdate()
    }

    private func annotationIndex(at point: CGPoint) -> Int? {
        annotations.indices.reversed().first {
            !isPrivacyAnnotation(annotations[$0]) && annotations[$0].bounds.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func eraseAnnotation(at point: CGPoint) {
        let updatedAnnotations = annotations.flatMap { eraseAnnotation($0, at: point) }
        guard updatedAnnotations != annotations else {
            return
        }

        annotations = updatedAnnotations
        selectedAnnotationIndex = nil
        schedulePrivacyPreviewOverlayUpdate()
    }

    private func eraseAnnotation(_ annotation: ClipOverlayAnnotation, at point: CGPoint) -> [ClipOverlayAnnotation] {
        if isPrivacyAnnotation(annotation) {
            return erasePrivacyPaint(from: annotation, at: point)
        }

        return eraserHits(annotation, at: point) ? [] : [annotation]
    }

    private func erasePrivacyPaint(from annotation: ClipOverlayAnnotation, at point: CGPoint) -> [ClipOverlayAnnotation] {
        guard isPrivacyAnnotation(annotation) else {
            return [annotation]
        }

        if annotation.points.isEmpty {
            return eraserHitsRect(annotation.bounds, at: point) ? [] : [annotation]
        }

        let eraserRadius = max(currentPrivacyTrackSize.lineWidth / 2, 12)
        let privacyRadius = max(annotation.style.lineWidth / 2, 1)
        let removalRadius = eraserRadius + privacyRadius
        var segments: [[CGPoint]] = [[]]

        for privacyPoint in annotation.points {
            if distance(privacyPoint, point) <= removalRadius {
                if segments.last?.isEmpty == false {
                    segments.append([])
                }
            } else {
                segments[segments.count - 1].append(privacyPoint)
            }
        }

        return segments
            .filter { !$0.isEmpty }
            .map { points in
                ClipOverlayAnnotation(
                    kind: annotation.kind,
                    rect: annotation.rect,
                    points: points,
                    text: annotation.text,
                    style: annotation.style
                )
            }
    }

    private func eraserHits(_ annotation: ClipOverlayAnnotation, at point: CGPoint) -> Bool {
        switch annotation.kind {
        case .rectangle, .text:
            return eraserHitsRect(annotation.bounds, at: point)
        case .arrow, .pencil, .marker:
            return eraserHitsStroke(points: annotation.points, lineWidth: annotation.style.lineWidth, at: point)
        case .mosaic, .blur:
            return eraserHitsRect(annotation.bounds, at: point)
        }
    }

    private func eraserHitsRect(_ rect: CGRect, at point: CGPoint) -> Bool {
        rect.standardized.insetBy(dx: -eraserRadius, dy: -eraserRadius).contains(point)
    }

    private func eraserHitsStroke(points: [CGPoint], lineWidth: CGFloat, at point: CGPoint) -> Bool {
        guard let first = points.first else {
            return false
        }

        let hitRadius = eraserRadius + max(lineWidth / 2, 3)
        if points.count == 1 {
            return distance(first, point) <= hitRadius
        }

        return zip(points, points.dropFirst()).contains { start, end in
            distance(from: point, toSegmentStart: start, end: end) <= hitRadius
        }
    }

    private var eraserRadius: CGFloat {
        max(currentPrivacyTrackSize.lineWidth / 2, 12)
    }

    private func isPrivacyAnnotation(_ annotation: ClipOverlayAnnotation) -> Bool {
        annotation.kind == .blur || annotation.kind == .mosaic
    }

    private func canResize(_ annotation: ClipOverlayAnnotation) -> Bool {
        switch annotation.kind {
        case .rectangle, .text:
            return true
        case .arrow, .pencil, .marker, .mosaic, .blur:
            return false
        }
    }

    private func resize(_ annotation: ClipOverlayAnnotation, handle: SelectionResizeHandle, to point: CGPoint) -> ClipOverlayAnnotation {
        guard canResize(annotation) else {
            return annotation
        }

        var resized = annotation
        resized.rect = resize(annotation.rect, handle: handle, to: point)
        return resized
    }

    private func updateSelectedAnnotationStyle() {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return
        }

        let kind = annotations[selectedAnnotationIndex].kind
        guard kind != .mosaic && kind != .blur else {
            return
        }

        pushUndo()
        annotations[selectedAnnotationIndex].style = currentColor.style(
            for: tool(for: kind),
            lineWidth: currentLineWidth
        )
    }

    private func tool(for kind: ClipOverlayAnnotation.Kind) -> ClipOverlayTool {
        switch kind {
        case .rectangle: return .rectangle
        case .arrow: return .arrow
        case .pencil: return .pencil
        case .marker: return .marker
        case .mosaic, .blur: return .privacy
        case .text: return .text
        }
    }

    private func editTextAnnotation(at index: Int) {
        guard annotations.indices.contains(index) else {
            return
        }

        isEditingText = true
        editingTextAnnotationIndex = index
        editingTextDraft = annotations[index].text
        selectedAnnotationIndex = index
        updateSelectionViews()
    }

    private func handleTextEditingKey(_ event: NSEvent) {
        if event.keyCode == 53 {
            cancelTextEditing()
            updateSelectionViews()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            commitTextEditing()
            updateSelectionViews()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if !editingTextDraft.isEmpty {
                editingTextDraft.removeLast()
            }
            updateSelectionViews()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            if let pastedText = NSPasteboard.general.string(forType: .string) {
                editingTextDraft += pastedText
            }
            updateSelectionViews()
            return
        }
        guard !event.modifierFlags.contains(.command),
              let characters = event.characters,
              !characters.isEmpty
        else {
            return
        }

        let text = String(characters.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        guard !text.isEmpty else {
            return
        }

        editingTextDraft += text
        updateSelectionViews()
    }

    private func commitTextEditing() {
        guard
            let editingTextAnnotationIndex,
            annotations.indices.contains(editingTextAnnotationIndex)
        else {
            cancelTextEditing()
            return
        }

        if annotations[editingTextAnnotationIndex].text != editingTextDraft {
            pushUndo()
            annotations[editingTextAnnotationIndex].text = editingTextDraft
        }
        selectedAnnotationIndex = editingTextAnnotationIndex
        isEditingText = false
        self.editingTextAnnotationIndex = nil
        editingTextDraft = ""
    }

    private func cancelTextEditing() {
        isEditingText = false
        editingTextAnnotationIndex = nil
        editingTextDraft = ""
    }

    private func shouldAppend(_ point: CGPoint, to points: [CGPoint]) -> Bool {
        guard let last = points.last else {
            return true
        }
        return distance(last, point) > 1.5
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(point, start)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closest = CGPoint(
            x: start.x + clampedProjection * dx,
            y: start.y + clampedProjection * dy
        )
        return distance(point, closest)
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func translate(_ annotation: ClipOverlayAnnotation, dx: CGFloat, dy: CGFloat) -> ClipOverlayAnnotation {
        ClipOverlayAnnotation(
            kind: annotation.kind,
            rect: annotation.rect.offsetBy(dx: dx, dy: dy),
            points: annotation.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) },
            text: annotation.text,
            style: annotation.style
        )
    }

    private func resize(_ rect: CGRect, handle: SelectionResizeHandle, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        let minimumSize: CGFloat = 16

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .top:
            maxY = max(point.y, minY + minimumSize)
        case .topRight:
            maxX = max(point.x, minX + minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .left:
            minX = min(point.x, maxX - minimumSize)
        case .right:
            maxX = max(point.x, minX + minimumSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .bottom:
            minY = min(point.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(point.x, minX + minimumSize)
            minY = min(point.y, maxY - minimumSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func resizeHandle(at point: CGPoint, in rect: CGRect) -> SelectionResizeHandle? {
        SelectionResizeHandle.allCases.first { handleRect(for: $0, in: rect).contains(point) }
    }

    private func handleRect(for handle: SelectionResizeHandle, in rect: CGRect) -> CGRect {
        let size: CGFloat = 14
        let center: CGPoint
        switch handle {
        case .topLeft:
            center = CGPoint(x: rect.minX, y: rect.maxY)
        case .top:
            center = CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .left:
            center = CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:
            center = CGPoint(x: rect.minX, y: rect.minY)
        case .bottom:
            center = CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight:
            center = CGPoint(x: rect.maxX, y: rect.minY)
        }
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func toolbarAction(at point: CGPoint, for rect: CGRect) -> ToolbarAction? {
        let toolbarRect = toolbarRect(for: rect)
        guard toolbarRect.contains(point) else {
            return nil
        }

        let items = toolbarItems
        let iconWidth = toolbarRect.width / CGFloat(items.count)
        let index = Int((point.x - toolbarRect.minX) / iconWidth)
        guard items.indices.contains(index) else {
            return nil
        }
        return items[index].action
    }

    private func toolbarRect(for rect: CGRect) -> CGRect {
        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main)?.frame ?? rect
        let width = toolbarWidth(in: screenFrame)
        let height: CGFloat = 38
        let x = min(max(rect.minX, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = rect.minY - height - 8
        if y < screenFrame.minY + 8 {
            y = rect.maxY + 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func toolbarWidth(in rect: CGRect) -> CGFloat {
        min(660, max(430, rect.width - 16))
    }

    private var toolbarItems: [(label: String, action: ToolbarAction)] {
        [
            (ClipOverlayTool.move.label, .tool(.move)),
            (ClipOverlayTool.rectangle.label, .tool(.rectangle)),
            (ClipOverlayTool.arrow.label, .tool(.arrow)),
            (ClipOverlayTool.pencil.label, .tool(.pencil)),
            (ClipOverlayTool.marker.label, .tool(.marker)),
            (ClipOverlayTool.privacy.label, .tool(.privacy)),
            (ClipOverlayTool.text.label, .tool(.text)),
            (ClipOverlayTool.eraser.label, .tool(.eraser)),
            ("↶", .undo),
            ("↷", .redo),
            ("⌫", .delete),
            ("📌", .pin),
            ("⇩", .save),
            ("OCR", .ocr),
            ("×", .cancel),
            ("✓", .capture)
        ]
    }

    private func stylePaletteColor(at point: CGPoint) -> AnnotationStyleColor? {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            canStyle(annotations[selectedAnnotationIndex])
        else {
            return nil
        }

        let paletteRect = stylePaletteRect(for: annotations[selectedAnnotationIndex].bounds)
        guard paletteRect.contains(point) else {
            return nil
        }

        let colors = AnnotationStyleColor.allCases
        let cellWidth = paletteRect.width / CGFloat(colors.count)
        let index = Int((point.x - paletteRect.minX) / cellWidth)
        guard colors.indices.contains(index) else {
            return nil
        }
        return colors[index]
    }

    private func privacyEffect(at point: CGPoint, for selectionRect: CGRect) -> PrivacyEffect? {
        guard activeTool == .privacy else {
            return nil
        }

        let optionsRect = privacyEffectOptionsRect(for: selectionRect)
        guard optionsRect.contains(point) else {
            return nil
        }

        let options = PrivacyEffect.allCases
        let cellWidth = optionsRect.width / CGFloat(options.count)
        let index = Int((point.x - optionsRect.minX) / cellWidth)
        guard options.indices.contains(index) else {
            return nil
        }
        return options[index]
    }

    private func privacyTrackSize(at point: CGPoint, for selectionRect: CGRect) -> PrivacyTrackSize? {
        guard activeTool == .privacy else {
            return nil
        }

        let optionsRect = privacyTrackSizeOptionsRect(for: selectionRect)
        guard optionsRect.contains(point) else {
            return nil
        }

        let options = PrivacyTrackSize.allCases
        let cellWidth = optionsRect.width / CGFloat(options.count)
        let index = Int((point.x - optionsRect.minX) / cellWidth)
        guard options.indices.contains(index) else {
            return nil
        }
        return options[index]
    }

    private func privacyOptionsBaseRect(for selectionRect: CGRect) -> CGRect {
        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(selectionRect) } ?? NSScreen.main)?.frame ?? selectionRect
        let toolbarRect = toolbarRect(for: selectionRect)
        let width: CGFloat = 246
        let height: CGFloat = 34
        let x = min(max(toolbarRect.minX, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = toolbarRect.minY - height - 8
        if y < screenFrame.minY + 8 {
            y = toolbarRect.maxY + 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func privacyEffectOptionsRect(for selectionRect: CGRect) -> CGRect {
        let baseRect = privacyOptionsBaseRect(for: selectionRect)
        return CGRect(x: baseRect.minX, y: baseRect.minY, width: 136, height: baseRect.height)
    }

    private func privacyTrackSizeOptionsRect(for selectionRect: CGRect) -> CGRect {
        let baseRect = privacyOptionsBaseRect(for: selectionRect)
        return CGRect(x: baseRect.minX + 146, y: baseRect.minY, width: 92, height: baseRect.height)
    }

    private func stylePaletteRect(for annotationBounds: CGRect) -> CGRect {
        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(annotationBounds) } ?? NSScreen.main)?.frame ?? annotationBounds
        let width: CGFloat = 116
        let height: CGFloat = 34
        let x = min(max(annotationBounds.midX - width / 2, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = annotationBounds.maxY + 8
        if y + height > screenFrame.maxY - 8 {
            y = annotationBounds.minY - height - 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func canStyle(_ annotation: ClipOverlayAnnotation) -> Bool {
        switch annotation.kind {
        case .rectangle, .arrow, .pencil, .marker, .text:
            return true
        case .mosaic, .blur:
            return false
        }
    }

    private func constrain(_ rect: CGRect, near point: CGPoint) -> CGRect {
        let displayBounds = availableDisplayBounds
        guard !displayBounds.isNull else {
            return rect
        }

        var adjusted = rect
        if adjusted.minX < displayBounds.minX {
            adjusted.origin.x = displayBounds.minX
        }
        if adjusted.maxX > displayBounds.maxX {
            adjusted.origin.x = displayBounds.maxX - adjusted.width
        }
        if adjusted.minY < displayBounds.minY {
            adjusted.origin.y = displayBounds.minY
        }
        if adjusted.maxY > displayBounds.maxY {
            adjusted.origin.y = displayBounds.maxY - adjusted.height
        }
        return adjusted
    }

    private var availableDisplayBounds: CGRect {
        NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { $0.union($1) }
    }

    private func clampToDisplayBounds(_ point: CGPoint) -> CGPoint {
        let displayBounds = availableDisplayBounds
        guard !displayBounds.isNull else {
            return point
        }

        return clamp(point, to: displayBounds)
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
    var onCancel: (() -> Void)?
    var screenFrame: CGRect = .zero
    var selectionRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }
    var mousePoint: CGPoint? {
        didSet {
            needsDisplay = true
        }
    }
    var isEditing = false {
        didSet {
            needsDisplay = true
        }
    }
    var annotations: [ClipOverlayAnnotation] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var draftAnnotation: ClipOverlayAnnotation? {
        didSet {
            needsDisplay = true
        }
    }
    var activeTool: ClipOverlayTool = .move {
        didSet {
            needsDisplay = true
        }
    }
    var selectedAnnotationIndex: Int? {
        didSet {
            needsDisplay = true
        }
    }
    var editingTextAnnotationIndex: Int? {
        didSet {
            needsDisplay = true
        }
    }
    var editingText = "" {
        didSet {
            needsDisplay = true
        }
    }
    var currentPrivacyEffect: PrivacyEffect = .blur {
        didSet {
            needsDisplay = true
        }
    }
    var currentPrivacyTrackSize: PrivacyTrackSize = .medium {
        didSet {
            needsDisplay = true
        }
    }
    var currentColor: AnnotationStyleColor = .red {
        didSet {
            needsDisplay = true
        }
    }
    var currentLineWidth: CGFloat = 4 {
        didSet {
            needsDisplay = true
        }
    }
    var privacyPreviewBaseImage: NSImage? {
        didSet {
            needsDisplay = true
        }
    }
    var privacyPreviewOverlayImage: NSImage? {
        didSet {
            needsDisplay = true
        }
    }
    var privacyPreviewRect: CGRect? {
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        dirtyRect.fill()

        if localSelectionRect() != nil, let globalSelectionRect = selectionRect {
            let selectionRect = localRect(globalSelectionRect)
            NSColor.clear.setFill()
            selectionRect.fill(using: .copy)
            let didDrawPrivacyPreview = drawPrivacyPreviews()
            let shouldHidePrivacyFeedback = didDrawPrivacyPreview || hasAvailablePrivacyPreviewBase()

            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()

            drawAnnotations(hidePrivacyAnnotations: shouldHidePrivacyFeedback)
            drawSelectedAnnotation()
            drawHandles(for: selectionRect)
            drawSizeLabel(forGlobal: globalSelectionRect)
            if isEditing {
                drawToolbar(forGlobal: globalSelectionRect)
            }
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

    private func drawPrivacyPreviews() -> Bool {
        guard
            let privacyPreviewOverlayImage,
            let privacyPreviewRect,
            let selectionRect,
            privacyPreviewRect == selectionRect.integral
        else {
            return false
        }

        privacyPreviewOverlayImage.draw(
            in: localRect(privacyPreviewRect),
            from: CGRect(origin: .zero, size: privacyPreviewOverlayImage.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        return true
    }

    private func hasAvailablePrivacyPreviewBase() -> Bool {
        guard
            privacyPreviewBaseImage != nil,
            let privacyPreviewRect,
            let selectionRect,
            privacyPreviewRect == selectionRect.integral
        else {
            return false
        }

        return true
    }

    private func drawHandles(for rect: CGRect) {
        NSColor.systemBlue.setFill()
        for handle in SelectionResizeHandle.allCases {
            NSBezierPath(ovalIn: handleRect(for: handle, in: rect)).fill()
        }
    }

    private func handleRect(for handle: SelectionResizeHandle, in rect: CGRect) -> CGRect {
        let size: CGFloat = 7
        let center: CGPoint
        switch handle {
        case .topLeft:
            center = CGPoint(x: rect.minX, y: rect.maxY)
        case .top:
            center = CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .left:
            center = CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:
            center = CGPoint(x: rect.minX, y: rect.minY)
        case .bottom:
            center = CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight:
            center = CGPoint(x: rect.maxX, y: rect.minY)
        }
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func drawSizeLabel(forGlobal rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = localRect(CGRect(
            x: rect.minX,
            y: labelY(forGlobal: rect, height: size.height + 6),
            width: size.width + 12,
            height: size.height + 6
        ))

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        text.draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: attributes)
    }

    private func labelY(forGlobal rect: CGRect, height: CGFloat) -> CGFloat {
        let screenFrame = screenFrame(containing: rect)
        return min(screenFrame.maxY - height - 8, rect.maxY + 6)
    }

    private func drawToolbar(forGlobal rect: CGRect) {
        let toolbarRect = localRect(toolbarRect(forGlobal: rect))
        guard toolbarRect.intersects(bounds) else {
            return
        }

        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 9, yRadius: 9).fill()

        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(roundedRect: toolbarRect, xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        let items = toolbarItems
        let iconWidth = toolbarRect.width / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let iconRect = CGRect(
                x: toolbarRect.minX + CGFloat(index) * iconWidth,
                y: toolbarRect.minY,
                width: iconWidth,
                height: toolbarRect.height
            )
            drawToolbarIcon(
                item.label,
                symbolName: item.symbolName,
                in: iconRect,
                highlighted: item.tool == activeTool || item.label == "✓"
            )
        }

        if activeTool == .privacy {
            drawPrivacyOptions(forGlobal: rect)
        }
    }

    private func drawPrivacyOptions(forGlobal rect: CGRect) {
        let optionsRect = localRect(privacyOptionsBaseRect(forGlobal: rect))
        guard optionsRect.intersects(bounds) else {
            return
        }

        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: optionsRect, xRadius: 9, yRadius: 9).fill()

        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(roundedRect: optionsRect, xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawPrivacyEffectOptions(in: localRect(privacyEffectOptionsRect(forGlobal: rect)))
        drawPrivacyTrackSizeOptions(in: localRect(privacyTrackSizeOptionsRect(forGlobal: rect)))

        let dividerX = localRect(privacyTrackSizeOptionsRect(forGlobal: rect)).minX - 5
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: dividerX, y: optionsRect.minY + 7))
        divider.line(to: CGPoint(x: dividerX, y: optionsRect.maxY - 7))
        divider.lineWidth = 1
        divider.stroke()
    }

    private func drawPrivacyEffectOptions(in rect: CGRect) {
        let options = PrivacyEffect.allCases
        let cellWidth = rect.width / CGFloat(options.count)
        for (index, option) in options.enumerated() {
            let cell = CGRect(
                x: rect.minX + CGFloat(index) * cellWidth,
                y: rect.minY,
                width: cellWidth,
                height: rect.height
            ).insetBy(dx: 4, dy: 4)
            let isSelected = option == currentPrivacyEffect
            if isSelected {
                NSColor.systemBlue.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.systemBlue : NSColor.labelColor
            ]
            let size = option.title.size(withAttributes: attributes)
            option.title.draw(
                at: CGPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func drawPrivacyTrackSizeOptions(in rect: CGRect) {
        let options = PrivacyTrackSize.allCases
        let cellWidth = rect.width / CGFloat(options.count)
        for (index, option) in options.enumerated() {
            let cell = CGRect(
                x: rect.minX + CGFloat(index) * cellWidth,
                y: rect.minY,
                width: cellWidth,
                height: rect.height
            ).insetBy(dx: 3, dy: 4)
            let isSelected = option == currentPrivacyTrackSize
            if isSelected {
                NSColor.systemBlue.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.systemBlue : NSColor.labelColor
            ]
            let size = option.title.size(withAttributes: attributes)
            option.title.draw(
                at: CGPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func drawToolbarIcon(_ icon: String, symbolName: String?, in rect: CGRect, highlighted: Bool) {
        let itemRect = rect.insetBy(dx: 3, dy: 4)
        if highlighted {
            NSColor.systemBlue.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: itemRect, xRadius: 6, yRadius: 6).fill()
        }

        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: icon)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: highlighted ? .semibold : .regular)) {
            let imageRect = CGRect(
                x: rect.midX - image.size.width / 2,
                y: rect.midY - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: highlighted ? 1 : 0.82)
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: icon.count > 1 ? 13 : 17, weight: highlighted ? .semibold : .regular),
            .foregroundColor: highlighted ? NSColor.systemBlue : NSColor.labelColor
        ]
        let size = icon.size(withAttributes: attributes)
        icon.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func toolbarRect(forGlobal rect: CGRect) -> CGRect {
        let screenFrame = screenFrame(containing: rect)
        let width = toolbarWidth(in: screenFrame)
        let height: CGFloat = 38
        let x = min(max(rect.minX, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = rect.minY - height - 8
        if y < screenFrame.minY + 8 {
            y = rect.maxY + 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func toolbarWidth(in rect: CGRect) -> CGFloat {
        min(660, max(430, rect.width - 16))
    }

    private func privacyOptionsBaseRect(forGlobal rect: CGRect) -> CGRect {
        let screenFrame = screenFrame(containing: rect)
        let toolbarRect = toolbarRect(forGlobal: rect)
        let width: CGFloat = 246
        let height: CGFloat = 34
        let x = min(max(toolbarRect.minX, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = toolbarRect.minY - height - 8
        if y < screenFrame.minY + 8 {
            y = toolbarRect.maxY + 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func privacyEffectOptionsRect(forGlobal rect: CGRect) -> CGRect {
        let baseRect = privacyOptionsBaseRect(forGlobal: rect)
        return CGRect(x: baseRect.minX, y: baseRect.minY, width: 136, height: baseRect.height)
    }

    private func privacyTrackSizeOptionsRect(forGlobal rect: CGRect) -> CGRect {
        let baseRect = privacyOptionsBaseRect(forGlobal: rect)
        return CGRect(x: baseRect.minX + 146, y: baseRect.minY, width: 92, height: baseRect.height)
    }

    private func screenFrame(containing rect: CGRect) -> CGRect {
        (NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main)?.frame ?? screenFrame
    }

    private func localPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }

    private var toolbarItems: [(label: String, symbolName: String?, tool: ClipOverlayTool?)] {
        [
            (ClipOverlayTool.move.label, ClipOverlayTool.move.symbolName, .move),
            (ClipOverlayTool.rectangle.label, ClipOverlayTool.rectangle.symbolName, .rectangle),
            (ClipOverlayTool.arrow.label, ClipOverlayTool.arrow.symbolName, .arrow),
            (ClipOverlayTool.pencil.label, ClipOverlayTool.pencil.symbolName, .pencil),
            (ClipOverlayTool.marker.label, ClipOverlayTool.marker.symbolName, .marker),
            (ClipOverlayTool.privacy.label, ClipOverlayTool.privacy.symbolName, .privacy),
            (ClipOverlayTool.text.label, ClipOverlayTool.text.symbolName, .text),
            (ClipOverlayTool.eraser.label, ClipOverlayTool.eraser.symbolName, .eraser),
            ("↶", "arrow.uturn.backward", nil),
            ("↷", "arrow.uturn.forward", nil),
            ("⌫", "trash", nil),
            ("📌", "pin.fill", nil),
            ("⇩", "square.and.arrow.down", nil),
            ("OCR", "text.viewfinder", nil),
            ("×", "xmark", nil),
            ("✓", "checkmark", nil)
        ]
    }

    private func drawAnnotations(hidePrivacyAnnotations: Bool = false) {
        for (index, annotation) in annotations.enumerated() {
            if hidePrivacyAnnotations && isPrivacyAnnotation(annotation) {
                continue
            }
            let overrideText = index == editingTextAnnotationIndex ? editingText : nil
            draw(annotation, overrideText: overrideText)
        }
        if let draftAnnotation, !(hidePrivacyAnnotations && isPrivacyAnnotation(draftAnnotation)) {
            draw(draftAnnotation, overrideText: nil)
        }
    }

    private func isPrivacyAnnotation(_ annotation: ClipOverlayAnnotation) -> Bool {
        annotation.kind == .blur || annotation.kind == .mosaic
    }

    private func drawSelectedAnnotation() {
        guard
            let selectedAnnotationIndex,
            annotations.indices.contains(selectedAnnotationIndex),
            !isPrivacyAnnotation(annotations[selectedAnnotationIndex])
        else {
            return
        }

        let bounds = localRect(annotations[selectedAnnotationIndex].bounds).insetBy(dx: -3, dy: -3)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: bounds)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()

        if canShowAnnotationHandles(annotations[selectedAnnotationIndex]) {
            NSColor.systemBlue.setFill()
            for handle in SelectionResizeHandle.allCases {
                NSBezierPath(ovalIn: handleRect(for: handle, in: bounds)).fill()
            }
        }

        if canShowStylePalette(annotations[selectedAnnotationIndex]) {
            drawStylePalette(for: annotations[selectedAnnotationIndex])
        }
    }

    private func canShowAnnotationHandles(_ annotation: ClipOverlayAnnotation) -> Bool {
        switch annotation.kind {
        case .rectangle, .text:
            return true
        case .arrow, .pencil, .marker, .mosaic, .blur:
            return false
        }
    }

    private func canShowStylePalette(_ annotation: ClipOverlayAnnotation) -> Bool {
        switch annotation.kind {
        case .rectangle, .arrow, .pencil, .marker, .text:
            return true
        case .mosaic, .blur:
            return false
        }
    }

    private func drawStylePalette(for annotation: ClipOverlayAnnotation) {
        let paletteRect = localRect(stylePaletteRect(for: annotation.bounds))
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: paletteRect, xRadius: 9, yRadius: 9).fill()

        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(roundedRect: paletteRect, xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        let colors = AnnotationStyleColor.allCases
        let cellWidth = paletteRect.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            let cell = CGRect(
                x: paletteRect.minX + CGFloat(index) * cellWidth,
                y: paletteRect.minY,
                width: cellWidth,
                height: paletteRect.height
            )
            let dot = CGRect(x: cell.midX - 6, y: cell.midY - 6, width: 12, height: 12)
            color.nsColor.setFill()
            NSBezierPath(ovalIn: dot).fill()

            if color.matches(annotation.style) {
                NSColor.systemBlue.setStroke()
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -4, dy: -4))
                ring.lineWidth = 2
                ring.stroke()
            }
        }
    }

    private func draw(_ annotation: ClipOverlayAnnotation, overrideText: String?) {
        let color = NSColor(
            calibratedRed: annotation.style.red,
            green: annotation.style.green,
            blue: annotation.style.blue,
            alpha: annotation.style.alpha
        )
        color.setStroke()
        color.setFill()

        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: localRect(annotation.rect))
            path.lineWidth = annotation.style.lineWidth
            path.stroke()
        case .arrow:
            stroke(annotation.points, style: annotation.style)
            drawArrowHead(annotation.points, style: annotation.style)
        case .pencil, .marker:
            stroke(annotation.points, style: annotation.style)
        case .mosaic, .blur:
            drawPrivacyFeedback(annotation)
        case .text:
            let rect = localRect(annotation.rect)
            if overrideText != nil {
                drawTextEditingBackground(in: rect)
            }
            drawText(overrideText ?? annotation.text, in: rect, style: annotation.style, isEditing: overrideText != nil)
        }
    }

    private func drawTextEditingBackground(in rect: CGRect) {
        let editRect = rect.insetBy(dx: 2, dy: 2)
        NSColor.textBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: editRect, xRadius: 5, yRadius: 5).fill()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(roundedRect: editRect, xRadius: 5, yRadius: 5)
        border.lineWidth = 1.5
        border.stroke()
    }

    private func stroke(_ points: [CGPoint], style: ClipOverlayAnnotation.Style) {
        guard let first = points.first else {
            return
        }

        let path = NSBezierPath()
        path.move(to: localPoint(fromGlobal: first))
        points.dropFirst().forEach { path.line(to: localPoint(fromGlobal: $0)) }
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawArrowHead(_ points: [CGPoint], style: ClipOverlayAnnotation.Style) {
        guard points.count >= 2, let start = points.first, let end = points.last else {
            return
        }

        let localStart = localPoint(fromGlobal: start)
        let localEnd = localPoint(fromGlobal: end)
        let angle = atan2(localEnd.y - localStart.y, localEnd.x - localStart.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: localEnd.x - length * cos(angle - spread), y: localEnd.y - length * sin(angle - spread))
        let right = CGPoint(x: localEnd.x - length * cos(angle + spread), y: localEnd.y - length * sin(angle + spread))

        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: localEnd)
        path.line(to: right)
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawPrivacyBody(
        _ annotation: ClipOverlayAnnotation,
        color: NSColor,
        lineWidthMultiplier: CGFloat = 1
    ) {
        let path = privacyPath(for: annotation)
        if !annotation.points.isEmpty {
            color.setStroke()
            path.lineWidth = annotation.style.lineWidth * lineWidthMultiplier
            path.stroke()
            return
        }

        color.setFill()
        path.fill()
    }

    private func drawPrivacyFeedback(_ annotation: ClipOverlayAnnotation) {
        drawPrivacyBody(annotation, color: privacyFeedbackColor)
    }

    private var privacyFeedbackColor: NSColor {
        NSColor(calibratedWhite: 0.18, alpha: 0.12)
    }

    private func privacyPath(for annotation: ClipOverlayAnnotation) -> NSBezierPath {
        if !annotation.points.isEmpty {
            if annotation.points.count == 1, let point = annotation.points.first {
                let center = localPoint(fromGlobal: point)
                let radius = max(annotation.style.lineWidth / 2, 6)
                return NSBezierPath(
                    ovalIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
            return strokePath(annotation.points, lineWidth: annotation.style.lineWidth)
        }
        let path = NSBezierPath(roundedRect: localRect(annotation.rect), xRadius: 5, yRadius: 5)
        path.lineWidth = 1
        return path
    }

    private func strokePath(_ points: [CGPoint], lineWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else {
            return path
        }
        path.move(to: localPoint(fromGlobal: first))
        let localPoints = points.map(localPoint(fromGlobal:))
        localPoints.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    private func drawText(_ text: String, in rect: CGRect, style: ClipOverlayAnnotation.Style, isEditing: Bool = false) {
        let displayText = isEditing ? "\(text)|" : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(15, min(30, rect.height * 0.48)), weight: .semibold),
            .foregroundColor: NSColor(
                calibratedRed: style.red,
                green: style.green,
                blue: style.blue,
                alpha: 1
            )
        ]
        displayText.draw(in: rect.insetBy(dx: 6, dy: 6), withAttributes: attributes)
    }

    private func localRect(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        return CGRect(
            x: standardized.minX - screenFrame.minX,
            y: standardized.minY - screenFrame.minY,
            width: standardized.width,
            height: standardized.height
        )
    }

    private func stylePaletteRect(for annotationBounds: CGRect) -> CGRect {
        let width: CGFloat = 116
        let height: CGFloat = 34
        let x = min(max(annotationBounds.midX - width / 2, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        var y = annotationBounds.maxY + 8
        if y + height > screenFrame.maxY - 8 {
            y = annotationBounds.minY - height - 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
