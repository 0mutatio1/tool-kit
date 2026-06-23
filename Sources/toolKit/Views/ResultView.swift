import SwiftUI

struct ResultView: View {
    let result: OCRResult
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.source.rawValue)
                        .font(.headline)
                    Text(result.recognizedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let confidence = result.confidence {
                    Text("Confidence \(Int(confidence * 100))%")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            Group {
                if result.isEmpty {
                    ContentUnavailableView(
                        "No text detected",
                        systemImage: "text.viewfinder",
                        description: Text("Try a clearer image or capture a slightly larger region.")
                    )
                } else {
                    ScrollView {
                        Text(result.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button("Copy Text", action: onCopy)
                    .keyboardShortcut("c", modifiers: [.command])
                    .disabled(result.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }
}
