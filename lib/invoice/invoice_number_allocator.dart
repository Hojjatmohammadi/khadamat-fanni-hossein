import 'package:sqflite/sqflite.dart';

/// A number reserved for one invoice. The reservation must be made inside the
/// same SQLite transaction that stores the invoice and its immutable archive.
class InvoiceNumberReservation {
  final String invoiceNumber;
  final int nextNumber;

  const InvoiceNumberReservation({
    required this.invoiceNumber,
    required this.nextNumber,
  });
}

/// Allocates invoice numbers transactionally instead of relying only on
/// SharedPreferences. SQLite is the source of truth, so app restarts, failed
/// writes, and two rapid issue actions cannot silently reuse a number.
class InvoiceNumberAllocator {
  InvoiceNumberAllocator._();

  static const tableName = 'invoice_number_sequences';
  static const defaultWidth = 5;

  static String normalizePrefix(String value) {
    final prefix = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (prefix.isEmpty || prefix.length > 32 ||
        prefix.contains('/') || prefix.contains(String.fromCharCode(92))) {
      throw ArgumentError('پیشوند شماره فاکتور معتبر نیست.');
    }
    return prefix;
  }

  static Future<void> createTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        prefix TEXT PRIMARY KEY,
        next_number INTEGER NOT NULL CHECK (next_number >= 1),
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Seeds every prefix from the immutable archive and reconciles the active
  /// prefix with the user preference. Counters can move forward, never back
  /// below an already issued invoice number.
  static Future<int> initialize(
    DatabaseExecutor db, {
    required String prefix,
    required int preferredNextNumber,
  }) async {
    if (preferredNextNumber < 1) {
      throw ArgumentError.value(
        preferredNextNumber,
        'preferredNextNumber',
        'شماره بعدی فاکتور باید مثبت باشد.',
      );
    }
    await createTable(db);

    final highestNextByPrefix = <String, int>{};
    final archivedRows = await db.query(
      'invoice_archive',
      columns: const ['invoice_number'],
    );
    final pattern = RegExp(r'^(.*)-([0-9]+)$');
    for (final row in archivedRows) {
      final invoiceNumber = (row['invoice_number'] ?? '').toString();
      final match = pattern.firstMatch(invoiceNumber);
      if (match == null) continue;
      final archivedPrefix = match.group(1)!;
      final serial = int.tryParse(match.group(2)!);
      if (serial == null || serial < 1) continue;
      final next = serial + 1;
      final previous = highestNextByPrefix[archivedPrefix] ?? 1;
      if (next > previous) highestNextByPrefix[archivedPrefix] = next;
    }

    final normalizedPrefix = normalizePrefix(prefix);
    highestNextByPrefix[normalizedPrefix] = _max(
      highestNextByPrefix[normalizedPrefix] ?? 1,
      preferredNextNumber,
    );

    for (final entry in highestNextByPrefix.entries) {
      await db.insert(
        tableName,
        {
          'prefix': entry.key,
          'next_number': entry.value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.rawUpdate(
        'UPDATE $tableName SET next_number = CASE '
        'WHEN next_number < ? THEN ? ELSE next_number END, updated_at = ? '
        'WHERE prefix = ?',
        [
          entry.value,
          entry.value,
          DateTime.now().toIso8601String(),
          entry.key,
        ],
      );
    }

    final rows = await db.query(
      tableName,
      columns: const ['next_number'],
      where: 'prefix = ?',
      whereArgs: [normalizedPrefix],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('شمارنده شماره فاکتور ایجاد نشد.');
    }
    return (rows.single['next_number'] as num).toInt();
  }

  /// Reserves a number inside the caller's transaction. If an old or manually
  /// imported invoice already uses the candidate, the allocator skips it.
  static Future<InvoiceNumberReservation> reserve(
    DatabaseExecutor txn, {
    required String prefix,
    required int fallbackNextNumber,
    int width = defaultWidth,
  }) async {
    final normalizedPrefix = normalizePrefix(prefix);
    if (fallbackNextNumber < 1 || width < 1 || width > 12) {
      throw ArgumentError('تنظیمات شماره‌گذاری فاکتور معتبر نیست.');
    }
    await createTable(txn);
    final now = DateTime.now().toIso8601String();
    await txn.insert(
      tableName,
      {
        'prefix': normalizedPrefix,
        'next_number': fallbackNextNumber,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final rows = await txn.query(
      tableName,
      columns: const ['next_number'],
      where: 'prefix = ?',
      whereArgs: [normalizedPrefix],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('شمارنده شماره فاکتور در دسترس نیست.');
    }

    var candidate = _max(
      (rows.single['next_number'] as num).toInt(),
      fallbackNextNumber,
    );
    while (true) {
      final invoiceNumber =
          '$normalizedPrefix-${candidate.toString().padLeft(width, '0')}';
      final existing = await txn.query(
        'invoice_archive',
        columns: const ['id'],
        where: 'invoice_number = ?',
        whereArgs: [invoiceNumber],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.update(
          tableName,
          {
            'next_number': candidate + 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'prefix = ?',
          whereArgs: [normalizedPrefix],
        );
        return InvoiceNumberReservation(
          invoiceNumber: invoiceNumber,
          nextNumber: candidate + 1,
        );
      }
      candidate++;
    }
  }

  static int _max(int first, int second) =>
      first > second ? first : second;
}
