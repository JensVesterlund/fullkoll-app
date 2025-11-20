# Google Play - Internal Testing Checklist

Owner: Android Lead

Preflight
- [ ] Bump versionCode/versionName in pubspec.yaml and android/app/build.gradle if present
- [ ] Set FULLKOLL_ENV=stage via dart-define for staging builds
- [ ] AndroidManifest has POST_NOTIFICATIONS (Android 13+)
- [ ] Verify camera usage string in Play Console data safety

Build & upload
- [ ] Build aab (release)
- [ ] Upload to Play Console Internal testing track
- [ ] Provide release notes with link to app/release/GO-NOGO.md

Play Console setup
- [ ] Create internal testing release
- [ ] Add testers (email list)
- [ ] Add privacy policy URL

Smoke tests
- [ ] App launches and auth screen loads
- [ ] Navigate to Home/Receipts/Gift Cards/Budget/Split
- [ ] Notifications permission prompt handled (Android 13+)
- [ ] CSV/PDF export superficial check (if enabled)

Reporting
- [ ] Collect feedback in shared doc
- [ ] File issues matching Known issues in GO-NOGO