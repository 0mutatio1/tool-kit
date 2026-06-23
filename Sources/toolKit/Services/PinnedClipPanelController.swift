import AppKit
import SwiftUI

@MainActor
final class PinnedClipPanelController: NSObject {
    private var panels: [ClipUtilityPanel] = []

    func pin(image: NSImage, near rect: CGRect, onOCR: @escaping (NSImage, CGRect) -> Void) {
        let size = panelSize(for: image)
        let state = PinnedClipState()
        let panel = ClipUtilityPanel(
            contentRect: panelFrame(size: size, near: rect),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.baseSize = size
        panel.state = state
        panel.onSelect = { [weak self, weak panel] in
            guard let panel else {
                return
            }
            self?.select(panel)
        }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let hostingView = NSHostingView(rootView: PinnedClipView(
            image: image,
            state: state,
            onClose: { [weak panel] in
                panel?.close()
            },
            onOCR: { [weak panel, weak self] in
                self?.select(panel)
                onOCR(image, panel?.frame ?? rect)
            },
            onCopy: {
                ClipboardImageService().writeImage(image)
            },
            onSave: {
                Self.save(image)
            }
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.contentsScale = max(imageScale(for: image), panel.screen?.backingScaleFactor ?? 1)
        panel.contentView = hostingView

        panels.append(panel)
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel) { [weak panel] in
            panel?.close()
        }
        panel.orderFrontRegardless()
    }

    private func panelSize(for image: NSImage) -> CGSize {
        CGSize(
            width: max(image.size.width, 1),
            height: max(image.size.height, 1)
        )
    }

    private func imageScale(for image: NSImage) -> CGFloat {
        let widthScale = image.representations
            .map { CGFloat($0.pixelsWide) / max(image.size.width, 1) }
            .max() ?? 1
        let heightScale = image.representations
            .map { CGFloat($0.pixelsHigh) / max(image.size.height, 1) }
            .max() ?? 1
        return max(widthScale, heightScale, 1)
    }

    private func select(_ selectedPanel: ClipUtilityPanel?) {
        panels.forEach { panel in
            panel.state?.isSelected = panel === selectedPanel
        }
    }

    private static func save(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Pinned Clip.png"
        guard panel.runModal() == .OK, let url = panel.url, let data = pngData(for: image) else {
            return
        }
        try? data.write(to: url)
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension PinnedClipPanelController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }
        ClipOverlayInteractionRegistry.shared.removeIgnoredFrame(for: panel)
        panels.removeAll { $0 === panel }
    }
}

private final class PinnedClipState: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var isSelected = false
    @Published var isHovering = false
}

private struct PinnedClipView: View {
    let image: NSImage
    @ObservedObject var state: PinnedClipState
    let onClose: () -> Void
    let onOCR: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFill()
                .frame(width: imageWidth, height: imageHeight)
                .clipped()
                .background(Color(nsColor: .textBackgroundColor))

            if state.isHovering || state.isSelected {
                HStack(spacing: 6) {
                    Button(action: onOCR) {
                        Image(systemName: "text.viewfinder")
                    }
                    .help("Run OCR")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .help("Close pinned clip")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.isSelected ? Color.accentColor : Color.accentColor.opacity(0.55), lineWidth: state.isSelected ? 3 : 1)
        )
        .onHover { state.isHovering = $0 }
        .contextMenu {
            Button("Copy Image", action: onCopy)
            Button("Save as PNG", action: onSave)
            Button("OCR", action: onOCR)
            Divider()
            Button("Close", action: onClose)
        }
        .frame(
            width: imageWidth,
            height: imageHeight
        )
    }

    private var imageWidth: CGFloat {
        max(image.size.width * state.zoom, 1)
    }

    private var imageHeight: CGFloat {
        max(image.size.height * state.zoom, 1)
    }
}

private final class ClipUtilityPanel: NSPanel {
    private var dragStartMouseLocation: CGPoint?
    private var dragStartFrame: CGRect?
    var baseSize: CGSize = .zero
    var state: PinnedClipState?
    var onSelect: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        orderFrontRegardless()
        ClipOverlayInteractionRegistry.shared.select(self)
        onSelect?()
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(frame, for: self)
        if controlsRect.contains(event.locationInWindow) {
            super.mouseDown(with: event)
            return
        }

        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartFrame = frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartMouseLocation, let dragStartFrame else {
            super.mouseDragged(with: event)
            return
        }

        let currentLocation = NSEvent.mouseLocation
        setFrameOrigin(CGPoint(
            x: dragStartFrame.minX + currentLocation.x - dragStartMouseLocation.x,
            y: dragStartFrame.minY + currentLocation.y - dragStartMouseLocation.y
        ))
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(frame, for: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouseLocation = nil
        dragStartFrame = nil
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(frame, for: self)
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
            zoom(by: 1.12)
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "-" {
            zoom(by: 1 / 1.12)
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "0" {
            setZoom(1)
            return
        }

        super.keyDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification)
    }

    private func zoom(by multiplier: CGFloat) {
        setZoom((state?.zoom ?? 1) * multiplier)
    }

    private func setZoom(_ zoom: CGFloat) {
        guard let state else {
            return
        }
        state.zoom = min(max(zoom, 0.35), 4)
        let newSize = CGSize(width: baseSize.width * state.zoom, height: baseSize.height * state.zoom)
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        setFrame(CGRect(x: topLeft.x, y: topLeft.y - newSize.height, width: newSize.width, height: newSize.height), display: true)
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(frame, for: self)
    }

    private var controlsRect: CGRect {
        CGRect(x: frame.width - 112, y: frame.height - 58, width: 112, height: 58)
    }
}

@MainActor
func panelFrame(size: CGSize, near rect: CGRect) -> CGRect {
    let screen = NSScreen.screens.first { $0.frame.intersects(rect) }
        ?? NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        ?? NSScreen.main
    guard let screen else {
        return CGRect(origin: CGPoint(x: rect.maxX + 10, y: rect.minY), size: size)
    }

    let visibleFrame = screen.visibleFrame
    let gap: CGFloat = 10
    var origin = CGPoint(x: rect.maxX + gap, y: rect.maxY - size.height)

    if origin.x + size.width > visibleFrame.maxX {
        origin.x = rect.minX - size.width - gap
    }
    if origin.x < visibleFrame.minX {
        origin.x = min(max(rect.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
    }
    if origin.y < visibleFrame.minY {
        origin.y = min(rect.maxY + gap, visibleFrame.maxY - size.height)
    }
    if origin.y + size.height > visibleFrame.maxY {
        origin.y = visibleFrame.maxY - size.height
    }

    origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - size.width))
    origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - size.height))
    return CGRect(origin: origin, size: size)
}
