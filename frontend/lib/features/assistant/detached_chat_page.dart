import 'package:flutter/material.dart';

import '../../chat_window.dart' as chat_window;
import 'assistant_api.dart';
import 'assistant_conversation.dart';
import 'assistant_panel.dart';
import 'remote_school_profile.dart';
import 'shared_school_context.dart';

class DetachedChatWindow extends StatefulWidget {
  const DetachedChatWindow({
    super.key,
    this.assistantFactory,
    this.schoolProfileFactory,
  });
  final AssistantGateway Function()? assistantFactory;
  final RemoteSchoolProfile Function()? schoolProfileFactory;
  @override
  State<DetachedChatWindow> createState() => _DetachedChatWindowState();
}

class _DetachedChatWindowState extends State<DetachedChatWindow> {
  late final _conversation = AssistantConversation(
    api: widget.assistantFactory?.call(),
  );
  late final _profile =
      widget.schoolProfileFactory?.call() ?? RemoteSchoolProfile();
  late final _shared = SharedSchoolContext(_profile, _conversation);
  @override
  void initState() {
    super.initState();
    _shared;
    _profile.load();
  }

  @override
  void dispose() {
    _shared.dispose();
    _profile.dispose();
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _profile,
          builder: (context, _) => Column(
            children: [
              if (_profile.isLoading)
                const LinearProgressIndicator()
              else if (_profile.loadFailed)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const Text('메인 창의 학교 정보를 읽지 못했습니다. 다시 읽어 주세요.'),
                      TextButton(
                        onPressed: _profile.load,
                        child: const Text('학교 정보 다시 읽기'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: AssistantPanel(
                  conversation: _conversation,
                  saveContext: _shared.save,
                  width: constraints.maxWidth,
                  onClose: chat_window.closeDetachedChatWindow,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
