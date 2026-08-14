# Install — Interview Copilot (macOS)

**Requirements:** a Mac on **macOS 14+**, and your own **API key** (OpenAI,
Anthropic, or Google Gemini — Gemini has a free tier). A **Deepgram** key is
optional but gives much better transcription.

---

## 1. Download

**[⬇️ Download InterviewCopilot-macOS.zip](../../releases/latest/download/InterviewCopilot-macOS.zip)**
(or pick it from the [Releases](../../releases) page). Unzip it and drag
**InterviewCopilot.app** into your **Applications** folder.

## 2. Remove the quarantine (one time)

Because the app isn't from the App Store, macOS blocks it until you clear the
download flag. Open **Terminal** and run:

```bash
xattr -dr com.apple.quarantine /Applications/InterviewCopilot.app
```

> If you skip this, macOS may say the app is "damaged." That message just means
> the quarantine flag is still set — run the command above and it opens fine.
>
> *Alternative:* double-click the app, let it get blocked once, then go to
> **System Settings → Privacy & Security** and click **Open Anyway**.

## 3. Launch it

Open it from **Spotlight** (⌘Space → type "Interview Copilot") or Launchpad.
A **waveform icon** appears in your **menu bar** (top-right). There's no Dock icon.
<img width="366" height="358" alt="image" src="https://github.com/user-attachments/assets/1a1ac57d-0ed2-45dd-8872-102ffbe0826e" />


## 4. Grant permissions (first time you press Start)

Click the menu-bar icon → **Start listening**. macOS will ask for permissions —
grant these in **System Settings → Privacy & Security**:

- **Screen Recording** — needed to capture the call's audio (it does *not*
  record your screen).
- **Microphone** — to transcribe your side.
- **Speech Recognition** — only if you use the free Apple engine.

After granting **Screen Recording**, use the menu bar → **Relaunch app** so it
takes effect.

## 5. Add your API key

Menu-bar icon → **Open settings…** → pick your provider, paste your key, choose a
model, **Save**. *(Optional: choose **Deepgram** under Transcription and paste
that key for better accuracy.)*

---

## You're done

Press **Start listening** before your call. The interviewer's questions appear as
**Q:** lines and answers stream into the overlay. Use the shortcuts:

| Key | Action |
|---|---|
| **⌃⌥A** | Answer the spoken question |
| **⌃⌥S** | Answer what's on your screen |
| **⌃⌥H** | Show / hide the overlay |
| **⌃⌥M** | Toggle mic |
| **⌃⌥R** | Toggle résumé use |

The overlay is **hidden from screen sharing and recordings**, so only you see it.

Full details and troubleshooting are in the [README](README.md).
