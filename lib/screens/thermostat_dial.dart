import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plug_tile.dart' show heatOrange, neonGreen;

/// A round thermostat control: tapping the disc toggles power on/off, and
/// dragging along the top half of the rim sets the target temperature
/// (left = [min], right = [max], sweeping through the top).
class ThermostatDial extends StatefulWidget {
  final double? currentTemperature;
  final double target;
  final double min;
  final double max;
  final bool power;
  final bool isHeating;
  final bool enabled;
  final ValueChanged<bool> onPowerChanged;
  final ValueChanged<double> onTargetChanging;
  final ValueChanged<double> onTargetCommitted;

  const ThermostatDial({
    super.key,
    required this.currentTemperature,
    required this.target,
    required this.min,
    required this.max,
    required this.power,
    required this.isHeating,
    required this.enabled,
    required this.onPowerChanged,
    required this.onTargetChanging,
    required this.onTargetCommitted,
  });

  @override
  State<ThermostatDial> createState() => _ThermostatDialState();
}

class _ThermostatDialState extends State<ThermostatDial> {
  static const _size = 220.0;
  bool _dragging = false;

  double _tempForAngle(double angle) {
    final clamped = angle.clamp(-math.pi, 0.0);
    final t = (clamped + math.pi) / math.pi;
    return widget.min + t * (widget.max - widget.min);
  }

  Offset _center() => const Offset(_size / 2, _size / 2);

  bool _inTopHalf(Offset local) => (local.dy - _center().dy) <= 12;

  void _updateFromLocal(Offset local) {
    final center = _center();
    var angle = math.atan2(local.dy - center.dy, local.dx - center.dx);
    if (angle > 0) angle = 0;
    if (angle < -math.pi) angle = -math.pi;
    final rawTemp = _tempForAngle(angle);
    final snapped = ((rawTemp * 2).round() / 2).clamp(widget.min, widget.max);
    widget.onTargetChanging(snapped);
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    widget.onPowerChanged(!widget.power);
  }

  void _handlePanStart(DragStartDetails details) {
    _dragging = widget.enabled && widget.power && _inTopHalf(details.localPosition);
    if (_dragging) _updateFromLocal(details.localPosition);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _updateFromLocal(details.localPosition);
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    widget.onTargetCommitted(widget.target);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isHeating ? heatOrange : neonGreen;
    final progress = ((widget.target - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

    return GestureDetector(
      onTapUp: _handleTapUp,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _ThermostatPainter(progress: progress, power: widget.power, accent: accent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.currentTemperature == null
                      ? '—'
                      : '${widget.currentTemperature!.toStringAsFixed(1)}°',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300),
                ),
                Text(
                  widget.power ? (widget.isHeating ? 'Heating' : 'Idle') : 'Off',
                  style: TextStyle(color: widget.power ? accent : Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Target ${widget.target.toStringAsFixed(1)}°C',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThermostatPainter extends CustomPainter {
  final double progress;
  final bool power;
  final Color accent;

  _ThermostatPainter({required this.progress, required this.power, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius - 14, Paint()..color = const Color(0xFF141414));
    canvas.drawCircle(
      center,
      radius - 14,
      Paint()
        ..color = power ? accent.withValues(alpha: 0.6) : Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final arcRect = Rect.fromCircle(center: center, radius: radius - 6);
    canvas.drawArc(
      arcRect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      arcRect,
      math.pi,
      math.pi * progress,
      false,
      Paint()
        ..color = power ? accent : Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    final knobAngle = math.pi + math.pi * progress;
    final knobCenter =
        center + Offset(math.cos(knobAngle), math.sin(knobAngle)) * (radius - 6);
    canvas.drawCircle(knobCenter, 8, Paint()..color = power ? accent : Colors.white54);
  }

  @override
  bool shouldRepaint(covariant _ThermostatPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.power != power || oldDelegate.accent != accent;
}
