/// Low-level HTTP client (bearer auth + auto-refresh) plus the two
/// generation-specific climate clients for Tado's REST API. Endpoint paths
/// and request/response shapes are taken from node-tado-client
/// (https://github.com/mattdavis90/node-tado-client), a well-maintained
/// open-source reference for this unofficial-but-widely-used API.
library;

import 'dart:convert';
import 'dart:io';

import 'tado_auth_client.dart';
import 'tado_token_repository.dart';

class TadoApiException implements Exception {
  final String message;
  TadoApiException(this.message);
  @override
  String toString() => 'TadoApiException: $message';
}

double? _asDouble(dynamic v) => v == null ? null : (v as num).toDouble();

class TadoRoomStatus {
  final String id;
  final String name;
  final double? currentTemperature;
  final double? targetTemperature;
  final bool power;
  final double? heatingPowerPercent;
  final double? humidity;
  final bool hasManualOverlay;

  TadoRoomStatus({
    required this.id,
    required this.name,
    required this.currentTemperature,
    required this.targetTemperature,
    required this.power,
    required this.heatingPowerPercent,
    required this.humidity,
    required this.hasManualOverlay,
  });
}

/// Handles bearer-token auth and silent refresh for every Tado API call.
class TadoApiClient {
  final TadoTokenRepository _tokenRepository;
  final TadoAuthClient _authClient;
  TadoTokens _tokens;
  final HttpClient _http = HttpClient();

  TadoApiClient(this._tokenRepository, this._authClient, this._tokens);

  Future<void> _ensureFreshToken() async {
    if (!_tokens.isExpired) return;
    _tokens = await _authClient.refresh(_tokens.refreshToken);
    await _tokenRepository.save(_tokens);
  }

  Future<dynamic> request(String method, Uri uri, {Object? body}) async {
    await _ensureFreshToken();
    final req = await _http.openUrl(method, uri);
    req.headers.set('Authorization', 'Bearer ${_tokens.accessToken}');
    req.headers.set('Content-Type', 'application/json');
    if (body != null) {
      req.add(utf8.encode(jsonEncode(body)));
    }
    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TadoApiException('HTTP ${response.statusCode} for $method $uri: $text');
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  void close() => _http.close(force: true);
}

abstract class TadoClimateClient {
  Future<List<TadoRoomStatus>> getRooms();
  Future<void> setTemperature(String roomId, double celsius);
  Future<void> turnOff(String roomId);
  Future<void> resumeSchedule(String roomId);
}

class TadoClassicClient implements TadoClimateClient {
  static const _base = 'https://my.tado.com/api/v2';

  final TadoApiClient _api;
  final int homeId;

  TadoClassicClient(this._api, this.homeId);

  @override
  Future<List<TadoRoomStatus>> getRooms() async {
    final zones =
        (await _api.request('GET', Uri.parse('$_base/homes/$homeId/zones'))) as List<dynamic>;
    final zoneStatesResponse =
        (await _api.request('GET', Uri.parse('$_base/homes/$homeId/zoneStates')))
            as Map<String, dynamic>;
    final zoneStates = zoneStatesResponse['zoneStates'] as Map<String, dynamic>;

    return zones.cast<Map<String, dynamic>>().map((zone) {
      final id = zone['id'].toString();
      final state = zoneStates[id] as Map<String, dynamic>?;
      final sensor = state?['sensorDataPoints'] as Map<String, dynamic>?;
      final setting = state?['setting'] as Map<String, dynamic>?;
      final activity = state?['activityDataPoints'] as Map<String, dynamic>?;
      return TadoRoomStatus(
        id: id,
        name: zone['name'] as String,
        currentTemperature: _asDouble(
          (sensor?['insideTemperature'] as Map<String, dynamic>?)?['celsius'],
        ),
        targetTemperature: _asDouble(
          (setting?['temperature'] as Map<String, dynamic>?)?['celsius'],
        ),
        power: setting?['power'] == 'ON',
        heatingPowerPercent: _asDouble(
          (activity?['heatingPower'] as Map<String, dynamic>?)?['percentage'],
        ),
        humidity: _asDouble((sensor?['humidity'] as Map<String, dynamic>?)?['percentage']),
        hasManualOverlay: state?['overlayType'] == 'MANUAL',
      );
    }).toList();
  }

  @override
  Future<void> setTemperature(String roomId, double celsius) async {
    await _api.request(
      'PUT',
      Uri.parse('$_base/homes/$homeId/zones/$roomId/overlay'),
      body: {
        'setting': {
          'type': 'HEATING',
          'power': 'ON',
          'temperature': {'celsius': celsius},
        },
        'termination': {'typeSkillBasedApp': 'MANUAL'},
        'type': 'MANUAL',
      },
    );
  }

  @override
  Future<void> turnOff(String roomId) async {
    await _api.request(
      'PUT',
      Uri.parse('$_base/homes/$homeId/zones/$roomId/overlay'),
      body: {
        'setting': {'type': 'HEATING', 'power': 'OFF'},
        'termination': {'typeSkillBasedApp': 'MANUAL'},
        'type': 'MANUAL',
      },
    );
  }

  @override
  Future<void> resumeSchedule(String roomId) async {
    await _api.request('DELETE', Uri.parse('$_base/homes/$homeId/zones/$roomId/overlay'));
  }

  /// Schedule (timetable) editing — classic Tado only, no Tado X equivalent
  /// is known to exist.
  Future<int> getActiveTimetableId(String zoneId) async {
    final result =
        (await _api.request(
              'GET',
              Uri.parse('$_base/homes/$homeId/zones/$zoneId/schedule/activeTimetable'),
            ))
            as Map<String, dynamic>;
    return result['id'] as int;
  }

  Future<List<Map<String, dynamic>>> getTimetableBlocks(String zoneId, int timetableId) async {
    final result =
        (await _api.request(
              'GET',
              Uri.parse(
                '$_base/homes/$homeId/zones/$zoneId/schedule/timetables/$timetableId/blocks',
              ),
            ))
            as List<dynamic>;
    return result.cast<Map<String, dynamic>>();
  }

  Future<void> setDayBlocks(
    String zoneId,
    int timetableId,
    String dayType,
    List<Map<String, dynamic>> blocks,
  ) async {
    await _api.request(
      'PUT',
      Uri.parse('$_base/homes/$homeId/zones/$zoneId/schedule/timetables/$timetableId/blocks/$dayType'),
      body: blocks,
    );
  }
}

class TadoXClient implements TadoClimateClient {
  static const _base = 'https://hops.tado.com';

  final TadoApiClient _api;
  final int homeId;

  TadoXClient(this._api, this.homeId);

  @override
  Future<List<TadoRoomStatus>> getRooms() async {
    final rooms =
        (await _api.request('GET', Uri.parse('$_base/homes/$homeId/rooms'))) as List<dynamic>;
    return rooms.cast<Map<String, dynamic>>().map((room) {
      final sensor = room['sensorDataPoints'] as Map<String, dynamic>?;
      final setting = room['setting'] as Map<String, dynamic>?;
      final heatingPower = room['heatingPower'] as Map<String, dynamic>?;
      return TadoRoomStatus(
        id: room['id'].toString(),
        name: room['name'] as String,
        currentTemperature: _asDouble(
          (sensor?['insideTemperature'] as Map<String, dynamic>?)?['value'],
        ),
        targetTemperature: _asDouble((setting?['temperature'] as Map<String, dynamic>?)?['value']),
        power: setting?['power'] == 'ON',
        heatingPowerPercent: _asDouble(heatingPower?['percentage']),
        humidity: _asDouble((sensor?['humidity'] as Map<String, dynamic>?)?['percentage']),
        hasManualOverlay: room['manualControlTermination'] != null,
      );
    }).toList();
  }

  @override
  Future<void> setTemperature(String roomId, double celsius) async {
    await _api.request(
      'POST',
      Uri.parse('$_base/homes/$homeId/rooms/$roomId/manualControl'),
      body: {
        'setting': {
          'power': 'ON',
          'temperature': {'value': celsius, 'precision': 0.1},
        },
        'termination': {'type': 'MANUAL'},
      },
    );
  }

  @override
  Future<void> turnOff(String roomId) async {
    await _api.request(
      'POST',
      Uri.parse('$_base/homes/$homeId/rooms/$roomId/manualControl'),
      body: {
        'setting': {'power': 'OFF', 'temperature': null},
        'termination': {'type': 'MANUAL'},
      },
    );
  }

  @override
  Future<void> resumeSchedule(String roomId) async {
    await _api.request(
      'POST',
      Uri.parse('$_base/homes/$homeId/rooms/$roomId/resumeSchedule'),
      body: {},
    );
  }
}

class TadoHomeInfo {
  final int homeId;
  final String homeName;
  final bool isTadoX;

  TadoHomeInfo({required this.homeId, required this.homeName, required this.isTadoX});
}

/// Fetches the account's first home and its generation, so the app can pick
/// the right endpoint set without the user needing to know their hardware
/// generation. Residential accounts almost always have exactly one home.
Future<TadoHomeInfo> discoverHome(TadoApiClient api) async {
  final me =
      (await api.request('GET', Uri.parse('https://my.tado.com/api/v2/me')))
          as Map<String, dynamic>;
  final homes = (me['homes'] as List<dynamic>).cast<Map<String, dynamic>>();
  if (homes.isEmpty) {
    throw TadoApiException('No Tado homes found on this account');
  }
  final home = homes.first;
  final homeId = home['id'] as int;
  final details =
      (await api.request('GET', Uri.parse('https://my.tado.com/api/v2/homes/$homeId')))
          as Map<String, dynamic>;
  return TadoHomeInfo(
    homeId: homeId,
    homeName: home['name'] as String,
    isTadoX: details['generation'] == 'LINE_X',
  );
}
