import 'package:flutter/material.dart';

import '../../shared/external_links.dart';

/// Dialog-only input. This is not a server request or a persisted application.
class UnregisteredSchoolApplicationDraft extends ChangeNotifier {
  final schoolName = TextEditingController(),
      officialUrl = TextEditingController(),
      position = TextEditingController(),
      email = TextEditingController(),
      reason = TextEditingController();

  UnregisteredSchoolApplicationDraft() {
    for (final controller in controllers) {
      controller.addListener(notifyListeners);
    }
  }

  List<TextEditingController> get controllers => [
    schoolName,
    officialUrl,
    position,
    email,
    reason,
  ];
  bool get hasContent => controllers.any((c) => c.text.isNotEmpty);

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class UnregisteredSchoolApplicationForm extends StatelessWidget {
  const UnregisteredSchoolApplicationForm({
    super.key,
    required this.draft,
    required this.applicantName,
    this.enabled = true,
  });

  final UnregisteredSchoolApplicationDraft draft;
  final String applicantName;
  final bool enabled;

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label 입력이 필요합니다.' : null;

  String? _email(String? value) {
    final required = _required(value, '연락 이메일');
    if (required != null) return required;
    final raw = value!.trim();
    final pattern = RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$",
    );
    final local = raw.split('@').first;
    if (!pattern.hasMatch(raw) ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..')) {
      return '연락 이메일 주소 형식을 확인하세요.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Form(
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text('미등록 학교 신청은 아직 접수할 수 없습니다. 작성 내용은 서버에 저장되지 않습니다.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: draft.schoolName,
          enabled: enabled,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: '학교명',
            helperText: '필수 · 등록을 요청하려는 학교의 이름',
          ),
          validator: (v) => _required(v, '학교명'),
        ),
        TextFormField(
          controller: draft.officialUrl,
          enabled: enabled,
          maxLength: 2048,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '공식 홈페이지',
            helperText: '선택 · http:// 또는 https:// 주소',
          ),
          validator: (v) =>
              (v?.trim().isEmpty ?? true) || browserLink(v!) != null
              ? null
              : '유효한 http/https 홈페이지 주소를 입력하세요.',
        ),
        TextFormField(
          initialValue: applicantName,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: '신청자 이름',
            helperText: '현재 로그인한 계정의 이름',
          ),
        ),
        TextFormField(
          controller: draft.position,
          enabled: enabled,
          maxLength: 128,
          decoration: const InputDecoration(labelText: '직책', helperText: '필수'),
          validator: (v) => _required(v, '직책'),
        ),
        TextFormField(
          controller: draft.email,
          enabled: enabled,
          maxLength: 254,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: '연락 이메일',
            helperText: '필수 · name@example.com',
          ),
          validator: _email,
        ),
        TextFormField(
          controller: draft.reason,
          enabled: enabled,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '신청 사유',
            helperText: '필수',
          ),
          validator: (v) => _required(v, '신청 사유'),
        ),
        const Text(
          '학교가 등록되면 등록된 학교 유형에서 목록을 다시 읽고 직접 선택해 신청하세요. 작성 내용은 이 창을 닫으면 폐기됩니다.',
        ),
        const SizedBox(height: 12),
        const FilledButton(onPressed: null, child: Text('접수 연동 대기')),
      ],
    ),
  );
}
