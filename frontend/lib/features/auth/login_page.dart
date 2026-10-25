import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_role.dart';
import 'auth_api.dart';
import '../admin/unregistered_school_application_form.dart';
import '../api/school_signup_models.dart';
import '../records/personal_record_repository.dart';

import 'package:university_path_frontend/shared/app_typography.dart';

/// Production delegates authentication to the server; sample callbacks are debug-only.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onSignedIn,
    this.onSampleSignedIn,
    this.authenticate,
    this.notice,
    this.registerSchoolAdmin,
  });

  final VoidCallback onSignedIn;
  final String? notice;
  final Future<SchoolAdminSignupView> Function({
    required String email,
    required String password,
    required String displayName,
    required SchoolAdminSignupDetails details,
  })?
  registerSchoolAdmin;
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
  bool _schoolAdminSignup = false;
  final String _signupClientId = PersonalRecord.newId();
  String? _signupFingerprint;
  SchoolAdminSignupView? _signupReceipt;
  bool _signupUncertain = false;
  bool get _fieldsEnabled => !_submitting && (_isLogin || !_signupUncertain);
  final _schoolDraft = UnregisteredSchoolApplicationDraft();
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
    _schoolDraft.dispose();
    super.dispose();
  }

  void _selectMode(bool isLogin) {
    if (_isLogin == isLogin || _submitting || _signupReceipt != null) return;
    setState(() {
      _isLogin = isLogin;
      _error = null;
      _serverFields = const [];
    });
  }

  Future<void> _submit() async {
    if (_submitting ||
        (!_isLogin &&
            _schoolAdminSignup &&
            widget.registerSchoolAdmin == null)) {
      return;
    }
    _serverFields = const [];
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (!_isLogin && _schoolAdminSignup) {
        final details = SchoolAdminSignupDetails(
          clientId: _signupClientId,
          schoolName: _schoolDraft.schoolName.text.trim(),
          officialUrl: _schoolDraft.officialUrl.text.trim(),
          position: _schoolDraft.position.text.trim(),
          contactEmail: _schoolDraft.email.text.trim(),
          reason: _schoolDraft.reason.text.trim(),
        );
        // Retain the exact replay key and input after a response is lost.
        final fingerprint =
            '${_nameController.text}\u0000${_emailController.text}\u0000${details.toJson()}';
        if (_signupUncertain && _signupFingerprint != fingerprint) {
          throw const AuthFailure(
            '앞선 접수 결과가 불명확합니다. 기존 입력으로 재확인하거나 로그인 후 신청 이력을 확인해 주세요.',
          );
        }
        _signupFingerprint = fingerprint;
        final receipt = await widget.registerSchoolAdmin!(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
          details: details,
        );
        if (mounted) {
          setState(() {
            _signupReceipt = receipt;
            _signupUncertain = false;
          });
          _passwordController.clear();
          _passwordConfirmController.clear();
        }
        return;
      }
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
          if (!_isLogin && _schoolAdminSignup) {
            _signupUncertain =
                error.status == null || (error.status ?? 0) >= 500;
          }
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
                    if (_signupReceipt != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '계정과 학교 신청이 접수되었습니다.\n접수 번호: ${_signupReceipt!.id}\n상태: ${switch (_signupReceipt!.status) {
                            'pending' => '승인 대기',
                            'approved' => '승인',
                            'rejected' => '반려',
                            'cancelled' => '취소',
                            _ => '상태 확인 필요',
                          }}\n승인 전에는 일반 계정 권한으로 이용합니다.',
                        ),
                      ),
                      FilledButton(
                        onPressed: widget.onSignedIn,
                        child: const Text('계속하기'),
                      ),
                    ] else if (_isLogin)
                      ..._loginFields()
                    else ...[
                      const Text('가입 유형'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final admin in [false, true])
                            ChoiceChip(
                              key: Key(
                                admin
                                    ? 'signup-school-admin'
                                    : 'signup-student',
                              ),
                              label: Text(admin ? '학교관리자' : '학생'),
                              selected: _schoolAdminSignup == admin,
                              onSelected: _submitting || _signupUncertain
                                  ? null
                                  : (_) => setState(() {
                                      _schoolAdminSignup = admin;
                                      _error = null;
                                      _serverFields = const [];
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ..._signupFields(),
                      if (_schoolAdminSignup) ...[
                        const SizedBox(height: 24),
                        Text(
                          '학교 및 담당자 정보',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.registerSchoolAdmin == null
                              ? '학교관리자 가입 신청은 아직 접수할 수 없습니다. 입력한 계정·학교 정보는 서버에 저장되지 않습니다.'
                              : '계정과 학교 신청을 함께 접수합니다. 학교 등록과 관리자 권한은 신원·소속 검토 후 부여됩니다.',
                        ),
                        const SizedBox(height: 12),
                        SchoolAdminApplicationFields(
                          draft: _schoolDraft,
                          enabled: _fieldsEnabled,
                        ),
                      ],
                    ],
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
                    if (_signupReceipt == null)
                      FilledButton(
                        key: Key(_isLogin ? 'login-submit' : 'signup-submit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onPrimary,
                          minimumSize: const Size.fromHeight(52),
                          textStyle: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed:
                            _submitting ||
                                (!_isLogin &&
                                    _schoolAdminSignup &&
                                    widget.registerSchoolAdmin == null)
                            ? null
                            : _submit,
                        child: Text(
                          _submitting
                              ? '처리 중…'
                              : (_isLogin
                                    ? '로그인'
                                    : _schoolAdminSignup
                                    ? (widget.registerSchoolAdmin == null
                                          ? '학교관리자 가입 신청 · 접수 준비 중'
                                          : '학교관리자 가입 신청')
                                    : '회원가입'),
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
      enabled: _fieldsEnabled,
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
      enabled: _fieldsEnabled,
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
    enabled: _fieldsEnabled,
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
    enabled: _fieldsEnabled,
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
