// Turn a raw square art PNG (possibly on a dark background) into a proper macOS
// app icon: trims the dark margin to the artwork, then composites it into a
// 1024×1024 canvas with a rounded-rect mask (transparent corners) and padding.
//
//   swift make_icon.swift <input.png> <output.png>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3,
      let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make_icon <in.png> <out.png>\n".utf8))
    exit(1)
}

let w = cg.width, h = cg.height
let bpr = w * 4
var px = [UInt8](repeating: 0, count: h * bpr)
let space = CGColorSpaceCreateDeviceRGB()
let readCtx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: bpr, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
readCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// Bounding box of bright (artwork) pixels — the dark backdrop is near-black.
let thr: Double = 0.35 * 255
var minX = w, minY = h, maxX = 0, maxY = 0   // buffer coords, y up
for y in 0..<h {
    for x in 0..<w {
        let i = y * bpr + x * 4
        let m = max(Double(px[i]), max(Double(px[i+1]), Double(px[i+2])))
        if m > thr {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
if maxX <= minX || maxY <= minY { minX = 0; minY = 0; maxX = w - 1; maxY = h - 1 }

// Make it a centered square crop (top-left origin for CGImage.cropping).
let cropW = maxX - minX + 1, cropH = maxY - minY + 1
let side = max(cropW, cropH)
let cx = (minX + maxX) / 2, cyBottom = (minY + maxY) / 2
var ox = cx - side / 2
var oyTop = (h - cyBottom) - side / 2   // convert center to top-left origin
ox = max(0, min(ox, w - side))
oyTop = max(0, min(oyTop, h - side))
let cropRect = CGRect(x: ox, y: oyTop, width: side, height: side)
let art = cg.cropping(to: cropRect) ?? cg

// Compose into 1024×1024 with padding + rounded-rect mask (transparent corners).
let size = 1024
let pad = 60                         // transparent margin, matches native sizing
let tile = CGRect(x: pad, y: pad, width: size - 2*pad, height: size - 2*pad)
let radius = CGFloat(size - 2*pad) * 0.2237   // macOS-style corner radius

let outCtx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                       bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
outCtx.clear(CGRect(x: 0, y: 0, width: size, height: size))
let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius,
                  transform: nil)
outCtx.addPath(path)
outCtx.clip()
outCtx.draw(art, in: tile)

guard let outImage = outCtx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: outImage)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: args[2]))
FileHandle.standardError.write(Data("wrote \(args[2]) (\(size)x\(size))\n".utf8))
