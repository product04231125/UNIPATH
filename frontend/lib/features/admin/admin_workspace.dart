import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/page_header.dart';

class AdminWorkspace extends StatelessWidget {
  const AdminWorkspace({
    super.key,
    required this.role,
    required this.path,
    required this.onNavigate,
    required this.onSignedOut,
  });
  final AppRole role;
  final String path;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;

  static const menus = <String, String>{
    '/admin/overview': '관리 현황',
    '/admin/schools': '학교·학과',
    '/admin/curricula': '교육과정·과목',
    '/admin/rules': '졸업요건',
    '/admin/documents': '공식 문서',
    '/admin/history': '관리 이력',
    '/admin/accounts': '관리자 관리',
  };

  @override
  Widget build(BuildContext context) {
    final allowed =
        role != AppRole.user &&
        menus.containsKey(path) &&
        (path != '/admin/accounts' || role == AppRole.superAdmin);
    return Scaffold(
      body: SafeArea(
        child: ContentScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${role.label} · 관리자 작업 공간'),
                const Text('개발용 목업 · 실제 권한 및 서버 저장 없음'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in menus.entries)
                      if (entry.key != '/admin/accounts' ||
                          role == AppRole.superAdmin)
                        TextButton(
                          onPressed: () => onNavigate(entry.key),
                          child: Text(entry.value),
                        ),
                    TextButton(
                      onPressed: onSignedOut,
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PageHeader(title: allowed ? menus[path]! : '접근할 수 없습니다.'),
                if (!allowed) const Text('현재 역할의 관리 범위를 확인하고 관리 현황으로 이동하세요.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
