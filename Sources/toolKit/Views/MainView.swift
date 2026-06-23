import AppKit
import SwiftUI

struct MainView: View {
    private enum CopyHistoryFilter: String, CaseIterable, Identifiable {
        case all
        case ocr
        case json
        case clipboard
        case image

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .ocr: return "OCR"
            case .json: return "JSON"
            case .clipboard: return "Clipboard"
            case .image: return "Image"
            }
        }
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var isNavigationCollapsed = false
    @State private var hoveredNavigationTab: MainTab?
    @State private var copyHistorySearchText = ""
    @State private var copyHistoryFilter: CopyHistoryFilter = .all
    @State private var selectedCopyHistoryItemID: CopyHistoryItem.ID?

    var body: some View {
        GeometryReader { rootProxy in
            let isCompactWindow = rootProxy.size.width < 900
            let sidebarWidth: CGFloat = isNavigationCollapsed ? 68 : (isCompactWindow ? 176 : 220)
            let contentPadding: CGFloat = isCompactWindow ? 16 : 28

            HStack(spacing: 0) {
                navigationSidebar
                    .frame(width: sidebarWidth)

                Divider()

                GeometryReader { proxy in
                    selectedTabContent(width: proxy.size.width, height: proxy.size.height)
                        .padding(contentPadding)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .animation(.easeInOut(duration: 0.18), value: isNavigationCollapsed)
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if !isNavigationCollapsed {
                    Text("ToolKit")
                        .font(.headline)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isNavigationCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isNavigationCollapsed ? "sidebar.left" : "sidebar.leading")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(isNavigationCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .padding(.horizontal, isNavigationCollapsed ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: isNavigationCollapsed ? .center : .leading)
            .frame(height: 34)

            VStack(spacing: 6) {
                ForEach(MainTab.allCases) { tab in
                    sidebarTabButton(tab)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func sidebarTabButton(_ tab: MainTab) -> some View {
        let isSelected = viewModel.selectedMainTab == tab
        let isHovered = hoveredNavigationTab == tab

        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                viewModel.selectedMainTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22)

                if !isNavigationCollapsed {
                    Text(tab.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, isNavigationCollapsed ? 0 : 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: isNavigationCollapsed ? .center : .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                sidebarTabBackground(isSelected: isSelected, isHovered: isHovered),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { isHovering in
            hoveredNavigationTab = isHovering ? tab : (hoveredNavigationTab == tab ? nil : hoveredNavigationTab)
        }
    }

    private func sidebarTabBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    @ViewBuilder
    private func selectedTabContent(width: CGFloat, height: CGFloat) -> some View {
        switch viewModel.selectedMainTab {
        case .capture:
            captureTabContent(width: width, height: height)
        case .jsonFormatter:
            jsonFormatterSection(width: width, height: height)
        case .cron:
            cronSection(width: width, height: height)
        case .diff:
            diffSection(width: width, height: height)
        case .copyHistory:
            copyHistorySection(width: width, height: height)
        case .settings:
            settingsSection(width: width, height: height)
        }
    }

    private func captureTabContent(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Clip OCR")
                    .font(.largeTitle.weight(.bold))
                Text("Capture or annotate a screen region, copy or pin it as an image, or run on-device OCR with English and Chinese recognition.")
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
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .leading)
    }

    private var captureActionCards: some View {
        actionCard(
            title: "Clip Screen",
            subtitle: "Drag across one or more displays, adjust or annotate the area, then capture, pin, or OCR it.",
            systemImage: "selection.pin.in.out",
            action: { viewModel.runScreenClipOCR() }
        )
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
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .leading)
    }

    private func cronSection(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cronHeader

            if let errorMessage = viewModel.cronErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let statusMessage = viewModel.cronStatusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if width > 900 {
                HStack(alignment: .top, spacing: 14) {
                    cronGeneratorPanel
                        .frame(width: min(max(width * 0.36, 320), 430))
                    cronDecoderPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    cronGeneratorPanel
                    cronDecoderPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .leading)
    }

    private var cronHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cron")
                .font(.largeTitle.weight(.bold))
            Text("Generate cron expressions, decode existing schedules, and preview upcoming execution times.")
                .foregroundStyle(.secondary)
        }
    }

    private var cronGeneratorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate")
                .font(.title3.weight(.semibold))

            cronSchedulePicker

            switch viewModel.cronGeneratorMode {
            case .everyNMinutes:
                cronStepper("Every", value: $viewModel.cronIntervalMinutes, range: 1...59, suffix: "minutes")
            case .hourly:
                cronStepper("Minute", value: $viewModel.cronMinute, range: 0...59)
            case .daily:
                cronStepper("Hour", value: $viewModel.cronHour, range: 0...23)
                cronStepper("Minute", value: $viewModel.cronMinute, range: 0...59)
            case .weekly:
                Picker("Weekday", selection: $viewModel.cronWeekday) {
                    ForEach(Array(cronWeekdays.enumerated()), id: \.offset) { index, day in
                        Text(day).tag(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                cronStepper("Hour", value: $viewModel.cronHour, range: 0...23)
                cronStepper("Minute", value: $viewModel.cronMinute, range: 0...59)
            case .monthly:
                cronStepper("Day", value: $viewModel.cronDayOfMonth, range: 1...31)
                cronStepper("Hour", value: $viewModel.cronHour, range: 0...23)
                cronStepper("Minute", value: $viewModel.cronMinute, range: 0...59)
            }

            Button {
                viewModel.generateCronExpression()
            } label: {
                Label("Generate Expression", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Generated schedules use standard 5-field cron: minute, hour, day of month, month, day of week.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private var cronSchedulePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(CronGeneratorMode.allCases) { mode in
                cronScheduleButton(mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cronScheduleButton(_ mode: CronGeneratorMode) -> some View {
        let isSelected = viewModel.cronGeneratorMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                viewModel.cronGeneratorMode = mode
            }
        } label: {
            Text(mode.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.14))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(mode.title)
    }

    private var cronDecoderPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Decode")
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                TextField("*/15 * * * *", text: cronExpressionBinding)
                    .font(.system(.title3, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.explainCronExpression()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .help("Explain cron expression")
                .disabled(!viewModel.hasCronExpression)

                Button {
                    viewModel.copyCronExpression()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy cron expression")
                .disabled(!viewModel.hasCronExpression)
            }
            .buttonStyle(.bordered)

            if viewModel.cronExplanationSummary.isEmpty {
                ContentUnavailableView(
                    "No cron explanation",
                    systemImage: "calendar.badge.clock",
                    description: Text("Enter or generate a cron expression to see its meaning and upcoming run times.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.cronExplanationSummary)
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.cronExplanationDetails, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text("Upcoming Runs")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.cronTimeline, id: \.self) { date in
                                HStack(spacing: 10) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.tint)
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text(relativeCronDate(date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private var cronExpressionBinding: Binding<String> {
        Binding(
            get: { viewModel.cronExpression },
            set: { viewModel.updateCronExpression($0) }
        )
    }

    private func cronStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String? = nil) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)\(suffix.map { " \($0)" } ?? "")")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cronWeekdays: [String] {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }

    private func relativeCronDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    private func diffSection(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            diffHeader

            if let errorMessage = viewModel.diffErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let statusMessage = viewModel.diffStatusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if width > 900 {
                HStack(alignment: .top, spacing: 14) {
                    diffEditorPanel(
                        title: "Left",
                        text: diffLeftBinding,
                        pasteAction: viewModel.pasteDiffLeftFromClipboard
                    )
                    diffEditorPanel(
                        title: "Right",
                        text: diffRightBinding,
                        pasteAction: viewModel.pasteDiffRightFromClipboard
                    )
                }
                .frame(height: max((height - 210) * 0.36, 220))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    diffEditorPanel(
                        title: "Left",
                        text: diffLeftBinding,
                        pasteAction: viewModel.pasteDiffLeftFromClipboard
                    )
                    diffEditorPanel(
                        title: "Right",
                        text: diffRightBinding,
                        pasteAction: viewModel.pasteDiffRightFromClipboard
                    )
                }
                .frame(height: max((height - 210) * 0.48, 300))
            }

            diffToolbar
            diffResultPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .leading)
    }

    private var diffHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diff")
                .font(.largeTitle.weight(.bold))
            Text("Compare two text blocks side-by-side and highlight inserted, deleted, and changed parts.")
                .foregroundStyle(.secondary)
        }
    }

    private var diffLeftBinding: Binding<String> {
        Binding(
            get: { viewModel.diffLeftText },
            set: { viewModel.updateDiffLeftText($0) }
        )
    }

    private var diffRightBinding: Binding<String> {
        Binding(
            get: { viewModel.diffRightText },
            set: { viewModel.updateDiffRightText($0) }
        )
    }

    private func diffEditorPanel(
        title: String,
        text: Binding<String>,
        pasteAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: pasteAction) {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste into \(title.lowercased()) side")
                Text("\(text.wrappedValue.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14))
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private var diffToolbar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.compareDiffText()
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.hasDiffText)

            Button {
                viewModel.swapDiffText()
            } label: {
                Label("Swap", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!viewModel.hasDiffText)

            Button {
                viewModel.copyDiffSummary()
            } label: {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.diffRows.isEmpty)

            Spacer()

            diffSummaryBadge("Added", value: viewModel.diffSummary.added, color: .green)
            diffSummaryBadge("Deleted", value: viewModel.diffSummary.deleted, color: .red)
            diffSummaryBadge("Changed", value: viewModel.diffSummary.changed, color: .orange)

            Button(role: .destructive) {
                viewModel.clearDiffText()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!viewModel.hasDiffText && viewModel.diffRows.isEmpty)
        }
        .buttonStyle(.bordered)
    }

    private func diffSummaryBadge(_ title: String, value: Int, color: Color) -> some View {
        Text("\(title): \(value)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var diffResultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Result")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.diffRows.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.diffRows.isEmpty {
                ContentUnavailableView(
                    "No diff yet",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Paste or type text on both sides, then compare.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.diffRows) { row in
                            diffRow(row)
                            if row.id != viewModel.diffRows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private func diffRow(_ row: TextDiffRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            diffCell(
                lineNumber: row.leftLineNumber,
                parts: row.left,
                side: .left,
                kind: row.kind
            )
            Divider()
            diffCell(
                lineNumber: row.rightLineNumber,
                parts: row.right,
                side: .right,
                kind: row.kind
            )
        }
        .background(diffRowBackground(row.kind))
    }

    private enum DiffSide {
        case left
        case right
    }

    private func diffCell(
        lineNumber: Int?,
        parts: TextDiffRow.Parts?,
        side: DiffSide,
        kind: TextDiffRow.Kind
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            highlightedDiffText(parts, side: side, kind: kind)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func highlightedDiffText(
        _ parts: TextDiffRow.Parts?,
        side: DiffSide,
        kind: TextDiffRow.Kind
    ) -> Text {
        guard let parts else {
            return Text("")
        }

        let highlightColor = diffHighlightColor(side: side, kind: kind)
        return Text(parts.prefix)
            + Text(parts.highlighted).foregroundStyle(highlightColor).bold()
            + Text(parts.suffix)
    }

    private func diffHighlightColor(side: DiffSide, kind: TextDiffRow.Kind) -> Color {
        switch kind {
        case .equal:
            return .primary
        case .inserted:
            return .green
        case .deleted:
            return .red
        case .changed:
            return side == .left ? .orange : .blue
        }
    }

    private func diffRowBackground(_ kind: TextDiffRow.Kind) -> Color {
        switch kind {
        case .equal:
            return .clear
        case .inserted:
            return .green.opacity(0.08)
        case .deleted:
            return .red.opacity(0.08)
        case .changed:
            return .orange.opacity(0.08)
        }
    }

    private func copyHistorySection(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
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

            if viewModel.copyHistoryItems.isEmpty {
                ContentUnavailableView(
                    "No copy history yet",
                    systemImage: "clock.badge.xmark",
                    description: Text("Copied OCR text and formatted JSON will appear here for quick reuse.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                copyHistoryTools(width: width)

                if filteredCopyHistoryItems.isEmpty {
                    ContentUnavailableView(
                        "No matching history",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or filter.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if width > 980 {
                    HStack(alignment: .top, spacing: 16) {
                        copyHistoryList
                            .frame(width: min(max(width * 0.38, 340), 460))
                        copyHistoryDetail
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        copyHistoryList
                            .frame(height: max((height - 210) * 0.46, 220))
                        copyHistoryDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .leading)
    }

    private var copyHistoryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copy History")
                .font(.largeTitle.weight(.bold))
            Text("Automatically records copied text and images while monitoring is on, plus OCR and JSON copies for quick reuse.")
                .foregroundStyle(.secondary)
        }
    }

    private var copyHistoryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                copyHistoryMonitoringControls
                copyHistoryClearControls
            }

            VStack(alignment: .leading, spacing: 10) {
                copyHistoryMonitoringControls
                copyHistoryClearControls
            }
        }
    }

    private var copyHistoryMonitoringControls: some View {
        HStack(spacing: 10) {
            Label(
                viewModel.settings.clipboardMonitoringEnabled ? "Monitoring on" : "Monitoring paused",
                systemImage: viewModel.settings.clipboardMonitoringEnabled ? "record.circle" : "pause.circle"
            )
            .font(.callout)
            .foregroundStyle(viewModel.settings.clipboardMonitoringEnabled ? .green : .secondary)

            Button {
                viewModel.toggleClipboardMonitoring()
            } label: {
                Label(
                    viewModel.settings.clipboardMonitoringEnabled ? "Pause" : "Resume",
                    systemImage: viewModel.settings.clipboardMonitoringEnabled ? "pause.fill" : "play.fill"
                )
            }
        }
    }

    private var copyHistoryClearControls: some View {
        HStack(spacing: 10) {
            Label(copyHistoryCountLabel, systemImage: "tray.full")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                viewModel.clearCopyHistory()
                selectedCopyHistoryItemID = nil
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(viewModel.copyHistoryItems.isEmpty)
        }
    }

    @ViewBuilder
    private func copyHistoryTools(width: CGFloat) -> some View {
        if width > 760 {
            HStack(spacing: 12) {
                copyHistorySearchField
                copyHistoryFilterPicker
                    .frame(width: min(420, max(width * 0.44, 320)))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                copyHistorySearchField
                copyHistoryFilterPicker
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var copyHistorySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $copyHistorySearchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18))
        )
    }

    private var copyHistoryFilterPicker: some View {
        Picker("Type", selection: $copyHistoryFilter) {
            ForEach(CopyHistoryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var copyHistoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredCopyHistoryItems) { item in
                    copyHistoryRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCopyHistoryItemID = item.id
                        }
                        .contextMenu {
                            copyHistoryItemMenu(item)
                        }

                    if item.id != filteredCopyHistoryItems.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private func copyHistoryRow(_ item: CopyHistoryItem) -> some View {
        let isSelected = item.id == effectiveSelectedCopyHistoryItem?.id
        return HStack(alignment: .top, spacing: 12) {
            copyHistoryRowIcon(item)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Text(item.kind.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(item.preview.isEmpty ? "(Empty content)" : item.preview)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(copyHistoryMetadata(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private var copyHistoryDetail: some View {
        if let item = effectiveSelectedCopyHistoryItem {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.title, systemImage: copyHistoryIcon(for: item.kind))
                            .font(.title3.weight(.semibold))
                        Text(item.createdAt.formatted(date: .complete, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    copyHistoryKindBadge(item.kind)
                }

                HStack(spacing: 10) {
                    if item.kind == .image {
                        Label(item.content, systemImage: "photo")
                    } else {
                        Label("\(item.content.count) chars", systemImage: "character.cursor.ibeam")
                        Label("\(lineCount(for: item.content)) lines", systemImage: "text.alignleft")
                    }
                    if item.kind == .json {
                        Label(jsonSummary(for: item.content), systemImage: "curlybraces")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                copyHistoryPreview(item)

                HStack {
                    Button {
                        viewModel.copyHistoryItem(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)

                    if item.kind == .image {
                        Button {
                            viewModel.runCopyHistoryImageOCR(item)
                        } label: {
                            Label("OCR", systemImage: "text.viewfinder")
                        }
                        .disabled(item.imageData == nil || viewModel.isProcessing)
                    }

                    if item.kind == .json {
                        Button {
                            viewModel.useHistoryItemInLeftJSON(item)
                        } label: {
                            Label("Use Left", systemImage: "arrow.left.to.line")
                        }

                        Button {
                            viewModel.useHistoryItemInRightJSON(item)
                        } label: {
                            Label("Use Right", systemImage: "arrow.right.to.line")
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        deleteCopyHistoryItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.14))
            )
        }
    }

    private func copyHistoryKindBadge(_ kind: CopyHistoryItem.Kind) -> some View {
        Text(kind.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(copyHistoryColor(for: kind))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(copyHistoryColor(for: kind).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func copyHistoryRowIcon(_ item: CopyHistoryItem) -> some View {
        if item.kind == .image,
           let imageData = item.imageData,
           let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18))
                )
        } else {
            Image(systemName: copyHistoryIcon(for: item.kind))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(copyHistoryColor(for: item.kind))
                .frame(width: 30, height: 30)
                .background(copyHistoryColor(for: item.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private func copyHistoryPreview(_ item: CopyHistoryItem) -> some View {
        if item.kind == .image,
           let imageData = item.imageData,
           let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14))
                )
        } else {
            ScrollView {
                Text(item.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.14))
            )
        }
    }

    @ViewBuilder
    private func copyHistoryItemMenu(_ item: CopyHistoryItem) -> some View {
        Button("Copy") {
            viewModel.copyHistoryItem(item)
        }
        if item.kind == .json {
            Button("Use in Left JSON Editor") {
                viewModel.useHistoryItemInLeftJSON(item)
            }
            Button("Use in Right JSON Editor") {
                viewModel.useHistoryItemInRightJSON(item)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            deleteCopyHistoryItem(item)
        }
    }

    private func deleteCopyHistoryItem(_ item: CopyHistoryItem) {
        viewModel.deleteCopyHistoryItem(item)
        if selectedCopyHistoryItemID == item.id {
            selectedCopyHistoryItemID = nil
        }
    }

    private var filteredCopyHistoryItems: [CopyHistoryItem] {
        let query = copyHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.copyHistoryItems.filter { item in
            let matchesFilter: Bool
            switch copyHistoryFilter {
            case .all:
                matchesFilter = true
            case .ocr:
                matchesFilter = item.kind == .ocr
            case .json:
                matchesFilter = item.kind == .json
            case .clipboard:
                matchesFilter = item.kind == .clipboard
            case .image:
                matchesFilter = item.kind == .image
            }

            guard matchesFilter else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }

            return item.content.lowercased().contains(query)
                || item.title.lowercased().contains(query)
                || item.kind.rawValue.lowercased().contains(query)
        }
    }

    private var effectiveSelectedCopyHistoryItem: CopyHistoryItem? {
        if let selectedCopyHistoryItemID,
           let selected = filteredCopyHistoryItems.first(where: { $0.id == selectedCopyHistoryItemID }) {
            return selected
        }
        return filteredCopyHistoryItems.first
    }

    private var copyHistoryCountLabel: String {
        let total = viewModel.copyHistoryItems.count
        let filtered = filteredCopyHistoryItems.count
        if filtered == total {
            return "\(total) item\(total == 1 ? "" : "s")"
        }
        return "\(filtered) of \(total)"
    }

    private func lineCount(for text: String) -> Int {
        max(text.split(whereSeparator: \.isNewline).count, text.isEmpty ? 0 : 1)
    }

    private func jsonSummary(for text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return "JSON text"
        }
        if let dictionary = object as? [String: Any] {
            return "\(dictionary.count) keys"
        }
        if let array = object as? [Any] {
            return "\(array.count) items"
        }
        return "JSON value"
    }

    private func copyHistoryIcon(for kind: CopyHistoryItem.Kind) -> String {
        switch kind {
        case .ocr:
            return "text.viewfinder"
        case .json:
            return "curlybraces"
        case .clipboard:
            return "doc.on.clipboard"
        case .image:
            return "photo"
        }
    }

    private func copyHistoryColor(for kind: CopyHistoryItem.Kind) -> Color {
        switch kind {
        case .ocr:
            return .accentColor
        case .json:
            return .green
        case .clipboard:
            return .orange
        case .image:
            return .pink
        }
    }

    private func copyHistoryMetadata(for item: CopyHistoryItem) -> String {
        if item.kind == .image {
            return "\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.content)"
        }

        return "\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.content.count) chars · \(lineCount(for: item.content)) lines"
    }

    private func settingsSection(width: CGFloat, height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader

                if let errorMessage = viewModel.settingsErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let statusMessage = viewModel.settingsStatusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if width > 940 {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            settingsLifecyclePanel
                            settingsCapturePanel
                        }
                        VStack(spacing: 16) {
                            settingsClipboardPanel
                            settingsOCRPanel
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        settingsLifecyclePanel
                        settingsClipboardPanel
                        settingsCapturePanel
                        settingsOCRPanel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: max(height - 56, 360), maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.largeTitle.weight(.bold))
            Text("Tune ToolKit behavior for menu bar use, clipboard privacy, clip saving, history size, and OCR language priority.")
                .foregroundStyle(.secondary)
        }
    }

    private var settingsLifecyclePanel: some View {
        settingsPanel(
            title: "App",
            subtitle: "Control launch and close behavior.",
            systemImage: "macwindow"
        ) {
            Toggle(isOn: launchAtLoginBinding) {
                settingsToggleText(
                    title: "Launch at login",
                    subtitle: "Start OCRMac automatically when you sign in."
                )
            }
            .toggleStyle(.switch)

            Toggle(isOn: hideToMenuBarBinding) {
                settingsToggleText(
                    title: "Hide to menu bar after close",
                    subtitle: "Keep the menu bar icon and global hotkey alive after closing the main window."
                )
            }
            .toggleStyle(.switch)
        }
    }

    private var settingsClipboardPanel: some View {
        settingsPanel(
            title: "Clipboard",
            subtitle: "Pause monitoring for private work and keep history bounded.",
            systemImage: "doc.on.clipboard"
        ) {
            Toggle(isOn: clipboardMonitoringBinding) {
                settingsToggleText(
                    title: viewModel.settings.clipboardMonitoringEnabled ? "Monitoring enabled" : "Monitoring paused",
                    subtitle: "When paused, external text and image clipboard changes are not recorded."
                )
            }
            .toggleStyle(.switch)

            Stepper(value: copyHistoryLimitBinding, in: 25...500, step: 25) {
                settingsValueText(
                    title: "Copy history retention",
                    value: "\(viewModel.settings.copyHistoryLimit) items"
                )
            }

            Stepper(value: imageHistoryMaxSizeBinding, in: 1...100, step: 1) {
                settingsValueText(
                    title: "Image history max size",
                    value: "\(viewModel.settings.imageHistoryMaxSizeMB) MB"
                )
            }
        }
    }

    private var settingsCapturePanel: some View {
        settingsPanel(
            title: "Clip",
            subtitle: "Choose where saved PNG captures start.",
            systemImage: "selection.pin.in.out"
        ) {
            Picker("Default save location", selection: defaultSaveLocationBinding) {
                ForEach(SaveLocation.allCases) { location in
                    Label(location.title, systemImage: location.systemImage)
                        .tag(location)
                }
            }
            .pickerStyle(.menu)

            Label("Save still opens a save panel so you can rename or choose another folder.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsOCRPanel: some View {
        settingsPanel(
            title: "OCR",
            subtitle: "Set the language priority used by screen clips, pinned images, and history image OCR.",
            systemImage: "text.viewfinder"
        ) {
            Picker("Language mode", selection: ocrLanguageModeBinding) {
                ForEach(OCRLanguageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.settings.ocrLanguageMode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsPanel<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        )
    }

    private func settingsToggleText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsValueText(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.launchAtLoginEnabled },
            set: { viewModel.setLaunchAtLoginEnabled($0) }
        )
    }

    private var hideToMenuBarBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.hideToMenuBarAfterClose },
            set: { viewModel.setHideToMenuBarAfterClose($0) }
        )
    }

    private var clipboardMonitoringBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.clipboardMonitoringEnabled },
            set: { viewModel.setClipboardMonitoringEnabled($0) }
        )
    }

    private var copyHistoryLimitBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.copyHistoryLimit },
            set: { viewModel.updateCopyHistoryLimit($0) }
        )
    }

    private var imageHistoryMaxSizeBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.imageHistoryMaxSizeMB },
            set: { viewModel.updateImageHistoryMaxSizeMB($0) }
        )
    }

    private var defaultSaveLocationBinding: Binding<SaveLocation> {
        Binding(
            get: { viewModel.settings.defaultSaveLocation },
            set: { viewModel.setDefaultSaveLocation($0) }
        )
    }

    private var ocrLanguageModeBinding: Binding<OCRLanguageMode> {
        Binding(
            get: { viewModel.settings.ocrLanguageMode },
            set: { viewModel.setOCRLanguageMode($0) }
        )
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
