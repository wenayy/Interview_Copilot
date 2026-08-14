import Foundation

/// A single turn of the interview transcript that we send to the model.
struct TranscriptSegment: Sendable {
    enum Speaker: String, Sendable {
        case interviewer   // captured from system audio (the other person)
        case me            // captured from the microphone
    }
    let speaker: Speaker
    let text: String
}

/// Swappable AI backend. Implement this to point the app at a different
/// provider, a proxy server, or a local model — the rest of the app only
/// depends on this protocol.
/// How the answer should be shaped.
enum AnswerStyle: String, CaseIterable, Identifiable, Sendable {
    case concise, detailed, star, code
    var id: String { rawValue }
    var label: String {
        switch self {
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        case .star: return "STAR"
        case .code: return "Code"
        }
    }
    var instruction: String {
        switch self {
        case .concise:
            return "Answer in 2-4 short spoken sentences. Lead with the answer."
        case .detailed:
            return "Give a thorough spoken answer (5-8 sentences) with a concrete " +
                "example or reasoning, still natural to say out loud."
        case .star:
            return "This is likely a behavioral question. Answer using the STAR " +
                "structure (Situation, Task, Action, Result) in first person, " +
                "concise and natural — don't label the sections out loud."
        case .code:
            return "This is a technical/coding question. Give the concrete answer: " +
                "a short explanation of the approach, then a clean, correct code " +
                "solution in a fenced code block, then note time/space complexity."
        }
    }
}

protocol AIProvider: Sendable {
    /// Stream a suggested answer for the most recent interviewer question,
    /// given the running transcript, optional on-screen image, and answer style.
    func streamSuggestion(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Shared prompt building

/// The system prompt is identical across providers — keep it in one place.
func copilotSystemPrompt(jobContext: String, style: AnswerStyle) -> String {
    """
    You are a real-time interview copilot. The user is in a live job \
    interview. You are given the running transcript (the interviewer's \
    questions and the user's replies), optionally a screenshot of the user's \
    screen (which may contain a coding task, a multiple-choice question, or a \
    shared document), plus optional context about the role and the user's \
    background.

    Produce an answer the user can use immediately — first person, natural \
    spoken language, no preamble, no "here's what you could say". Lead with \
    the answer. If a screenshot is provided, answer what it shows (read code, \
    questions, or diagrams from it). \(style.instruction)

    Background you can draw on (role/job notes and the candidate's résumé):
    \(jobContext.isEmpty ? "(none provided)" : jobContext)

    Decide per question which mode to use:
    • If the question is about the candidate's projects, experience, or résumé \
    ("tell me about a project", "what did you build", "why you", "your \
    strengths", or it references something on the résumé) → ground the answer \
    in the résumé: name the specific project, the tech used, your role, and the \
    concrete outcome/impact. Vary which experience you cite across questions; \
    don't reuse the same project every time.
    • If the question is technical, conceptual, or a coding problem (how X \
    works, design/algorithm questions, "explain Y") → give a strong, correct, \
    well-structured expert answer that actually teaches the concept — clear \
    reasoning, the key idea, and a concrete example or code where useful. Do \
    NOT force the résumé in here; answer it as an expert would.

    When in doubt, prefer a genuinely helpful, accurate answer over name-dropping \
    the résumé.
    """
}

func copilotUserPrompt(transcript: [TranscriptSegment],
                       hasScreenshot: Bool) -> String {
    let convo = transcript.map { seg -> String in
        let who = seg.speaker == .interviewer ? "INTERVIEWER" : "ME"
        return "\(who): \(seg.text)"
    }.joined(separator: "\n")
    let convoBlock = convo.isEmpty ? "(no transcript yet)" : convo

    if hasScreenshot {
        return """
        A screenshot of my screen is attached. It contains the actual question \
        or task (e.g. a coding problem, a multiple-choice question, or a \
        document). ANSWER WHAT IS IN THE SCREENSHOT — read the code, question, \
        or prompt directly from the image. Use the transcript below only as \
        extra background, not as the question.

        Transcript (background only):
        \(convoBlock)
        """
    }
    return """
    Here is the interview transcript so far:

    \(convoBlock)

    Give me the answer to the interviewer's most recent question.
    """
}

// MARK: - Anthropic implementation

/// Talks directly to the Claude Messages API with streaming.
///
/// The API key is read from `ANTHROPIC_API_KEY` (or set explicitly). If you'd
/// rather hide the key, implement a `ProxyProvider` that hits your own server
/// and swap it in `CopilotViewModel` — nothing else changes.
struct AnthropicProvider: AIProvider {
    var apiKey: String
    /// Fast model keeps latency low for live suggestions. Swap to
    /// `claude-opus-4-8` for maximum quality if latency is acceptable.
    var model: String = "claude-sonnet-4-6"
    var maxTokens: Int = 640

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func streamSuggestion(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(transcript: transcript, jobContext: jobContext,
                                  screenshot: screenshot, style: style,
                                  continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                         forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let system = copilotSystemPrompt(jobContext: jobContext, style: style)
        let userText = copilotUserPrompt(transcript: transcript, hasScreenshot: screenshot != nil)

        var content: [[String: Any]] = [["type": "text", "text": userText]]
        if let shot = screenshot {
            content.insert(["type": "image", "source": [
                "type": "base64", "media_type": "image/png",
                "data": shot.base64EncodedString()]], at: 0)
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var detail = ""
            for try await line in bytes.lines { detail += line }
            throw NSError(
                domain: "AnthropicProvider", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey:
                    "HTTP \(http.statusCode): \(detail)"])
        }

        // Parse the SSE stream: lines like `data: {json}`.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            switch type {
            case "content_block_delta":
                if let delta = obj["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    continuation.yield(text)
                }
            case "message_stop":
                continuation.finish()
                return
            case "error":
                let msg = (obj["error"] as? [String: Any])?["message"]
                    as? String ?? "unknown error"
                throw NSError(domain: "AnthropicProvider", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            default:
                break
            }
        }
        continuation.finish()
    }
}

// MARK: - OpenAI implementation

/// Talks to the OpenAI Chat Completions API with streaming.
///
/// The API key is read from `OPENAI_API_KEY` or set via Settings. Same shape as
/// `AnthropicProvider` — pick whichever you have a key for.
struct OpenAIProvider: AIProvider {
    var apiKey: String
    /// Fast, cheap model keeps latency low for live suggestions. Swap to
    /// `gpt-4o` or another model in Settings for higher quality.
    var model: String = "gpt-4o-mini"
    var maxTokens: Int = 640

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func streamSuggestion(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(transcript: transcript, jobContext: jobContext,
                                  screenshot: screenshot, style: style,
                                  continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        // Newer models (gpt-5.x, o-series) require `max_completion_tokens` and
        // reject `max_tokens`; they also only accept the default temperature,
        // so we don't send one. `max_completion_tokens` is accepted by gpt-4o
        // too, so it's safe across the board.
        var userContent: [[String: Any]] =
            [["type": "text", "text": copilotUserPrompt(transcript: transcript, hasScreenshot: screenshot != nil)]]
        if let shot = screenshot {
            userContent.append(["type": "image_url", "image_url":
                ["url": "data:image/png;base64,\(shot.base64EncodedString())"]])
        }

        let body: [String: Any] = [
            "model": model,
            "max_completion_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "system",
                 "content": copilotSystemPrompt(jobContext: jobContext, style: style)],
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var detail = ""
            for try await line in bytes.lines { detail += line }
            throw NSError(
                domain: "OpenAIProvider", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey:
                    "HTTP \(http.statusCode): \(detail)"])
        }

        // Parse the SSE stream: `data: {json}` lines, terminated by `data: [DONE]`.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { continuation.finish(); return }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { continue }

            if let choices = obj["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let text = delta["content"] as? String {
                continuation.yield(text)
            }
            if let err = obj["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "unknown error"
                throw NSError(domain: "OpenAIProvider", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        continuation.finish()
    }
}

// MARK: - Google Gemini implementation

/// Talks to the Google Gemini API (Generative Language) with streaming. The
/// free tier works with a key from https://aistudio.google.com/apikey.
struct GeminiProvider: AIProvider {
    var apiKey: String
    /// `gemini-2.0-flash` is fast and available on the free tier.
    var model: String = "gemini-2.0-flash"
    var maxTokens: Int = 640

    func streamSuggestion(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(transcript: transcript, jobContext: jobContext,
                                  screenshot: screenshot, style: style,
                                  continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Streaming SSE endpoint. Key goes in the query string.
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/" +
            "\(model):streamGenerateContent?alt=sse&key=\(key)"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "GeminiProvider", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid model name."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] =
            [["text": copilotUserPrompt(transcript: transcript, hasScreenshot: screenshot != nil)]]
        if let shot = screenshot {
            parts.append(["inline_data":
                ["mime_type": "image/png", "data": shot.base64EncodedString()]])
        }

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": copilotSystemPrompt(jobContext: jobContext,
                                                       style: style)]]
            ],
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "generationConfig": ["maxOutputTokens": maxTokens]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var detail = ""
            for try await line in bytes.lines { detail += line }
            throw NSError(
                domain: "GeminiProvider", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey:
                    "HTTP \(http.statusCode): \(detail)"])
        }

        // SSE: `data: {json}` chunks, each with candidates[].content.parts[].text.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { continue }

            if let candidates = obj["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String {
                        continuation.yield(text)
                    }
                }
            }
            if let err = obj["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "unknown error"
                throw NSError(domain: "GeminiProvider", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        continuation.finish()
    }
}

// MARK: - Placeholder / offline provider

/// Used when no API key is configured, so the app still runs and you can see
/// the transcript + overlay working before wiring up a real backend.
struct EchoProvider: AIProvider {
    func streamSuggestion(
        transcript: [TranscriptSegment],
        jobContext: String,
        screenshot: Data?,
        style: AnswerStyle
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let last = transcript.last(where: { $0.speaker == .interviewer })?.text
                ?? "…"
            let msg = "[No AI backend configured — add an OpenAI or Anthropic " +
                "key in Settings.]\nHeard question: \"\(last)\""
            for word in msg.split(separator: " ") {
                continuation.yield(String(word) + " ")
            }
            continuation.finish()
        }
    }
}
