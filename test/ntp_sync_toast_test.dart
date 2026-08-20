import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/incremental_sync_service.dart';

void main() {
  test('public toast publisher emits a sync toast event', () async {
    final service = IncrementalSyncService();
    final eventFuture = service.toastStream.first;

    service.showToast(success: true, message: 'NTP synced');

    final event = await eventFuture;
    expect(event.success, isTrue);
    expect(event.message, 'NTP synced');
  });
}
