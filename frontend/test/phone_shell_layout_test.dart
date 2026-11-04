import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';

void main() {
  test('classifies phone portrait chrome by width and ratio', () {
    expect(isPhonePortraitShell(const Size(360, 800)), isTrue);
    expect(isPhonePortraitShell(const Size(390, 844)), isTrue);
    expect(isPhonePortraitShell(const Size(430, 932)), isTrue);
    expect(isPhonePortraitShell(const Size(450, 900)), isTrue);
    expect(isPhonePortraitShell(const Size(480, 520)), isFalse);
    expect(isPhonePortraitShell(const Size(480, 768)), isFalse);
    expect(isPhonePortraitShell(const Size(900, 768)), isFalse);
    expect(isPhonePortraitShell(const Size(1440, 900)), isFalse);
    expect(isPhonePortraitShell(const Size(400, 500)), isFalse);
  });

  test('keeps admin more menus out of the primary four', () {
    const menus = {
      '/admin/overview': '관리 현황',
      '/admin/schools': '학교·학과',
      '/admin/curricula': '교육과정·과목',
      '/admin/rules': '졸업요건',
      '/admin/documents': '공식 문서',
      '/admin/history': '관리 이력',
      '/admin/settings': '설정',
    };
    expect(
      adminPhonePrimaryMenus(menus).map((entry) => entry.key),
      adminPhonePrimaryPaths,
    );
    expect(adminPhoneMoreMenus(menus).map((entry) => entry.key), [
      '/admin/documents',
      '/admin/history',
      '/admin/settings',
    ]);
  });
}
