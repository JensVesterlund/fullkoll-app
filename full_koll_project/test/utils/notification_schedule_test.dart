import 'package:flutter_test/flutter_test.dart';

import 'package:full_koll/utils/notification_schedule.dart';

void main() {
  test('normalize resets to 09:00', () {
    final input = DateTime(2025, 1, 31, 22, 45);
    final normalised = NotificationScheduleUtils.normalize(input);
    expect(normalised.hour, equals(9));
    expect(normalised.minute, equals(0));
    expect(normalised.year, equals(input.year));
    expect(normalised.day, equals(input.day));
  });

  test('buildSlots filters past timestamps and sorts ascending', () {
    final now = DateTime(2025, 1, 10, 8);
    final deadline = DateTime(2025, 1, 20, 15);
    final slots = NotificationScheduleUtils.buildSlots(
      deadline: deadline,
      offsetDays: const [30, 7, 1],
      now: now,
    );

    expect(slots.length, equals(2));
    expect(slots.first.isBefore(slots.last), isTrue);
    expect(deadline.difference(slots.first).inDays, equals(7));
    expect(deadline.difference(slots.last).inDays, equals(1));
  });
}