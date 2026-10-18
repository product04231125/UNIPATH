import 'package:flutter/material.dart';

import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import 'app_role.dart';
import 'auth_api.dart';

/// Live identity/scopes only. The unrelated synthetic editor is not a server adapter.
class AccountAccessPage extends StatefulWidget {
  const AccountAccessPage({
    super.key,
    required this.identity,
    required this.api,
    required this.onSignedOut,
  });
  final AuthIdentity identity;
  final AuthGateway api;
  final Future<void> Function() onSignedOut;
  @override
  State<AccountAccessPage> createState() => _AccountAccessPageState();
}

class _AccountAccessPageState extends State<AccountAccessPage> {
  List<Map<String, dynamic>>? _schools;
  String? _error;
  bool _busy = false;
  int _loadEpoch = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountAccessPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.id != widget.identity.id ||
        oldWidget.identity.version != widget.identity.version) {
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    try {
      final schools = await widget.api.institutions();
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _schools = schools;
          _error = null;
        });
      }
    } on AuthFailure catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() => _error = error.message);
      }
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSignedOut();
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ContentScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(title: '계정과 관리 범위'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.identity.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(widget.identity.email),
                  Text('역할: ${widget.identity.role.label}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _logout,
                    child: Text(_busy ? '로그아웃 중…' : '로그아웃'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('관리 가능한 학교', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              OutlinedButton(onPressed: _load, child: const Text('다시 조회')),
            ] else if (_schools == null)
              const CircularProgressIndicator()
            else if (_schools!.isEmpty)
              const Text('지정된 학교가 없습니다. 관리 범위를 부여받은 뒤 다시 조회해 주세요.')
            else
              for (final school in _schools!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(child: Text(school['name'] as String)),
                ),
          ],
        ),
      ),
    ),
  );
}
