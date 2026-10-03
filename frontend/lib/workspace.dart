import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell/workspace_shell.dart';
import 'shared/pending_ui_action.dart';
import 'chat_window.dart' as chat_window;
import 'features/assistant/assistant_conversation.dart';
import 'features/assistant/assistant_panel.dart';
import 'features/graduation/graduation_page.dart';
import 'features/home/home_page.dart';
import 'features/planning/planning_repository.dart';
import 'features/planning/weekly_schedule.dart';
import 'features/records/activity/activity_page.dart';
import 'features/records/course/course_page.dart';
import 'features/records/credential/credential_page.dart';
import 'features/records/experience/experience_page.dart';
import 'features/records/portfolio/portfolio_page.dart';
import 'features/settings/settings_page.dart';
import 'features/schedule/schedule_page.dart';

/// Coordinates navigation, mock-data visibility, and the assistant window.
/// Feature pages own their own mock state and input interactions.
class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const _labels = [
    '홈',
    '일정',
    '수강 관리',
    '졸업 요건',
    '활동',
    '경험',
    '자격',
    '포트폴리오·성과',
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.menu_book_outlined,
    Icons.school_outlined,
    Icons.volunteer_activism_outlined,
    Icons.business_center_outlined,
    Icons.workspace_premium_outlined,
    Icons.collections_bookmark_outlined,
  ];

  var _page = 0;
  var _showMockData = true;
  var _chatOpen = false;
  var _chatManuallyOpened = false;
  var _detachedChatActive = false;
  var _mainWindowMaximized = false;
  var _chatWidth = 360.0;
  double _graduationMinimumWidth = 0;
  final _graduationPageKey = GlobalKey();
  final _assistantConversation = AssistantConversation();
  final _planningRepository = PlanningRepository();
  DateTime? _scheduleInitialDay;
  PendingUiAction? _scheduleAddRequest;
  StreamSubscription<bool>? _detachedChatSubscription;
  StreamSubscription<bool>? _mainWindowMaximizeSubscription;

  @override
  void initState() {
    super.initState();
    _planningRepository.load();
    chat_window.isMainWindowMaximized().then((maximized) {
      if (mounted) setState(() => _mainWindowMaximized = maximized);
    });
    _mainWindowMaximizeSubscription = chat_window
        .mainWindowMaximizeChanges()
        .listen((maximized) {
          if (mounted) setState(() => _mainWindowMaximized = maximized);
        });
    _detachedChatSubscription = chat_window.detachedChatWindowChanges().listen((
      isOpen,
    ) {
      if (!mounted || _detachedChatActive == isOpen) return;
      setState(() {
        final wasDetached = _detachedChatActive;
        _detachedChatActive = isOpen;
        // Closing a detached Windows window returns to the same closed state as
        // closing the dock: the user can reopen the assistant from its button.
        if (wasDetached && !isOpen) {
          _chatOpen = false;
          _chatManuallyOpened = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _detachedChatSubscription?.cancel();
    _mainWindowMaximizeSubscription?.cancel();
    _assistantConversation.dispose();
    _planningRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = [
      for (var index = 0; index < _labels.length; index++)
        WorkspaceNavigationItem(label: _labels[index], icon: _icons[index]),
      const WorkspaceNavigationItem(label: '설정', icon: Icons.settings_outlined),
    ];
    return WorkspaceShell(
      selectedPage: _page,
      navigationItems: navigationItems,
      onPageSelected: _selectPage,
      minimumContentWidth: switch (_page) {
        0 => WeeklySchedule.minimumWidth + 16,
        3 =>
          _showMockData && _graduationMinimumWidth > 0
              ? _graduationMinimumWidth + 16
              : 0,
        _ => 0,
      },
      showMockData: _showMockData,
      onMockDataChanged: (value) => setState(() => _showMockData = value),
      onSignedOut: widget.onSignedOut,
      isAssistantOpen: _chatOpen,
      isAssistantManuallyOpened: _chatManuallyOpened,
      assistantWidth: _chatWidth,
      assistantTooltip: _detachedChatActive ? '분리된 AI 도우미 앞으로' : 'AI 도우미 열기',
      onOpenAssistant: _openAssistant,
      onAssistantWidthChanged: (delta) => setState(() {
        _chatWidth = (_chatWidth - delta).clamp(300.0, 480.0);
      }),
      pageBuilder: (context, layout) => _buildPage(navigationItems.length),
      assistantBuilder: (context, width) => AssistantPanel(
        conversation: _assistantConversation,
        onClose: _closeChat,
        onDetach:
            chat_window.supportsDetachedChatWindow && !_mainWindowMaximized
            ? _openDetachedChat
            : null,
        width: width,
      ),
    );
  }

  Widget _buildPage(int settingsPage) => switch (_page) {
    0 => HomePage(
      repository: _planningRepository,
      onOpenPage: _selectPage,
      onOpenSettings: () => _selectPage(settingsPage - 1),
      onOpenSchedule: (day) => setState(() {
        _scheduleAddRequest = null;
        _scheduleInitialDay = day;
        _page = 1;
      }),
      onAddSchedule: () => setState(() {
        _scheduleInitialDay = DateTime.now();
        _scheduleAddRequest = PendingUiAction();
        _page = 1;
      }),
    ),
    1 => SchedulePage(
      repository: _planningRepository,
      initialDay: _scheduleInitialDay,
      addRequest: _scheduleAddRequest,
    ),
    2 => CoursePage(showMockData: _showMockData),
    3 => GraduationPage(
      key: _graduationPageKey,
      showMockData: _showMockData,
      onMinimumWidthChanged: (width) => setState(() {
        _graduationMinimumWidth = width;
      }),
    ),
    4 => ActivityPage(showMockData: _showMockData),
    5 => ExperiencePage(showMockData: _showMockData),
    6 => CredentialPage(showMockData: _showMockData),
    7 => PortfolioPage(showMockData: _showMockData),
    _ when _page == settingsPage - 1 => SettingsPage(
      repository: _planningRepository,
    ),
    _ => const SizedBox.shrink(),
  };

  void _selectPage(int value) => setState(() {
    _scheduleAddRequest = null;
    if (_page != value) _graduationMinimumWidth = 0;
    _page = value;
  });

  Future<void> _openAssistant() async {
    if (_detachedChatActive) {
      final exists = await chat_window.hasDetachedChatWindow();
      if (exists) {
        await _openDetachedChat();
      } else if (mounted) {
        setState(() {
          _detachedChatActive = false;
          _chatOpen = true;
          _chatManuallyOpened = true;
        });
      }
      return;
    }
    setState(() {
      _chatOpen = true;
      _chatManuallyOpened = true;
    });
  }

  void _closeChat() => setState(() {
    _chatOpen = false;
    _chatManuallyOpened = false;
  });

  Future<void> _openDetachedChat() async {
    await chat_window.openDetachedChatWindow(width: _chatWidth);
    if (!mounted) return;
    setState(() {
      _detachedChatActive = true;
      _chatOpen = false;
      _chatManuallyOpened = false;
    });
  }
}
