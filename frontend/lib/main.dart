import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_window.dart' as chat_window;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final detached = await chat_window.isDetachedChatWindow();
  if (detached) {
    await chat_window.initializeDetachedChatWindow();
  } else {
    await chat_window.initializeMainWindowCloseBehavior();
  }
  runApp(detached ? const DetachedChatApp() : const UniversityPathApp());
}

class UniversityPathApp extends StatelessWidget {
  const UniversityPathApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'UniversityPath',
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Malgun Gothic',
      scaffoldBackgroundColor: const Color(0xfff7f8f8),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff193f59)),
    ),
    home: const Workspace(),
  );
}

class DetachedChatApp extends StatelessWidget {
  const DetachedChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'UniversityPath AI 도우미',
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Malgun Gothic',
      scaffoldBackgroundColor: const Color(0xfff7f8f8),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff193f59)),
    ),
    home: const DetachedChatWindow(),
  );
}

class DetachedChatWindow extends StatefulWidget {
  const DetachedChatWindow({super.key});

  @override
  State<DetachedChatWindow> createState() => _DetachedChatWindowState();
}

class _DetachedChatWindowState extends State<DetachedChatWindow> {
  final input = TextEditingController();
  final messages = <String>['독립 AI 창입니다. 현재 화면 문맥을 바탕으로 질문을 정리해 드립니다.'];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      messages.add('나: $text');
      messages.add('AI 답변: 독립 창에서도 현재 작업 맥락을 기준으로 다음 확인 항목을 정리합니다.');
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xff193f59),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAG 기반 대화',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff946c2e),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'AI 도우미 · 독립 창',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '현재 문맥 · 졸업 요건 / 경동대학교 컴퓨터공학과 / 2024학번',
                style: TextStyle(fontSize: 12, color: Color(0xff607386)),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (_, index) {
                final user = messages[index].startsWith('나:');
                return Align(
                  alignment: user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: user
                          ? const Color(0xff1c425e)
                          : const Color(0xffeef4f6),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      messages[index],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: user ? Colors.white : const Color(0xff243d52),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: '자연어로 질문해 보세요',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: send, child: const Text('보내기')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int page = 0;
  String tab = '대학 공통';
  bool chatOpen = false;
  bool chatManuallyOpened = false;
  bool detachedChatActive = false;
  double chatWidth = 360;
  final input = TextEditingController();
  final curriculumScrollController = ScrollController();
  StreamSubscription<bool>? detachedChatSubscription;
  final messages = <String>[
    '궁금한 점이나 정리할 일을 자연어로 물어보세요. 규정 질문에는 문서 근거를 자동으로 붙입니다.',
  ];
  final labels = const ['홈', '수강 관리', '졸업 요건', '활동', '경험', '자격', '포트폴리오·성과'];
  final icons = const [
    Icons.home_outlined,
    Icons.menu_book_outlined,
    Icons.school_outlined,
    Icons.volunteer_activism_outlined,
    Icons.business_center_outlined,
    Icons.workspace_premium_outlined,
    Icons.collections_bookmark_outlined,
  ];

  @override
  void initState() {
    super.initState();
    detachedChatSubscription = chat_window.detachedChatWindowChanges().listen((
      isOpen,
    ) {
      if (!mounted || detachedChatActive == isOpen) return;
      setState(() => detachedChatActive = isOpen);
    });
  }

  @override
  void dispose() {
    detachedChatSubscription?.cancel();
    input.dispose();
    curriculumScrollController.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      messages.add('나: $text');
      messages.add(
        text.contains('졸업') || text.contains('학점')
            ? '문서 근거 답변: 졸업 충족 여부는 Rule Engine 결과와 공식 문서의 페이지 근거를 함께 확인합니다.'
            : 'AI 답변: 현재 화면의 기록을 문맥으로 사용해 다음 확인 항목을 정리합니다.',
      );
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktopPanel = constraints.maxWidth >= 1180 && chatOpen;
            final chatOverlay =
                constraints.maxWidth < 1180 && chatOpen && chatManuallyOpened;
            final overlayWidth = constraints.maxWidth < 480
                ? constraints.maxWidth
                : 360.0;
            return Stack(
              children: [
                Row(
                  children: [
                    Container(
                      width: 220,
                      color: const Color(0xfff2f5f6),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 10, 8, 18),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(0xff19344d),
                                  child: Icon(
                                    Icons.route_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'UniversityPath',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'serif',
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '화면 목업',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xff708192),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (var i = 0; i < labels.length; i++) _nav(i),
                          const Spacer(),
                          const Divider(),
                          const ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor: Color(0xff19344d),
                              child: Text(
                                '정',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              '정민서',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '2024학번 · 컴퓨터공학과',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 52,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'UniversityPath  화면 목업',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xff27445d),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  constraints.maxWidth < 900 ? 16 : 28,
                                  26,
                                  constraints.maxWidth < 900 ? 16 : 28,
                                  30,
                                ),
                                child: page == 0
                                    ? _home()
                                    : page == 2
                                    ? _graduation()
                                    : _record(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (desktopPanel)
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              chatWidth = (chatWidth - details.delta.dx).clamp(
                                300.0,
                                480.0,
                              );
                            });
                          },
                          child: Container(
                            width: 6,
                            color: const Color(0xffd8e1e7),
                          ),
                        ),
                      ),
                    if (desktopPanel)
                      _chat(
                        onClose: _closeChat,
                        onDetach: _openDetachedChat,
                        width: chatWidth,
                      ),
                  ],
                ),
                if (chatOverlay)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: overlayWidth,
                    child: Material(
                      elevation: 18,
                      child: _chat(
                        onClose: _closeChat,
                        onDetach: _openDetachedChat,
                        width: overlayWidth,
                      ),
                    ),
                  ),
                if (!desktopPanel && !chatOverlay)
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: Tooltip(
                      message: detachedChatActive
                          ? '분리된 AI 도우미 앞으로'
                          : 'AI 도우미 열기',
                      child: FloatingActionButton(
                        onPressed: () async {
                          if (detachedChatActive) {
                            final exists = await chat_window
                                .hasDetachedChatWindow();
                            if (exists) {
                              await _openDetachedChat();
                            } else if (mounted) {
                              setState(() {
                                detachedChatActive = false;
                                chatOpen = true;
                                chatManuallyOpened = true;
                              });
                            }
                            return;
                          }
                          setState(() {
                            chatOpen = true;
                            chatManuallyOpened = true;
                          });
                        },
                        backgroundColor: const Color(0xff193f59),
                        foregroundColor: Colors.white,
                        child: const Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _closeChat() {
    setState(() {
      chatOpen = false;
      chatManuallyOpened = false;
    });
  }

  Future<void> _openDetachedChat() async {
    await chat_window.openDetachedChatWindow(width: chatWidth);
    if (!mounted) return;
    setState(() {
      detachedChatActive = true;
      chatOpen = false;
      chatManuallyOpened = false;
    });
  }

  Widget _nav(int index) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: page == index ? const Color(0xffdcebf1) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => page = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icons[index], size: 18, color: const Color(0xff25465f)),
              const SizedBox(width: 10),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: page == index ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _home() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 720;
      final tight = constraints.maxHeight < 600;
      final gap = compact ? 10.0 : 14.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!tight)
            const Text(
              '경동대학교 컴퓨터공학과 · 2024학번',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xff946c2e),
                fontWeight: FontWeight.w700,
              ),
            ),
          if (!tight) const SizedBox(height: 4),
          Text(
            tight ? '오늘 무엇을 정리해볼까요?' : '정민서님, 오늘 무엇을 정리해볼까요?',
            style: TextStyle(
              fontSize: compact ? 24 : 29,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!tight) const SizedBox(height: 5),
          if (!tight)
            const Text(
              '기록과 기준은 본문에서 확인하고, 정리·탐색·계획은 오른쪽 AI 도우미에서 시작해요.',
              style: TextStyle(color: Color(0xff607386)),
            ),
          SizedBox(height: compact ? 10 : 22),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(
              tight
                  ? 16
                  : compact
                  ? 22
                  : 30,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 16 : 20),
              gradient: const LinearGradient(
                colors: [Color(0xff19344d), Color(0xff326176)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!tight)
                  const Text(
                    '•  MY UNIVERSITY PATH',
                    style: TextStyle(
                      color: Color(0xffbde9df),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                if (!tight) SizedBox(height: compact ? 7 : 12),
                Text(
                  tight
                      ? '기록을 쌓고, 다음 선택을 이어가세요.'
                      : '기록을 쌓고, 다음 선택을\n차분하게 이어가세요.',
                  style: TextStyle(
                    fontFamily: 'serif',
                    color: Colors.white,
                    fontSize: tight
                        ? 21
                        : compact
                        ? 26
                        : 32,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!tight) SizedBox(height: compact ? 6 : 10),
                if (!tight)
                  const Text(
                    '수강 계획, 학교 승인 활동, 경험과 성과를 한곳에서 확인합니다.',
                    style: TextStyle(color: Color(0xffd8e6ed)),
                  ),
              ],
            ),
          ),
          SizedBox(height: gap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, gridConstraints) {
                final singleColumn = gridConstraints.maxWidth < 650;
                final rows = singleColumn ? 4 : 2;
                final cardHeight =
                    (gridConstraints.maxHeight - gap * (rows - 1)) / rows;
                return GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: singleColumn ? 1 : 2,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: cardHeight,
                  children: [
                    _homeCard(
                      'ACADEMIC BASIS',
                      '학사 기준',
                      '연결한 학교·학과·입학연도에 맞는 적용 기준을 확인합니다.',
                      Icons.school_outlined,
                      2,
                      compact: compact || singleColumn,
                    ),
                    _homeCard(
                      'MY RECORDS',
                      '이번 학기와 활동',
                      '수강 계획 2과목 · 학교 승인 봉사 30시간 · 경험 2건',
                      Icons.book_outlined,
                      1,
                      compact: compact || singleColumn,
                    ),
                    _homeCard(
                      'OFFICIAL SOURCES',
                      '공식 문서',
                      '규정 원문과 페이지 근거를 확인합니다.',
                      Icons.description_outlined,
                      2,
                      compact: compact || singleColumn,
                    ),
                    _homeCard(
                      'PERSONAL GROWTH',
                      '성과와 진로',
                      '성과 1건 · 보유 자격 1건',
                      Icons.auto_awesome_outlined,
                      6,
                      compact: compact || singleColumn,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    },
  );
  Widget _homeCard(
    String caption,
    String title,
    String text,
    IconData icon,
    int target, {
    required bool compact,
  }) => Container(
    padding: EdgeInsets.all(compact ? 11 : 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffd8e1e7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              caption,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xff7c93a4),
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(icon, color: const Color(0xff315a77)),
          ],
        ),
        SizedBox(height: compact ? 5 : 10),
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 16 : 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (!compact) const SizedBox(height: 5),
        if (!compact)
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xff607386), fontSize: 12),
          ),
        const Spacer(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => page = target),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('열기  →'),
          ),
        ),
      ],
    ),
  );
  Widget _graduation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '경동대학교 컴퓨터공학과 · 2024학번',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xff946c2e),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '졸업 요건',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '기준 선택',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Text(
                '대학 공통 기준부터 봅니다. 탭을 누르면 해당 기준의 상세 표로 전환됩니다.',
                style: TextStyle(fontSize: 12, color: Color(0xff607386)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['대학 공통', '내 교육과정', '학과 기준']
                    .map(
                      (v) => OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: tab == v
                              ? const Color(0xffe5f0f5)
                              : Colors.white,
                        ),
                        onPressed: () => setState(() => tab = v),
                        child: Text(v),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: tab == '대학 공통'
                ? _commonRules()
                : tab == '내 교육과정'
                ? _curriculumCredits()
                : _departmentCertification(),
          ),
        ),
      ],
    );
  }

  Widget _commonRules() => _graduationSection(
    title: '대학 공통 기준',
    description: '경동대학교 일반 학부생에게 공통으로 적용되는 기준입니다. 개인 예외는 학교 학사 시스템에서 확인합니다.',
    child: _auditTable(
      const ['요건', '현재 상태', '판정', '공식 기준'],
      const [
        ['최소 총 취득학점 120학점', '88 / 120학점', '미충족', '학칙 제34조'],
        ['일반 졸업 등록학기 8학기 이상', '학적 확인 필요', '확인 필요', '졸업자격심사 규정 제2조'],
        ['필수 교과목 및 필수 P/N 이수', '과목별 확인 필요', '확인 필요', '졸업자격심사 규정 제2조'],
        ['사회봉사활동 교양필수 이수', '학교 승인 시간 확인 필요', '확인 필요', '사회봉사활동 운영 규정'],
      ],
      firstColumnWidth: 260,
    ),
  );

  Widget _curriculumCredits() => _graduationSection(
    title: '내 교육과정 학점 현황',
    description: '학교 화면의 학점 항목과 적용 교육과정 기준을 나란히 보여줍니다. 이 표 자체에는 판정 행을 넣지 않습니다.',
    child: _auditTable(
      const [
        '구분',
        '총학점',
        '사회봉사',
        '교필',
        '교선',
        '외국어',
        '전탐',
        '균형',
        '정선',
        '전필',
        '전선',
        '자유',
        '교직',
        '복수',
        '부전',
      ],
      const [
        [
          '졸업기준',
          '120',
          '—',
          '4',
          '—',
          '—',
          '—',
          '—',
          '—',
          '23',
          '—',
          '—',
          '—',
          '—',
          '—',
        ],
        [
          '취득학점',
          '88',
          '확인 필요',
          '—',
          '—',
          '4',
          '—',
          '—',
          '—',
          '14',
          '—',
          '—',
          '—',
          '—',
          '—',
        ],
        [
          '신청학점',
          '6',
          '—',
          '0',
          '0',
          '0',
          '0',
          '0',
          '3',
          '3',
          '0',
          '0',
          '0',
          '0',
          '0',
        ],
        [
          '부족학점',
          '32',
          '—',
          '—',
          '—',
          '0',
          '—',
          '—',
          '—',
          '9',
          '—',
          '—',
          '—',
          '—',
          '—',
        ],
      ],
      firstColumnWidth: 92,
      compact: true,
      groupHeaderBuilder: _creditGroupHeader,
    ),
  );

  Widget _creditGroupHeader(double firstColumnWidth, double cellWidth) =>
      Container(
        height: 34,
        color: const Color(0xfff4f1ed),
        child: Row(
          children: [
            SizedBox(width: firstColumnWidth + cellWidth * 2),
            SizedBox(
              width: cellWidth * 6,
              child: Center(
                child: Text(
                  '교양',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SizedBox(
              width: cellWidth * 2,
              child: Center(
                child: Text(
                  '전공',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SizedBox(width: cellWidth * 4),
          ],
        ),
      );

  Widget _departmentCertification() => _graduationSection(
    title: '규칙 엔진 판정 · 학과 졸업인증',
    description: '창의영역 택 1과 전공영역 택 1을 함께 충족해야 합니다. 택 1 안에서는 한 경로만 채우면 됩니다.',
    child: _auditTable(
      const ['묶음', '규칙', '상태'],
      const [
        ['창의영역', '창의영역 택 1', '충족'],
        ['전공영역 I', '자격·면허 또는 실무·실습', '확인 필요'],
        ['전공영역 II', '취업 또는 창업 증빙', '미충족'],
      ],
      firstColumnWidth: 130,
    ),
  );

  Widget _graduationSection({
    required String title,
    required String description,
    required Widget child,
  }) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Color(0xff607386)),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _auditTable(
    List<String> headers,
    List<List<String>> rows, {
    double firstColumnWidth = 170,
    bool compact = false,
    Widget Function(double firstColumnWidth, double cellWidth)?
    groupHeaderBuilder,
  }) {
    if (!compact) {
      return Table(
        border: TableBorder(
          horizontalInside: const BorderSide(color: Color(0xffd8e1e7)),
          verticalInside: const BorderSide(color: Color(0xffe6ecef)),
          top: const BorderSide(color: Color(0xffd8e1e7)),
          bottom: const BorderSide(color: Color(0xffd8e1e7)),
        ),
        columnWidths: {
          0: const FlexColumnWidth(1.9),
          for (var i = 1; i < headers.length; i++) i: const FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xffe9f0f4)),
            children: [
              for (final header in headers) _tableCell(header, header: true),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < row.length; i++)
                  _tableCell(
                    row[i],
                    status: headers[i] == '판정' ? row[i] : null,
                  ),
              ],
            ),
        ],
      );
    }
    final minimumCellWidth = compact ? 58.0 : 155.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = math.max(
          minimumCellWidth,
          (constraints.maxWidth - firstColumnWidth) / (headers.length - 1),
        );
        final tableWidth = firstColumnWidth + cellWidth * (headers.length - 1);
        return Scrollbar(
          controller: curriculumScrollController,
          thumbVisibility: tableWidth > constraints.maxWidth,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: curriculumScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?groupHeaderBuilder?.call(firstColumnWidth, cellWidth),
                  Table(
                    border: TableBorder(
                      horizontalInside: const BorderSide(
                        color: Color(0xffd8e1e7),
                      ),
                      verticalInside: const BorderSide(
                        color: Color(0xffe6ecef),
                      ),
                      top: const BorderSide(color: Color(0xffd8e1e7)),
                      bottom: const BorderSide(color: Color(0xffd8e1e7)),
                    ),
                    columnWidths: {
                      0: FixedColumnWidth(firstColumnWidth),
                      for (var i = 1; i < headers.length; i++)
                        i: FixedColumnWidth(cellWidth),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xffe9f0f4),
                        ),
                        children: [
                          for (final header in headers)
                            _tableCell(header, header: true, compact: compact),
                        ],
                      ),
                      for (final row in rows)
                        TableRow(
                          children: [
                            for (var i = 0; i < row.length; i++)
                              _tableCell(
                                row[i],
                                compact: compact,
                                status: !compact && headers[i] == '판정'
                                    ? row[i]
                                    : null,
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableCell(
    String value, {
    bool header = false,
    bool compact = false,
    String? status,
  }) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 10,
      vertical: compact ? 9 : 12,
    ),
    child: status == null
        ? Text(
            value,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: header ? const Color(0xff28465f) : const Color(0xff314b60),
              fontWeight: header ? FontWeight.w800 : FontWeight.w500,
            ),
          )
        : Align(alignment: Alignment.centerLeft, child: _statusBadge(status)),
  );

  Widget _statusBadge(String status) {
    final color = status == '충족'
        ? const Color(0xff157766)
        : status == '미충족'
        ? const Color(0xffb44232)
        : const Color(0xff956720);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _record() {
    switch (page) {
      case 1:
        return _recordPage(
          kicker: 'ACADEMIC RECORDS',
          title: '수강 관리',
          description: '학교 수강 내역을 기준으로 이번 학기 계획과 이수 기록을 정리합니다.',
          notice: '학교 수강 시스템에서 확정된 과목만 등록해 주세요.',
          listTitle: '이번 학기 수강 과목',
          entries: const [
            ('자료구조', '전공선택 · 3학점', '수강 중'),
            ('데이터베이스', '전공선택 · 3학점', '수강 예정'),
            ('사회봉사', '교양필수 · 승인 시간 확인', '확인 필요'),
          ],
          guideTitle: '교육과정 확인',
          guides: const [
            '인정 영역과 학점 분류 확인',
            '다음 학기 수강 계획 정리',
            '학과 공지의 변경 사항 확인',
          ],
        );
      case 3:
        return _recordPage(
          kicker: 'ACTIVITY RECORDS',
          title: '활동',
          description: '교내외 활동과 봉사 내역을 한곳에 기록합니다.',
          notice: '졸업 반영이 필요한 활동은 학교 시스템 승인 후 등록해 주세요.',
          listTitle: '등록한 활동',
          entries: const [
            ('학과 멘토링', '교내 활동 · 2026.03–06', '기록됨'),
            ('지역 아동센터 봉사', '1365 연계 · 30시간', '학교 승인 확인'),
            ('학술 동아리', '프로젝트 활동 · 2026.03–', '진행 중'),
          ],
          guideTitle: '활동 준비',
          guides: const [
            '봉사 시간·증빙 자료 점검',
            '교내 활동 인정 절차 확인',
            '필요할 때 외부 봉사 사이트 안내',
          ],
        );
      case 4:
        return _recordPage(
          kicker: 'EXPERIENCE RECORDS',
          title: '경험',
          description: '프로젝트·인턴·동아리 경험을 이력 문장과 강점으로 정리합니다.',
          notice: '사실과 역할을 먼저 기록하고, 표현 정리는 AI 도우미에게 물어보세요.',
          listTitle: '경험 타임라인',
          entries: const [
            ('캡스톤 설계 프로젝트', '프론트엔드 구현 · 팀 프로젝트', '정리 필요'),
            ('학과 해커톤', '서비스 기획·발표', '기록됨'),
            ('스터디 운영', '주 1회 진행 · 2025.09–', '진행 중'),
          ],
          guideTitle: '이력 정리',
          guides: const [
            '내 역할과 결과를 분리해 기록',
            '증빙 링크·자료 위치 보관',
            '자기소개서 문장 초안 만들기',
          ],
        );
      case 5:
        return _recordPage(
          kicker: 'CERTIFICATE RECORDS',
          title: '자격',
          description: '자격증·어학·교육 이수 내역을 관리합니다.',
          notice: '발급·등록이 완료된 자격만 등록해 주세요.',
          listTitle: '등록한 자격',
          entries: const [
            ('정보처리기사', 'Q-Net 발급 확인 후 등록', '준비 중'),
            ('SQLD', '국가공인 민간자격', '취득'),
            ('OPIc', '어학 성적 · 유효기간 확인', '확인 필요'),
          ],
          guideTitle: '자격 준비',
          guides: const [
            '희망 직무와 자격의 연관성 탐색',
            'Q-Net 시험 일정·발급 정보 안내',
            '성적·자격 유효기간 점검',
          ],
        );
      case 6:
        return _recordPage(
          kicker: 'PORTFOLIO & OUTCOMES',
          title: '포트폴리오·성과',
          description: '프로젝트, 논문, 수상과 산출물을 포트폴리오로 구성합니다.',
          notice: '파일은 증빙·보관용으로 올리고, 핵심 내용은 설명으로 함께 기록해 주세요.',
          listTitle: '포트폴리오 초안',
          entries: const [
            ('UniversityPath AI', '기획·화면 설계·구현 기록', '초안'),
            ('캡스톤 결과물', '발표 자료·저장소 링크', '자료 필요'),
            ('학과 해커톤 장려상', '상장·역할·결과 정리', '기록됨'),
          ],
          guideTitle: '성과 구성',
          guides: const [
            '설명·역할·결과·링크를 함께 보관',
            '공개 가능한 파일만 첨부',
            '지원 목적에 맞게 항목 순서 구성',
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _recordPage({
    required String kicker,
    required String title,
    required String description,
    required String notice,
    required String listTitle,
    required List<(String, String, String)> entries,
    required String guideTitle,
    required List<String> guides,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        kicker,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: .5,
          fontWeight: FontWeight.w800,
          color: Color(0xff738ba0),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        title,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      Text(description, style: const TextStyle(color: Color(0xff607386))),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xfffff7e5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffefdba7)),
        ),
        child: Text(
          notice,
          style: const TextStyle(fontSize: 12, color: Color(0xff795a22)),
        ),
      ),
      const SizedBox(height: 14),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 760;
            final records = _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '학교 승인 상태와 개인 기록은 구분해서 표시합니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xff607386)),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in entries)
                    _recordEntry(entry.$1, entry.$2, entry.$3),
                ],
              ),
            );
            final guide = _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guideTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in guides)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 17,
                            color: Color(0xff38738a),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  const Text(
                    '질문이나 정리 요청은 오른쪽 AI 도우미에서 이어갈 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xff607386)),
                  ),
                ],
              ),
            );
            return SingleChildScrollView(
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: records),
                        const SizedBox(width: 14),
                        Expanded(flex: 4, child: guide),
                      ],
                    )
                  : Column(
                      children: [records, const SizedBox(height: 14), guide],
                    ),
            );
          },
        ),
      ),
    ],
  );

  Widget _recordEntry(String title, String detail, String status) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xffe4ebef))),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 19,
          color: Color(0xff315a77),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Color(0xff607386)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _statusBadge(status == '취득' || status == '기록됨' ? '충족' : status),
      ],
    ),
  );
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffd8e1e7)),
    ),
    child: child,
  );
  Widget _chat({
    required VoidCallback onClose,
    VoidCallback? onDetach,
    required double width,
  }) {
    return Container(
      width: width,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAG 기반 대화',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff946c2e),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'AI 도우미',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDetach != null)
                  Tooltip(
                    message: '새 창으로 분리',
                    child: IconButton(
                      onPressed: onDetach,
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ),
                Tooltip(
                  message: 'AI 도우미 닫기',
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '현재 화면의 기록을 읽고 답합니다. 규정 질문에는 공식 문서 근거를 자동으로 붙입니다.',
              style: TextStyle(fontSize: 12, color: Color(0xff607386)),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final user = messages[i].startsWith('나:');
                return Align(
                  alignment: user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 285),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: user
                          ? const Color(0xff1c425e)
                          : const Color(0xffeef4f6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      messages[i],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: user ? Colors.white : const Color(0xff243d52),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: '자연어로 질문해 보세요',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: send, child: const Text('보내기')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
