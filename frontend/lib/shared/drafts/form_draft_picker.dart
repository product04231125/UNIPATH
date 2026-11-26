import 'package:flutter/material.dart';

import 'form_draft_entry.dart';
import 'form_draft_store.dart';

/// Shows saved drafts for [collectionKey]. Returns the chosen entry, or null.
Future<FormDraftEntry?> showFormDraftPicker({
  required BuildContext context,
  required String collectionKey,
  FormDraftStore? store,
}) async {
  final drafts = store ?? FormDraftStore.instance;
  var entries = await drafts.list(collectionKey);
  if (!context.mounted) return null;
  if (entries.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('불러올 임시저장이 없습니다.')),
    );
    return null;
  }

  return showDialog<FormDraftEntry>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('임시저장 불러오기'),
        content: SizedBox(
          width: 420,
          child: entries.isEmpty
              ? const Text('불러올 임시저장이 없습니다.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final when = _formatSavedAt(entry.savedAt);
                    return ListTile(
                      key: ValueKey('form-draft-${entry.id}'),
                      title: Text(entry.summary),
                      subtitle: Text(when),
                      onTap: () => Navigator.pop(dialogContext, entry),
                      trailing: IconButton(
                        tooltip: '삭제',
                        onPressed: () async {
                          await drafts.delete(collectionKey, entry.id);
                          entries = await drafts.list(collectionKey);
                          if (!context.mounted) return;
                          setState(() {});
                          if (entries.isEmpty && dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    ),
  );
}

String _formatSavedAt(DateTime savedAt) {
  final local = savedAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
