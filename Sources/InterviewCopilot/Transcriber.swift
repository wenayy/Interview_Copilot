import Foundation
import Speech
import AVFoundation

/// A streaming speech-to-text engine. We run two instances (interviewer + you),
/// and can swap the concrete engine (Apple on-device vs. Deepgram) at runtime.
protocol SpeechEngine: AnyObject {
    var onResult: ((String, Bool) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start()
    func append(_ buffer: AVAudioPCMBuffer)
    func stop()
}

/// Wraps one on-device `SFSpeechRecognizer` streaming session. We run two of
/// these: one fed by system audio (the interviewer) and one by the mic (you).
final class Transcriber: SpeechEngine, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let name: String

    /// Called with (text, isFinal) as recognition progresses.
    var onResult: ((String, Bool) -> Void)?
    /// Called with a human-readable message when recognition fails.
    var onError: ((String) -> Void)?

    init(name: String, locale: Locale = Locale(identifier: "en-US")) {
        self.name = name
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func start() {
        stop()
        guard let recognizer else {
            onError?("Speech recognizer unavailable for this locale.")
            return
        }
        guard recognizer.isAvailable else {
            onError?("Speech recognizer not available right now (try again, or " +
                     "check network — server recognition needs it).")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Only force on-device when it's actually supported; otherwise let it
        // use Apple's server recognition. Forcing on-device when unsupported
        // makes the task fail immediately with no transcript.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        NSLog("[\(name)] start: onDevice=\(recognizer.supportsOnDeviceRecognition) " +
              "available=\(recognizer.isAvailable)")
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onResult?(result.bestTranscription.formattedString,
                               result.isFinal)
            }
            if let error {
                let ns = error as NSError
                // Code 1110 = "no speech detected"; harmless, just restart.
                if ns.code != 1110 {
                    NSLog("[\(self.name)] recog error: \(ns.domain) \(ns.code) " +
                          "\(ns.localizedDescription)")
                    self.onError?("Transcription error (\(self.name)): " +
                                  ns.localizedDescription)
                }
                self.restartAfterFinal()
            } else if result?.isFinal ?? false {
                // Recognizer stops after a final result; restart for the next
                // utterance so the session keeps running for the whole call.
                self.restartAfterFinal()
            }
        }
    }

    private func restartAfterFinal() {
        request?.endAudio()
        task = nil
        request = nil
        start()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
