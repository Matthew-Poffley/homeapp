import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tapo/action_repository.dart';
import '../tapo/group_repository.dart';
import '../tapo/legacy_plug.dart';
import '../tapo/plug_action.dart';
import '../tapo/plug_group.dart';
import '../tapo/plug_repository.dart';
import '../tapo/saved_plug.dart';
import '../tapo/smart_plug_client.dart';
import '../tapo/tapo_account_repository.dart';
import '../tapo/tapo_plug.dart';
import 'action_tile.dart';
import 'group_tile.dart';
import 'heating_tab.dart';
import 'plug_tile.dart';

class _PlugState {
  final SavedPlug saved;
  SmartPlugClient? client;
  bool isOn = false;
  bool isLoading = true;
  String? error;
  NextAction? nextAction;

  _PlugState(this.saved);
}

class PlugListScreen extends StatefulWidget {
  const PlugListScreen({super.key});

  @override
  State<PlugListScreen> createState() => _PlugListScreenState();
}

class _PlugListScreenState extends State<PlugListScreen> with SingleTickerProviderStateMixin {
  final _repository = PlugRepository();
  final _accountRepository = TapoAccountRepository();
  final _groupRepository = GroupRepository();
  final _actionRepository = ActionRepository();
  final List<_PlugState> _plugs = [];
  List<PlugGroup> _groups = [];
  List<PlugAction> _actions = [];
  final Set<String> _busyActionIds = {};
  bool _loadingList = true;
  late final TabController _tabController;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadPlugs();
    _loadGroups();
    _loadActions();
    // Catches an action whose pause should have already lifted, in case
    // the app wasn't open when it expired.
    _expiryTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _resumeAnyExpiredActions(),
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _tabController.dispose();
    for (final plug in _plugs) {
      plug.client?.close();
    }
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final groups = await _groupRepository.loadGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  Future<void> _loadActions() async {
    final actions = await _actionRepository.loadActions();
    if (!mounted) return;
    setState(() => _actions = actions);
    await _resumeAnyExpiredActions();
  }

  /// Re-enables the schedule on any action whose pause window has already
  /// lifted — covers the case where the app wasn't open at the exact
  /// moment it expired. Only reloads from storage if something actually
  /// changed, to avoid looping back into _loadActions unconditionally.
  Future<void> _resumeAnyExpiredActions() async {
    var changed = false;
    for (final action in _actions) {
      if (action.activeUntil == null || action.isActive) continue;
      await _resumeActionMembers(action);
      await _actionRepository.updateAction(action.withActiveUntil(null));
      changed = true;
    }
    if (!changed) return;
    final refreshed = await _actionRepository.loadActions();
    if (!mounted) return;
    setState(() => _actions = refreshed);
  }

  _PlugState? _findPlugById(String id) {
    for (final p in _plugs) {
      if (p.saved.id == id) return p;
    }
    return null;
  }

  Future<void> _resumeActionMembers(PlugAction action) async {
    for (final memberId in action.plugIds) {
      final member = _findPlugById(memberId);
      final client = member?.client;
      if (client is LegacyKasaPlug) {
        try {
          await client.setScheduleEnabled(true);
        } catch (_) {
          // Best-effort — the next periodic check will retry.
        }
      }
    }
  }

  Future<void> _triggerAction(PlugAction action) async {
    if (_busyActionIds.contains(action.id)) return;
    setState(() => _busyActionIds.add(action.id));
    try {
      for (final memberId in action.plugIds) {
        final member = _findPlugById(memberId);
        if (member == null) continue;
        final client = member.client;
        if (client is LegacyKasaPlug) {
          try {
            await client.setScheduleEnabled(false);
          } catch (_) {
            // Still turn the plug off even if the schedule pause fails.
          }
        }
        await _togglePlug(member, false);
      }
      final activeUntil = DateTime.now().add(Duration(hours: action.pauseHours));
      await _actionRepository.updateAction(action.withActiveUntil(activeUntil));
      await _loadActions();
    } finally {
      if (mounted) setState(() => _busyActionIds.remove(action.id));
    }
  }

  Future<void> _cancelAction(PlugAction action) async {
    if (_busyActionIds.contains(action.id)) return;
    setState(() => _busyActionIds.add(action.id));
    try {
      await _resumeActionMembers(action);
      await _actionRepository.updateAction(action.withActiveUntil(null));
      await _loadActions();
    } finally {
      if (mounted) setState(() => _busyActionIds.remove(action.id));
    }
  }

  Future<void> _loadPlugs() async {
    final saved = await _repository.loadPlugs();
    setState(() {
      _plugs
        ..clear()
        ..addAll(saved.map(_PlugState.new));
      _loadingList = false;
    });
    for (final plug in _plugs) {
      unawaited(_refreshPlug(plug));
    }
  }

  Future<void> _refreshPlug(_PlugState plug) async {
    setState(() => plug.isLoading = true);
    try {
      var client = plug.client;
      if (client == null) {
        if (plug.saved.protocol == PlugProtocol.legacy) {
          client = LegacyKasaPlug(host: plug.saved.host, childId: plug.saved.childId);
        } else {
          final password = await _repository.loadPassword(plug.saved.id);
          if (password == null) {
            throw StateError('No stored password for this plug');
          }
          client = TapoPlug(host: plug.saved.host, email: plug.saved.email, password: password);
        }
        plug.client = client;
      }
      final status = await client.getStatus();
      if (!mounted) return;
      setState(() {
        plug.isOn = status.deviceOn;
        plug.nextAction = status.nextAction;
        plug.error = null;
        plug.isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        plug.error = _describeError(e);
        plug.isLoading = false;
      });
    }
  }

  Future<void> _togglePlug(_PlugState plug, bool value) async {
    final client = plug.client;
    if (client == null) return;
    setState(() {
      plug.isOn = value;
      plug.isLoading = true;
    });
    try {
      await client.setPower(value);
      if (!mounted) return;
      setState(() {
        plug.error = null;
        plug.isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        plug.isOn = !value;
        plug.error = _describeError(e);
        plug.isLoading = false;
      });
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    return message.length > 140 ? '${message.substring(0, 140)}…' : message;
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _showAddPlugDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final savedAccount = await _accountRepository.load();
    if (!mounted) return;
    final emailController = TextEditingController(text: savedAccount?.email ?? '');
    final passwordController = TextEditingController(text: savedAccount?.password ?? '');
    bool isSubmitting = false;
    String? submitError;
    var protocol = PlugProtocol.klap;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final needsAccount = protocol == PlugProtocol.klap;
            return AlertDialog(
              title: const Text('Add smart plug'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: hostController,
                        decoration: const InputDecoration(
                          labelText: 'Local IP address',
                          hintText: '192.168.1.50',
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<PlugProtocol>(
                        segments: const [
                          ButtonSegment(
                            value: PlugProtocol.klap,
                            label: Text('Standard'),
                          ),
                          ButtonSegment(
                            value: PlugProtocol.legacy,
                            label: Text('Legacy (port 9999)'),
                          ),
                        ],
                        selected: {protocol},
                        onSelectionChanged: (selection) {
                          setDialogState(() => protocol = selection.first);
                        },
                      ),
                      if (!needsAccount) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Older devices on this protocol need no account — '
                          'just the IP address.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                      if (needsAccount) ...[
                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'TP-Link account email'),
                          validator: (v) =>
                              needsAccount && (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        TextFormField(
                          controller: passwordController,
                          decoration: const InputDecoration(
                            labelText: 'TP-Link account password',
                          ),
                          obscureText: true,
                          validator: (v) =>
                              needsAccount && (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ],
                      if (submitError != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 150),
                                child: Scrollbar(
                                  child: SingleChildScrollView(
                                    child: SelectableText(
                                      submitError!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy error',
                              onPressed: () => _copyToClipboard(context, submitError!),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSubmitting = true;
                            submitError = null;
                          });
                          final host = hostController.text.trim();
                          final email = emailController.text.trim();
                          final password = passwordController.text;
                          try {
                            if (protocol == PlugProtocol.legacy) {
                              final legacyClient = LegacyKasaPlug(host: host);
                              try {
                                await legacyClient.connect();
                                final children = await legacyClient.discoverChildren();
                                if (children != null) {
                                  // A power strip: one saved entry per outlet,
                                  // named after that outlet's own alias.
                                  for (final child in children) {
                                    await _repository.addPlug(
                                      name: child.alias,
                                      host: host,
                                      protocol: PlugProtocol.legacy,
                                      childId: child.id,
                                    );
                                  }
                                } else {
                                  await legacyClient.getStatus();
                                  await _repository.addPlug(
                                    name: nameController.text.trim(),
                                    host: host,
                                    protocol: PlugProtocol.legacy,
                                  );
                                }
                              } finally {
                                legacyClient.close();
                              }
                            } else {
                              final testClient = TapoPlug(host: host, email: email, password: password);
                              try {
                                await testClient.connect();
                                await testClient.getStatus();
                              } finally {
                                testClient.close();
                              }
                              await _repository.addPlug(
                                name: nameController.text.trim(),
                                host: host,
                                protocol: PlugProtocol.klap,
                                email: email,
                                password: password,
                              );
                              await _accountRepository.save(email, password);
                            }
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            await _loadPlugs();
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              submitError = e.toString();
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removePlug(_PlugState plug) async {
    plug.client?.close();
    await _repository.removePlug(plug.saved.id);
    await _loadPlugs();
  }

  Future<void> _showAccountDialog() async {
    final account = await _accountRepository.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Saved Tapo account'),
          content: Text(
            account == null
                ? 'No account saved yet. It will be saved automatically the '
                      'next time you add a plug.'
                : 'Saved email: ${account.email}\n\n'
                      'This is used to pre-fill the email/password when adding '
                      'new plugs.',
          ),
          actions: [
            if (account != null)
              TextButton(
                onPressed: () async {
                  await _accountRepository.clear();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: const Text('Forget account'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  List<_PlugState> _groupMembers(PlugGroup group) =>
      _plugs.where((p) => group.plugIds.contains(p.saved.id)).toList();

  GroupPowerState _groupState(PlugGroup group) {
    final members = _groupMembers(group);
    if (members.isEmpty) return GroupPowerState.allOff;
    final onCount = members.where((p) => p.isOn).length;
    if (onCount == 0) return GroupPowerState.allOff;
    if (onCount == members.length) return GroupPowerState.allOn;
    return GroupPowerState.mixed;
  }

  bool _groupLoading(PlugGroup group) => _groupMembers(group).any((p) => p.isLoading);

  Future<void> _toggleGroup(PlugGroup group) async {
    final members = _groupMembers(group);
    final turnOn = _groupState(group) != GroupPowerState.allOn;
    await Future.wait(members.map((p) => _togglePlug(p, turnOn)));
  }

  Future<void> _showGroupDialog({PlugGroup? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final selectedIds = {...(existing?.plugIds ?? const <String>[])};
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'New group' : 'Edit group'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Group name'),
                    ),
                    const SizedBox(height: 12),
                    const Text('Devices', style: TextStyle(color: Colors.white70)),
                    ..._plugs.map(
                      (p) => CheckboxListTile(
                        title: Text(p.saved.name),
                        value: selectedIds.contains(p.saved.id),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedIds.add(p.saved.id);
                            } else {
                              selectedIds.remove(p.saved.id);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            await _groupRepository.removeGroup(existing.id);
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            await _loadGroups();
                          },
                    child: const Text('Delete group', style: TextStyle(color: Colors.redAccent)),
                  ),
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty || selectedIds.isEmpty) return;
                          setDialogState(() => isSubmitting = true);
                          if (existing == null) {
                            await _groupRepository.addGroup(
                              name: name,
                              plugIds: selectedIds.toList(),
                            );
                          } else {
                            await _groupRepository.updateGroup(
                              PlugGroup(id: existing.id, name: name, plugIds: selectedIds.toList()),
                            );
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          await _loadGroups();
                        },
                  child: Text(existing == null ? 'Create' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDevicesTab() {
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plugs.isEmpty) {
      return const Center(
        child: Text('No plugs added yet. Tap + to add one.', style: TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: _plugs.length,
      itemBuilder: (context, index) {
        final plug = _plugs[index];
        return PlugTile(
          name: plug.saved.name,
          subtitle: plug.error ?? plug.saved.host,
          isOn: plug.isOn,
          isLoading: plug.isLoading,
          isError: plug.error != null,
          enabled: plug.client != null,
          nextAction: plug.nextAction,
          onChanged: plug.client == null ? null : (value) => _togglePlug(plug, value),
          onLongPress: () => _removePlug(plug),
        );
      },
    );
  }

  Widget _buildGroupsTab() {
    if (_groups.isEmpty) {
      return const Center(
        child: Text(
          'No groups yet. Tap + to create one.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        return GroupTile(
          name: group.name,
          memberCount: _groupMembers(group).length,
          state: _groupState(group),
          isLoading: _groupLoading(group),
          onTap: () => _toggleGroup(group),
          onLongPress: () => _showGroupDialog(existing: group),
        );
      },
    );
  }

  Future<void> _showActionDialog({PlugAction? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hoursController = TextEditingController(
      text: (existing?.pauseHours ?? 24).toString(),
    );
    final selectedIds = {...(existing?.plugIds ?? const <String>[])};
    final pausablePlugs = _plugs.where((p) => p.saved.protocol == PlugProtocol.legacy).toList();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'New action' : 'Edit action'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Action name'),
                    ),
                    TextField(
                      controller: hoursController,
                      decoration: const InputDecoration(labelText: 'Pause for (hours)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Devices (only devices whose schedule can be paused)',
                      style: TextStyle(color: Colors.white70),
                    ),
                    if (pausablePlugs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'No eligible devices yet — this only works with '
                          'the older (legacy) protocol, since that\'s the '
                          'only one with a verified way to pause a schedule.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    ...pausablePlugs.map(
                      (p) => CheckboxListTile(
                        title: Text(p.saved.name),
                        value: selectedIds.contains(p.saved.id),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedIds.add(p.saved.id);
                            } else {
                              selectedIds.remove(p.saved.id);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            await _actionRepository.removeAction(existing.id);
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            await _loadActions();
                          },
                    child: const Text('Delete action', style: TextStyle(color: Colors.redAccent)),
                  ),
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final hours = int.tryParse(hoursController.text.trim());
                          if (name.isEmpty || hours == null || hours <= 0 || selectedIds.isEmpty) {
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          if (existing == null) {
                            await _actionRepository.addAction(
                              name: name,
                              plugIds: selectedIds.toList(),
                              pauseHours: hours,
                            );
                          } else {
                            await _actionRepository.updateAction(
                              PlugAction(
                                id: existing.id,
                                name: name,
                                plugIds: selectedIds.toList(),
                                pauseHours: hours,
                                activeUntil: existing.activeUntil,
                              ),
                            );
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          await _loadActions();
                        },
                  child: Text(existing == null ? 'Create' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActionsTab() {
    if (_actions.isEmpty) {
      return const Center(
        child: Text(
          'No actions yet. Tap + to create one.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: _actions.length,
      itemBuilder: (context, index) {
        final action = _actions[index];
        final subtitle = action.isActive
            ? 'Active until ${TimeOfDay.fromDateTime(action.activeUntil!).format(context)}'
            : 'Pauses schedule ${action.pauseHours}h';
        return ActionTile(
          name: action.name,
          isActive: action.isActive,
          subtitle: subtitle,
          isLoading: _busyActionIds.contains(action.id),
          onTap: () => action.isActive ? _cancelAction(action) : _triggerAction(action),
          onLongPress: () => _showActionDialog(existing: action),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Plugs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Groups'),
            Tab(text: 'Devices'),
            Tab(text: 'Actions'),
            Tab(text: 'Heating'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Saved Tapo account',
            onPressed: _showAccountDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGroupsTab(),
          _buildDevicesTab(),
          _buildActionsTab(),
          const HeatingTab(),
        ],
      ),
      floatingActionButton: switch (_tabController.index) {
        0 => FloatingActionButton(onPressed: _showGroupDialog, child: const Icon(Icons.add)),
        1 => FloatingActionButton(onPressed: _showAddPlugDialog, child: const Icon(Icons.add)),
        2 => FloatingActionButton(onPressed: _showActionDialog, child: const Icon(Icons.add)),
        _ => null,
      },
    );
  }
}
