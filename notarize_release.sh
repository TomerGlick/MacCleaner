#!/bin/bash
#
# Build, sign, notarize and staple a release DMG that opens without a Gatekeeper warning.
#
# Gatekeeper needs four things, and all four have to be true at once:
#
#   1. Signed with a *Developer ID Application* certificate. Not "Apple Development"
#      (works only on machines registered to the team) and not "Apple Distribution"
#      (Mac App Store / TestFlight only).
#   2. Hardened runtime enabled. Already set in the project.
#   3. A secure timestamp on the signature.
#   4. Notarized by Apple and the ticket stapled to the DMG, so it validates offline.
#
# ── One-time setup ────────────────────────────────────────────────────────────
#
#   a) Create the certificate. Only the team's *Account Holder* can do this, and a
#      team is limited to five. In Xcode: Settings → Accounts → select the team →
#      Manage Certificates → + → Developer ID Application. Or via
#      developer.apple.com/account/resources/certificates.
#
#   b) Create an app-specific password at appleid.apple.com → Sign-In and Security →
#      App-Specific Passwords. Your normal Apple ID password will not work.
#
#   c) Store the notarization credentials in the keychain once:
#
#        xcrun notarytool store-credentials "MacCleanerNotary" \
#          --apple-id "<your-apple-id>" \
#          --team-id "<your-team-id>" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# Then: ./notarize_release.sh 1.3.0
#
set -euo pipefail

VERSION=${1:-}
# Read off the signing certificate rather than hardcoded, so the script carries no
# account details and works for whoever holds the Developer ID.
TEAM_ID=${TEAM_ID:-}
KEYCHAIN_PROFILE=${KEYCHAIN_PROFILE:-MacCleanerNotary}
APP_NAME="Mac Storage Cleanup"
SCHEME="MacStorageCleanupApp"
BUILD_DIR="./build/notarize"
DMG_NAME="MacCleaner-v${VERSION}.dmg"

if [ -z "$VERSION" ]; then
    echo "Usage: ./notarize_release.sh <version>    e.g. ./notarize_release.sh 1.3.0"
    exit 1
fi

# ── Preflight ─────────────────────────────────────────────────────────────────
# Fail early with an explanation rather than part-way through a signed build.

# `|| true` matters: with `set -euo pipefail`, a grep that matches nothing would kill
# the script here — silently, before the explanation below ever prints.
IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" \
    | head -1 \
    | sed -E 's/.*"(.*)"/\1/' || true)

if [ -z "$IDENTITY" ]; then
    echo "❌ No 'Developer ID Application' certificate in the keychain."
    echo
    echo "   Found instead:"
    security find-identity -v -p codesigning | sed 's/^/     /'
    echo
    echo "   'Apple Development' only opens on Macs registered to the team."
    echo "   'Apple Distribution' is for the Mac App Store, not direct download."
    echo
    echo "   See the one-time setup notes at the top of this script."
    exit 1
fi

# "Developer ID Application: Name (TEAMID)" -> TEAMID
if [ -z "$TEAM_ID" ]; then
    TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$IDENTITY")
fi

echo "🔑 Signing identity: $IDENTITY"
echo "👥 Team: $TEAM_ID"

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    echo "❌ No stored notarization credentials under profile '$KEYCHAIN_PROFILE'."
    echo "   See step (c) in the setup notes at the top of this script."
    exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "❌ create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────

echo "🏗  Building Release…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project MacStorageCleanupApp.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build | tail -3

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$SCHEME.app"
[ -d "$APP_PATH" ] || { echo "❌ Build produced no app at $APP_PATH"; exit 1; }

# ── Verify the signature before spending a notarization round-trip on it ───────

echo "🔍 Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Captured once rather than piped into `grep -q`: under `set -o pipefail`, grep -q exits
# on the first match, codesign takes SIGPIPE, and the pipeline reports failure on a
# signature that was perfectly fine.
SIGNATURE=$(codesign -dvvv "$APP_PATH" 2>&1)

if ! grep -q "Authority=Developer ID Application" <<<"$SIGNATURE"; then
    echo "❌ App is not signed with Developer ID Application. Actual:"
    grep -E "Authority|TeamIdentifier" <<<"$SIGNATURE" | sed 's/^/     /'
    exit 1
fi

if ! grep -q "flags=.*runtime" <<<"$SIGNATURE"; then
    echo "❌ Hardened runtime is not enabled on the built app."
    exit 1
fi

if ! grep -q "TeamIdentifier=$TEAM_ID" <<<"$SIGNATURE"; then
    echo "❌ Signed by a different team than \$TEAM_ID ($TEAM_ID). Actual:"
    grep "TeamIdentifier" <<<"$SIGNATURE" | sed 's/^/     /'
    exit 1
fi

# `get-task-allow` is the debug entitlement that lets a debugger attach. Xcode injects it
# on a plain `build`, and the notary service rejects any archive carrying it. Catching it
# here costs a second; catching it at Apple costs a round-trip.
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true)

if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
    echo "❌ Built app requests com.apple.security.get-task-allow; the notary service"
    echo "   rejects this. CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO should have prevented it."
    exit 1
fi

# ── Package ───────────────────────────────────────────────────────────────────

echo "💿 Creating DMG…"
STAGE="$BUILD_DIR/stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
rm -f "$DMG_NAME"

create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 425 120 \
    "$DMG_NAME" \
    "$STAGE"

# The DMG is signed too, so the download itself carries a verifiable signature.
echo "✍️  Signing DMG…"
codesign --sign "$IDENTITY" --timestamp "$DMG_NAME"

# ── Notarize ──────────────────────────────────────────────────────────────────

echo "📤 Submitting to Apple (this usually takes a few minutes)…"
# `notarytool submit --wait` exits 0 even when the result is Invalid, so the status has to
# be read out of the output rather than trusted to the exit code.
SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_NAME" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait 2>&1)
echo "$SUBMIT_OUTPUT"

SUBMISSION_ID=$(grep -m1 "  id: " <<<"$SUBMIT_OUTPUT" | awk '{print $2}')

if ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
    echo
    echo "❌ Notarization did not succeed. Apple's reasons:"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | sed 's/^/   /'
    exit 1
fi

# Stapling attaches the ticket to the DMG so it validates with no network access.
echo "📎 Stapling…"
xcrun stapler staple "$DMG_NAME"

# ── Final check: what Gatekeeper itself will say ──────────────────────────────

echo "✅ Verifying as Gatekeeper sees it…"
xcrun stapler validate "$DMG_NAME"
spctl --assess --type open --context context:primary-signature -vv "$DMG_NAME"

echo
echo "🎉 $DMG_NAME is signed, notarized and stapled."
echo "   Attach it to the release:  gh release upload $VERSION $DMG_NAME --clobber"
