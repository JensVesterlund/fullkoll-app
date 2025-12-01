#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="ios_backup_${STAMP}"
echo "Backing up iOS into: ${BACKUP_DIR}"

mkdir -p "${BACKUP_DIR}"
if [ -d "ios" ]; then
  cp -R "ios" "${BACKUP_DIR}/ios"
fi

echo "Regenerating ios/ with flutter create ."
rm -rf ios
flutter create .

echo "Restore selected files if they existed (best effort)"
# Restore common files if they were in the old ios
if [ -d "${BACKUP_DIR}/ios" ]; then
  # Info.plist / entitlements / AppDelegate / Assets / Firebase
  cp -f "${BACKUP_DIR}/ios/Runner/Info.plist" "ios/Runner/Info.plist" 2>/dev/null || true
  cp -f "${BACKUP_DIR}/ios/Runner/"*.entitlements "ios/Runner/" 2>/dev/null || true
  cp -f "${BACKUP_DIR}/ios/Runner/AppDelegate."* "ios/Runner/" 2>/dev/null || true
  cp -f "${BACKUP_DIR}/ios/Runner/GoogleService-Info.plist" "ios/Runner/" 2>/dev/null || true
  cp -R "${BACKUP_DIR}/ios/Runner/Assets.xcassets" "ios/Runner/" 2>/dev/null || true

  # If you had custom Podfile, restore (optional) — otherwise keep fresh.
  # cp -f "${BACKUP_DIR}/ios/Podfile" "ios/Podfile" 2>/dev/null || true
fi

echo "Done. New ios/ generated. Backup kept at ${BACKUP_DIR}."
