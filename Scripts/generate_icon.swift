#!/usr/bin/env swift

import AppKit
import Foundation

let iconEntries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let icnsEntries: [(type: String, fileName: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = rootURL.appendingPathComponent("AppBundle/toolKit-icon-source.png")
let iconsetURL = rootURL.appendingPathComponent("AppBundle/toolKit.iconset")
let icnsURL = rootURL.appendingPathComponent("AppBundle/toolKit.icns")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Could not load icon source at \(sourceURL.path)")
}

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for entry in iconEntries {
    let image = renderIcon(from: sourceImage, pixels: entry.pixels)
    let outputURL = iconsetURL.appendingPathComponent(entry.name)
    try savePNG(image, to: outputURL)
    print("Saved \(outputURL.path)")
}

try writeICNS(from: iconsetURL, to: icnsURL)
print("Created \(icnsURL.path)")

func renderIcon(from sourceImage: NSImage, pixels: Int) -> NSImage {
    let size = CGSize(width: pixels, height: pixels)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        return image
    }

    context.clear(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current?.imageInterpolation = .high

    let sourceSize = sourceImage.size
    let sourceSide = min(sourceSize.width, sourceSize.height)
    let sourceRect = CGRect(
        x: (sourceSize.width - sourceSide) / 2,
        y: (sourceSize.height - sourceSide) / 2,
        width: sourceSide,
        height: sourceSide
    )

    sourceImage.draw(
        in: CGRect(origin: .zero, size: size),
        from: sourceRect,
        operation: .copy,
        fraction: 1
    )

    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw IconError.cannotCreateCGImage
    }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cgImage.width,
        pixelsHigh: cgImage.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let bitmap else {
        throw IconError.cannotCreateBitmap
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: cgImage, size: image.size).draw(
        in: CGRect(origin: .zero, size: image.size),
        from: CGRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.cannotCreatePNG
    }

    try data.write(to: url)
}

enum IconError: Error {
    case cannotCreateCGImage
    case cannotCreateBitmap
    case cannotCreatePNG
    case invalidICNSType
}

func writeICNS(from iconsetURL: URL, to outputURL: URL) throws {
    var chunks = Data()

    for entry in icnsEntries {
        guard let typeData = entry.type.data(using: .macOSRoman), typeData.count == 4 else {
            throw IconError.invalidICNSType
        }

        let pngData = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.fileName))
        chunks.append(typeData)
        chunks.append(bigEndianData(UInt32(pngData.count + 8)))
        chunks.append(pngData)
    }

    var icns = Data()
    icns.append(Data("icns".utf8))
    icns.append(bigEndianData(UInt32(chunks.count + 8)))
    icns.append(chunks)
    try icns.write(to: outputURL)
}

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndianValue = value.bigEndian
    return Data(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size)
}
