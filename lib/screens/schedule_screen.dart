import 'package:flutter/material.dart';

import '../tado/tado_schedule.dart';
import '../tado/tado_service.dart';
import 'plug_tile.dart' show neonGreen;

class ScheduleScreen extends StatelessWidget {
  final TadoService service;
  final String roomId;
  final String roomName;

  const ScheduleScreen({
    super.key,
    required this.service,
    required this.roomId,
    required this.roomName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$roomName schedule')),
      body: ScheduleEditor(service: service, roomId: roomId),
    );
  }
}

/// The day-type chips + block list + add/edit controls, with no Scaffold of
/// its own so it can be embedded either as a full page or as one pane of a
/// split layout.
class ScheduleEditor extends StatefulWidget {
  final TadoService service;
  final String roomId;

  const ScheduleEditor({super.key, required this.service, required this.roomId});

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  bool _loading = true;
  String? _error;
  TadoSchedule? _schedule;
  String? _selectedDayType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final schedule = await widget.service.getSchedule(widget.roomId);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _selectedDayType ??= schedule.orderedDayTypes.isEmpty
            ? null
            : schedule.orderedDayTypes.first;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _describeError(e);
        _loading = false;
      });
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    return message.length > 160 ? '${message.substring(0, 160)}…' : message;
  }

  Future<void> _saveDayType(String dayType, List<TadoScheduleBlock> blocks) async {
    final schedule = _schedule;
    if (schedule == null) return;
    setState(() => _saving = true);
    try {
      await widget.service.saveDayBlocks(widget.roomId, schedule.timetableId, dayType, blocks);
      if (!mounted) return;
      setState(() {
        schedule.blocksByDayType[dayType] = blocks;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_describeError(e))));
    }
  }

  Future<void> _editBlock(String dayType, List<TadoScheduleBlock> blocks, int index) async {
    final result = await _showBlockEditor(existing: blocks[index]);
    if (result == null) return;
    final updated = [...blocks];
    if (result.delete) {
      updated.removeAt(index);
    } else {
      updated[index] = result.block!;
    }
    updated.sort((a, b) => a.start.compareTo(b.start));
    await _saveDayType(dayType, updated);
  }

  Future<void> _addBlock(String dayType, List<TadoScheduleBlock> blocks) async {
    final lastEnd = blocks.isEmpty ? '00:00:00' : blocks.last.end;
    final result = await _showBlockEditor(
      existing: TadoScheduleBlock(
        dayType: dayType,
        start: lastEnd,
        end: '23:59:00',
        temperature: 20,
      ),
      isNew: true,
    );
    if (result == null || result.block == null) return;
    final updated = [...blocks, result.block!];
    updated.sort((a, b) => a.start.compareTo(b.start));
    await _saveDayType(dayType, updated);
  }

  Future<_BlockEditResult?> _showBlockEditor({
    required TadoScheduleBlock existing,
    bool isNew = false,
  }) async {
    var start = _parseTime(existing.start);
    var end = _parseTime(existing.end);
    var temperature = existing.temperature ?? 20.0;
    var isOff = existing.temperature == null;

    return showDialog<_BlockEditResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isNew ? 'Add block' : 'Edit block'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start'),
                    trailing: Text(start.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: start);
                      if (picked != null) setDialogState(() => start = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End'),
                    trailing: Text(end.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: end);
                      if (picked != null) setDialogState(() => end = picked);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Heating on'),
                    value: !isOff,
                    onChanged: (value) => setDialogState(() => isOff = !value),
                  ),
                  if (!isOff)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              setDialogState(() => temperature = (temperature - 0.5).clamp(5, 25)),
                        ),
                        Text(
                          '${temperature.toStringAsFixed(1)}°C',
                          style: const TextStyle(fontSize: 22, color: Colors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () =>
                              setDialogState(() => temperature = (temperature + 0.5).clamp(5, 25)),
                        ),
                      ],
                    ),
                ],
              ),
              actions: [
                if (!isNew)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(_BlockEditResult.deleteResult()),
                    child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _BlockEditResult(
                        block: existing.copyWith(
                          start: _formatTime(start),
                          end: _formatTime(end),
                          temperature: isOff ? null : temperature,
                          clearTemperature: isOff,
                        ),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return _buildContent();
  }

  Widget _buildContent() {
    final schedule = _schedule!;
    final dayTypes = schedule.orderedDayTypes;
    final selected = _selectedDayType ?? (dayTypes.isEmpty ? null : dayTypes.first);
    final blocks = selected == null ? const <TadoScheduleBlock>[] : schedule.blocksByDayType[selected]!;

    return Column(
      children: [
        if (_saving) const LinearProgressIndicator(minHeight: 2, color: neonGreen),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: dayTypes.map((dayType) {
              return ChoiceChip(
                label: Text(tadoDayTypeLabels[dayType] ?? dayType),
                selected: dayType == selected,
                onSelected: (_) => setState(() => _selectedDayType = dayType),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Text('No schedule found.', style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    final isOff = block.temperature == null;
                    return Card(
                      color: const Color(0xFF141414),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                          isOff ? Icons.power_settings_new_rounded : Icons.thermostat_rounded,
                          color: isOff ? Colors.white38 : neonGreen,
                        ),
                        title: Text(
                          '${block.start.substring(0, 5)} – ${block.end.substring(0, 5)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          isOff ? 'Off' : '${block.temperature!.toStringAsFixed(1)}°C',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () => _editBlock(selected, blocks, index),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: selected == null ? null : () => _addBlock(selected, blocks),
            icon: const Icon(Icons.add),
            label: const Text('Add block'),
          ),
        ),
      ],
    );
  }
}

class _BlockEditResult {
  final TadoScheduleBlock? block;
  final bool delete;

  _BlockEditResult({this.block}) : delete = false;
  _BlockEditResult.deleteResult() : block = null, delete = true;
}
