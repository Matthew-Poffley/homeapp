/// Ties together device-code auth, home/generation discovery, and the
/// generation-specific climate client into the small surface the UI needs.
library;

import 'tado_auth_client.dart';
import 'tado_client.dart';
import 'tado_home_config_repository.dart';
import 'tado_schedule.dart';
import 'tado_token_repository.dart';

class TadoService {
  final TadoTokenRepository _tokenRepository;
  final TadoHomeConfigRepository _homeConfigRepository;
  final TadoAuthClient _authClient = TadoAuthClient();

  TadoApiClient? _apiClient;
  TadoClimateClient? _climateClient;
  TadoHomeConfig? homeConfig;

  TadoService({TadoTokenRepository? tokenRepository, TadoHomeConfigRepository? homeConfigRepository})
    : _tokenRepository = tokenRepository ?? TadoTokenRepository(),
      _homeConfigRepository = homeConfigRepository ?? TadoHomeConfigRepository();

  Future<bool> isConnected() async => (await _tokenRepository.load()) != null;

  Future<DeviceAuthorization> startConnect() => _authClient.startDeviceAuthorization();

  /// Polls until the user completes authorization in their browser, the
  /// device code expires, or [isCancelled] returns true. [onWaiting] fires
  /// once per poll so the UI can show progress.
  Future<void> completeConnect(
    DeviceAuthorization auth, {
    void Function()? onWaiting,
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: auth.expiresInSeconds));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw TadoAuthException('Connection cancelled.');
      }
      final tokens = await _authClient.pollForToken(auth);
      if (tokens != null) {
        await _tokenRepository.save(tokens);
        _apiClient = TadoApiClient(_tokenRepository, _authClient, tokens);
        final homeInfo = await discoverHome(_apiClient!);
        final config = TadoHomeConfig(
          homeId: homeInfo.homeId,
          homeName: homeInfo.homeName,
          isTadoX: homeInfo.isTadoX,
        );
        await _homeConfigRepository.save(config);
        homeConfig = config;
        _climateClient = config.isTadoX
            ? TadoXClient(_apiClient!, config.homeId)
            : TadoClassicClient(_apiClient!, config.homeId);
        return;
      }
      onWaiting?.call();
      await Future.delayed(Duration(seconds: auth.pollIntervalSeconds));
    }
    throw TadoAuthException('Authorization timed out — please try connecting again.');
  }

  Future<void> _ensureReady() async {
    if (_climateClient != null) return;
    final tokens = await _tokenRepository.load();
    if (tokens == null) {
      throw TadoAuthException('Not connected to Tado yet.');
    }
    _apiClient = TadoApiClient(_tokenRepository, _authClient, tokens);

    var config = await _homeConfigRepository.load();
    if (config == null) {
      final homeInfo = await discoverHome(_apiClient!);
      config = TadoHomeConfig(
        homeId: homeInfo.homeId,
        homeName: homeInfo.homeName,
        isTadoX: homeInfo.isTadoX,
      );
      await _homeConfigRepository.save(config);
    }
    homeConfig = config;
    _climateClient = config.isTadoX
        ? TadoXClient(_apiClient!, config.homeId)
        : TadoClassicClient(_apiClient!, config.homeId);
  }

  Future<List<TadoRoomStatus>> getRooms() async {
    await _ensureReady();
    return _climateClient!.getRooms();
  }

  Future<void> setTemperature(String roomId, double celsius) async {
    await _ensureReady();
    await _climateClient!.setTemperature(roomId, celsius);
  }

  Future<void> turnOff(String roomId) async {
    await _ensureReady();
    await _climateClient!.turnOff(roomId);
  }

  Future<void> resumeSchedule(String roomId) async {
    await _ensureReady();
    await _climateClient!.resumeSchedule(roomId);
  }

  /// True once the current home is known and isn't Tado X — schedule
  /// editing has no known API for Tado X.
  bool get supportsScheduleEditing => homeConfig != null && !homeConfig!.isTadoX;

  TadoClassicClient _requireClassicClient() {
    final client = _climateClient;
    if (client is! TadoClassicClient) {
      throw TadoApiException('Schedule editing is only available for classic Tado, not Tado X.');
    }
    return client;
  }

  Future<TadoSchedule> getSchedule(String roomId) async {
    await _ensureReady();
    final client = _requireClassicClient();
    final timetableId = await client.getActiveTimetableId(roomId);
    final rawBlocks = await client.getTimetableBlocks(roomId, timetableId);
    return TadoSchedule.fromRaw(timetableId, rawBlocks);
  }

  Future<void> saveDayBlocks(
    String roomId,
    int timetableId,
    String dayType,
    List<TadoScheduleBlock> blocks,
  ) async {
    await _ensureReady();
    final client = _requireClassicClient();
    await client.setDayBlocks(roomId, timetableId, dayType, blocks.map((b) => b.toJson()).toList());
  }

  Future<void> disconnect() async {
    await _tokenRepository.clear();
    await _homeConfigRepository.clear();
    _apiClient?.close();
    _apiClient = null;
    _climateClient = null;
    homeConfig = null;
  }
}
