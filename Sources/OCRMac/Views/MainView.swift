import AppKit
import SwiftUI

struct MainView: View {
    private enum MainTab: Hashable {
        case capture
        case jsonFormatter
        case copyHistory
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: MainTab = .capture

    var body: some View {
        TabView(selection: $selectedTab) {
            GeometryReader { proxy in
                ScrollView {
                    captureTabContent(width: proxy.size.width)
                        .padding(28)
                }
            }
            .tabItem {
                Label("Capture OCR", systemImage: "text.viewfinder")
            }
            .tag(MainTab.capture)

            GeometryReader { proxy in
                jsonFormatterSection(width: proxy.size.width, height: proxy.size.height)
                    .padding(28)
            }
            .tabItem {
                Label("JSON Formatter", systemImage: "curlybraces")
            }
            .tag(MainTab.jsonFormatter)

            GeometryReader { proxy in
                ScrollView {
                    copyHistorySection(width: proxy.size.width)
                        .padding(28)
                }
            }
            .tabItem {
                Label("Copy History", systemImage: "clock.arrow.circlepath")
            }
            .tag(MainTab.copyHistory)
        }
    }

    private func captureTabContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Clip OCR")
                    .font(.largeTitle.weight(.bold))
                Text("Capture a screen region or read an image from the clipboard, then extract text on-device with English and Chinese recognition.")
                    .foregroundStyle(.secondary)

                Label("Global clip shortcut: \(viewModel.clipShortcutDisplay)", systemImage: "keyboard")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if width > 820 {
                HStack(spacing: 16) {
                    captureActionCards
                }
            } else {
                VStack(spacing: 16) {
                    captureActionCards
                }
            }

            if let errorMessage = viewModel.lastErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Current status")
                    .font(.headline)

                if viewModel.isProcessing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Processing image…")
                    }
                } else if let result = viewModel.result {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last result: \(result.source.rawValue)")
                            .fontWeight(.medium)
                        Text(result.isEmpty ? "No text detected" : result.text)
                            .lineLimit(4)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose a capture source to begin.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureActionCards: some View {
        Group {
            actionCard(
                title: "Clip Screen",
                subtitle: "Drag across one or more displays to select an area and extract text from it.",
                systemImage: "selection.pin.in.out",
                action: { viewModel.runScreenClipOCR() }
            )

            actionCard(
                title: "Read Clipboard Image",
                subtitle: "Use the current clipboard image as the OCR source.",
                systemImage: "doc.on.clipboard",
                action: viewModel.runClipboardOCR
            )
        }
    }

    @ViewBuilder
    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
        .keyboardShortcut(
            title == "Clip Screen" ? KeyEquivalent("c") : KeyEquivalent("v"),
            modifiers: title == "Clip Screen" ? [.command, .option, .control] : [.command, .shift]
        )
    }

    private func jsonFormatterSection(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            formatterHeader

            if let errorMessage = viewModel.jsonFormatterErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let statusMessage = viewModel.jsonFormatterStatusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            formatterEditors(width: width)
                .layoutPriority(1)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 420), maxHeight: .infinity, alignment: .leading)
    }

    private func copyHistorySection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if width > 780 {
                    HStack(alignment: .top) {
                        copyHistoryHeader
                        Spacer()
                        copyHistoryActions
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        copyHistoryHeader
                        copyHistoryActions
                    }
                }
            }

            if viewModel.copyHistoryItems.isEmpty {
                ContentUnavailableView(
                    "No copy history yet",
                    systemImage: "clock.badge.xmark",
                    description: Text("Copied OCR text and formatted JSON will appear here for quick reuse.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if width > 980 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    copyHistoryCards
                }
            } else {
                VStack(spacing: 16) {
                    copyHistoryCards
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copyHistoryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copy History")
                .font(.largeTitle.weight(.bold))
            Text("Quickly revisit copied OCR text and formatted JSON. Re-copy items instantly or remove entries you no longer need.")
                .foregroundStyle(.secondary)
        }
    }

    private var copyHistoryActions: some View {
        HStack {
            Label("\(viewModel.copyHistoryItems.count) item\(viewModel.copyHistoryItems.count == 1 ? "" : "s")", systemImage: "tray.full")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Clear All", role: .destructive) {
                viewModel.clearCopyHistory()
            }
            .disabled(viewModel.copyHistoryItems.isEmpty)
        }
    }

    private var copyHistoryCards: some View {
        ForEach(viewModel.copyHistoryItems) { item in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.title, systemImage: item.kind == .ocr ? "text.viewfinder" : "curlybraces")
                            .font(.headline)

                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(item.kind.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(item.kind == .ocr ? Color.accentColor.opacity(0.12) : Color.green.opacity(0.12), in: Capsule())
                }

                Text(item.preview.isEmpty ? "(Empty content)" : item.preview)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Button("Copy Again") {
                        viewModel.copyHistoryItem(item)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Delete", role: .destructive) {
                        viewModel.deleteCopyHistoryItem(item)
                    }
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.72), Color.white.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.38))
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        }
    }

    private var formatterHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JSON Formatter")
                .font(.title3.weight(.semibold))
            Text("Use two independent JSONEditor panes for validating, formatting, repairing, compacting, and copying JSON.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func formatterEditors(width: CGFloat) -> some View {
        GeometryReader { proxy in
            if width > 860 {
                HStack(alignment: .top, spacing: 14) {
                    jsonLeftEditorPanel
                    jsonRightEditorPanel
                }
                .frame(maxWidth: .infinity, maxHeight: proxy.size.height)
            } else {
                let editorHeight = max((proxy.size.height - 14) / 2, 220)
                VStack(alignment: .leading, spacing: 14) {
                    jsonLeftEditorPanel
                        .frame(height: editorHeight)
                    jsonRightEditorPanel
                        .frame(height: editorHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jsonLeftBinding: Binding<String> {
        Binding(
            get: { viewModel.jsonInput },
            set: { viewModel.updateLeftJSONText($0) }
        )
    }

    private var jsonRightBinding: Binding<String> {
        Binding(
            get: { viewModel.formattedJSON },
            set: { viewModel.updateRightJSONText($0) }
        )
    }

    private var jsonLeftEditorPanel: some View {
        jsonEditorPanel(
            title: "Left",
            text: jsonLeftBinding,
            mode: "code",
            actions: {
                Button(action: viewModel.pasteJSONIntoLeftEditor) {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste into left editor")

                Button(action: viewModel.validateLeftJSON) {
                    Image(systemName: "checkmark.seal")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Validate left editor")

                Button(action: viewModel.formatLeftJSON) {
                    Image(systemName: "text.alignleft")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Format left editor")

                Button(action: viewModel.repairLeftJSON) {
                    Image(systemName: "wand.and.stars")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Repair left editor")

                Button(action: viewModel.compactLeftJSON) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Compact left editor")

                Button(action: viewModel.copyLeftJSONToRight) {
                    Image(systemName: "arrow.right")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Copy left editor to right editor")

                Button(action: viewModel.copyLeftJSON) {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Copy left editor")

                Button(role: .destructive, action: viewModel.clearJSONInput) {
                    Image(systemName: "trash")
                }
                .disabled(!viewModel.hasLeftJSONText)
                .help("Clear left editor")
            }
        )
    }

    private var jsonRightEditorPanel: some View {
        jsonEditorPanel(
            title: "Right",
            text: jsonRightBinding,
            mode: "tree",
            actions: {
                Button(action: viewModel.pasteJSONIntoRightEditor) {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste into right editor")

                Button(action: viewModel.validateRightJSON) {
                    Image(systemName: "checkmark.seal")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Validate right editor")

                Button(action: viewModel.formatRightJSON) {
                    Image(systemName: "text.alignleft")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Format right editor")

                Button(action: viewModel.repairRightJSON) {
                    Image(systemName: "wand.and.stars")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Repair right editor")

                Button(action: viewModel.compactRightJSON) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Compact right editor")

                Button(action: viewModel.copyRightJSONToLeft) {
                    Image(systemName: "arrow.left")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Copy right editor to left editor")

                Button(action: viewModel.copyRightJSON) {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Copy right editor")

                Button(role: .destructive, action: viewModel.clearFormattedJSON) {
                    Image(systemName: "trash")
                }
                .disabled(!viewModel.hasRightJSONText)
                .help("Clear right editor")
            }
        )
    }

    private func jsonEditorPanel<Actions: View>(
        title: String,
        text: Binding<String>,
        mode: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    actions()
                }
                .buttonStyle(.bordered)
                Text("\(text.wrappedValue.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JSONEditorWebView(
                text: text,
                errorMessage: $viewModel.jsonFormatterErrorMessage,
                mode: mode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
