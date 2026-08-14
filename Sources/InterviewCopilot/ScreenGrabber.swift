import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit

/// Captures a single still frame of the main display as PNG data, for the
/// vision path. The overlay window is automatically excluded because it uses
/// `sharingType = .none`, so screenshots never contain the copilot itself.
enum ScreenGrabber {
    static func capturePNG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenGrabber", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display available."])
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: [],
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        // Downscale large displays a bit to keep the upload/token cost sane.
        let maxW = 1600
        if display.width > maxW {
            let scale = Double(maxW) / Double(display.width)
            config.width = maxW
            config.height = Int(Double(display.height) * scale)
        }

        let cg = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
        return try png(from: cg)
    }

    private static func png(from cg: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScreenGrabber", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG."])
        }
        return data
    }
}
