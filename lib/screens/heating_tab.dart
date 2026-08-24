import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tado/tado_auth_client.dart';
import '../tado/tado_client.dart';
import '../tado/tado_service.dart';
import 'plug_tile.dart' show neonGreen;
import 'room_detail_screen.dart';

class HeatingTab extends StatefulWidget {
  const HeatingTab({super.key});

  @override
  State<HeatingTab> createState() => _HeatingTabState();
}

class _HeatingTabState extends State<HeatingTab> {
  final _service = TadoService();
  bool _loadingConnection = true;
  bool _connected = false;
  bool _refreshing = false;
  List<TadoRoomStatus> _rooms = [];
  String? _error;
  bool _cancelConnect = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final connected = await _service.isConnected();
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _loadingConnection = false;
    });
    if (connected) await _refreshRooms();
  }

  Future<void> _refreshRooms() async {
    setState(() => _refreshing = true);
    try {
      final rooms = await _service.getRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _describeError(e);
        _refreshing = false;
      });
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    return message.length > 140 ? '${message.substring(0, 140)}…' : message;
  }

  Future<void> _connect() async {
    DeviceAuthorization auth;
    try {
      auth = await _service.startConnect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start: ${_describeError(e)}')));
      return;
    }

    unawaited(launchUrl(Uri.parse(auth.verificationUriComplete)));

    _cancelConnect = false;
    Object? connectError;
    final pollFuture = _service
        .completeConnect(auth, isCancelled: () => _cancelConnect)
        .catchError((Object e) => connectError = e);
    pollFuture.whenComplete(() {
      if (mounted) Navigator.of(context).maybePop();
    });

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect Tado account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A browser window should have opened. If not, go to:'),
            const SizedBox(height: 8),
            SelectableText(
              auth.verificationUriComplete,
              style: const TextStyle(color: neonGreen),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter this code if asked: ${auth.userCode}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Waiting for you to log in…'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cancelConnect = true;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (connectError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_describeError(connectError!))));
      return;
    }
    if (!mounted) return;
    setState(() => _connected = true);
    await _refreshRooms();
  }

  Future<void> _disconnect() async {
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _rooms = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingConnection) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.thermostat_outlined, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'Connect your Tado account to control your heating.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _connect, child: const Text('Connect Tado account')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _service.homeConfig?.homeName ?? 'Tado',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white54),
                tooltip: 'Refresh',
                onPressed: _refreshing ? null : _refreshRooms,
              ),
              IconButton(
                icon: const Icon(Icons.link_off, color: Colors.white54),
                tooltip: 'Disconnect Tado account',
                onPressed: _disconnect,
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        Expanded(
          child: _rooms.isEmpty
              ? const Center(
                  child: Text('No rooms found.', style: TextStyle(color: Colors.white54)),
                )
              : RoomControlPanel(service: _service, status: _rooms.first),
        ),
      ],
    );
  }
}
