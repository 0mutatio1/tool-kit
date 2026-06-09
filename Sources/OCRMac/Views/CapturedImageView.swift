import AppKit
import SwiftUI

struct CapturedImageView: View {
    let image: NSImage
    let onCopyImage: () -> Void
    let onRunOCR: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clipped Image")
                        .font(.headline)
                    Text("\(Int(image.size.width)) x \(Int(image.size.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCopyImage) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy clipped image")

                Button(action: onRunOCR) {
                    Image(systemName: "text.viewfinder")
                }
                .keyboardShortcut("o", modifiers: [.command])
                .help("Run OCR")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .help("Close")
            }
            .buttonStyle(.bordered)
            .padding(14)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
