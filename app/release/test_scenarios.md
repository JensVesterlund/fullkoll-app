# Internal Test Scenarios (5-8 cases)

1) First launch and locale
- Preconditions: Fresh install, system locale sv-SE
- Steps: Launch -> observe onboarding/auth, switch language in Settings to EN, restart app
- Expected: Localized strings update; persisted locale respected after restart

2) Receipts flow with OCR hint
- Steps: Go to Receipts -> Add -> use /dev/ocr with file name "ica_kvitto_437kr.jpg" -> confirm fields
- Expected: Store/amount/date prefilled; low-confidence fields marked; user can edit and save

3) Gift card with sensitive reveal
- Steps: Add gift card -> observe masked number -> tap "Show for 60s" and re-auth
- Expected: Number visible for 60s; auto-mask afterwards

4) Budget chart performance
- Steps: Open Budget -> navigate between months rapidly (10x)
- Expected: Smooth transitions; chart memoization prevents stutter; no sustained frame drops

5) Offline behavior and retry
- Steps: Disable network -> open Receipts/Gift Cards -> view last known data; try to add -> enable network
- Expected: Read shows cached data; write queues with banner; retries succeed when online

6) Export/Import toggle (if enabled)
- Steps: Enable feature flag FULLKOLL_FEATURE_EXPORT_IMPORT=true; export CSV; re-import sample file
- Expected: Mapping preview appears; bad rows flagged; successful rows imported

7) Notifications permission prompt (platform)
- Steps: Trigger a reminder scheduling (mock) -> grant/deny prompt
- Expected: App handles both outcomes gracefully; no crash

8) Accessibility quick tour
- Steps: Turn on VoiceOver/TalkBack -> navigate main tabs and a form
- Expected: Elements focusable in logical order; labels announced; sufficient contrast