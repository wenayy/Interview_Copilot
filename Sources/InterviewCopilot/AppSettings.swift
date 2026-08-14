import SwiftUI
import Foundation

/// Persisted user settings (provider choice, API keys, model). Stored in
/// `UserDefaults`. Keys are per-provider so you can keep both configured and
/// just flip the provider.
@MainActor
final class AppSettings: ObservableObject {
    enum ProviderKind: String, CaseIterable, Identifiable {
        case openai, anthropic, gemini
        var id: String { rawValue }
        var label: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .gemini: return "Gemini"
            }
        }
        var defaultModel: String {
            switch self {
            case .openai: return "gpt-4o-mini"
            case .anthropic: return "claude-sonnet-4-6"
            case .gemini: return "gemini-2.0-flash"
            }
        }
    }

    enum TranscriptionEngine: String, CaseIterable, Identifiable {
        case apple, deepgram
        var id: String { rawValue }
        var label: String {
            switch self {
            case .apple: return "Apple (on-device)"
            case .deepgram: return "Deepgram (accurate)"
            }
        }
    }

    private let d = UserDefaults.standard

    @Published var provider: ProviderKind {
        didSet { d.set(provider.rawValue, forKey: "provider") }
    }
    @Published var openAIKey: String {
        didSet { d.set(openAIKey, forKey: "openAIKey") }
    }
    @Published var anthropicKey: String {
        didSet { d.set(anthropicKey, forKey: "anthropicKey") }
    }
    @Published var geminiKey: String {
        didSet { d.set(geminiKey, forKey: "geminiKey") }
    }
    @Published var openAIModel: String {
        didSet { d.set(openAIModel, forKey: "openAIModel") }
    }
    @Published var anthropicModel: String {
        didSet { d.set(anthropicModel, forKey: "anthropicModel") }
    }
    @Published var geminiModel: String {
        didSet { d.set(geminiModel, forKey: "geminiModel") }
    }
    @Published var transcription: TranscriptionEngine {
        didSet { d.set(transcription.rawValue, forKey: "transcription") }
    }
    @Published var deepgramKey: String {
        didSet { d.set(deepgramKey, forKey: "deepgramKey") }
    }
    /// Transcribe your own mic (green "Me" lines) for follow-up context.
    /// Off = interviewer-only, which halves transcription cost.
    @Published var transcribeMic: Bool {
        didSet { d.set(transcribeMic, forKey: "transcribeMic") }
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        let geminiEnv = env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"]

        // Default provider: prefer whatever the user seems to have a key for,
        // otherwise OpenAI.
        let storedProvider = d.string(forKey: "provider")
            .flatMap(ProviderKind.init(rawValue:))
        provider = storedProvider
            ?? (env["OPENAI_API_KEY"] != nil ? .openai
                : env["ANTHROPIC_API_KEY"] != nil ? .anthropic
                : geminiEnv != nil ? .gemini : .openai)

        // Keys: stored value wins, else fall back to the env var.
        openAIKey = d.string(forKey: "openAIKey") ?? env["OPENAI_API_KEY"] ?? ""
        anthropicKey = d.string(forKey: "anthropicKey")
            ?? env["ANTHROPIC_API_KEY"] ?? ""
        geminiKey = d.string(forKey: "geminiKey") ?? geminiEnv ?? ""

        openAIModel = d.string(forKey: "openAIModel") ?? ProviderKind.openai.defaultModel
        anthropicModel = d.string(forKey: "anthropicModel")
            ?? ProviderKind.anthropic.defaultModel
        geminiModel = d.string(forKey: "geminiModel")
            ?? ProviderKind.gemini.defaultModel

        let dgKey = d.string(forKey: "deepgramKey") ?? env["DEEPGRAM_API_KEY"] ?? ""
        deepgramKey = dgKey
        // Default to Deepgram when a key is present (it's the reliable path),
        // otherwise Apple.
        transcription = d.string(forKey: "transcription")
            .flatMap(TranscriptionEngine.init(rawValue:))
            ?? (dgKey.isEmpty ? .apple : .deepgram)
        transcribeMic = (d.object(forKey: "transcribeMic") as? Bool) ?? true
    }

    var trimmedDeepgramKey: String {
        deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentKey: String {
        let raw: String
        switch provider {
        case .openai: raw = openAIKey
        case .anthropic: raw = anthropicKey
        case .gemini: raw = geminiKey
        }
        // Pasted keys often carry a trailing newline/space; a newline in an HTTP
        // header value makes Foundation drop the header entirely → 401.
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var currentModel: String {
        let m: String
        switch provider {
        case .openai: m = openAIModel
        case .anthropic: m = anthropicModel
        case .gemini: m = geminiModel
        }
        let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }
}

// MARK: - Settings window UI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title3.bold())

            Picker("AI provider", selection: $settings.provider) {
                ForEach(AppSettings.ProviderKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if settings.provider == .openai {
                field("OpenAI API key", systemImage: "key.fill") {
                    SecureField("sk-…", text: $settings.openAIKey)
                }
                field("Model", systemImage: "cpu") {
                    TextField(AppSettings.ProviderKind.openai.defaultModel,
                              text: $settings.openAIModel)
                }
                Text("Uses the Chat Completions API. Try gpt-4o-mini (fast) or gpt-4o.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if settings.provider == .anthropic {
                field("Anthropic API key", systemImage: "key.fill") {
                    SecureField("sk-ant-…", text: $settings.anthropicKey)
                }
                field("Model", systemImage: "cpu") {
                    TextField(AppSettings.ProviderKind.anthropic.defaultModel,
                              text: $settings.anthropicModel)
                }
                Text("Try claude-sonnet-4-6 (fast) or claude-opus-4-8 (best).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                field("Gemini API key", systemImage: "key.fill") {
                    SecureField("AIza…", text: $settings.geminiKey)
                }
                field("Model", systemImage: "cpu") {
                    TextField(AppSettings.ProviderKind.gemini.defaultModel,
                              text: $settings.geminiModel)
                }
                Text("Free key at aistudio.google.com/apikey. " +
                     "Try gemini-2.0-flash or gemini-2.5-flash.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 2)

            Text("Transcription").font(.headline)
            Picker("Engine", selection: $settings.transcription) {
                ForEach(AppSettings.TranscriptionEngine.allCases) { e in
                    Text(e.label).tag(e)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Transcribe my mic too (for follow-up context)",
                   isOn: $settings.transcribeMic)
                .font(.system(size: 12))
                .help("Off = transcribe only the interviewer, halving Deepgram cost.")

            if settings.transcription == .deepgram {
                field("Deepgram API key", systemImage: "waveform") {
                    SecureField("Token…", text: $settings.deepgramKey)
                }
                Text("Realtime, high-accuracy speech-to-text. Key from deepgram.com.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Apple's built-in recognizer. Free & private, but less " +
                     "accurate; needs the language installed for on-device.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, systemImage: String,
                                      @ViewBuilder _ content: () -> Content)
        -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
    }
}
