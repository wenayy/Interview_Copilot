import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var vm: CopilotViewModel
    @State private var showContext = false
    @State private var showKeys = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            controls

            if showKeys {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Shortcuts.all, id: \.keys) { s in
                        HStack(spacing: 8) {
                            Text(s.keys)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                                .frame(width: 44, alignment: .leading)
                            Text(s.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }

            if showContext {
                VStack(alignment: .leading, spacing: 6) {
                    Text("JOB / ROLE NOTES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                    contextEditor($vm.jobContext,
                                  placeholder: "Job description, target role, company…",
                                  height: 48)

                    HStack {
                        Text("RÉSUMÉ / BACKGROUND")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Button("Load file…") { vm.loadResumeFile() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    contextEditor($vm.profile,
                                  placeholder: "Paste résumé bullets or load a PDF/txt. " +
                                    "Used only when a question is about your experience.",
                                  height: 56)
                }
            }

            // Live transcript tail — hidden in compact mode
            if !vm.compactMode {
                transcriptView
                Divider().overlay(.white.opacity(0.15))
            }

            // Suggested answer
            ScrollView {
                Text(vm.suggestion.isEmpty
                     ? "Suggested answers appear here when the interviewer asks a question."
                     : vm.suggestion)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(vm.suggestion.isEmpty
                                     ? .white.opacity(0.35) : .white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.15))
            askQuestionBar
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: vm.compactMode ? 220 : 340)
        .background(Color.black.opacity(vm.overlayOpacity))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(vm.status)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer()
            if vm.apiCalls > 0 {
                Text("API: \(vm.apiCalls)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.6))
                    .cornerRadius(4)
            }
            Button(vm.compactMode ? "Full" : "Mini") {
                vm.compactMode.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.yellow)
            .help("Toggle compact mode (⌃⌥C)")
            Slider(value: $vm.overlayOpacity, in: 0.15...1.0, step: 0.05)
                .frame(width: 50)
                .help("Overlay opacity — slide left to see through")
            Button(showKeys ? "⌨︎✕" : "⌨︎") { showKeys.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .help("Show keyboard shortcuts")
            Button(showContext ? "Hide ctx" : "Context") { showContext.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Button(vm.isRunning ? "Stop" : "Start") { vm.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(vm.isRunning ? .red : .green)
        }
    }

    // Answer-style picker + auto toggle + Screen / Answer actions.
    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $vm.answerStyle) {
                ForEach(AnswerStyle.allCases) { s in Text(s.label).tag(s) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 11))
            .fixedSize()

            Toggle("Auto", isOn: $vm.autoAnswer)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Auto-answer each question (uses your API key automatically)")

            Toggle("Mic", isOn: Binding(get: { vm.micEnabled },
                                        set: { vm.setMic($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Transcribe your mic for follow-up context. Off = " +
                      "interviewer only, ~half the Deepgram cost, doesn't hear you.")

            Toggle("Résumé", isOn: $vm.useResume)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Use your résumé/background in answers. Off = never " +
                      "reference it (answers stay generic/technical).")

            Spacer()
            Button("Screen") { vm.answerFromScreen() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Button("Answer") { vm.requestSuggestion() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.transcript.suffix(6).enumerated()),
                            id: \.offset) { _, seg in
                        line(seg.speaker == .interviewer ? "Q" : "Me",
                             seg.text,
                             seg.speaker == .interviewer ? .cyan : .green)
                    }
                    if !vm.liveInterviewer.isEmpty {
                        line("Q", vm.liveInterviewer + "…", .cyan.opacity(0.6))
                    }
                    if !vm.liveMe.isEmpty {
                        line("Me", vm.liveMe + "…", .green.opacity(0.6))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 90)
            .onChange(of: vm.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    private var askQuestionBar: some View {
        HStack(spacing: 6) {
            Button { vm.askLast() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 11))
                    Text("Ask Last")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Ask AI about what you just said (⌃⌥Q)")

            TextField("Type a question…", text: $vm.questionText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                .onSubmit { vm.askQuestion() }

            Button { vm.askQuestion() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(vm.questionText.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty
                        ? .white.opacity(0.25) : .cyan)
            }
            .buttonStyle(.plain)
            .disabled(vm.questionText.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
            .help("Send question (Enter)")
        }
    }

    private func contextEditor(_ text: Binding<String>, placeholder: String,
                               height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 11))
            .frame(height: height)
            .scrollContentBackground(.hidden)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
    }

    private func line(_ tag: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(tag)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
