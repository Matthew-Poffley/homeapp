/// Common interface implemented by both the KLAP-based [TapoPlug] and the
/// legacy XOR-protocol [LegacyKasaPlug], so the UI doesn't need to know
/// which protocol a given saved plug actually speaks.
abstract class SmartPlugClient {
  Future<void> connect();
  Future<SmartPlugStatus> getStatus();
  Future<void> setPower(bool on);
  void close();
}

/// The next scheduled flip of a plug's relay, resolved to an absolute time.
class NextAction {
  final bool turningOn;
  final DateTime time;

  NextAction({required this.turningOn, required this.time});

  String get formattedTime {
    final now = DateTime.now();
    final isToday = time.year == now.year && time.month == now.month && time.day == now.day;

    final hour24 = time.hour;
    final minute = time.minute;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final timeStr = '$hour12:${minute.toString().padLeft(2, '0')} $period';

    if (isToday) return timeStr;
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdayNames[time.weekday - 1]} $timeStr';
  }
}

class SmartPlugStatus {
  final String nickname;
  final String model;
  final bool deviceOn;
  final NextAction? nextAction;

  SmartPlugStatus({
    required this.nickname,
    required this.model,
    required this.deviceOn,
    this.nextAction,
  });
}
