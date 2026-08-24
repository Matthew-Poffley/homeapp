import 'package:flutter/material.dart';

import '../tapo/smart_plug_client.dart';

const neonGreen = Color(0xFF39FF14);
const heatOrange = Color(0xFFFF8A3D);

/// A single glowing tile for one plug/outlet. The whole tile is tappable to
/// toggle power; long-press removes it. Active (on) tiles get a neon green
/// border and glow; inactive ones stay dim.
class PlugTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isOn;
  final bool isLoading;
  final bool isError;
  final bool enabled;
  final NextAction? nextAction;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onLongPress;

  const PlugTile({
    super.key,
    required this.name,
    required this.subtitle,
    required this.isOn,
    required this.isLoading,
    required this.isError,
    required this.enabled,
    required this.nextAction,
    required this.onChanged,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final active = isOn && !isError;
    final canTap = enabled && !isLoading && onChanged != null;

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: canTap ? () => onChanged!(!isOn) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isError
                ? Colors.redAccent.withValues(alpha: 0.7)
                : active
                ? neonGreen
                : Colors.white12,
            width: active || isError ? 1.5 : 1,
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
              Icons.power_settings_new_rounded,
              size: 30,
              color: isError
                  ? Colors.redAccent
                  : active
                  ? neonGreen
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
              isError ? subtitle : (isOn ? 'On' : 'Off'),
              style: TextStyle(
                color: isError ? Colors.redAccent : (active ? neonGreen : Colors.white38),
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isError && nextAction != null) ...[
              const SizedBox(height: 4),
              Text(
                '${nextAction!.turningOn ? "Turns on" : "Turns off"} at '
                '${nextAction!.formattedTime}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
