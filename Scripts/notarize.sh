#!/usr/bin/env bash
# TanqueStudio Notarization & Release Script
# Usage: bash Scripts/notarize.sh 0.9.15
# Requires: Developer ID Application cert + TanqueStudio-Notarization Keychain profile
# One-time setup: xcrun notarytool store-credentials "TanqueStudio-Notarization" \
#   --apple-id YOU@email.com --team-id TEAMID

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
VERSION="${1:?Usage: $0 <version>  e.g. $0 0.9.15}"
# Resolved from this script's own location, so the script works from any checkout —
# a worktree, a second machine, a fresh clone — rather than one hardcoded home directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT_DIR}/TanqueStudio.xcodeproj"
SCHEME="TanqueStudio"
APP_DISPLAY_NAME="Tanque Studio"      # CFBundleDisplayName — what xcodebuild actually exports
ARCHIVE="/tmp/TanqueStudio.xcarchive"
EXPORT_DIR="/tmp/TanqueStudioExport"
EXPORT_PLIST="/tmp/TanqueStudioExportOptions.plist"
APP_PATH="${EXPORT_DIR}/${APP_DISPLAY_NAME}.app"
NOTARIZE_ZIP="/tmp/TanqueStudio-notarize.zip"
ZIP_DIR="${PROJECT_DIR}/Archives"
ZIP_PATH="${ZIP_DIR}/TanqueStudio-${VERSION}.zip"
KEYCHAIN_PROFILE="TanqueStudio-Notarization"

# ─── Helpers ─────────────────────────────────────────────────────────────────
BOLD="\033[1m"; GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; RESET="\033[0m"

step() { echo -e "\n${BOLD}▶ STEP $1 — $2${RESET}"; }
ok()   { echo -e "  ${GREEN}✔ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${RESET}"; }
die()  { echo -e "  ${RED}✘ FATAL: $1${RESET}" >&2; exit 1; }

# ─── Pre-flight cleanup ───────────────────────────────────────────────────────
rm -rf "${ARCHIVE}" "${EXPORT_DIR}" "${NOTARIZE_ZIP}"
mkdir -p "${ZIP_DIR}"

# ─── STEP 1 — Verify certificate ─────────────────────────────────────────────
step 1 "Verify certificate"
CERT=$(security find-identity -v -p codesigning | grep "Developer ID Application: Ned Baugh" || true)
[[ -n "${CERT}" ]] || die "No 'Developer ID Application: Ned Baugh' certificate found.\nRun: security find-identity -v -p codesigning"
echo "${CERT}"

# Extract Team ID with fallback
TEAM_ID=$(echo "${CERT}" | grep -oE '\([A-Z0-9]+\)' | tr -d '()' | head -1 || true)
if [[ -z "${TEAM_ID}" ]]; then
    TEAM_ID=$(security find-certificate -c "Developer ID Application: Ned Baugh" -p | \
              openssl x509 -noout -subject 2>/dev/null | \
              grep -oE 'OU=[A-Z0-9]+' | head -1 | cut -d= -f2 || true)
fi
[[ -n "${TEAM_ID}" ]] || die "Could not extract Team ID from certificate."
ok "Certificate found. Team ID: ${TEAM_ID}"

# ─── STEP 2 — Create ExportOptions.plist ─────────────────────────────────────
step 2 "Create ExportOptions.plist"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>hardened-runtime</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST
ok "Written to ${EXPORT_PLIST}"

# ─── STEP 3 — Archive ────────────────────────────────────────────────────────
step 3 "Archive (this takes a few minutes…)"
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE}" \
    -destination "generic/platform=macOS" \
    ONLY_ACTIVE_ARCH=NO \
    | tee /tmp/ts_archive.log \
    | tail -5
if ! grep -q "ARCHIVE SUCCEEDED" /tmp/ts_archive.log; then
    warn "Relevant build output:"
    grep -E "error:|warning:|ARCHIVE" /tmp/ts_archive.log | tail -40
    die "Archive failed. Full log at /tmp/ts_archive.log"
fi
ARCHIVE_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
ok "Archive succeeded. Size: ${ARCHIVE_SIZE}"

# ─── STEP 4 — Export signed app ──────────────────────────────────────────────
step 4 "Export signed app"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportOptionsPlist "${EXPORT_PLIST}" \
    -exportPath "${EXPORT_DIR}" \
    | tee /tmp/ts_export.log \
    | tail -5
if ! grep -q "EXPORT SUCCEEDED" /tmp/ts_export.log; then
    warn "Relevant export output:"
    grep -E "error:|warning:|EXPORT" /tmp/ts_export.log | tail -40
    die "Export failed. Full log at /tmp/ts_export.log"
fi
[[ -d "${APP_PATH}" ]] || die "Export succeeded but '${APP_DISPLAY_NAME}.app' not found at ${APP_PATH}\nContents of ${EXPORT_DIR}:\n$(ls -1 ${EXPORT_DIR})"
ok "Export succeeded. App at: ${APP_PATH}"

# ─── STEP 5 — Verify signing ─────────────────────────────────────────────────
step 5 "Verify signing"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 || die "codesign verification failed."
ok "Code signature valid."

# ─── STEP 6 — Zip and submit for notarization ────────────────────────────────
# notarytool requires a .zip/.pkg/.dmg — cannot submit a bare .app directly
step 6 "Zip and submit for notarization (1–5 minutes…)"
cd "${EXPORT_DIR}"
ditto -c -k --keepParent "${APP_DISPLAY_NAME}.app" "${NOTARIZE_ZIP}"
ok "Zipped for submission: ${NOTARIZE_ZIP}"

NOTARIZE_OUTPUT=$(xcrun notarytool submit "${NOTARIZE_ZIP}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait 2>&1)
echo "${NOTARIZE_OUTPUT}"

SUBMISSION_ID=$(echo "${NOTARIZE_OUTPUT}" | grep -E "^\s*id:" | head -1 | awk '{print $2}' || true)
STATUS=$(echo "${NOTARIZE_OUTPUT}" | grep -E "^\s*status:" | tail -1 | awk '{print $2}' || true)

if [[ "${STATUS}" != "Accepted" ]]; then
    warn "Notarization status: ${STATUS}"
    if [[ -n "${SUBMISSION_ID}" ]]; then
        warn "Fetching notarization log for submission ${SUBMISSION_ID}…"
        xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${KEYCHAIN_PROFILE}" 2>&1 || true
    fi
    die "Notarization was not accepted (status: ${STATUS}). See log above."
fi
ok "Notarization accepted. Submission ID: ${SUBMISSION_ID}"

# ─── STEP 7 — Staple ─────────────────────────────────────────────────────────
step 7 "Staple notarization ticket"
STAPLE_OUT=$(xcrun stapler staple "${APP_PATH}" 2>&1)
echo "${STAPLE_OUT}"
echo "${STAPLE_OUT}" | grep -q "The staple and validate action worked" || die "Stapler did not confirm success."
ok "Staple successful."

# ─── STEP 8 — Package release zip ────────────────────────────────────────────
step 8 "Package release zip"
cd "${EXPORT_DIR}"
ditto -c -k --keepParent "${APP_DISPLAY_NAME}.app" "${ZIP_PATH}"
[[ -f "${ZIP_PATH}" ]] || die "Release zip not created at ${ZIP_PATH}"
ZIP_SIZE=$(du -sh "${ZIP_PATH}" | cut -f1)
ok "Release zip: ${ZIP_PATH} (${ZIP_SIZE})"

# ─── STEP 9 — Final Gatekeeper check ─────────────────────────────────────────
step 9 "Final Gatekeeper check (post-staple)"
SPCTL_OUT=$(spctl --assess --type execute --verbose "${APP_PATH}" 2>&1)
echo "  ${SPCTL_OUT}"
if echo "${SPCTL_OUT}" | grep -qi "notarized developer id\|accepted"; then
    ok "Gatekeeper confirms: Notarized Developer ID"
else
    warn "spctl did not confirm 'Notarized Developer ID' — may be a timing issue."
    warn "Retry manually: spctl --assess --type execute --verbose \"${APP_PATH}\""
fi

# ─── Final Report ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo -e "${BOLD} TanqueStudio ${VERSION} — Notarization Complete${RESET}"
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo -e "  Archive size  : ${ARCHIVE_SIZE}"
echo -e "  Submission ID : ${SUBMISSION_ID:-unknown}"
echo -e "  Release zip   : ${ZIP_PATH}"
echo -e "  Zip size      : ${ZIP_SIZE}"
echo -e "  Notarization  : ${GREEN}Accepted${RESET}"
echo -e "  Staple        : ${GREEN}Applied${RESET}"
echo ""
echo -e "  Next: github.com/skeptict/TanqueStudio/releases/new"
echo -e "        Tag: v${VERSION}  |  Upload: $(basename ${ZIP_PATH})"
echo ""
