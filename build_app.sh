#!/bin/bash
# Build InterviewCopilot and wrap it in a proper .app bundle so macOS will
# grant Microphone + Screen Recording permissions (a bare SwiftPM binary can't
# request them). Produces ./InterviewCopilot.app
set -euo pipefail

CONFIG="${1:-release}"
APP="InterviewCopilot.app"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/InterviewCopilot"

echo "▶ Assembling ${APP} …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/InterviewCopilot"
cp Info.plist "$APP/Contents/Info.plist"

# Sign with a stable self-signed identity if available, so macOS keeps the
# Screen Recording / Microphone grants across rebuilds. Falls back to ad-hoc
# (which re-prompts every build) if the cert isn't installed.
IDENTITY="InterviewCopilot Dev"
if security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▶ Signing with '$IDENTITY' (stable identity)…"
    codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
else
    echo "▶ Signing (ad-hoc — cert '$IDENTITY' not found; permissions will"
    echo "   reset each rebuild)…"
    codesign --force --deep --sign - "$APP"
fi

echo "✅ Built $APP"

# Keep the installed copy in /Applications up to date so the user can launch
# from Spotlight/Launchpad (no terminal) and permissions persist (same cert).
if [ -d "/Applications/$APP" ] || [ "${INSTALL:-1}" = "1" ]; then
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/"
    echo "📦 Installed to /Applications/$APP"
fi
echo
echo "Run it with your API key:"
echo "    ANTHROPIC_API_KEY=sk-ant-... open $APP"
echo "or launch the binary directly to keep the env var:"
echo "    ANTHROPIC_API_KEY=sk-ant-... ./$APP/Contents/MacOS/InterviewCopilot"
echo
echo "First launch: grant Microphone and Screen Recording in"
echo "System Settings › Privacy & Security, then relaunch."
