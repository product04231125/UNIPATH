import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell/workspace_shell.dart';
import 'shared/pending_ui_action.dart';
import 'features/assistant/assistant_window_host.dart';
import 'features/settings/chat_preferences.dart';
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
  const Workspace({
    super.key,
    required this.onSignedOut,
    this.windowHost = const AssistantWindowHost(),
    this.chatPreferences,
    this.selectedPage,
    this.onPageChanged,
  });

  final VoidCallback onSignedOut;
  final AssistantWindowHost windowHost;
  final ChatPreferences? chatPreferences;
  final int? selectedPage;
  final ValueChanged<int>? onPageChanged;

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
  bool _openingChat = false;
  bool _detachingChat = false;
  late final ChatPreferences _chatPreferences;
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
    _page = widget.selectedPage ?? 0;
    _planningRepository.load();
    _chatPreferences = widget.chatPreferences ?? ChatPreferences();
    _chatPreferences.load();
    widget.windowHost.isMaximized().then(_onMaximized, onError: (Object _) {});
    _mainWindowMaximizeSubscription = widget.windowHost.maximizeChanges.listen(
      _onMaximized,
      onError: (Object _) {},
    );
    _detachedChatSubscription = widget.windowHost.detachedChanges.listen((
      isOpen,
    ) {
      if (!mounted || _detachedChatActive == isOpen) return;
      setState(() {
        final wasDetached = _detachedChatActive;
        _detachedChatActive = isOpen;
        // Closing a detached Windows window returns to the same closed state as
        // closing the dock: the user can reopen the assistant from its button.
        if (wasDetached && !isOpen) {
          _chatOpen = _mainWindowMaximized;
          _chatManuallyOpened = _mainWindowMaximized;
        }
      });
    }, onError: (Object _) {});
  }

  void _onMaximized(bool value) {
    if (!mounted) return;
    setState(() {
      _mainWindowMaximized = value;
      if (value && _detachedChatActive) {
        _chatOpen = true;
        _chatManuallyOpened = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant Workspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPage != null && widget.selectedPage != _page) {
      _scheduleAddRequest = null;
      _graduationMinimumWidth = 0;
      _page = widget.selectedPage!;
    }
  }

  @override
  void dispose() {
    _detachedChatSubscription?.cancel();
    _mainWindowMaximizeSubscription?.cancel();
    _assistantConversation.dispose();
    _planningRepository.dispose();
    if (widget.chatPreferences == null) _chatPreferences.dispose();
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
      pageBuilder: (context, layout) =>
          _buildPage(navigationItems.length, layout),
      assistantBuilder: (context, width) => AssistantPanel(
        conversation: _assistantConversation,
        onClose: _closeChat,
        onDetach: widget.windowHost.supportsDetached && !_mainWindowMaximized
            ? _openDetachedChat
            : null,
        width: width,
      ),
    );
  }

  Widget _buildPage(int settingsPage, WorkspaceShellLayout layout) =>
      switch (_page) {
        0 => HomePage(
          repository: _planningRepository,
          coveredRightWidth: layout.showAssistantOverlay
              ? layout.assistantOverlayWidth
              : 0,
          onOpenPage: _selectPage,
          onOpenSettings: () => _selectPage(settingsPage - 1),
          onOpenSchedule: (day) {
            _scheduleAddRequest = null;
            _scheduleInitialDay = day;
            _selectPage(1);
          },
          onAddSchedule: () {
            _scheduleInitialDay = DateTime.now();
            _selectPage(1, addRequest: PendingUiAction());
          },
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
          chatPreferences: widget.windowHost.supportsDetached
              ? _chatPreferences
              : null,
        ),
        _ => const SizedBox.shrink(),
      };

  void _selectPage(int value, {PendingUiAction? addRequest}) {
    setState(() {
      _scheduleAddRequest = addRequest;
      if (_page != value) _graduationMinimumWidth = 0;
      _page = value;
    });
    widget.onPageChanged?.call(value);
  }

  Future<void> _openAssistant() async {
    if (_openingChat) return;
    _openingChat = true;
    try {
      await _chatPreferences.load();
      if (!mounted) return;
      if (widget.windowHost.supportsDetached &&
          !_mainWindowMaximized &&
          (_detachedChatActive ||
              _chatPreferences.mode == ChatOpeningMode.detached)) {
        await _openDetachedChat();
      } else {
        _showDock();
      }
    } finally {
      _openingChat = false;
    }
  }

  void _showDock() {
    if (!mounted) return;
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
    if (_detachingChat || _mainWindowMaximized) return;
    _detachingChat = true;
    try {
      await widget.windowHost.openDetached(_chatWidth);
    } catch (_) {
      if (!mounted) return;
      setState(() => _detachedChatActive = false);
      _showDock();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('분리 창을 열지 못해 내부 패널로 열었습니다. 다시 시도할 수 있습니다.'),
        ),
      );
      return;
    } finally {
      _detachingChat = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _detachedChatActive = true;
      _chatOpen = _mainWindowMaximized;
      _chatManuallyOpened = _mainWindowMaximized;
    });
  }
}
