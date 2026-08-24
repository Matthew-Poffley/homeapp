import 'package:flutter/material.dart';

import 'plug_tile.dart' show neonGreen;

/// A tile for a triggerable action. Tapping fires it (or cancels it early,
/// if it's already active); long-press edits/deletes it.
class ActionTile extends StatelessWidget {
  final String name;
  final bool isActive;
  final String subtitle;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const ActionTile({
    super.key,
    required this.name,
    required this.isActive,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? neonGreen : Colors.white12,
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: neonGreen.withValues(alpha: 0.45),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 30,
              color: isActive ? neonGreen : Colors.white24,
            ),
            const SizedBox(height: 14),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: isActive ? neonGreen : Colors.white38, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isLoading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(neonGreen),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
