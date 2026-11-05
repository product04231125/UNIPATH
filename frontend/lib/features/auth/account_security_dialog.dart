import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import 'account_security_gateway.dart';
import 'auth_api.dart';
import 'app_role.dart';

enum _SecurityAction { password, logoutAll }

class AccountSecurityDialog extends StatefulWidget {
  const AccountSecurityDialog({
    super.key,
    required this.identity,
    required this.gateway,
    required this.onKnownEnd,
  });
  final AuthIdentity identity;
  final AccountSecurityGateway gateway;
  // The caller can retain a login notice even if a periodic session observation
  // removes this old account's route during the request/exit animation.
  final ValueChanged<AccountSecurityOutcome> onKnownEnd;
  @override
  State<AccountSecurityDialog> createState() => _AccountSecurityDialogState();
}

class _AccountSecurityDialogState extends State<AccountSecurityDialog> {
  final _form = GlobalKey<FormState>();
  final _old = TextEditingController(),
      _new = TextEditingController(),
      _confirm = TextEditingController();
  late final _changes = Listenable.merge([_old, _new, _confirm]);
  final _visible = <String>{};
  bool _busy = false, _retryReady = false;
  String? _error, _status;
  _SecurityAction? _pending;
  String? _pendingOld, _pendingNew;
  bool get _hasInput =>
      _old.text.isNotEmpty ||
      _new.text.isNotEmpty ||
      _confirm.text.isNotEmpty ||
      _pending != null;

  void _clearSecrets() {
    _old.clear();
    _new.clear();
    _confirm.clear();
    _pendingOld = null;
    _pendingNew = null;
    _visible.clear();
  }

  @override
  void dispose() {
    _clearSecrets();
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _finish(AccountSecurityOutcome outcome) {
    widget.onKnownEnd(outcome);
    if (!mounted) return;
    _clearSecrets();
    Navigator.of(context).pop(outcome);
  }

  Future<void> _send(_SecurityAction action) async {
    if (_busy || (_pending != null && !_retryReady)) return;
    if (_pending == null &&
        action == _SecurityAction.password &&
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (_pending == null) {
      _pending = action;
      if (action == _SecurityAction.password) {
        _pendingOld = _old.text;
        _pendingNew = _new.text;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _retryReady = false;
    });
    try {
      if (_pending == _SecurityAction.password) {
        await widget.gateway.changePassword(
          oldPassword: _pendingOld!,
          newPassword: _pendingNew!,
        );
        _finish(AccountSecurityOutcome.passwordChanged);
      } else {
        await widget.gateway.logoutAll();
        _finish(AccountSecurityOutcome.allSessionsEnded);
      }
    } on AuthFailure catch (error) {
      if (error.status == 401) {
        _finish(AccountSecurityOutcome.expired);
        return;
      }
      if (error.status == 403) {
        _finish(AccountSecurityOutcome.changed);
        return;
      }
      if (!mounted) return;
      if (error.status == 422 || error.status == 429) {
        _pending = null;
        _pendingOld = null;
        _pendingNew = null;
        setState(
          () => _error = error.status == 422
              ? '현재 비밀번호와 새 비밀번호의 조건을 확인하세요. 입력은 유지됩니다.'
              : '시도 횟수가 많습니다. 잠시 후 다시 시도하세요. 입력은 유지됩니다.',
        );
      } else {
        setState(
          () => _error =
              '요청 완료 여부를 확인하지 못했습니다. 자동으로 다시 보내지 않습니다. 로그인 상태를 확인해 주세요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '요청 완료 여부를 확인하지 못했습니다. 로그인 상태를 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkSession() async {
    if (_busy || _pending == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.gateway.checkSession();
      if (state == AccountSessionStatus.expired) {
        _finish(AccountSecurityOutcome.expired);
        return;
      }
      if (state == AccountSessionStatus.changed) {
        _finish(AccountSecurityOutcome.changed);
        return;
      }
      if (mounted) {
        setState(() {
          _retryReady = true;
          _status = '현재 세션은 유효합니다. 앞선 요청의 완료 여부까지 확정된 것은 아닙니다. 같은 요청을 다시 시도하거나 닫은 뒤 로그인하여 확인하세요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '로그인 상태도 확인하지 못했습니다. 연결을 확인한 뒤 다시 조회하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutAll() async {
    if (_busy || _pending != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('모든 기기에서 로그아웃할까요?'),
        content: const Text(
          '현재 기기를 포함한 모든 서버 세션을 종료합니다. 작성 중인 비밀번호는 변경하지 않습니다. 저장된 개인 기록은 유지하지만 저장하지 않은 작업은 사라질 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('모든 기기 로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _clearSecrets();
    await _send(_SecurityAction.logoutAll);
  }

  Widget _password(
    TextEditingController controller,
    String key,
    String label, {
    bool newPassword = false,
    bool confirm = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      readOnly: _busy || _pending != null,
      obscureText: !_visible.contains(key),
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [
        newPassword || confirm
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      textInputAction: confirm ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: newPassword
            ? '15~128자 · 공백을 포함한 문장도 가능합니다. 입력을 자르거나 공백을 제거하지 않습니다.'
            : null,
        helperMaxLines: 5,
        suffixIcon: IconButton(
          tooltip: _visible.contains(key) ? '$label 숨기기' : '$label 표시',
          onPressed: _busy
              ? null
              : () => setState(
                  () => _visible.contains(key)
                      ? _visible.remove(key)
                      : _visible.add(key),
                ),
          icon: Icon(
            _visible.contains(key)
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: (value) {
        final raw = value ?? '';
        if (raw.isEmpty) return '$label 입력이 필요합니다.';
        if (raw.runes.length > 128 || (newPassword && raw.runes.length < 15)) {
          return newPassword ? '새 비밀번호는 15~128자로 입력하세요.' : '128자 이내로 입력하세요.';
        }
        if (newPassword && raw == _old.text) return '현재 비밀번호와 다르게 입력하세요.';
        if (confirm && raw != _new.text) return '새 비밀번호가 일치하지 않습니다.';
        return null;
      },
      onFieldSubmitted: confirm && _pending == null
          ? (_) => _send(_SecurityAction.password)
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('계정 보안'),
    saving: _busy,
    hasContent: () => _hasInput,
    changes: _changes,
    content: AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.identity.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(widget.identity.email),
            Text('역할: ${widget.identity.role.label}'),
            const SizedBox(height: 12),
            const Text(
              '비밀번호를 변경하면 현재 기기를 포함한 모든 세션이 종료됩니다. 저장된 개인 기록은 유지하지만 저장하지 않은 작업은 사라질 수 있습니다. 새 비밀번호로 다시 로그인해야 합니다.',
            ),
            _password(_old, 'security-old-password', '현재 비밀번호'),
            _password(
              _new,
              'security-new-password',
              '새 비밀번호',
              newPassword: true,
            ),
            _password(
              _confirm,
              'security-confirm-password',
              '새 비밀번호 확인',
              confirm: true,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_status!)),
              ),
            if (_pending != null) ...[
              const SizedBox(height: 12),
              Text(
                '전송한 요청: ${_pending == _SecurityAction.password ? '비밀번호 변경' : '모든 기기 로그아웃'}',
              ),
              const Text(
                '전송한 내용은 고정되어 있습니다. 창을 닫아도 서버에 도착한 요청을 취소하지는 않습니다. 앱 종료 뒤에는 새 비밀번호로 로그인하여 결과를 확인하세요.',
              ),
              OutlinedButton(
                onPressed: _busy ? null : _checkSession,
                child: const Text('로그인 상태 확인'),
              ),
            ] else ...[
              const Divider(height: 32),
              OutlinedButton(
                onPressed: _busy ? null : _logoutAll,
                child: const Text('모든 기기 로그아웃'),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => InputDialog.cancel<AccountSecurityOutcome>(context),
        child: const Text('닫기'),
      ),
      FilledButton(
        onPressed: _busy || (_pending != null && !_retryReady)
            ? null
            : () => _send(_pending ?? _SecurityAction.password),
        child: Text(
          _busy
              ? '확인 중…'
              : _retryReady
              ? '같은 요청으로 다시 시도'
              : _pending == _SecurityAction.logoutAll
              ? '로그아웃 확인 필요'
              : '비밀번호 변경',
        ),
      ),
    ],
  );
}
