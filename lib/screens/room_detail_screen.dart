import 'package:flutter/material.dart';

import '../tado/tado_client.dart';
import '../tado/tado_service.dart';
import 'schedule_screen.dart';
import 'thermostat_dial.dart';

/// The room view: a thermostat control on one side (current temp, on/off,
/// target-temperature slider) and the weekly schedule on the other. Used as
/// the entire Heating tab body, since there's only one thermostat.
class RoomControlPanel extends StatefulWidget {
  final TadoService service;
  final TadoRoomStatus status;

  const RoomControlPanel({super.key, required this.service, required this.status});

  @override
  State<RoomControlPanel> createState() => _RoomControlPanelState();
}

class _RoomControlPanelState extends State<RoomControlPanel> {
  late TadoRoomStatus _status;
  late double _target;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _target = _status.targetTemperature ?? _status.currentTemperature ?? 20.0;
  }

  @override
  void didUpdateWidget(RoomControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_submitting && oldWidget.status != widget.status) {
      _status = widget.status;
      _target = _status.targetTemperature ?? _status.currentTemperature ?? _target;
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final rooms = await widget.service.getRooms();
      final matches = rooms.where((r) => r.id == _status.id);
      final updated = matches.isEmpty ? null : matches.first;
      if (!mounted || updated == null) return;
      setState(() {
        _status = updated;
        _target = updated.targetTemperature ?? updated.currentTemperature ?? _target;
      });
    } catch (_) {
      // Keep showing the last known status; the action itself already
      // reported success or failure.
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await action();
      await _refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _togglePower(bool on) async {
    if (on) {
      await _runAction(() => widget.service.setTemperature(_status.id, _target));
    } else {
      await _runAction(() => widget.service.turnOff(_status.id));
    }
  }

  Future<void> _commitTarget(double value) async {
    if (!_status.power) return;
    await _runAction(() => widget.service.setTemperature(_status.id, value));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final thermostat = _buildThermostatPanel();
        final schedule = widget.service.supportsScheduleEditing
            ? ScheduleEditor(service: widget.service, roomId: _status.id)
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Schedule editing isn\'t available for Tado X yet.',
                    style: TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              );

        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: thermostat),
              const VerticalDivider(width: 1, color: Colors.white12),
              Expanded(child: schedule),
            ],
          );
        }
        return Column(
          children: [
            thermostat,
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: schedule),
          ],
        );
      },
    );
  }

  Widget _buildThermostatPanel() {
    final isHeating = (_status.heatingPowerPercent ?? 0) > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ThermostatDial(
            currentTemperature: _status.currentTemperature,
            target: _target,
            min: 5,
            max: 25,
            power: _status.power,
            isHeating: isHeating,
            enabled: !_submitting,
            onPowerChanged: _togglePower,
            onTargetChanging: (value) => setState(() => _target = value),
            onTargetCommitted: _commitTarget,
          ),
          if (_status.hasManualOverlay) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => _runAction(() => widget.service.resumeSchedule(_status.id)),
              child: const Text('Resume schedule'),
            ),
          ],
          if (_submitting) ...[
            const SizedBox(height: 12),
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
