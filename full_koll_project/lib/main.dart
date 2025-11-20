import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme.dart';
import 'i18n/app_localizations.dart';
import 'settings_screen.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'receipts_screen.dart';
import 'giftcards_screen.dart';
import 'budget_screen.dart';
import 'split_screen.dart';
import 'autogiro_screen.dart';
import 'services.dart';
import 'models.dart' as app_models;
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'dev_status_screen.dart';
import 'dev_i18n_screen.dart';
import 'services/analytics.dart';
import 'widgets/global_error_boundary.dart';
import 'legal/privacy_page.dart';
import 'utils/perf.dart';
import 'dev_health_screen.dart';
import 'config/env.dart';
import 'dev_ocr_screen.dart';
import 'config.dart'; // Supabase config (URL + anon key)
// Web dev-only cache/service worker safeguards
import 'utils/web_dev_safeguards_stub.dart'
    if (dart.library.html) 'utils/web_dev_safeguards_web.dart';
// Web KV store for locale persistence
import 'utils/web_kv_store_stub.dart'
    if (dart.library.html) 'utils/web_kv_store_web.dart';

const bool _envDevMode = bool.fromEnvironment('FULLKOLL_DEV_MODE', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safe debug-only log to confirm Supabase constants are wired without leaking secrets.
  assert(() {
    final urlOk = supabaseUrl.startsWith('http');
    final keyLen = supabaseAnonKey.isEmpty ? 0 : supabaseAnonKey.length;
    debugPrint('[Config] Supabase URL ok: $urlOk, anonKey length: $keyLen');
    return true;
  }());

  // In web debug/development, ensure we don't have a stale service worker/cache
  // that can blank the preview. This will reload the page once if cleanup ran.
  if (kIsWeb) {
    final devMode = Env.isDev || _envDevMode || kDebugMode || Env.legacyDevMode;
    await ensureCleanWebStartIfNeeded(devMode: devMode);
  }

  // Initialize Supabase before booting the app
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    // Keep events rate modest in dev to avoid noisy streams
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 5),
  );

  // Debug-only: log auth state changes so we can see session transitions.
  assert(() {
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      debugPrint('[Supabase] auth state: ${event.event.name}, user=${event.session?.user.id ?? 'none'}');
    });
    return true;
  }());

  // Simple debug-only sanity check that the client is accessible.
  assert(() {
    final user = Supabase.instance.client.auth.currentUser;
    debugPrint('[Supabase] client ready; currentUser: ${user?.id ?? 'none'}');
    return true;
  }());

  // Mark app start for perf tracking and create the Flutter binding when runApp is called.
  PerfTracker.markAppStart();
  runApp(const MyApp());

  // Configure error handlers and run async, non-critical init AFTER first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // First frame reached: use this as our rough TTI in preview/dev.
    PerfTracker.markFirstFrame();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final stack = details.stack ?? StackTrace.current;
      AnalyticsService.logError(details.exception, stack, hint: 'flutter_error');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AnalyticsService.logError(error, stack, hint: 'platform_dispatcher');
      return true;
    };

    unawaited(AnalyticsService.logBreadcrumb('main: init date formatting start'));
    try {
      await initializeDateFormatting('sv-SE', null).timeout(const Duration(seconds: 5));
      unawaited(AnalyticsService.logBreadcrumb('main: date formatting ok'));
    } catch (e, st) {
      debugPrint('main: date formatting failed or timed out: $e');
      unawaited(AnalyticsService.logError(e, st, hint: 'init_date_formatting'));
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  app_models.User? _currentUser;
  bool _isCheckingAuth = true;
  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
  // Development-like UI affordances (guest login, auth watchdogs)
  late final bool _isDevLikeRuntime = Env.isDev || Env.legacyDevMode || kDebugMode;
  final LocaleController _localeController = LocaleController();
  bool _loggedFirstBuild = false;
  bool _authFallbackToScreen = false; // Show /auth if auth check is slow

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.logBreadcrumb('MyApp.initState'));
    unawaited(AnalyticsService.logBreadcrumb('zone: MyApp.initState', context: {
      'hash': Zone.current.hashCode,
      'isRoot': Zone.current == Zone.root,
    }));
    // Apply any stored locale preference early (before auth applies user locale)
    try {
      final tag = webGetItem('locale');
      if (tag != null && tag.isNotEmpty) {
        final parts = tag.split('-');
        if (parts.length == 2) {
          _localeController.setLocale(Locale(parts[0], parts[1]));
        } else if (parts.isNotEmpty) {
          _localeController.setLocale(Locale(parts.first));
        }
      }
    } catch (_) {}

    _checkAuth();

    // Dev safeguard: if something stalls during initial auth check on web,
    // make sure we don't sit on the spinner forever.
    if (_isDevLikeRuntime) {
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        if (_isCheckingAuth) {
          unawaited(AnalyticsService.logBreadcrumb('auth: watchdog clearing spinner after 5s'));
          setState(() => _isCheckingAuth = false);
        }
      });
    }

    // UX fallback: if auth check takes >1s, render router at /auth immediately
    // and continue checking in background to keep UI responsive.
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_isCheckingAuth && !_authFallbackToScreen) {
        unawaited(AnalyticsService.logBreadcrumb('auth: fallback to /auth after 1s'));
        setState(() => _authFallbackToScreen = true);
      }
    });
  }

  @override
  void dispose() {
    _localeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    try {
      unawaited(AnalyticsService.logBreadcrumb('auth: getCurrentUser start'));
      _currentUser = await AuthService.getCurrentUser();
      unawaited(AnalyticsService.logBreadcrumb('auth: getCurrentUser done', context: {
        'hasUser': _currentUser != null,
      }));
      final user = _currentUser;
      if (user != null) {
        _applyUserLocale(user);
        if (user.privacyAcceptedAt == null) {
          await _showPrivacyDialog();
        }
      }
    } finally {
      if (mounted) {
        unawaited(AnalyticsService.logBreadcrumb('auth: setState clearing spinner'));
        setState(() => _isCheckingAuth = false);
        // If router is already showing /auth due to fallback, navigate to /home when ready.
        if (_currentUser != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _rootNavigatorKey.currentContext;
            if (ctx != null) {
              try {
                GoRouter.of(ctx).go('/home');
              } catch (_) {}
            }
          });
        }
        unawaited(AnalyticsService.logBreadcrumb('auth: setState done'));
      }
    }
  }

  Future<void> _showPrivacyDialog() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final dialogContext = _rootNavigatorKey.currentContext;
    if (dialogContext == null) return;
    await showDialog(
      context: dialogContext,
      barrierDismissible: false,
          builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('legal.privacy.title')),
        content: SingleChildScrollView(
          child: Text(
            context.l10n.translate('legal.privacy.dialog.body'),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final user = _currentUser;
              if (user == null) return;
              final acceptedAt = await AuthService.acceptPrivacy(user.id);
              if (!mounted) return;
              setState(() {
                _currentUser = user.copyWith(
                  privacyAcceptedAt: acceptedAt,
                  privacyVersion: 1,
                );
              });
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: Text(context.l10n.translate('common.accept')),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_currentUser?.id == AuthService.guestUserId) {
      await AuthService.logoutGuest();
    } else {
      await AuthService.logout();
    }
    if (!mounted) return;
    setState(() => _currentUser = null);
    _localeController.setLocale(const Locale('sv', 'SE'));
    // Clear persisted locale on web to return to default after logout.
    webRemoveItem('locale');
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx != null) {
      GoRouter.of(ctx).go('/auth');
    }
  }

  void _applyUserLocale(app_models.User user) {
    final localeParts = user.locale.split('-');
    if (localeParts.length == 2) {
      final locale = Locale(localeParts[0], localeParts[1]);
      _localeController.setLocale(locale);
      webSetItem('locale', AppLocalizations.tagFor(locale));
    } else if (localeParts.length == 1 && localeParts.first.isNotEmpty) {
      final locale = Locale(localeParts.first);
      _localeController.setLocale(locale);
      webSetItem('locale', AppLocalizations.tagFor(locale));
    } else {
      final locale = const Locale('sv', 'SE');
      _localeController.setLocale(locale);
      webSetItem('locale', AppLocalizations.tagFor(locale));
    }
  }

  void _handleAuthenticated(app_models.User user, BuildContext context) {
    setState(() => _currentUser = user);
    _applyUserLocale(user);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _localeController,
      builder: (context, _) {
        final locale = _localeController.locale;

        if (_isCheckingAuth && !_authFallbackToScreen) {
          if (!_loggedFirstBuild) {
            _loggedFirstBuild = true;
            unawaited(AnalyticsService.logBreadcrumb('build: showing auth spinner'));
          }
          return MaterialApp(
            navigatorKey: _rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              // Use a Builder so that Theme.of and context.l10n resolve inside MaterialApp's
              // Localizations/Theme scope. Using the outer AnimatedBuilder context caused
              // AppLocalizations to be null.
              builder: (appCtx) => Scaffold(
                backgroundColor: Theme.of(appCtx).colorScheme.surface,
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Theme.of(appCtx).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        appCtx.l10n.translate('common.loading'),
                        style: Theme.of(appCtx).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final routes = <RouteBase>[
          GoRoute(
            path: '/auth',
            builder: (context, state) => AuthScreen(
              onAuthenticated: (user) => _handleAuthenticated(user, context),
              showGuestLogin: FeatureFlags.devRoutes,
              localeController: _localeController,
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => _currentUser == null
                ? AuthScreen(onAuthenticated: (user) => _handleAuthenticated(user, context), localeController: _localeController)
                : HomeScreen(
                    user: _currentUser!,
                    onLogout: _handleLogout,
                  ),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : ReceiptsScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
          GoRoute(
            path: '/giftcards',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : GiftCardsScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
          GoRoute(
            path: '/budget',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : BudgetScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
          GoRoute(
            path: '/split',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : SplitScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
          GoRoute(
            path: '/autogiro',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : AutoGiroScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
          GoRoute(
            path: '/legal/privacy',
            builder: (context, state) => const PrivacyPage(),
          ),
          GoRoute(
            path: '/privacy',
            redirect: (context, state) => '/legal/privacy',
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => _currentUser == null
                ? Scaffold(body: Center(child: Text(context.l10n.translate('auth.notAuthenticated'))))
                : SettingsScreen(
                    user: _currentUser!,
                    localeController: _localeController,
                    onUserUpdated: (user) => setState(() => _currentUser = user),
                    onLogout: _handleLogout,
                  ),
          ),
          // Always expose /dev/health so QA can access health checks in preview builds
          // even if FULLKOLL_FEATURE_DEV_ROUTES is off. The screen itself only
          // contains diagnostic/tests and keeps asserts for debug-only hints.
          GoRoute(
            path: '/dev/health',
            builder: (context, state) => const DevHealthScreen(),
          ),
        ];

        if (FeatureFlags.devRoutes) {
          routes.addAll([
            GoRoute(
              path: '/dev/guest-login',
              builder: (context, state) => DevGuestLoginScreen(
                onAuthenticated: (user) {
                  _handleAuthenticated(user, _rootNavigatorKey.currentContext ?? context);
                },
              ),
            ),
            GoRoute(
              path: '/dev/ocr',
              builder: (context, state) => const DevOcrScreen(),
            ),
            GoRoute(
              path: '/dev/status',
              builder: (context, state) => _currentUser == null
                  ? Scaffold(body: Center(child: Text(context.l10n.translate('dev.status.loginToSee'))))
                  : DevStatusScreen(user: _currentUser!),
            ),
            GoRoute(
              path: '/dev/i18n',
              builder: (context, state) => const DevI18nScreen(),
            ),
          ]);
        }

        unawaited(AnalyticsService.logBreadcrumb('build: creating router', context: {
          'initialLocation': _currentUser == null ? '/auth' : '/home',
        }));

        final router = GoRouter(
          navigatorKey: _rootNavigatorKey,
          // If we fell back while checking auth, start on /auth immediately.
          initialLocation: (_isCheckingAuth && _authFallbackToScreen) || _currentUser == null ? '/auth' : '/home',
          routes: routes,
          observers: [PerfTracker.routeObserver],
        );

        unawaited(AnalyticsService.logBreadcrumb('build: returning MaterialApp.router'));

        return MaterialApp.router(
          // Use onGenerateTitle to obtain localized title with a context inside MaterialApp
          onGenerateTitle: (ctx) => ctx.l10n.translate('common.appName'),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
          builder: (context, child) => GlobalErrorBoundary(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

class DevGuestLoginScreen extends StatefulWidget {
  final ValueChanged<app_models.User> onAuthenticated;

  const DevGuestLoginScreen({super.key, required this.onAuthenticated});

  @override
  State<DevGuestLoginScreen> createState() => _DevGuestLoginScreenState();
}

class _DevGuestLoginScreenState extends State<DevGuestLoginScreen> {
  bool _isWorking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      final user = await AuthService.loginGuest();
      if (!mounted) return;
      widget.onAuthenticated(user);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _error = context.l10n.translate('errors.couldNotStartGuest', params: {'error': e});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.translate('dev.guest.mode'))),
      body: Center(
        child: _isWorking
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.l10n.translate('dev.guest.preparing')),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text(_error ?? context.l10n.translate('errors.unknown')),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _bootstrap,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.l10n.translate('common.tryAgain')),
                  ),
                ],
              ),
      ),
    );
  }
}
