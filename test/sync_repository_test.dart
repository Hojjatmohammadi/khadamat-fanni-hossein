import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late SyncRepository sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_sync_test_');
    database = AppDatabase(databasePath: '${tempDir.path}/sync.db');
    await database.database;
    sync = SyncRepository(database);
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  SyncEventDraft draft({
    String eventId = 'device-a:1',
    Map<String, Object?> payload = const {'name': 'خازن ۱۰۰ میکرو'},
  }) =>
      SyncEventDraft(
        eventId: eventId,
        deviceId: 'device-a',
        entityType: 'product',
        entityId: 'product-12',
        operation: 'create',
        payload: payload,
      );

  test('enqueue is idempotent and rejects event id reuse with different data', () async {
    final first = await sync.enqueue(draft());
    final duplicate = await sync.enqueue(draft());
    expect(duplicate, first);
    expect(await sync.getPendingCount(), 1);

    await expectLater(
      sync.enqueue(draft(payload: const {'name': 'نام متفاوت'})),
      throwsA(isA<StateError>()),
    );
    expect(await sync.getPendingCount(), 1);
  });

  test('pending events are ordered and can be acknowledged once', () async {
    await sync.enqueue(draft());
    await sync.enqueue(draft(eventId: 'device-a:2'));

    final pending = await sync.getPending(limit: 10);
    expect(pending, hasLength(2));
    expect(pending.first['event_id'], 'device-a:1');

    await sync.markSynced('device-a:1');
    await sync.markSynced('device-a:1');
    expect(await sync.getPendingCount(), 1);
  });

  test('failed attempts are counted without dropping the event', () async {
    await sync.enqueue(draft());
    await sync.recordAttemptFailure('device-a:1', 'network unavailable');

    final pending = await sync.getPending();
    expect(pending.single['attempt_count'], 1);
    expect(pending.single['last_error'], 'network unavailable');
  });

  test('conflicts retain both payloads until explicit resolution', () async {
    await sync.enqueue(draft());
    await sync.recordConflict(
      conflictKey: 'conflict-1',
      eventId: 'device-a:1',
      remotePayload: const {'name': 'خازن ۲۲۰ میکرو'},
    );

    expect(await sync.getPendingCount(), 0);
    final conflicts = await sync.getUnresolvedConflicts();
    expect(conflicts, hasLength(1));
    expect(conflicts.single['local_payload_json'], contains('۱۰۰'));
    expect(conflicts.single['remote_payload_json'], contains('۲۲۰'));

    await sync.resolveConflict(
      conflictKey: 'conflict-1',
      resolution: 'keep_remote',
    );
    expect(await sync.getUnresolvedConflicts(), isEmpty);
    final pending = await sync.getPending();
    expect(pending, hasLength(1));
    expect(pending.single['payload_json'], contains('۲۲۰'));
  });

  test('manual conflict resolution requires an explicit payload', () async {
    await sync.enqueue(draft());
    await sync.recordConflict(
      conflictKey: 'conflict-manual',
      eventId: 'device-a:1',
      remotePayload: const {'name': 'remote'},
    );

    await expectLater(
      sync.resolveConflict(
        conflictKey: 'conflict-manual',
        resolution: 'manual',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await sync.getUnresolvedConflicts(), hasLength(1));
  });
}
