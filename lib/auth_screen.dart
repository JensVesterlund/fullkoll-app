import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services.dart';
import 'services/analytics.dart';
import 'services/auth_supabase.dart';
import 'models.dart';
import 'i18n/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  final Function(User) onAuthenticated;
  final bool showGuestLogin;

  const AuthScreen({super.key, required this.onAuthenticated, this.showGuestLogin = false, this.localeController});

  final LocaleController? localeController;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _sendingMagic = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = await AuthService.login(_loginEmailController.text.trim(), _loginPasswordController.text);
      if (user == null) {
        setState(() {
          _errorMessage = context.l10n.translate('auth.error.invalidCredentials');
          _isLoading = false;
        });
        return;
      }
      widget.onAuthenticated(user);
    } catch (e) {
      setState(() {
        _errorMessage = context.l10n.translate('auth.error.generic', params: {'error': e});
        _isLoading = false;
      });
    }
  }

  Future<void> _handleMagicLink() async {
    final l10n = context.l10n;
    final email = _loginEmailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = l10n.translate('auth.validation.emailInvalid'));
      return;
    }
    setState(() {
      _sendingMagic = true;
      _errorMessage = null;
    });
    try {
      await SupabaseAuthAdapter.signInWithMagicLink(email: email, emailRedirectTo: 'io.fullkoll://login-callback');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('auth.magic.sent'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.translate('auth.error.generic', params: {'error': e});
      });
    } finally {
      if (mounted) setState(() => _sendingMagic = false);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;
      setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // ignore: avoid_print
      print('[UI] Signup pressed');
      final user = await AuthService.signup(_signupEmailController.text.trim(), _signupPasswordController.text);
      // ignore: avoid_print
      print('[UI] Signup created user, seeding...');
      await SeedService.seedData(user);
      // ignore: avoid_print
      print('[UI] Seeding complete, navigating home');
      widget.onAuthenticated(user);
    } catch (e) {
      setState(() {
        _errorMessage = context.l10n.translate('auth.error.generic', params: {'error': e});
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Diagnostics: confirm that AuthScreen is actually building without blocking UI thread.
    // ignore: discarded_futures
    // ignore: unnecessary_await_in_return
    Future.microtask(() => AnalyticsService.logBreadcrumb('AuthScreen.build'));
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text(context.l10n.translate('auth.title'), style: Theme.of(context).textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(context.l10n.translate('auth.subtitle'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: _LanguageSwitcher(controller: widget.localeController),
              ),
              const SizedBox(height: 48),
              TabBar(
                controller: _tabController,
                tabs: [Tab(text: context.l10n.translate('auth.tab.signIn')), Tab(text: context.l10n.translate('auth.tab.signUp'))],
              ),
              SizedBox(
                height: 400,
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildLoginForm(), _buildSignupForm()],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              ],
              if (widget.showGuestLogin) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text(context.l10n.translate('dev.tools'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.engineering),
                  label: Text(context.l10n.translate('dev.guest.start')),
                  onPressed: _isLoading
                      ? null
                      : () {
                          context.go('/dev/guest-login');
                        },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() => Form(
    key: _loginFormKey,
    child: Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _loginEmailController,
            decoration: InputDecoration(labelText: context.l10n.translate('auth.email'), prefixIcon: const Icon(Icons.email)),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v == null || v.isEmpty ? context.l10n.translate('auth.validation.emailRequired') : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            decoration: InputDecoration(labelText: context.l10n.translate('auth.password'), prefixIcon: const Icon(Icons.lock)),
            obscureText: true,
            validator: (v) => v == null || v.isEmpty ? context.l10n.translate('auth.validation.passwordRequired') : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.l10n.translate('auth.tab.signIn')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _sendingMagic ? null : _handleMagicLink,
            icon: const Icon(Icons.mail_outline),
            label: _sendingMagic
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text(context.l10n.translate('auth.magic.sending')),
                    ],
                  )
                : Text(context.l10n.translate('auth.magic.send')),
          ),
        ],
      ),
    ),
  );

  Widget _buildSignupForm() => Form(
    key: _signupFormKey,
    child: Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _signupEmailController,
            decoration: InputDecoration(labelText: context.l10n.translate('auth.email'), prefixIcon: const Icon(Icons.email)),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v == null || !v.contains('@') ? context.l10n.translate('auth.validation.emailInvalid') : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _signupPasswordController,
            decoration: InputDecoration(labelText: context.l10n.translate('auth.password.minLength'), prefixIcon: const Icon(Icons.lock)),
            obscureText: true,
            validator: (v) => v == null || v.length < 10 ? context.l10n.translate('auth.validation.passwordTooShort') : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSignup,
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text(context.l10n.translate('auth.signingUp')),
                    ],
                  )
                : Text(context.l10n.translate('auth.tab.signUp')),
          ),
        ],
      ),
    ),
  );
}

class _LanguageSwitcher extends StatelessWidget {
  final LocaleController? controller;
  const _LanguageSwitcher({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) return const SizedBox.shrink();
    final current = ctrl.locale.languageCode == 'en' ? 'en' : 'sv';
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButton<String>(
          value: current,
          icon: const Icon(Icons.language),
          items: [
            DropdownMenuItem(value: 'sv', child: Text(context.l10n.translate('common.language.sv'))),
            DropdownMenuItem(value: 'en', child: Text(context.l10n.translate('common.language.en'))),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == 'en') {
              ctrl.setLocale(const Locale('en', 'US'));
            } else {
              ctrl.setLocale(const Locale('sv', 'SE'));
            }
          },
        ),
      ),
    );
  }
}
