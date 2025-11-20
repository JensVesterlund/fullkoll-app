/// Centralized environment and feature-flag configuration.
///
/// Use --dart-define to override at build time:
///  - FULLKOLL_ENV=dev|stage|prod
///  - FULLKOLL_FEATURE_DEV_ROUTES=true|false
///  - FULLKOLL_FEATURE_EXPORT_IMPORT=true|false
///  - FULLKOLL_PUSH_ENABLED=true|false
///
/// Defaults:
///  - Env.dev in debug; Env.prod in release unless overridden
///  - Dev routes enabled in dev/stage, disabled in prod
///  - Export/Import enabled in dev/stage, disabled in prod
///  - Push disabled unless explicitly enabled
library env;

import 'package:flutter/foundation.dart';

enum FullKollEnv { dev, stage, prod }

class Env {
  Env._();

  static final String _raw = const String.fromEnvironment('FULLKOLL_ENV', defaultValue: '');

  static FullKollEnv get current {
    final v = _raw.trim().toLowerCase();
    if (v == 'dev') return FullKollEnv.dev;
    if (v == 'stage' || v == 'staging') return FullKollEnv.stage;
    if (v == 'prod' || v == 'production') return FullKollEnv.prod;
    // Fallback: debug -> dev, release/profile -> prod
    return kDebugMode ? FullKollEnv.dev : FullKollEnv.prod;
  }

  static bool get isDev => current == FullKollEnv.dev;
  static bool get isStage => current == FullKollEnv.stage;
  static bool get isProd => current == FullKollEnv.prod;

  /// A permissive switch that treats any legacy FULLKOLL_DEV_MODE=true as dev.
  static const bool legacyDevMode = bool.fromEnvironment('FULLKOLL_DEV_MODE', defaultValue: false);

  /// Whether push-related code paths may be active. This only toggles client-side features;
  /// actual backend/keys must be provisioned separately.
  static const bool pushEnabled = bool.fromEnvironment('FULLKOLL_PUSH_ENABLED', defaultValue: false);
}

class FeatureFlags {
  FeatureFlags._();

  /// Enable developer routes like /dev/ocr, /dev/i18n, /dev/health.
  static bool get devRoutes {
    const override = bool.fromEnvironment('FULLKOLL_FEATURE_DEV_ROUTES');
    if (override) return true; // explicit true wins
    // If not explicitly true/false, default to on in dev/stage, off in prod.
    final hasDefine = const bool.hasEnvironment('FULLKOLL_FEATURE_DEV_ROUTES');
    if (!hasDefine) return Env.isDev || Env.isStage || Env.legacyDevMode || kDebugMode;
    return false; // explicit false
  }

  /// Export/Import UI enablement. Off by default in prod.
  static bool get exportImport {
    const override = bool.fromEnvironment('FULLKOLL_FEATURE_EXPORT_IMPORT');
    if (override) return true;
    final hasDefine = const bool.hasEnvironment('FULLKOLL_FEATURE_EXPORT_IMPORT');
    if (!hasDefine) return Env.isDev || Env.isStage || kDebugMode;
    return false;
  }
}
