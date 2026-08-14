import Foundation
import AVFoundation

/// Streaming speech-to-text via Deepgram's realtime WebSocket API. Much more
/// accurate than Apple's recognizer for interview audio. Feeds 16 kHz mono
/// linear16 PCM and receives interim + final transcripts.
final class DeepgramEngine: NSObject, SpeechEngine, @unchecked Sendable {
    var onResult: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let apiKey: String
    private let name: String
    private let model: String
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)

    /// Finalized segments of the current utterance (Deepgram sends them
    /// incrementally; we join them for a clean live + final transcript).
    private var utterance = ""

    init(apiKey: String, name: String, model: String = "nova-2") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name
        self.model = model
    }

    func start() {
        var comps = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        comps.queryItems = [
            .init(name: "model", value: model),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "channels", value: "1"),
            .init(name: "interim_results", value: "true"),
            .init(name: "punctuate", value: "true"),
            .init(name: "smart_format", value: "true"),
            .init(name: "endpointing", value: "300"),
        ]
        guard let url = comps.url else {
            onError?("Deepgram: bad URL"); return
        }
        var req = URLRequest(url: url)
        req.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        utterance = ""
        let t = session.webSocketTask(with: req)
        task = t
        t.resume()
        NSLog("[\(name)] Deepgram socket opening")
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                let ns = error as NSError
                // Cancelled on stop() is expected — don't surface it.
                if ns.code != NSURLErrorCancelled {
                    NSLog("[\(self.name)] Deepgram recv error: \(ns.code) \(ns.localizedDescription)")
                    self.onError?("Deepgram: \(ns.localizedDescription)")
                }
            case .success(let message):
                switch message {
                case .string(let s): self.handle(s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { self.handle(s) }
                @unknown default: break
                }
                self.receive()   // keep listening
            }
        }
    }

    private func handle(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else { return }

        if let err = obj["error"] as? String ??
            (obj["error"] as? [String: Any])?["message"] as? String {
            onError?("Deepgram: \(err)")
            return
        }

        guard let channel = obj["channel"] as? [String: Any],
              let alts = channel["alternatives"] as? [[String: Any]],
              let text = alts.first?["transcript"] as? String,
              !text.isEmpty else { return }

        let isFinal = (obj["is_final"] as? Bool) ?? false
        let speechFinal = (obj["speech_final"] as? Bool) ?? false

        if speechFinal {
            // End of utterance → emit the whole thing as final and reset.
            let full = (utterance + " " + text).trimmingCharacters(in: .whitespaces)
            utterance = ""
            onResult?(full, true)
        } else if isFinal {
            // A finalized segment mid-utterance → accumulate, show as live.
            utterance = (utterance + " " + text).trimmingCharacters(in: .whitespaces)
            onResult?(utterance, false)
        } else {
            // Interim words → live display over the accumulated final segments.
            let live = (utterance + " " + text).trimmingCharacters(in: .whitespaces)
            onResult?(live, false)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // Convert 16 kHz mono float32 → little-endian Int16 PCM bytes.
        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let src = ch[0]
        var pcm = Data(count: n * 2)
        pcm.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: Int16.self)
            for i in 0..<n {
                let v = max(-1.0, min(1.0, src[i]))
                dst[i] = Int16(v * 32767).littleEndian
            }
        }
        task?.send(.data(pcm)) { error in
            if let error { NSLog("Deepgram send error: \(error.localizedDescription)") }
        }
    }

    func stop() {
        if let t = task {
            // Tell Deepgram to flush + close, then tear down.
            t.send(.string("{\"type\":\"CloseStream\"}")) { _ in }
            t.cancel(with: .goingAway, reason: nil)
        }
        task = nil
        utterance = ""
    }
}
