import 'package:flutter/material.dart';

class SurfaceCard extends StatelessWidget {
  static const horizontalInsets = 38.0;

  const SurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffd8e1e7)),
    ),
    child: child,
  );
}
