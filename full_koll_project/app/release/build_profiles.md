# Build Profiles and Feature Flags

Files
- lib/config/env.dart: central environment and feature flags
- ios/Runner/Info.plist: UIBackgroundModes (remote-notification)
- ios/Runner/Runner.entitlements: aps-environment (development by default)
- android/app/src/main/AndroidManifest.xml: POST_NOTIFICATIONS permission

Dart defines (examples)
- FULLKOLL_ENV=dev|stage|prod
- FULLKOLL_FEATURE_DEV_ROUTES=true|false
- FULLKOLL_FEATURE_EXPORT_IMPORT=true|false
- FULLKOLL_PUSH_ENABLED=true|false

Defaults
- Env: debug -> dev, release/profile -> prod
- Dev routes: enabled in dev/stage, disabled in prod
- Export/Import: enabled in dev/stage, disabled in prod
- Push: disabled unless FULLKOLL_PUSH_ENABLED=true

Notes
- Dreamflow Publish builds use these if provided as dart-define. Without overrides, sensible defaults apply.
- Backend (Firebase/Supabase) is not connected; push is stubbed.