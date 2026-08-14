import Foundation
@preconcurrency import AVFoundation
import ScreenCaptureKit

/// Captures the interviewer's voice (system/output audio) via ScreenCaptureKit
/// and your voice (microphone) via AVAudioEngine, converting both to the PCM
/// format the speech recognizer expects.
final class AudioCapture: NSObject, @unchecked Sendable {
    /// Buffers of system audio (interviewer).
    var onSystemAudio: ((AVAudioPCMBuffer) -> Void)?
    /// Buffers of mic audio (you).
    var onMicAudio: ((AVAudioPCMBuffer) -> Void)?

    /// Called once, the first time system audio actually flows (for diagnostics).
    var onFirstSystemBuffer: (() -> Void)?
    private var systemBufferCount = 0

    private var stream: SCStream?
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    // The format SFSpeechRecognizer is happy with.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    // MARK: System audio (ScreenCaptureKit)

    func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display available for capture."])
        }

        // We must specify a content filter even though we only want audio.
        let filter = SCContentFilter(display: display,
                                     excludingApplications: [],
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // don't capture our own output
        config.sampleRate = 48_000
        config.channelCount = 2
        // Keep video minimal — we only need the stream alive for audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        self.stream = stream
    }

    func stopSystemAudio() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: Microphone (AVAudioEngine)

    func startMic() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let micConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self, let micConverter else { return }
            if let out = self.convert(buffer, using: micConverter) {
                self.onMicAudio?(out)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stopMic() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: Conversion helpers

    private func convert(_ buffer: AVAudioPCMBuffer,
                         using conv: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: capacity) else { return nil }
        // `AVAudioConverter`'s input block is `@Sendable`, but it runs
        // synchronously on this thread, so a small box is safe here.
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if once.done { status.pointee = .noDataNow; return nil }
            once.done = true
            status.pointee = .haveData
            return buffer
        }
        if err != nil || out.frameLength == 0 { return nil }
        return out
    }
}

// MARK: - SCStreamDelegate / SCStreamOutput

extension AudioCapture: SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        systemBufferCount += 1
        if systemBufferCount == 1 {
            NSLog("AudioCapture: first system-audio buffer received")
            onFirstSystemBuffer?()
        }
        // Downmix/resample to the recognizer format.
        if let conv = converterForSystem(inputFormat: pcm.format),
           let out = convert(pcm, using: conv) {
            onSystemAudio?(out)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio stream stopped: \(error.localizedDescription)")
    }

    private func converterForSystem(inputFormat: AVAudioFormat) -> AVAudioConverter? {
        if converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        return converter
    }

    /// Build an AVAudioPCMBuffer from a CMSampleBuffer produced by SCStream.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer)
        -> AVAudioPCMBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
        else { return nil }
        var streamDesc = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDesc)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frames) else { return nil }
        buffer.frameLength = frames

        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList)
        return buffer
    }
}
