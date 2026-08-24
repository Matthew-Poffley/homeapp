/// High-level client for a single Tapo smart plug (P100/P105/P110/P115 and
/// similar "SMART"-protocol devices), speaking the JSON command envelope
/// over a KLAP-encrypted session as ported in klap_transport.dart.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'klap_transport.dart';
import 'schedule_rules.dart';
import 'smart_plug_client.dart';

SmartPlugStatus _statusFromJson(Map<String, dynamic> json) {
  final nicknameB64 = json['nickname'] as String?;
  String nickname = '';
  if (nicknameB64 != null && nicknameB64.isNotEmpty) {
    try {
      nickname = utf8.decode(base64.decode(nicknameB64));
    } catch (_) {
      nickname = nicknameB64;
    }
  }
  return SmartPlugStatus(
    nickname: nickname,
    model: json['model'] as String? ?? '',
    deviceOn: json['device_on'] as bool? ?? false,
  );
}

/// Computes the soonest upcoming flip across all enabled rules in a
/// `get_schedule_rules` response, or null if there's no enabled schedule.
NextAction? _nextActionFromScheduleRules(Map<String, dynamic> scheduleResult) {
  final globallyEnabled = scheduleResult['enable'] as bool? ?? true;
  if (!globallyEnabled) return null;

  final rules = (scheduleResult['rule_list'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .map((rule) {
        final startMinute = rule['s_min'] as int?;
        final desiredOn = (rule['desired_states'] as Map<String, dynamic>?)?['on'] as bool?;
        final weekDayMask = rule['week_day'] as int?;
        if (startMinute == null || desiredOn == null) return null;
        return ScheduleRule(
          enabled: rule['enable'] == true,
          startMinute: startMinute,
          turnsOn: desiredOn,
          appliesOn: (day) =>
              weekDayMask == null ||
              weekDayMask == 0 ||
              (weekDayMask & (1 << weekdayIndexSundayFirst(day))) != 0,
        );
      })
      .whereType<ScheduleRule>()
      .toList();

  return computeNextAction(rules);
}

class TapoDeviceException implements Exception {
  final String message;
  final int? errorCode;
  TapoDeviceException(this.message, {this.errorCode});
  @override
  String toString() => 'TapoDeviceException($errorCode): $message';
}

class TapoPlug implements SmartPlugClient {
  final String host;
  final String email;
  final String password;
  final KlapTransport _transport;
  late final String _terminalUuid;

  TapoPlug({required this.host, required this.email, required this.password, int port = 80})
    : _transport = KlapTransport(host: host, port: port) {
    _terminalUuid = base64.encode(
      md5.convert(_randomBytes(16)).bytes,
    );
  }

  static Uint8List _randomBytes(int length) {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rand.nextInt(256)));
  }

  @override
  Future<void> connect() async {
    await _transport.handshake(email, password);
  }

  Map<String, dynamic> _envelope(String method, [Map<String, dynamic>? params]) {
    final request = <String, dynamic>{
      'method': method,
      'request_time_milis': DateTime.now().millisecondsSinceEpoch,
      'terminal_uuid': _terminalUuid,
    };
    if (params != null) {
      request['params'] = params;
    }
    return request;
  }

  /// A 403 on the very first request after a fresh handshake is a known,
  /// expected occurrence with real Tapo firmware (the reference
  /// implementations retry it automatically) rather than a sign that
  /// something is wrong, so one retry with a fresh handshake happens
  /// silently before surfacing an error.
  Future<Map<String, dynamic>> _query(String method, [Map<String, dynamic>? params]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_transport.isHandshakeComplete) {
        await connect();
      }
      try {
        final response = await _transport.send(_envelope(method, params));
        final errorCode = response['error_code'] as int? ?? 0;
        if (errorCode != 0) {
          throw TapoDeviceException(
            'Device returned error for $method',
            errorCode: errorCode,
          );
        }
        return response;
      } on TapoRequestException {
        if (attempt == 0 && !_transport.isHandshakeComplete) {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('unreachable');
  }

  @override
  Future<SmartPlugStatus> getStatus() async {
    final response = await _query('get_device_info');
    final status = _statusFromJson(response['result'] as Map<String, dynamic>);

    NextAction? nextAction;
    try {
      final scheduleResponse = await _query('get_schedule_rules', {'start_index': 0});
      nextAction = _nextActionFromScheduleRules(
        scheduleResponse['result'] as Map<String, dynamic>,
      );
    } catch (_) {
      // Older/different firmware may not support this — just show no
      // schedule info rather than failing the whole status refresh.
    }

    return SmartPlugStatus(
      nickname: status.nickname,
      model: status.model,
      deviceOn: status.deviceOn,
      nextAction: nextAction,
    );
  }

  @override
  Future<void> setPower(bool on) async {
    await _query('set_device_info', {'device_on': on});
  }

  Future<void> turnOn() => setPower(true);
  Future<void> turnOff() => setPower(false);

  @override
  void close() => _transport.close();
}
