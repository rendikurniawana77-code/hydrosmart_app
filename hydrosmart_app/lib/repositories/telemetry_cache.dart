import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/telemetry_sample.dart';

class TelemetryCache {
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasePath, 'hydrosmart_telemetry.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE telemetry (
            push_key TEXT PRIMARY KEY,
            waktu INTEGER NOT NULL,
            tds REAL,
            tds_adc REAL,
            level REAL,
            level_adc REAL,
            isi_ulang INTEGER,
            pompa INTEGER,
            waktu_pasti INTEGER,
            tertunda INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX telemetry_waktu_idx ON telemetry(waktu)',
        );
      },
    );
    return _database!;
  }

  Future<void> upsert(Map<String, Map<dynamic, dynamic>> records) async {
    if (records.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final entry in records.entries) {
      final record = entry.value;
      if (_isFalse(record['waktu_pasti'])) continue;
      final time = _epochSeconds(record['waktu']);
      if (time == null || time <= 0) continue;

      batch.insert('telemetry', {
        'push_key': entry.key,
        'waktu': time,
        'tds': _number(record['tds']),
        'tds_adc': _number(record['tds_adc']),
        'level': _number(record['level']),
        'level_adc': _number(record['level_adc']),
        'isi_ulang': _boolInt(record['isi_ulang']),
        'pompa': _boolInt(record['pompa']),
        'waktu_pasti': _boolInt(record['waktu_pasti']),
        'tertunda': _boolInt(record['tertunda']),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TelemetrySample>> readRange(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.query(
      'telemetry',
      columns: ['waktu', 'tds', 'level'],
      where: 'waktu >= ? AND waktu <= ?',
      whereArgs: [
        start.millisecondsSinceEpoch ~/ 1000,
        end.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'waktu ASC',
    );
    return rows
        .map(
          (row) => TelemetrySample(
            time: DateTime.fromMillisecondsSinceEpoch(
              (row['waktu']! as int) * 1000,
            ),
            tds: (row['tds'] as num?)?.toDouble(),
            waterPct: (row['level'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  Future<int?> oldestTimestamp() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT MIN(waktu) AS waktu FROM telemetry');
    return rows.first['waktu'] as int?;
  }

  Future<int?> latestTimestamp() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT MAX(waktu) AS waktu FROM telemetry');
    return rows.first['waktu'] as int?;
  }

  Future<void> pruneBefore(DateTime cutoff) async {
    final db = await _db;
    await db.delete(
      'telemetry',
      where: 'waktu < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch ~/ 1000],
    );
  }

  static int? _epochSeconds(dynamic value) {
    final number = _number(value);
    if (number == null) return null;
    return number > 10000000000 ? (number / 1000).floor() : number.floor();
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _isFalse(dynamic value) =>
      value == false || value?.toString().toLowerCase() == 'false';

  static int? _boolInt(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value == 0 ? 0 : 1;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
        case 'on':
          return 1;
        case 'false':
        case '0':
        case 'off':
          return 0;
      }
    }
    return null;
  }
}
