import 'package:flutter/material.dart';

/// Temporary entry screen. It has no API, token, or role behavior yet.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _selectMode(bool isLogin) {
    if (_isLogin == isLogin) return;
    setState(() {
      _isLogin = isLogin;
      _formKey.currentState?.reset();
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f8f8),
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
                    const Text(
                      'YOUR UNIVERSITY PATH',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xff5d7786),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '나의 대학생활 경로를\n관리하세요.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: const Color(0xff1b3445),
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '학업, 활동, 진로 기록을 한 곳에서 이어갑니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xff607386),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _AuthModeSelector(
                      isLogin: _isLogin,
                      onSelected: _selectMode,
                    ),
                    const SizedBox(height: 28),
                    if (_isLogin) ..._loginFields() else ..._signupFields(),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: Key(_isLogin ? 'login-submit' : 'signup-submit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff193f59),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: _submit,
                      child: Text(_isLogin ? '로그인' : '가입하고 목업 보기'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isLogin
                          ? '인증 API 연동 전 화면 목업입니다. 입력값은 서버에 전송하거나 저장하지 않습니다.'
                          : '회원가입은 화면 흐름만 재현합니다. 계정, 학교 정보, 역할은 생성·저장되지 않습니다.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xff607386),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const Key('sample-student-entry'),
                      onPressed: widget.onSignedIn,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('입력 없이 학생 화면 목업 보기'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '관리자 역할과 학교 검색은 API·권한 계약 확정 후 연결합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff778894), fontSize: 12),
                    ),
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
      controller: _nameController,
      autofillHints: const [AutofillHints.name],
      textInputAction: TextInputAction.next,
      decoration: _decoration('이름', '예: 홍길동'),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '이름을 입력해 주세요.' : null,
    ),
    const SizedBox(height: 16),
    _emailField(),
    const SizedBox(height: 16),
    _passwordField(newPassword: true),
    const SizedBox(height: 16),
    TextFormField(
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
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    textInputAction: TextInputAction.next,
    decoration: _decoration('이메일 주소', 'name@example.com'),
    validator: (value) =>
        value == null || value.trim().isEmpty ? '이메일 주소를 입력해 주세요.' : null,
  );

  TextFormField _passwordField({bool newPassword = false}) => TextFormField(
    controller: _passwordController,
    obscureText: _obscurePassword,
    autofillHints: [
      newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: newPassword ? TextInputAction.next : TextInputAction.done,
    decoration: _decoration('비밀번호').copyWith(
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
    validator: (value) =>
        value == null || value.isEmpty ? '비밀번호를 입력해 주세요.' : null,
    onFieldSubmitted: (_) => newPassword ? null : _submit(),
  );

  InputDecoration _decoration(String label, [String? hint]) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: const OutlineInputBorder(),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xff193f59),
        child: Icon(Icons.route_outlined, color: Colors.white),
      ),
      SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UniversityPath',
            style: TextStyle(
              color: Color(0xff193f59),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '화면 목업',
            style: TextStyle(color: Color(0xff607386), fontSize: 12),
          ),
        ],
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
