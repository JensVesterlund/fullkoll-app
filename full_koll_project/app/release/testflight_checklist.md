# TestFlight - Internal Testing Checklist

Owner: iOS Lead

Preflight
- [ ] Bump version/build in pubspec.yaml and iOS build number
- [ ] Set FULLKOLL_ENV=stage via dart-define for staging builds
- [ ] Ensure Runner.entitlements includes aps-environment (development or production)
- [ ] Info.plist UIBackgroundModes includes remote-notification
- [ ] Verify notifications usage strings present in Info.plist

Build & upload
- [ ] Build archive with correct signing profile
- [ ] Validate archive; upload via Transporter/Xcode
- [ ] Add release notes (internal) referencing app/release/GO-NOGO.md

App Store Connect setup
- [ ] Create new TestFlight build group
- [ ] Add internal testers
- [ ] Attach privacy policy URL
- [ ] Ensure screenshots/placeholders ok (or skip for internal)

Smoke tests
- [ ] App launches and auth screen loads
- [ ] Navigate to Home/Receipts/Gift Cards/Budget/Split
- [ ] Notifications permission prompt deferred or handled gracefully
- [ ] PDF/CSV export superficial check (if enabled)

Reporting
- [ ] Collect feedback in shared doc
- [ ] File issues using titles matching Known issues in GO-NOGO