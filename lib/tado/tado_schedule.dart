/// The weekly heating schedule (timetable) model — only available for
/// classic Tado; there is no documented API for reading or editing a Tado
/// X room's schedule (confirmed against multiple community
/// reverse-engineering projects, including one specifically covering the
/// Tado X API), so schedule editing is restricted to classic homes.
library;

/// Display order and human-readable labels for the day-type groupings that
/// can appear depending on which timetable mode (ONE_DAY/THREE_DAY/
/// SEVEN_DAY) is active for a zone.
const tadoDayTypeOrder = [
  'MONDAY_TO_SUNDAY',
  'MONDAY_TO_FRIDAY',
  'SATURDAY',
  'SUNDAY',
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
];

const tadoDayTypeLabels = {
  'MONDAY_TO_SUNDAY': 'Every day',
  'MONDAY_TO_FRIDAY': 'Weekdays',
  'SATURDAY': 'Saturday',
  'SUNDAY': 'Sunday',
  'MONDAY': 'Monday',
  'TUESDAY': 'Tuesday',
  'WEDNESDAY': 'Wednesday',
  'THURSDAY': 'Thursday',
  'FRIDAY': 'Friday',
};

class TadoScheduleBlock {
  final String dayType;
  final String start; // "HH:mm:ss"
  final String end;
  final double? temperature; // null means the block turns heating off

  TadoScheduleBlock({
    required this.dayType,
    required this.start,
    required this.end,
    required this.temperature,
  });

  factory TadoScheduleBlock.fromJson(Map<String, dynamic> json) {
    final setting = json['setting'] as Map<String, dynamic>?;
    final temp = setting?['temperature'] as Map<String, dynamic>?;
    final power = setting?['power'];
    return TadoScheduleBlock(
      dayType: json['dayType'] as String,
      start: json['start'] as String,
      end: json['end'] as String,
      temperature: power == 'OFF' ? null : (temp?['celsius'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'dayType': dayType,
    'start': start,
    'end': end,
    'geolocationOverride': false,
    'setting': {
      'type': 'HEATING',
      'power': temperature == null ? 'OFF' : 'ON',
      if (temperature != null) 'temperature': {'celsius': temperature},
    },
  };

  TadoScheduleBlock copyWith({String? start, String? end, double? temperature, bool clearTemperature = false}) {
    return TadoScheduleBlock(
      dayType: dayType,
      start: start ?? this.start,
      end: end ?? this.end,
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
    );
  }
}

class TadoSchedule {
  final int timetableId;
  final Map<String, List<TadoScheduleBlock>> blocksByDayType;

  TadoSchedule({required this.timetableId, required this.blocksByDayType});

  factory TadoSchedule.fromRaw(int timetableId, List<Map<String, dynamic>> rawBlocks) {
    final blocks = rawBlocks.map(TadoScheduleBlock.fromJson).toList();
    final grouped = <String, List<TadoScheduleBlock>>{};
    for (final block in blocks) {
      grouped.putIfAbsent(block.dayType, () => []).add(block);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return TadoSchedule(timetableId: timetableId, blocksByDayType: grouped);
  }

  List<String> get orderedDayTypes =>
      tadoDayTypeOrder.where(blocksByDayType.containsKey).toList();
}
