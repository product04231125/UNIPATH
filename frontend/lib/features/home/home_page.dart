import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onOpenPage});

  final ValueChanged<int> onOpenPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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
                    _HomeCard(
                      caption: 'ACADEMIC BASIS',
                      title: '학사 기준',
                      text: '지원하지 않는 학교·학과도 내 기준을 직접 설정해 관리할 수 있습니다.',
                      icon: Icons.school_outlined,
                      target: 2,
                      compact: compact || singleColumn,
                      onOpenPage: onOpenPage,
                    ),
                    _HomeCard(
                      caption: 'MY RECORDS',
                      title: '이번 학기와 활동',
                      text: '수강 계획 2과목 · 학교 승인 봉사 30시간 · 경험 2건',
                      icon: Icons.book_outlined,
                      target: 1,
                      compact: compact || singleColumn,
                      onOpenPage: onOpenPage,
                    ),
                    _HomeCard(
                      caption: 'OFFICIAL SOURCES',
                      title: '공식 문서',
                      text: '규정 원문과 페이지 근거를 확인합니다.',
                      icon: Icons.description_outlined,
                      target: 2,
                      compact: compact || singleColumn,
                      onOpenPage: onOpenPage,
                    ),
                    _HomeCard(
                      caption: 'PERSONAL GROWTH',
                      title: '성과와 진로',
                      text: '성과 1건 · 보유 자격 1건',
                      icon: Icons.auto_awesome_outlined,
                      target: 6,
                      compact: compact || singleColumn,
                      onOpenPage: onOpenPage,
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
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.caption,
    required this.title,
    required this.text,
    required this.icon,
    required this.target,
    required this.compact,
    required this.onOpenPage,
  });

  final String caption;
  final String title;
  final String text;
  final IconData icon;
  final int target;
  final bool compact;
  final ValueChanged<int> onOpenPage;

  @override
  Widget build(BuildContext context) => Container(
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
            onPressed: () => onOpenPage(target),
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
}
