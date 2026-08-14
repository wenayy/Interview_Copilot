# Interview Copilot for macOS

[![Download](https://img.shields.io/github/downloads/wenayy/Interview_Copilot/total?label=downloads&color=2ea44f)](../../releases/latest)
[![Stars](https://img.shields.io/github/stars/wenayy/Interview_Copilot?style=social)](../../stargazers)

A native macOS interview assistant that helps you during live interviews by
listening to the conversation, detecting questions, and giving you fast
AI-generated answer suggestions in real time. It transcribes both sides of the
call and shows the answers in an overlay that is **hidden from screen sharing and
recordings**. Bring your own API keys; runs entirely on your machine.

> **macOS only.** This is built on Apple-only frameworks (AppKit, ScreenCaptureKit,
> Speech). It does **not** run on Windows or Linux.

> ⭐ **If you find this useful, please [star the repo](../../)** — it helps other
> people find it.

## ⬇️ Download

**[➡️ Download the latest version (InterviewCopilot-macOS.zip)](../../releases/latest/download/InterviewCopilot-macOS.zip)**

Then follow **[INSTALL.md](INSTALL.md)** (takes ~2 minutes). New to this? Start there.

> 💡 **After you open it, there's no window and no Dock icon** — look for the
> **waveform icon in your menu bar** (top-right of the screen). Click it to start,
> open settings, and control everything.

---

## ✨ Features

- **Real-time transcription** of the interviewer (system/call audio) and you (mic)
  — works with headphones.
- **AI answers** streamed live, from **OpenAI, Anthropic (Claude), or Google Gemini**
  — your key, your model.
- **Answer styles**: Concise · Detailed · STAR (behavioral) · Code (with complexity).
- **Screen answers** — capture your screen and answer what's *shown* (coding
  problems, multiple-choice, shared docs) using a vision model.
- **Personalization** — paste or load your résumé (PDF/txt); a toggle controls
  whether answers use it, so it's never forced in.
- **Hidden from screen share** — the overlay and settings are excluded from
  Zoom/Meet/Teams/QuickTime screen capture.
- **Global hotkeys** that work while another app is focused (no extra permission).
- **Menu-bar app** — no Dock icon; start/stop/show/hide from the menu bar.
- **Cheap to run** — see [Cost](#-cost).
- **Two transcription engines**: Apple on-device (free) or Deepgram (more accurate).

---

## ✅ Requirements

- A **Mac** running **macOS 14 (Sonoma) or newer**.
- **API keys** (bring your own — the app has no backend/billing):
  - One LLM key: **OpenAI**, **Anthropic**, or **Google Gemini** (Gemini has a free tier).
  - *Optional but recommended:* a **Deepgram** key for accurate transcription
    (Apple's built-in engine works without it).

---

## 📦 Install

### Option A — Download the app (easiest)

1. Download **[InterviewCopilot-macOS.zip](../../releases/latest/download/InterviewCopilot-macOS.zip)**
   (or pick it from the [Releases](../../releases) page).
2. Unzip it and drag **InterviewCopilot.app** into your **Applications** folder.
3. Because the app isn't from the App Store, macOS quarantines it. Remove the
   quarantine so it will open (one time). Open **Terminal** and run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/InterviewCopilot.app
   ```
   *(Alternative: try to open it, then go to **System Settings → Privacy &
   Security** and click **Open Anyway**.)*
4. Launch it from **Spotlight** (⌘Space → "Interview Copilot") or Launchpad.
   A **waveform icon** appears in your menu bar.

### Option B — Build from source (no quarantine issues)

Requires **Xcode Command Line Tools** (`xcode-select --install`).

```bash
git clone <this-repo-url>
cd interview-copilot
./build_app.sh          # builds + installs to /Applications
open /Applications/InterviewCopilot.app
```

For a stable identity so macOS remembers permissions across rebuilds, create a
self-signed **Code Signing** certificate named `InterviewCopilot Dev` in
**Keychain Access → Certificate Assistant → Create a Certificate…**
(Type: *Code Signing*, Self-Signed Root). `build_app.sh` uses it automatically
if present, otherwise falls back to ad-hoc signing.

---

## 🔐 First-run permissions

The first time you click **Start listening**, macOS asks for permissions. Grant
all three in **System Settings → Privacy & Security**:

| Permission | Why |
|---|---|
| **Screen Recording** | Required by macOS to capture the **system/call audio** (it does *not* record your screen). |
| **Microphone** | To transcribe your side of the conversation. |
| **Speech Recognition** | Only if you use the Apple (on-device) engine. |

After granting **Screen Recording**, use the menu bar → **Relaunch app** so it
takes effect.

---

## ⚙️ Setup

1. Menu bar **waveform icon → Open settings…**
2. Pick your **AI provider** and paste your key + model.
3. *(Recommended)* Under **Transcription**, choose **Deepgram** and paste your
   Deepgram key for accurate speech-to-text.
4. Save. The overlay status shows `Using <provider> · <model>`.
5. *(Optional)* Open the overlay → **Context** → load your **résumé** (PDF/txt)
   and add job/role notes.

---

## 🎧 Usage

1. **Start listening** (menu bar or the overlay button). Status turns green and
   shows **"audio ✓"** once call audio is detected.
2. The interviewer's speech appears as cyan **Q:** lines.
3. Get an answer:
   - **Auto** on → answers each question automatically.
   - **Auto** off → press **⌃⌥A** (or click **Answer**) when you want one.
4. For an on-screen question (coding/MCQ), press **⌃⌥S** (or **Screen**).

### Keyboard shortcuts

| Key | Action |
|---|---|
| **⌃⌥A** | Answer the spoken question |
| **⌃⌥S** | Answer from the screen |
| **⌃⌥H** | Show / hide the overlay |
| **⌃⌥M** | Toggle mic listening |
| **⌃⌥R** | Toggle whether answers use your résumé |

These work even when your browser/Meet is focused. The **⌨︎** button in the
overlay shows this list any time.

**Tip:** position the overlay before the call, then drive everything with
shortcuts so you barely touch the mouse.

---

## 💰 Cost

You pay your API providers directly — there's no markup. It's cheap:

- **LLM (answers):** on a low-cost model (e.g. ~$0.20 / $1.20 per 1M tokens),
  each answer is roughly **$0.0007 (well under a cent)**. A whole interview is
  usually **a few cents**.
- **Deepgram (transcription):** ~**$0.006/min per stream**. With both sides that's
  ~**$0.70/hour**; turn **Mic off** for interviewer-only and it's ~**$0.35/hour**.
- **Apple transcription:** free (but less accurate).

Ways to keep it minimal: turn **Auto off** (answer only when you ask), turn
**Mic off** (halves Deepgram), use **Screen** only when the question is on screen,
and use a cheap model. The overlay shows a live **call counter**.

---

## 🫥 How it stays hidden (and the limits)

- The overlay and Settings window use `NSWindow.sharingType = .none`, which
  **excludes them from macOS screen capture** — Zoom/Meet/Teams screen share and
  screen recordings won't show them. You still see them locally.
- **It does not defend against:**
  - a **second camera / phone** pointed at your screen,
  - **proctoring or lockdown software** that scans running processes or blocks
    screen access (some assessment platforms) — such tools can detect a running
    app or prevent capture entirely.

Treat it as invisible on normal video calls, and **detectable** in monitored/
proctored environments.

---

## 🔒 Privacy

- Runs entirely on your Mac. There's no server owned by this project.
- Audio is sent to **your** chosen providers (OpenAI/Anthropic/Gemini/Deepgram)
  for transcription and answers, under **your** API keys.
- Keys are stored locally in your macOS `UserDefaults`. Don't share them.

---

## 🧯 Troubleshooting

- **"Interview Copilot is damaged / can't be opened"** → you skipped the
  quarantine step: `xattr -dr com.apple.quarantine /Applications/InterviewCopilot.app`.
- **Start just reopens the permission screen** → grant **Screen Recording**, then
  menu bar → **Relaunch app** (macOS needs a restart for it to apply).
- **Status stuck on "waiting for audio…"** → the call audio isn't being captured;
  make sure Screen Recording is granted and something is actually playing.
- **"audio ✓" but no Q: lines** → transcription issue; try switching to Deepgram
  in Settings, or check your Deepgram key.
- **401 from the LLM** → re-paste your key (⌘A then ⌘V) and Save; keys are trimmed
  automatically but make sure it's complete.
- **Shortcuts don't fire** → another app may use the same combo; open an issue and
  we'll add remapping.

---

## 🛠️ Contributing

Open source and PRs welcome. Structure:

```
Sources/InterviewCopilot/
  main.swift            menu bar + overlay panel (sharingType = .none) + hotkeys
  ContentView.swift     overlay UI
  CopilotViewModel.swift orchestration (audio → transcribe → answer)
  AudioCapture.swift    ScreenCaptureKit system audio + mic
  Transcriber.swift     Apple SFSpeechRecognizer engine
  DeepgramEngine.swift  Deepgram streaming engine
  AIProvider.swift      OpenAI / Anthropic / Gemini providers + prompts
  AppSettings.swift     persisted settings + Settings window
  ScreenGrabber.swift   one-shot screen capture for vision answers
  HotKeys.swift         global hotkeys (Carbon RegisterEventHotKey)
build_app.sh            build + sign + install to /Applications
package.sh              build + zip for a GitHub Release
```

---

## ⚠️ Disclaimer

This tool is intended for **interview practice, preparation, and meeting
assistance where AI help is permitted**. You are responsible for using it in
accordance with the rules of any interview, assessment, or meeting you take part
in, and with applicable laws. Recording or transcribing others may require their
consent depending on your jurisdiction.
