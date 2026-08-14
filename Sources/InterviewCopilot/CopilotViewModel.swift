import Foundation
import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class CopilotViewModel: ObservableObject {
    @Published var transcript: [TranscriptSegment] = []
    @Published var liveInterviewer: String = ""
    @Published var liveMe: String = ""
    @Published var suggestion: String = ""
    @Published var status: String = "Idle"
    @Published var isRunning = false
    // Free-form job/role notes (persisted).
    @Published var jobContext: String =
        UserDefaults.standard.string(forKey: "jobContext") ?? "" {
        didSet { UserDefaults.standard.set(jobContext, forKey: "jobContext") }
    }
    // Your résumé / background (persisted). Used only when a question calls for
    // it, so answers aren't forced to reference your résumé every time.
    @Published var profile: String =
        UserDefaults.standard.string(forKey: "profile") ?? "" {
        didSet { UserDefaults.standard.set(profile, forKey: "profile") }
    }
    @Published var answerStyle: AnswerStyle = .concise
    /// When on, a finalized interviewer question auto-fires an answer (uses your
    /// API key). Off = the key is used only when you click Answer/Screen.
    @Published var autoAnswer = true
    /// How many API answer-requests this session (visible in the overlay).
    @Published var apiCalls = 0
    /// Flips true once system audio is actually flowing (capture works).
    @Published var audioHeard = false
    /// Mirror of settings.transcribeMic, editable live from the overlay.
    @Published var micEnabled = true
    /// Compact overlay mode — hides transcript, shows only answer + ask bar.
    @Published var compactMode = false
    /// Text typed into the "Ask a question" bar.
    @Published var questionText = ""
    /// When off, the résumé/background is NOT sent — answers won't reference it.
    @Published var useResume: Bool =
        (UserDefaults.standard.object(forKey: "useResume") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(useResume, forKey: "useResume") }
    }

    /// Only the last N transcript lines are sent to the model, to keep per-call
    /// token cost flat over a long interview.
    private let transcriptWindow = 14

    private let capture = AudioCapture()
    private var interviewerEngine: SpeechEngine
    private var meEngine: SpeechEngine
    private let settings: AppSettings
    private var provider: AIProvider = EchoProvider()
    private var suggestionTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        // Temporary engines; rebuilt from settings in makeEngines() below.
        interviewerEngine = Transcriber(name: "interviewer")
        meEngine = Transcriber(name: "me")
        micEnabled = settings.transcribeMic
        rebuildProvider()
        makeEngines()

        capture.onSystemAudio = { [weak self] buf in
            self?.interviewerEngine.append(buf)
        }
        capture.onMicAudio = { [weak self] buf in
            self?.meEngine.append(buf)
        }
        capture.onFirstSystemBuffer = { [weak self] in
            Task { @MainActor in
                self?.audioHeard = true
                self?.status = "Listening — audio ✓ (hidden from screen share)"
            }
        }
    }

    /// (Re)create the two speech engines from current settings and wire their
    /// callbacks. Called on init and before each Start, so a Settings change
    /// takes effect on the next Start.
    private func makeEngines() {
        interviewerEngine.stop()
        meEngine.stop()

        func make(_ name: String) -> SpeechEngine {
            if settings.transcription == .deepgram,
               !settings.trimmedDeepgramKey.isEmpty {
                return DeepgramEngine(apiKey: settings.trimmedDeepgramKey, name: name)
            }
            return Transcriber(name: name)
        }

        let iv = make("interviewer")
        iv.onResult = { [weak self] text, isFinal in
            Task { @MainActor in self?.handleInterviewer(text, isFinal: isFinal) }
        }
        iv.onError = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }
        interviewerEngine = iv

        let me = make("me")
        me.onResult = { [weak self] text, isFinal in
            Task { @MainActor in self?.handleMe(text, isFinal: isFinal) }
        }
        me.onError = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }
        meEngine = me
    }

    func toggle() {
        if isRunning { stop() } else { Task { await start() } }
    }

    /// Turn mic transcription on/off from the overlay — applies live if running.
    func setMic(_ on: Bool) {
        micEnabled = on
        settings.transcribeMic = on
        guard isRunning else { return }
        if on {
            meEngine.start()
            try? capture.startMic()
        } else {
            capture.stopMic()
            meEngine.stop()
            liveMe = ""
        }
    }

    /// Rebuild the AI backend from the current settings. Call after the user
    /// saves Settings.
    func rebuildProvider() {
        let key = settings.currentKey
        if !key.isEmpty {
            switch settings.provider {
            case .openai:
                provider = OpenAIProvider(apiKey: key, model: settings.currentModel)
            case .anthropic:
                provider = AnthropicProvider(apiKey: key, model: settings.currentModel)
            case .gemini:
                provider = GeminiProvider(apiKey: key, model: settings.currentModel)
            }
            status = "Using \(settings.provider.label) · \(settings.currentModel)"
        } else {
            provider = EchoProvider()
            status = "No API key set — open Settings"
        }
    }

    /// True once Screen Recording is granted. Published so the UI can show a
    /// "grant + relaunch" prompt.
    @Published var needsScreenPermission = false

    func start() async {
        status = "Requesting permissions…"
        guard await Transcriber.requestAuthorization() else {
            status = "Speech recognition denied. Enable it in System Settings › Privacy."
            return
        }

        // Don't gate on CGPreflightScreenCaptureAccess() — it reports false
        // negatives for menu-bar apps on macOS 15. Just try to capture; the
        // ScreenCaptureKit call itself throws a specific error if we truly
        // lack Screen Recording permission.
        do {
            audioHeard = false
            makeEngines()               // pick up any transcription setting change
            interviewerEngine.start()
            try await capture.startSystemAudio()
            // Only listen to your mic if enabled (off = interviewer-only, ~half
            // the Deepgram cost, and it doesn't listen to you at all).
            if settings.transcribeMic {
                meEngine.start()
                try capture.startMic()
            }
            isRunning = true
            needsScreenPermission = false
            status = "Listening — waiting for audio…"
        } catch {
            NSLog("start() failed: \(error) [\((error as NSError).domain) " +
                  "\((error as NSError).code)]")
            stop()
            if Self.isScreenPermissionError(error) {
                _ = CGRequestScreenCaptureAccess() // adds us to the list / prompts
                needsScreenPermission = true
                status = "Screen Recording not active for this build. Grant it, " +
                    "then menu bar ▸ Relaunch app."
                openScreenRecordingSettings()
            } else {
                status = "Failed to start: \(error.localizedDescription)"
            }
        }
    }

    /// True when the error is ScreenCaptureKit refusing for lack of permission
    /// (SCStreamError `userDeclined` == -3801), vs. any other failure.
    private static func isScreenPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.code == -3801 { return true }
        if ns.domain.localizedCaseInsensitiveContains("ScreenCaptureKit") { return true }
        return false
    }

    func openScreenRecordingSettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func stop() {
        suggestionTask?.cancel()
        Task { await capture.stopSystemAudio() }
        capture.stopMic()
        interviewerEngine.stop()
        meEngine.stop()
        isRunning = false
        status = "Stopped"
    }

    // MARK: Transcript handling

    private func handleInterviewer(_ text: String, isFinal: Bool) {
        liveInterviewer = text
        guard isFinal, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        transcript.append(.init(speaker: .interviewer, text: text))
        liveInterviewer = ""
        // A finalized interviewer utterance is our cue to answer — but only if
        // auto-answer is on (otherwise nothing hits your API key automatically).
        if autoAnswer { requestSuggestion() }
    }

    private func handleMe(_ text: String, isFinal: Bool) {
        liveMe = text
        guard isFinal, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        transcript.append(.init(speaker: .me, text: text))
        liveMe = ""
    }

    /// Manually re-request an answer (hotkey / Answer / Regenerate button).
    func requestSuggestion() { runSuggestion(screenshot: nil) }

    /// Capture the current screen and answer what's shown on it (coding tasks,
    /// MCQs, shared docs). Bound to ⌥⌘S and the "Screen" button.
    func answerFromScreen() {
        suggestionTask?.cancel()
        suggestion = ""
        status = "Reading screen…"
        suggestionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let png = try await ScreenGrabber.capturePNG()
                await MainActor.run { self.status = self.runningStatus() }
                await self.stream(screenshot: png)
            } catch {
                await MainActor.run {
                    self.suggestion = "⚠️ Couldn't read screen: " +
                        "\(error.localizedDescription)"
                }
            }
        }
    }

    private func runSuggestion(screenshot: Data?) {
        suggestionTask?.cancel()
        suggestion = ""
        suggestionTask = Task { [weak self] in
            await self?.stream(screenshot: screenshot)
        }
    }

    private func stream(screenshot: Data?) async {
        let snapshot = Array(transcript.suffix(transcriptWindow))
        // Nothing to answer: no captured question and no screenshot.
        if snapshot.isEmpty && screenshot == nil {
            suggestion = "No question captured yet. Start listening and wait for " +
                "cyan Q: lines to appear (status should say “audio ✓”), or use " +
                "Screen for an on-screen question."
            return
        }
        let ctx = combinedContext()
        let style = answerStyle
        apiCalls += 1
        do {
            for try await delta in provider.streamSuggestion(
                transcript: snapshot, jobContext: ctx,
                screenshot: screenshot, style: style) {
                if Task.isCancelled { return }
                suggestion += delta
            }
        } catch {
            suggestion = "⚠️ \(error.localizedDescription)"
        }
    }

    /// Combine job notes + résumé into the context we send. Either can be empty.
    private func combinedContext() -> String {
        var parts: [String] = []
        let job = jobContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let prof = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !job.isEmpty { parts.append("Role / job notes:\n\(job)") }
        // Only include the résumé when the user has enabled it.
        if useResume && !prof.isEmpty {
            parts.append("Candidate résumé / background:\n\(prof)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// Load a résumé file (PDF or text) into the profile field.
    func loadResumeFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .text, .rtf]
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let text = Self.extractText(from: url), !text.isEmpty {
            profile = text
            status = "Loaded résumé from \(url.lastPathComponent) " +
                "(\(text.count) chars)"
        } else {
            status = "Couldn't read text from \(url.lastPathComponent)."
        }
    }

    private static func extractText(from url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Ask a question

    /// Send a typed question to the AI.
    func askQuestion() {
        let q = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        questionText = ""
        askDirect(question: q)
    }

    /// Grab your last spoken "Me:" lines and send as a question.
    func askLast() {
        var parts: [String] = []
        for seg in transcript.reversed() {
            if seg.speaker == .me {
                parts.insert(seg.text, at: 0)
                if parts.count >= 3 { break }
            } else {
                if !parts.isEmpty { break }
            }
        }
        let live = liveMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { parts.append(live) }

        let q = parts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            suggestion = "Nothing captured from your mic yet. " +
                "Make sure Mic is on and say your question, then tap Ask Last."
            return
        }
        askDirect(question: q)
    }

    private func askDirect(question: String) {
        suggestionTask?.cancel()
        suggestion = ""
        apiCalls += 1
        suggestionTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = Array(self.transcript.suffix(self.transcriptWindow))
            let ctx = self.combinedContext()
            let style = self.answerStyle
            do {
                for try await delta in self.provider.streamSuggestion(
                    transcript: snapshot + [.init(speaker: .interviewer, text: question)],
                    jobContext: ctx, screenshot: nil, style: style) {
                    if Task.isCancelled { return }
                    self.suggestion += delta
                }
            } catch {
                self.suggestion = "⚠️ \(error.localizedDescription)"
            }
        }
    }

    private func runningStatus() -> String {
        isRunning ? "Listening — hidden from screen share"
                  : "Using \(settings.provider.label) · \(settings.currentModel)"
    }
}
