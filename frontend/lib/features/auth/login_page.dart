import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_role.dart';
import 'auth_api.dart';

import 'package:university_path_frontend/shared/app_typography.dart';

/// Production delegates authentication to the server; sample callbacks are debug-only.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onSignedIn,
    this.onSampleSignedIn,
    this.authenticate,
    this.notice,
  });

  final VoidCallback onSignedIn;
  final String? notice;
  final ValueChanged<AppRole>? onSampleSignedIn;
  final Future<void> Function({
    required String email,
    required String password,
    String? displayName,
  })?
  authenticate;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _submitting = false;
  String? _error;
  List<String> _serverFields = const [];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _selectMode(bool isLogin) {
    if (_isLogin == isLogin || _submitting) return;
    setState(() {
      _isLogin = isLogin;
      _formKey.currentState?.reset();
      _error = null;
      _serverFields = const [];
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _serverFields = const [];
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authenticate?.call(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _isLogin ? null : _nameController.text,
      );
      if (mounted) {
        _passwordController.clear();
        _passwordConfirmController.clear();
        widget.onSignedIn();
      }
    } on AuthFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _serverFields = error.fields;
        });
        _formKey.currentState?.validate();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '처리하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandHeader(),
                    const SizedBox(height: 46),
                    Text(
                      'YOUR UNIVERSITY PATH',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '나의 대학생활 경로를\n관리하세요.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '학업, 활동, 진로 기록을 한 곳에서 이어갑니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: AppTypography.body,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _AuthModeSelector(
                      isLogin: _isLogin,
                      onSelected: _selectMode,
                    ),
                    const SizedBox(height: 28),
                    if (_isLogin && widget.notice != null) ...[
                      Semantics(liveRegion: true, child: Text(widget.notice!)),
                      const SizedBox(height: 16),
                    ],
                    if (_isLogin) ..._loginFields() else ..._signupFields(),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      key: Key(_isLogin ? 'login-submit' : 'signup-submit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting ? '처리 중…' : (_isLogin ? '로그인' : '회원가입'),
                      ),
                    ),
                    if (!kReleaseMode) ...[
                      const SizedBox(height: 28),
                      const Divider(),
                      Text('개발용 샘플 진입 · 실제 인증 아님'),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('sample-student-entry'),
                              onPressed: _submitting
                                  ? null
                                  : () {
                                      if (widget.onSampleSignedIn != null) {
                                        widget.onSampleSignedIn!(AppRole.user);
                                      } else {
                                        widget.onSignedIn();
                                      }
                                    },
                              child: Text('학생'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton(
                                  key: const Key('sample-school-admin-entry'),
                                  onPressed:
                                      widget.onSampleSignedIn == null ||
                                          _submitting
                                      ? null
                                      : () => widget.onSampleSignedIn!(
                                          AppRole.schoolAdmin,
                                        ),
                                  child: Text('학교관리자'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  key: const Key('sample-super-admin-entry'),
                                  onPressed:
                                      widget.onSampleSignedIn == null ||
                                          _submitting
                                      ? null
                                      : () => widget.onSampleSignedIn!(
                                          AppRole.superAdmin,
                                        ),
                                  child: Text('슈퍼관리자'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _loginFields() => [
    _emailField(),
    const SizedBox(height: 16),
    _passwordField(),
  ];

  List<Widget> _signupFields() => [
    TextFormField(
      enabled: !_submitting,
      controller: _nameController,
      maxLength: 128,
      autofillHints: const [AutofillHints.name],
      textInputAction: TextInputAction.next,
      decoration: _decoration('이름', '예: 홍길동'),
      validator: (value) => value == null || value.trim().isEmpty
          ? '이름을 입력해 주세요.'
          : (_serverFields.contains('body.display_name')
                ? '이름 형식과 길이를 확인해 주세요.'
                : null),
    ),
    const SizedBox(height: 16),
    _emailField(),
    const SizedBox(height: 16),
    _passwordField(newPassword: true),
    const SizedBox(height: 16),
    TextFormField(
      enabled: !_submitting,
      controller: _passwordConfirmController,
      obscureText: _obscurePasswordConfirm,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: TextInputAction.done,
      decoration: _decoration('비밀번호 확인').copyWith(
        suffixIcon: IconButton(
          tooltip: _obscurePasswordConfirm ? '비밀번호 표시' : '비밀번호 숨기기',
          onPressed: () => setState(
            () => _obscurePasswordConfirm = !_obscurePasswordConfirm,
          ),
          icon: Icon(
            _obscurePasswordConfirm
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '비밀번호를 다시 입력해 주세요.';
        return value != _passwordController.text ? '비밀번호가 일치하지 않습니다.' : null;
      },
      onFieldSubmitted: (_) => _submit(),
    ),
  ];

  TextFormField _emailField() => TextFormField(
    enabled: !_submitting,
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    textInputAction: TextInputAction.next,
    decoration: _decoration('이메일 주소', 'name@example.com'),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return '이메일 주소를 입력해 주세요.';
      if (_serverFields.contains('body.email')) return '이메일 주소 형식을 확인해 주세요.';
      return null;
    },
  );

  TextFormField _passwordField({bool newPassword = false}) => TextFormField(
    enabled: !_submitting,
    controller: _passwordController,
    obscureText: _obscurePassword,
    autofillHints: [
      newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: newPassword ? TextInputAction.next : TextInputAction.done,
    decoration: _decoration('비밀번호').copyWith(
      helperText: newPassword ? '15~128자 · 공백을 포함한 긴 문장도 사용할 수 있습니다.' : null,
      suffixIcon: IconButton(
        tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: (value) {
      if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
      if (value.runes.length > 128 ||
          (newPassword && value.runes.length < 15) ||
          _serverFields.contains('body.password')) {
        return '비밀번호는 15~128자로 입력해 주세요.';
      }
      return null;
    },
    onFieldSubmitted: (_) => newPassword ? null : _submit(),
  );

  InputDecoration _decoration(String label, [String? hint]) =>
      InputDecoration(labelText: label, hintText: hint);
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.route_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UniversityPath',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTypography.section,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AuthModeSelector extends StatelessWidget {
  const _AuthModeSelector({required this.isLogin, required this.onSelected});

  final bool isLogin;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ModeButton(
          key: const Key('login-tab'),
          selected: isLogin,
          label: '로그인',
          onPressed: () => onSelected(true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ModeButton(
          key: const Key('signup-tab'),
          selected: !isLogin,
          label: '회원가입',
          onPressed: () => onSelected(false),
        ),
      ),
    ],
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: selected
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label)),
  );
}
