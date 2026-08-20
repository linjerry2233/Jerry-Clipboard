import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/cloud_sync_coordinator.dart';

void main() {
  test('cloud operations are serialized in submission order', () async {
    final coordinator = CloudSyncCoordinator();
    var active = 0;
    var maxActive = 0;
    final order = <String>[];
    final firstMayFinish = Completer<void>();

    final first = coordinator.run(() async {
      active++;
      maxActive = active > maxActive ? active : maxActive;
      order.add('first-start');
      await firstMayFinish.future;
      order.add('first-end');
      active--;
    });
    final second = coordinator.run(() async {
      active++;
      maxActive = active > maxActive ? active : maxActive;
      order.add('second-start');
      active--;
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    expect(coordinator.isBusy, isTrue);
    firstMayFinish.complete();
    await Future.wait([first, second]);

    expect(maxActive, 1);
    expect(order, ['first-start', 'first-end', 'second-start']);
    expect(coordinator.isBusy, isFalse);
  });

  test('clipboard image sync setting is persisted and legacy-safe', () {
    expect(
      CloudSyncConfig.fromJson(<String, dynamic>{}).syncClipboardImages,
      isFalse,
    );

    final disabled = CloudSyncConfig(syncClipboardImages: false);
    expect(
      CloudSyncConfig.fromJson(disabled.toJson()).syncClipboardImages,
      isFalse,
    );

    final enabled = CloudSyncConfig(syncClipboardImages: true);
    expect(
      CloudSyncConfig.fromJson(enabled.toJson()).syncClipboardImages,
      isTrue,
    );
  });
}
