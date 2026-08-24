import 'package:flutter/material.dart';

import 'plug_tile.dart' show neonGreen;

enum GroupPowerState { allOn, allOff, mixed }

/// A tile for a group of plugs. Tapping toggles every member together —
/// turning a mixed/off group fully on, or a fully-on group fully off.
class GroupTile extends StatelessWidget {
  final String name;
  final int memberCount;
  final GroupPowerState state;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const GroupTile({
    super.key,
    required this.name,
    required this.memberCount,
    required this.state,
    required this.isLoading,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final active = state == GroupPowerState.allOn;
    final mixed = state == GroupPowerState.mixed;

    final statusText = switch (state) {
      GroupPowerState.allOn => 'On',
      GroupPowerState.allOff => 'Off',
      GroupPowerState.mixed => 'Mixed',
    };
    final statusColor = active
        ? neonGreen
        : mixed
        ? Colors.amberAccent
        : Colors.white38;

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
            color: active
                ? neonGreen
                : mixed
                ? Colors.amberAccent.withValues(alpha: 0.6)
                : Colors.white12,
            width: active || mixed ? 1.5 : 1,
          ),
          boxShadow: active
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
              Icons.grid_view_rounded,
              size: 30,
              color: active
                  ? neonGreen
                  : mixed
                  ? Colors.amberAccent
                  : Colors.white24,
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
              '$statusText · $memberCount device${memberCount == 1 ? '' : 's'}',
              style: TextStyle(color: statusColor, fontSize: 12),
              maxLines: 1,
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
