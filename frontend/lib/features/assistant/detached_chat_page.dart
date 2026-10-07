import 'package:flutter/material.dart';

import '../../chat_window.dart' as chat_window;
import 'assistant_api.dart';
import 'assistant_conversation.dart';
import 'assistant_panel.dart';

class DetachedChatWindow extends StatefulWidget {
  const DetachedChatWindow({super.key, this.assistantFactory});
  final AssistantGateway Function()? assistantFactory;
  @override
  State<DetachedChatWindow> createState() => _DetachedChatWindowState();
}

class _DetachedChatWindowState extends State<DetachedChatWindow> {
  late final _conversation = AssistantConversation(
    api: widget.assistantFactory?.call(),
  );
  @override
  void dispose() {
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => AssistantPanel(
          conversation: _conversation,
          width: constraints.maxWidth,
          onClose: chat_window.closeDetachedChatWindow,
        ),
      ),
    ),
  );
}
