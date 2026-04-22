#!/usr/bin/env swift
// Generates AppIconDev.appiconset from AppIcon.appiconset by stamping an
// orange "DEV" pill in the bottom-right corner of each icon. Rerun after
// updating the main icon to keep the dev badge in sync.

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("Usage: make_dev_icon.swift <source-iconset> <dest-iconset>\n".data(using: .utf8)!)
    exit(1)
}

let sourceDir = CommandLine.arguments[1]
let destDir = CommandLine.arguments[2]
let fm = FileManager.default
try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

let badgeColor = NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0)

func pixelSize(of image: NSImage) -> NSSize {
    if let rep = image.representations.first as? NSBitmapImageRep {
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return image.size
}

let entries = try fm.contentsOfDirectory(atPath: sourceDir).sorted()
for name in entries where name.hasSuffix(".png") {
    let srcPath = "\(sourceDir)/\(name)"
    let dstPath = "\(destDir)/\(name)"

    guard let src = NSImage(contentsOfFile: srcPath) else { continue }
    let px = pixelSize(of: src)
    let w = Int(px.width), h = Int(px.height)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))

    let wF = CGFloat(w), hF = CGFloat(h)
    let badgeH = hF * 0.26
    let badgeW = wF * 0.50
    let badgeRect = NSRect(
        x: wF - badgeW - wF * 0.04,
        y: hF * 0.04,
        width: badgeW,
        height: badgeH
    )

    badgeColor.setFill()
    NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2).fill()

    if w >= 64 {
        let fontSize = badgeH * 0.55
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: "DEV", attributes: attrs)
        let ts = text.size()
        text.draw(at: NSPoint(x: badgeRect.midX - ts.width / 2, y: badgeRect.midY - ts.height / 2))
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: dstPath))
    print("✓ \(name) (\(w)×\(h))")
}

print("Wrote dev icons to \(destDir)")
