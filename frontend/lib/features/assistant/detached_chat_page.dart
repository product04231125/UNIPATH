import 'package:flutter/material.dart';

import '../../chat_window.dart' as chat_window;
import 'assistant_api.dart';
import 'assistant_conversation.dart';
import 'assistant_panel.dart';
import 'remote_school_profile.dart';
import 'shared_school_context.dart';
import 'conversation_bridge.dart';

class DetachedChatWindow extends StatefulWidget {
  const DetachedChatWindow({
    super.key,
    this.assistantFactory,
    this.schoolProfileFactory,
    this.conversationFactory,
  });
  final AssistantGateway Function()? assistantFactory;
  final RemoteSchoolProfile Function()? schoolProfileFactory;
  final AssistantConversation Function()? conversationFactory;
  @override
  State<DetachedChatWindow> createState() => _DetachedChatWindowState();
}

class _DetachedChatWindowState extends State<DetachedChatWindow> {
  late final AssistantConversation _conversation =
      widget.conversationFactory?.call() ??
      (widget.assistantFactory != null
          ? AssistantConversation(api: widget.assistantFactory!())
          : RemoteConversation(
              request: chat_window.requestConversation,
              changes: chat_window.conversationChanges(),
            ));
  late final _profile =
      widget.schoolProfileFactory?.call() ?? RemoteSchoolProfile();
  late final _shared = SharedSchoolContext(_profile, _conversation);
  @override
  void initState() {
    super.initState();
    _shared;
    _profile.load();
    if (_conversation is RemoteConversation) {
      final remote = _conversation;
      chat_window.bindConversationClose(remote.prepareClose);
      remote.load();
    }
  }

  @override
  void dispose() {
    chat_window.bindConversationClose(null);
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
          animation: Listenable.merge([_profile, _conversation]),
          builder: (context, _) => Column(
            children: [
              if (!_conversation.ready && _conversation.connectionError == null)
                const LinearProgressIndicator(),
              if (_conversation.connectionError != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(_conversation.connectionError!),
                      TextButton(
                        onPressed: () =>
                            (_conversation as RemoteConversation).load(),
                        child: const Text('대화 다시 연결'),
                      ),
                    ],
                  ),
                ),
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
