#!/bin/bash
# Build the app and produce a distributable zip for a GitHub Release.
# Output: dist/InterviewCopilot-macOS.zip
set -euo pipefail

./build_app.sh

mkdir -p dist
rm -f dist/InterviewCopilot-macOS.zip

# `ditto` makes a macOS-correct archive that preserves the code signature
# (a plain `zip` can corrupt it).
ditto -c -k --sequesterRsrc --keepParent InterviewCopilot.app \
    dist/InterviewCopilot-macOS.zip

echo "✅ Created dist/InterviewCopilot-macOS.zip"
echo "   Upload this to a GitHub Release. Users download, unzip, and follow"
echo "   the install steps in README.md."
