import 'package:flutter/material.dart';

import '../../chat_window.dart' as chat_window;
import 'assistant_api.dart';
import 'assistant_conversation.dart';
import 'assistant_panel.dart';
import 'remote_school_profile.dart';
import 'shared_school_context.dart';

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
  late final _profile = RemoteSchoolProfile();
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
        builder: (context, constraints) => AssistantPanel(
          conversation: _conversation,
          saveContext: _shared.save,
          width: constraints.maxWidth,
          onClose: chat_window.closeDetachedChatWindow,
        ),
      ),
    ),
  );
}
