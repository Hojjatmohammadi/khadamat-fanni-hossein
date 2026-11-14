import 'dart:convert';

import 'app_database.dart';

/// Durable local outbox for a future authenticated sync transport.
///
/// This class deliberately does not contact a server. It stores idempotent
/// events and conflict snapshots so transport can be added without losing
/// unsent changes.
class SyncEventDraft {
  const SyncEventDraft({
    required this.eventId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
  });

  final String eventId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, Object?> payload;
}

class SyncRepository {
  SyncRepository(this._database);

  final AppDatabase _database;

  Future<int> enqueue(SyncEventDraft draft) async {
    final eventId = draft.eventId.trim();
    final deviceId = draft.deviceId.trim();
    final entityType = draft.entityType.trim();
    final entityId = draft.entityId.trim();
    final operation = draft.operation.trim();
    if (eventId.isEmpty ||
        deviceId.isEmpty ||
        entityType.isEmpty ||
        entityId.isEmpty ||
        !const {'create', 'update', 'delete'}.contains(operation)) {
      throw ArgumentError('مشخصات رویداد همگام‌سازی معتبر نیست.');
    }

    final payload = jsonEncode(draft.payload);
    final db = await _database.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'sync_outbox',
        where: 'event_id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        final same = row['device_id'] == deviceId &&
            row['entity_type'] == entityType &&
            row['entity_id'] == entityId &&
            row['operation'] == operation &&
            row['payload_json'] == payload;
        if (!same) {
          throw StateError('شناسه رویداد قبلاً با اطلاعات متفاوت ثبت شده است.');
        }
        return row['id'] as int;
      }

      return txn.insert('sync_outbox', {
        'event_id': eventId,
        'device_id': deviceId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload_json': payload,
        'status': 'pending',
        'attempt_count': 0,
        'last_error': null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': null,
      });
    });
  }

  Future<List<Map<String, Object?>>> getPending({int limit = 100}) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'بازه دریافت باید بین ۱ تا ۵۰۰ باشد.');
    }
    final db = await _database.database;
    return db.query(
      'sync_outbox',
      where: "status = 'pending'",
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> recordAttemptFailure(String eventId, String message) async {
    final db = await _database.database;
    final changed = await db.rawUpdate(
      "UPDATE sync_outbox SET attempt_count = attempt_count + 1, last_error = ? "
      "WHERE event_id = ? AND status = 'pending'",
      [message.trim(), eventId],
    );
    if (changed != 1) {
      throw StateError('رویداد در صف انتظار پیدا نشد یا قبلاً تعیین تکلیف شده است.');
    }
  }

  Future<void> markSynced(String eventId) async {
    final db = await _database.database;
    final changed = await db.rawUpdate(
      "UPDATE sync_outbox SET status = 'synced', synced_at = ?, last_error = NULL "
      "WHERE event_id = ? AND status = 'pending'",
      [DateTime.now().toUtc().toIso8601String(), eventId],
    );
    if (changed != 1) {
      final existing = await db.query(
        'sync_outbox',
        columns: ['status'],
        where: 'event_id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (existing.isEmpty || existing.single['status'] != 'synced') {
        throw StateError('رویداد قابل تأیید نیست.');
      }
    }
  }

  Future<int> recordConflict({
    required String conflictKey,
    required String eventId,
    required Map<String, Object?> remotePayload,
  }) async {
    final key = conflictKey.trim();
    if (key.isEmpty) throw ArgumentError('شناسه تعارض نمی‌تواند خالی باشد.');
    final db = await _database.database;
    return db.transaction((txn) async {
      final events = await txn.query(
        'sync_outbox',
        where: 'event_id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (events.isEmpty) throw StateError('رویداد محلی برای تعارض پیدا نشد.');
      final localPayload = events.single['payload_json'] as String;
      final remoteJson = jsonEncode(remotePayload);
      final existing = await txn.query(
        'sync_conflicts',
        where: 'conflict_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['event_id'] != eventId ||
            row['local_payload_json'] != localPayload ||
            row['remote_payload_json'] != remoteJson) {
          throw StateError('شناسه تعارض با داده متفاوت قبلاً ثبت شده است.');
        }
        return row['id'] as int;
      }

      await txn.update(
        'sync_outbox',
        {'status': 'conflict', 'last_error': 'تعارض نیازمند تصمیم مدیر است.'},
        where: "event_id = ? AND status = 'pending'",
        whereArgs: [eventId],
      );
      return txn.insert('sync_conflicts', {
        'conflict_key': key,
        'event_id': eventId,
        'local_payload_json': localPayload,
        'remote_payload_json': remoteJson,
        'resolution': null,
        'resolved_payload_json': null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'resolved_at': null,
      });
    });
  }

  Future<List<Map<String, Object?>>> getUnresolvedConflicts() async {
    final db = await _database.database;
    return db.query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> resolveConflict({
    required String conflictKey,
    required String resolution,
    Map<String, Object?>? manualPayload,
  }) async {
    if (!const {'keep_local', 'keep_remote', 'manual'}.contains(resolution)) {
      throw ArgumentError('روش حل تعارض معتبر نیست.');
    }
    if (resolution == 'manual' && manualPayload == null) {
      throw ArgumentError('برای حل دستی باید اطلاعات نهایی وارد شود.');
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_conflicts',
        where: 'conflict_key = ?',
        whereArgs: [conflictKey],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('تعارض پیدا نشد.');
      final conflict = rows.single;
      if (conflict['resolved_at'] != null) {
        throw StateError('این تعارض قبلاً حل شده است.');
      }

      final selectedPayload = switch (resolution) {
        'keep_local' => conflict['local_payload_json'] as String,
        'keep_remote' => conflict['remote_payload_json'] as String,
        _ => jsonEncode(manualPayload),
      };
      await txn.update(
        'sync_conflicts',
        {
          'resolution': resolution,
          'resolved_payload_json': selectedPayload,
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [conflict['id']],
      );

      // A conflict is not silently marked synced. It returns to pending so a
      // future transport can send the explicitly selected resolution.
      await txn.update(
        'sync_outbox',
        {
          'status': 'pending',
          'payload_json': selectedPayload,
          'last_error': null,
        },
        where: 'event_id = ?',
        whereArgs: [conflict['event_id']],
      );
    });
  }

  Future<int> getPendingCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM sync_outbox WHERE status = 'pending'",
    );
    return (rows.single['total'] as num).toInt();
  }
}
