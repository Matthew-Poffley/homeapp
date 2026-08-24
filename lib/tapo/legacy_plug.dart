/// Client for TP-Link's original "Smart Home Protocol" — used by older
/// Kasa-branded devices (and some early Tapo firmware) that speak plain
/// XOR-obfuscated JSON over raw TCP on port 9999, with no authentication
/// at all. Ported from python-kasa's `kasa/transports/xortransport.py`.
///
/// Power strips (e.g. KP303) report multiple individually-switchable
/// outlets under a `children` array in `get_sysinfo` rather than a single
/// top-level `relay_state`; controlling one requires wrapping the command
/// in a `context: {child_ids: [...]}` envelope. [LegacyKasaPlug] represents
/// one outlet — either the device's only relay ([childId] null) or one
/// named child of a strip.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'byte_stream_reader.dart';
import 'schedule_rules.dart';
import 'smart_plug_client.dart';

class LegacyPlugException implements Exception {
  final String message;
  LegacyPlugException(this.message);
  @override
  String toString() => 'LegacyPlugException: $message';
}

class LegacyChildOutlet {
  final String id;
  final String alias;
  final bool on;
  LegacyChildOutlet({required this.id, required this.alias, required this.on});
}

Uint8List _xorEncrypt(String plaintext) {
  final plainBytes = utf8.encode(plaintext);
  var key = 171;
  final cipher = Uint8List(plainBytes.length);
  for (var i = 0; i < plainBytes.length; i++) {
    key = key ^ plainBytes[i];
    cipher[i] = key;
  }
  final framed = Uint8List(4 + cipher.length);
  ByteData.view(framed.buffer).setUint32(0, plainBytes.length, Endian.big);
  framed.setRange(4, framed.length, cipher);
  return framed;
}

String _xorDecrypt(Uint8List ciphertext) {
  var key = 171;
  final plain = Uint8List(ciphertext.length);
  for (var i = 0; i < ciphertext.length; i++) {
    plain[i] = key ^ ciphertext[i];
    key = ciphertext[i];
  }
  return utf8.decode(plain);
}

class LegacyKasaPlug implements SmartPlugClient {
  final String host;
  final int port;

  /// Which outlet this instance controls on a multi-outlet power strip.
  /// Null for a normal single-relay plug.
  final String? childId;

  LegacyKasaPlug({required this.host, this.port = 9999, this.childId});

  /// Opens a fresh, short-lived connection per request rather than
  /// reusing one persistent socket. Cheap embedded devices like a power
  /// strip often can't handle several long-lived connections at once (one
  /// per outlet, in our case), and reusing a socket that failed with a
  /// connection-level error would otherwise wedge that outlet permanently
  /// until the app restarts, since nothing would ever reset it.
  @override
  Future<void> connect() async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    socket.destroy();
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> command) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = ByteStreamReader(socket);
    try {
      socket.add(_xorEncrypt(jsonEncode(command)));
      await socket.flush();

      final lengthBytes = await reader.readExactly(4);
      final length = ByteData.view(lengthBytes.buffer).getUint32(0, Endian.big);
      final body = await reader.readExactly(length);

      return jsonDecode(_xorDecrypt(body)) as Map<String, dynamic>;
    } finally {
      reader.dispose();
      socket.destroy();
    }
  }

  void _checkErrCode(Map<String, dynamic> section, String context) {
    final errCode = section['err_code'] as int? ?? 0;
    if (errCode != 0) {
      throw LegacyPlugException('Device returned error for $context (err_code $errCode)');
    }
  }

  Future<Map<String, dynamic>> _getSysInfo() async {
    final response = await _send({
      'system': {'get_sysinfo': {}},
    });
    final sysinfo = (response['system'] as Map<String, dynamic>)['get_sysinfo']
        as Map<String, dynamic>;
    _checkErrCode(sysinfo, 'get_sysinfo');
    return sysinfo;
  }

  /// Returns this device's individually-switchable outlets if it's a power
  /// strip, or null if it's a normal single-relay plug.
  Future<List<LegacyChildOutlet>?> discoverChildren() async {
    final sysinfo = await _getSysInfo();
    final childrenRaw = sysinfo['children'] as List<dynamic>?;
    if (childrenRaw == null || childrenRaw.isEmpty) return null;
    return childrenRaw
        .cast<Map<String, dynamic>>()
        .map(
          (child) => LegacyChildOutlet(
            id: child['id'] as String,
            alias: child['alias'] as String? ?? '',
            on: (child['state'] as int? ?? 0) != 0,
          ),
        )
        .toList();
  }

  /// Fetches this outlet's own schedule rules. The `context` wrapper is
  /// required for a power strip's child outlets — without it, the device
  /// returns whichever outlet's rules it has cached internally, regardless
  /// of which child was asked, which silently gives the wrong schedule.
  Future<Map<String, dynamic>> _getScheduleRules() async {
    final command = childId != null
        ? {
            'context': {
              'child_ids': [childId],
            },
            'schedule': {'get_rules': {}},
          }
        : {
            'schedule': {'get_rules': {}},
          };
    final response = await _send(command);
    final result = (response['schedule'] as Map<String, dynamic>)['get_rules']
        as Map<String, dynamic>;
    _checkErrCode(result, 'get_rules');
    return result;
  }

  /// Enables or disables this outlet's entire schedule (all rules at
  /// once) without touching the individual rules themselves, so it can be
  /// resumed exactly as configured afterward.
  Future<void> setScheduleEnabled(bool enabled) async {
    final command = childId != null
        ? {
            'context': {
              'child_ids': [childId],
            },
            'schedule': {
              'set_overall_enable': {'enable': enabled ? 1 : 0},
            },
          }
        : {
            'schedule': {
              'set_overall_enable': {'enable': enabled ? 1 : 0},
            },
          };
    final response = await _send(command);
    final result = (response['schedule'] as Map<String, dynamic>)['set_overall_enable']
        as Map<String, dynamic>;
    _checkErrCode(result, 'set_overall_enable');
  }

  NextAction? _nextActionFromScheduleRules(Map<String, dynamic> scheduleResult) {
    final globallyEnabled = (scheduleResult['enable'] as int? ?? 1) != 0;
    if (!globallyEnabled) return null;

    final rules = (scheduleResult['rule_list'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((rule) {
          final startMinute = rule['smin'] as int?;
          final action = rule['sact'] as int?;
          final weekDays = rule['wday'] as List<dynamic>?;
          if (startMinute == null || action == null || weekDays == null) return null;
          return ScheduleRule(
            enabled: (rule['enable'] as int? ?? 0) != 0,
            startMinute: startMinute,
            turnsOn: action == 1,
            appliesOn: (day) => weekDays[weekdayIndexSundayFirst(day)] == 1,
          );
        })
        .whereType<ScheduleRule>()
        .toList();

    return computeNextAction(rules);
  }

  @override
  Future<SmartPlugStatus> getStatus() async {
    final sysinfo = await _getSysInfo();

    NextAction? nextAction;
    try {
      nextAction = _nextActionFromScheduleRules(await _getScheduleRules());
    } catch (_) {
      // Fall back to no schedule info rather than failing the whole
      // status refresh.
    }

    if (childId != null) {
      final childrenRaw = sysinfo['children'] as List<dynamic>? ?? const [];
      final match = childrenRaw.cast<Map<String, dynamic>>().firstWhere(
        (child) => child['id'] == childId,
        orElse: () => throw LegacyPlugException('Outlet $childId not found on this device'),
      );
      return SmartPlugStatus(
        nickname: match['alias'] as String? ?? '',
        model: sysinfo['model'] as String? ?? '',
        deviceOn: (match['state'] as int? ?? 0) != 0,
        nextAction: nextAction,
      );
    }
    return SmartPlugStatus(
      nickname: sysinfo['alias'] as String? ?? '',
      model: sysinfo['model'] as String? ?? '',
      deviceOn: (sysinfo['relay_state'] as int? ?? 0) != 0,
      nextAction: nextAction,
    );
  }

  @override
  Future<void> setPower(bool on) async {
    final command = childId != null
        ? {
            'context': {
              'child_ids': [childId],
            },
            'system': {
              'set_relay_state': {'state': on ? 1 : 0},
            },
          }
        : {
            'system': {
              'set_relay_state': {'state': on ? 1 : 0},
            },
          };
    final response = await _send(command);
    final result = (response['system'] as Map<String, dynamic>)['set_relay_state']
        as Map<String, dynamic>;
    _checkErrCode(result, 'set_relay_state');
  }

  @override
  void close() {}
}
