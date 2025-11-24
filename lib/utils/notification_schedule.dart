/// Utility helpers used by the reminder coordinator to keep the scheduling logic testable.
class NotificationScheduleUtils {
  const NotificationScheduleUtils._();

  /// Normalises the trigger time to a fixed [hour] on the same calendar day.
  static DateTime normalize(DateTime target, {int hour = 9}) => DateTime(target.year, target.month, target.day, hour);

  /// Builds reminder timestamps subtracting [offsetDays] from [deadline] and dropping timestamps
  /// that already passed relative to [now].
  static List<DateTime> buildSlots({
    required DateTime deadline,
    required Iterable<int> offsetDays,
    required DateTime now,
    int hour = 9,
  }) {
    final results = <DateTime>[];
    for (final days in offsetDays) {
      final candidate = deadline.subtract(Duration(days: days));
      final normalized = normalize(candidate, hour: hour);
      if (normalized.isAfter(now)) {
        results.add(normalized);
      }
    }
    results.sort();
    return results;
  }
}