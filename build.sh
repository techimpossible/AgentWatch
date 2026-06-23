#!/bin/bash
# Build AgentWatch.app from the SPM executable.
# Produces ./AgentWatch.app, ad-hoc signed, ready to drag into /Applications.
#
# Usage:
#   ./build.sh                  # build only
#   ./build.sh --run            # build + launch in place
#   ./build.sh --install        # build + copy to ~/Applications/AgentWatch.app
#   ./build.sh --install-system # build + copy to /Applications/ (sudo)
#   ./build.sh --dmg            # build + create AgentWatch-vX.Y.Z.dmg (ad-hoc, internal)
#   ./build.sh --release        # Developer ID sign + notarize + staple + DMG (public)
#
# --release one-time setup (needs an Apple Developer Program membership, $99/yr):
#   1. Create a "Developer ID Application" certificate and install it in your
#      login keychain (Xcode > Settings > Accounts, or developer.apple.com).
#   2. Store notarization credentials once (app-specific password from
#      appleid.apple.com, or an App Store Connect API key):
#        xcrun notarytool store-credentials agentwatch-notary \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" \
#          --password "abcd-efgh-ijkl-mnop"
#   Then:  ./build.sh --release
#   Override defaults with AGENTWATCH_SIGN_ID / AGENTWATCH_NOTARY_PROFILE.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/AgentWatch.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo "0.0.0")"

echo "==> swift build (release)"
cd "$ROOT"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/AgentWatch"
[ -x "$EXECUTABLE" ] || { echo "executable not found at $EXECUTABLE"; exit 1; }

echo "==> assembling .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/AgentWatch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc codesign"
xattr -cr "$APP"
codesign --sign - --force --timestamp=none "$APP"

echo "==> sanity: codesign verify + binding scope"
codesign -dvv "$APP" 2>&1 | grep -E "(Identifier|Signature|Authority)" || true

case "${1:-}" in
    --install)
        DEST="$HOME/Applications/AgentWatch.app"
        mkdir -p "$HOME/Applications"
        echo "==> installing to $DEST"
        # Stop any running copy first so the move doesn't clobber a live binary.
        pkill -x AgentWatch 2>/dev/null || true
        sleep 0.5
        rm -rf "$DEST"
        cp -R "$APP" "$DEST"
        echo "==> installed. Launch with: open '$DEST'"
        ;;
    --install-system)
        # System-wide install requires sudo. Most users don't need this.
        echo "==> installing to /Applications/AgentWatch.app (sudo required)"
        pkill -x AgentWatch 2>/dev/null || true
        sleep 0.5
        sudo rm -rf /Applications/AgentWatch.app
        sudo cp -R "$APP" /Applications/AgentWatch.app
        echo "==> installed. Launch with: open /Applications/AgentWatch.app"
        ;;
    --run)
        pkill -x AgentWatch 2>/dev/null || true
        sleep 0.5
        open "$APP"
        echo "==> launched: $APP"
        ;;
    --dmg)
        DMG="$ROOT/AgentWatch-v${VERSION}.dmg"
        STAGE="$(mktemp -d)/AgentWatch-v${VERSION}"
        mkdir -p "$STAGE"
        cp -R "$APP" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        echo "==> creating DMG: $DMG"
        rm -f "$DMG"
        hdiutil create \
            -volname "AgentWatch v${VERSION}" \
            -srcfolder "$STAGE" \
            -ov \
            -format UDZO \
            "$DMG" >/dev/null
        rm -rf "$STAGE"
        echo "==> done: $DMG"
        echo "    Size: $(du -h "$DMG" | cut -f1)"
        echo "    Share: drag the .dmg into Slack / GitHub release / wherever."
        echo "    Teammates: see INSTALL.md for the right-click → Open dance."
        ;;
    --release)
        # ---- Signed + notarized Developer ID release ----
        # Re-signs (the ad-hoc signature above is replaced) with a real
        # Developer ID Application identity + hardened runtime, notarizes via
        # Apple, and staples the ticket. No sandbox entitlements: AgentWatch
        # reads ~/.claude and drives Terminal via osascript, which the App
        # Sandbox would block. Notarization only requires the hardened runtime.
        NOTARY_PROFILE="${AGENTWATCH_NOTARY_PROFILE:-agentwatch-notary}"
        SIGN_ID="${AGENTWATCH_SIGN_ID:-}"
        if [ -z "$SIGN_ID" ]; then
            SIGN_ID="$(security find-identity -v -p codesigning \
                | awk -F'"' '/Developer ID Application/{print $2; exit}')"
        fi
        if [ -z "$SIGN_ID" ]; then
            echo "ERROR: no 'Developer ID Application' certificate found in the keychain." >&2
            echo "" >&2
            echo "One-time setup (needs Apple Developer Program, \$99/yr):" >&2
            echo "  1. https://developer.apple.com/programs/ — enroll." >&2
            echo "  2. Create + install a 'Developer ID Application' certificate" >&2
            echo "     (Xcode > Settings > Accounts > Manage Certificates, or developer.apple.com)." >&2
            echo "  3. xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
            echo "       --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>" >&2
            echo "" >&2
            echo "Then re-run: ./build.sh --release" >&2
            exit 1
        fi

        echo "==> Developer ID sign + hardened runtime"
        echo "    identity: $SIGN_ID"
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
        codesign --verify --strict --verbose=2 "$APP"
        codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime" || true

        echo "==> notarize (uploads to Apple; can take a few minutes)"
        WORK="$(mktemp -d)"
        ZIP="$WORK/AgentWatch.zip"
        /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
        if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
            echo "ERROR: notarytool failed. Check the credential profile '$NOTARY_PROFILE'" >&2
            echo "       (create it with: xcrun notarytool store-credentials $NOTARY_PROFILE ...)." >&2
            rm -rf "$WORK"; exit 1
        fi
        echo "==> staple the app"
        xcrun stapler staple "$APP"
        xcrun stapler validate "$APP"
        spctl --assess --type execute --verbose=4 "$APP" || true
        rm -rf "$WORK"

        echo "==> create DMG from the stapled app"
        DMG="$ROOT/AgentWatch-v${VERSION}.dmg"
        STAGE="$(mktemp -d)/AgentWatch-v${VERSION}"
        mkdir -p "$STAGE"
        cp -R "$APP" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        rm -f "$DMG"
        hdiutil create -volname "AgentWatch v${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
        rm -rf "$STAGE"

        echo "==> notarize + staple the DMG itself"
        if xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
            xcrun stapler staple "$DMG"
        fi
        echo "==> done: $DMG (Developer ID signed, notarized, stapled)"
        echo "    Size: $(du -h "$DMG" | cut -f1)"
        echo "    This downloads + launches with no Gatekeeper prompts."
        ;;
    *)
        echo "==> built: $APP"
        echo "Next: ./build.sh --run     (launch in place)"
        echo "      ./build.sh --install (copy to ~/Applications/)"
        echo "      ./build.sh --dmg     (ad-hoc DMG for internal sharing)"
        echo "      ./build.sh --release (Developer ID signed + notarized DMG)"
        ;;
esac
