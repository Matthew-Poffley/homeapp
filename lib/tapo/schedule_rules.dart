/// Shared "next scheduled flip" computation used by both the legacy
/// protocol's `wday` array and the SMART/KLAP protocol's `week_day`
/// bitmask — both use the same day-of-week convention, confirmed against a
/// real device's non-uniform legacy `wday` rules (weekday vs Fri/Sat/Sun
/// groupings only make sense with index/bit 0 = Sunday).
library;

import 'smart_plug_client.dart';

int weekdayIndexSundayFirst(DateTime date) =>
    date.weekday == DateTime.sunday ? 0 : date.weekday;

class ScheduleRule {
  final bool enabled;
  final int startMinute;
  final bool turnsOn;
  final bool Function(DateTime day) appliesOn;

  ScheduleRule({
    required this.enabled,
    required this.startMinute,
    required this.turnsOn,
    required this.appliesOn,
  });
}

/// Finds the soonest upcoming flip among enabled [rules], looking up to a
/// week ahead of [now].
NextAction? computeNextAction(List<ScheduleRule> rules, {DateTime? now}) {
  final currentTime = now ?? DateTime.now();
  DateTime? earliestTime;
  bool? earliestAction;

  for (final rule in rules) {
    if (!rule.enabled) continue;
    for (var dayOffset = 0; dayOffset < 8; dayOffset++) {
      final day = currentTime.add(Duration(days: dayOffset));
      if (!rule.appliesOn(day)) continue;
      final candidate = DateTime(
        day.year,
        day.month,
        day.day,
      ).add(Duration(minutes: rule.startMinute));
      if (candidate.isBefore(currentTime)) continue;
      if (earliestTime == null || candidate.isBefore(earliestTime)) {
        earliestTime = candidate;
        earliestAction = rule.turnsOn;
      }
      break;
    }
  }

  if (earliestTime == null || earliestAction == null) return null;
  return NextAction(turningOn: earliestAction, time: earliestTime);
}
