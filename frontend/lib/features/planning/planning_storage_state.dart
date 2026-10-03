import 'package:flutter/material.dart';

import 'planning_repository.dart';

class PlanningStorageState extends StatelessWidget {
  const PlanningStorageState({super.key, required this.repository});
  final PlanningRepository repository;

  @override
  Widget build(BuildContext context) => Center(
    child: repository.isLoading
        ? const CircularProgressIndicator()
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('개인 계획을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.'),
              TextButton(
                onPressed: repository.load,
                child: const Text('다시 시도'),
              ),
            ],
          ),
  );
}
