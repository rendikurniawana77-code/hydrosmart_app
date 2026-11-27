import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../firebase_options.dart';
import '../models/harvest_prediction.dart';
import '../models/history_range.dart';
import '../models/sensor_data.dart';
import '../models/telemetry_sample.dart'; // riwayat untuk grafik
import '../repositories/hydro_repository.dart';
import '../repositories/telemetry_cache.dart';

enum UserRole { penampil, operator, admin }

class HydroSmartProvider extends ChangeNotifier {
  UserRole _currentRole = UserRole.admin;
  late SensorData _sensorData;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;
  StreamSubscription<DatabaseEvent>? _kontrolSubscription;
  StreamSubscription<DatabaseEvent>? _predictionSubscription;
  StreamSubscription<DatabaseEvent>? _batchSubscription;
  Timer? _thresholdWriteTimer;
  Timer? _historyRefreshTimer;
  bool _hasControlMode = false;
  bool _historyFetchInProgress = false;
  bool _historyRefreshPending = false;

  double _minWaterLevel = 30.0;
  double _maxWaterLevel = 80.0;
  DateTime? _plantingStartDate;
  HarvestPrediction? _harvestPrediction;

  // [BARU] Status masing-masing pompa
  bool _pumpA = false;
  bool _pumpB = false;

  static const Duration _historyOverlap = Duration(hours: 3);
  static const Duration _historyRetention = Duration(days: 30);
  final TelemetryCache _telemetryCache = TelemetryCache();
  HistoryRange _historyRange = HistoryRange.hours24;
  final List<TelemetrySample> _history = [];
  bool _historyLoading = false;
  String? _historyError;

  UserRole get currentRole => _currentRole;
  SensorData get sensorData => _sensorData;
  double get minWaterLevel => _minWaterLevel;
  double get maxWaterLevel => _maxWaterLevel;
  int get currentHst =>
      _harvestPrediction?.dayIndex ??
      (_plantingStartDate == null
          ? 0
          : DateTime.now().difference(_plantingStartDate!).inDays);
  DateTime? get plantingStartDate => _plantingStartDate;
  HarvestPrediction? get harvestPrediction => _harvestPrediction;
  HistoryRange get historyRange => _historyRange;
  bool get historyLoading => _historyLoading;
  String? get historyError => _historyError;

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool? _boolean(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case 'on':
        case '1':
          return true;
        case 'false':
        case 'off':
        case '0':
          return false;
      }
    }
    return null;
  }

  static DateTime? _timestamp(dynamic value) {
    final milliseconds = _number(value);
    if (milliseconds == null || milliseconds <= 0) return null;
    final epoch = milliseconds > 10000000000
        ? milliseconds.toInt()
        : (milliseconds * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(epoch);
  }

  // [BARU]
  bool get pumpA => _pumpA;
  bool get pumpB => _pumpB;

  List<TelemetrySample> get history => List.unmodifiable(_history);

  HydroSmartProvider() {
    _sensorData = SensorData(
      tdsPpm: 0,
      waterLevelPct: 0,
      pumpStatus: 'OFF',
      mode: 'AUTO',
      isOnline: true,
      lastUpdated: DateTime.now(),
    );
    _initFirebaseListener();
    _historyRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => refreshHistory(),
    );
  }

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
  );

  late final HydroRepository hydroRepository = HydroRepository(_db);

  void setRole(UserRole role) {
    _currentRole = role;
    notifyListeners();
  }

  void setLowerWaterThreshold(double value) {
    _minWaterLevel = value;
    _scheduleThresholdWrite();
    notifyListeners();
  }

  void setUpperWaterThreshold(double value) {
    _maxWaterLevel = value;
    _scheduleThresholdWrite();
    notifyListeners();
  }

  void _scheduleThresholdWrite() {
    _thresholdWriteTimer?.cancel();
    _thresholdWriteTimer = Timer(const Duration(milliseconds: 250), () {
      _saveThresholds();
    });
  }

  Future<void> _saveThresholds() async {
    try {
      await _db.ref('hydrosmart/kontrol').update({
        'batas_bawah': _minWaterLevel,
        'batas_atas': _maxWaterLevel,
      });
    } catch (e) {
      debugPrint('Error update ambang batas ke Firebase: $e');
    }
  }

  Future<void> loadHistoryRange(HistoryRange range) async {
    _historyRange = range;
    _historyError = null;
    notifyListeners();
    await refreshHistory();
  }

  Future<void> refreshHistory() async {
    if (_historyFetchInProgress) {
      _historyRefreshPending = true;
      return;
    }
    _historyFetchInProgress = true;
    _historyLoading = true;
    notifyListeners();

    final now = DateTime.now();
    final rangeStart = now.subtract(_historyRange.duration);
    final startSeconds = rangeStart.millisecondsSinceEpoch ~/ 1000;
    final endSeconds = now.millisecondsSinceEpoch ~/ 1000;

    try {
      await _telemetryCache.pruneBefore(now.subtract(_historyRetention));
      _history
        ..clear()
        ..addAll(await _telemetryCache.readRange(rangeStart, now));
      notifyListeners();

      final cachedOldest = await _telemetryCache.oldestTimestamp();
      final cachedLatest = await _telemetryCache.latestTimestamp();
      final queryStart =
          cachedLatest == null ||
              cachedOldest == null ||
              cachedOldest > startSeconds
          ? startSeconds
          : (cachedLatest - _historyOverlap.inSeconds).clamp(
              startSeconds,
              endSeconds,
            );

      final snapshot = await _db
          .ref('hydrosmart/riwayat')
          .orderByChild('waktu')
          .startAt(queryStart.toDouble())
          .endAt(endSeconds.toDouble())
          .get();
      final records = <String, Map<dynamic, dynamic>>{};
      final value = snapshot.value;
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.value is Map) {
            records[entry.key.toString()] = Map<dynamic, dynamic>.from(
              entry.value as Map,
            );
          }
        }
      }

      await _telemetryCache.upsert(records);
      _history
        ..clear()
        ..addAll(await _telemetryCache.readRange(rangeStart, now));
      _historyError = null;
    } catch (error) {
      _historyError = 'Riwayat gagal dimuat: $error';
      debugPrint('Firebase/local telemetry history error: $error');
      try {
        _history
          ..clear()
          ..addAll(await _telemetryCache.readRange(rangeStart, now));
      } catch (cacheError) {
        debugPrint('Local telemetry cache error: $cacheError');
      }
    } finally {
      _historyLoading = false;
      _historyFetchInProgress = false;
      notifyListeners();
      if (_historyRefreshPending) {
        _historyRefreshPending = false;
        unawaited(refreshHistory());
      }
    }
  }

  Future<bool> setPlantingDate(DateTime date) async {
    final selectedDate = DateTime(date.year, date.month, date.day);
    final previousDate = _plantingStartDate;
    _plantingStartDate = selectedDate;
    notifyListeners();

    try {
      await _db.ref('hydrosmart/batch/aktif').update({
        'mulai': selectedDate.millisecondsSinceEpoch ~/ 1000,
      });
      return true;
    } catch (e) {
      _plantingStartDate = previousDate;
      notifyListeners();
      debugPrint('Error menyimpan hari pertama tanam ke Firebase: $e');
      return false;
    }
  }

  // ───────────────────────── MODE ─────────────────────────
  Future<void> toggleMode() async {
    final mode = _sensorData.mode == 'AUTO' ? 'MANUAL' : 'AUTO';
    await setMode(mode);
  }

  Future<void> setMode(String requestedMode) async {
    if (_currentRole == UserRole.penampil) return;
    final newMode = requestedMode.toUpperCase();
    if (newMode != 'AUTO' && newMode != 'MANUAL') return;

    try {
      await _db.ref('hydrosmart/kontrol').update({
        'mode': newMode.toLowerCase(),
        if (newMode == 'AUTO') ...{
          'pompa': false,
          'pompa_a': false,
          'pompa_b': false,
        },
      });
      _hasControlMode = true;
      if (newMode == 'AUTO') {
        _pumpA = false;
        _pumpB = false;
      }
      _sensorData = SensorData(
        tdsPpm: _sensorData.tdsPpm,
        waterLevelPct: _sensorData.waterLevelPct,
        pumpStatus: newMode == 'AUTO' ? 'OFF' : _sensorData.pumpStatus,
        mode: newMode,
        isOnline: _sensorData.isOnline,
        lastUpdated: _sensorData.lastUpdated,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error update mode ke Firebase: $e');
    }
  }

  // ───────────────────────── POMPA A + B ─────────────────────────
  Future<void> togglePumpAB() {
    final target = !(_pumpA || _pumpB);
    return _setPumps(target);
  }

  /// Kompatibilitas dengan kode lama (layar lain yang masih memanggil togglePump).
  Future<void> togglePump() => togglePumpAB();

  Future<void> _setPumps(bool enabled) async {
    if (_currentRole == UserRole.penampil) return;
    if (_sensorData.mode == 'AUTO') return;

    try {
      await _db.ref('hydrosmart/kontrol').update({
        'pompa': enabled,
        'pompa_a': enabled,
        'pompa_b': enabled,
      });
      _pumpA = enabled;
      _pumpB = enabled;
      _sensorData = SensorData(
        tdsPpm: _sensorData.tdsPpm,
        waterLevelPct: _sensorData.waterLevelPct,
        pumpStatus: enabled ? 'ON' : 'OFF',
        mode: _sensorData.mode,
        isOnline: _sensorData.isOnline,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error update pompa ke Firebase: $e');
    }
  }

  // ───────────────────────── FIREBASE LISTENER ─────────────────────────
  void _initFirebaseListener() {
    try {
      final database = _db;

      // 1. Data realtime di node 'hydrosmart/terbaru'
      _firebaseSubscription = database
          .ref('hydrosmart/terbaru')
          .onValue
          .listen(
            (DatabaseEvent event) {
              if (event.snapshot.exists && event.snapshot.value != null) {
                final data = event.snapshot.value;
                if (data is Map) {
                  final double level =
                      _number(data['level']) ?? _sensorData.waterLevelPct;
                  final bool pompa = _boolean(data['pompa']) ?? false;
                  final double tds = _number(data['tds']) ?? _sensorData.tdsPpm;
                  final String? mode = data['mode']?.toString().toUpperCase();

                  final bool? tA =
                      _boolean(data['pompa_a']) ?? _boolean(data['pompa_air']);
                  final bool? tB =
                      _boolean(data['pompa_b']) ??
                      _boolean(data['pompa_nutrisi']);
                  final effectiveMode = _hasControlMode
                      ? _sensorData.mode
                      : mode ?? _sensorData.mode;

                  // In MANUAL, kontrol is authoritative; terbaru can lag behind a command.
                  if (effectiveMode != 'MANUAL') {
                    if (tA != null || tB != null) {
                      _pumpA = tA ?? pompa;
                      _pumpB = tB ?? pompa;
                    } else {
                      _pumpA = pompa;
                      _pumpB = pompa;
                    }
                  }
                  final bool reportedPumpsOn = tA != null || tB != null
                      ? (tA ?? pompa) || (tB ?? pompa)
                      : pompa;

                  final updatedTime =
                      _timestamp(data['waktu']) ?? DateTime.now();

                  _sensorData = SensorData(
                    tdsPpm: tds,
                    waterLevelPct: level,
                    pumpStatus:
                        (effectiveMode == 'MANUAL'
                            ? _pumpA || _pumpB
                            : reportedPumpsOn)
                        ? 'ON'
                        : 'OFF',
                    mode: effectiveMode,
                    isOnline: true,
                    lastUpdated: updatedTime,
                  );
                  notifyListeners();
                }
              }
            },
            onError: (error) {
              debugPrint(
                'Firebase Database Error (hydrosmart/terbaru): $error',
              );
            },
          );

      // 2. Node 'hydrosmart/kontrol' agar status kontrol di HP selalu sinkron
      _kontrolSubscription = database
          .ref('hydrosmart/kontrol')
          .onValue
          .listen(
            (event) {
              if (event.snapshot.exists && event.snapshot.value != null) {
                final data = event.snapshot.value;
                if (data is Map) {
                  final String? kMode = data['mode']?.toString().toUpperCase();
                  final bool kPompa = data['pompa'] == true;
                  final bool? kA = data['pompa_a'] is bool
                      ? data['pompa_a'] as bool
                      : null;
                  final bool? kB = data['pompa_b'] is bool
                      ? data['pompa_b'] as bool
                      : null;
                  final double? lowerThreshold = _number(data['batas_bawah']);
                  final double? upperThreshold = _number(data['batas_atas']);

                  final bool modeChanged =
                      kMode != null && kMode != _sensorData.mode;
                  final bool thresholdsChanged =
                      (lowerThreshold != null &&
                          lowerThreshold != _minWaterLevel) ||
                      (upperThreshold != null &&
                          upperThreshold != _maxWaterLevel);
                  if (kMode != null) _hasControlMode = true;
                  if (lowerThreshold != null) {
                    _minWaterLevel = lowerThreshold;
                  }
                  if (upperThreshold != null) {
                    _maxWaterLevel = upperThreshold;
                  }
                  bool a = _pumpA;
                  bool b = _pumpB;

                  if (kA != null || kB != null) {
                    a = kA ?? a;
                    b = kB ?? b;
                  } else {
                    // Data lama tanpa A/B: pakai satu status 'pompa' untuk keduanya
                    a = b = kPompa;
                  }

                  final bool pumpChanged = a != _pumpA || b != _pumpB;

                  if (modeChanged || pumpChanged || thresholdsChanged) {
                    _pumpA = a;
                    _pumpB = b;
                    final String newMode = kMode ?? _sensorData.mode;
                    _sensorData = SensorData(
                      tdsPpm: _sensorData.tdsPpm,
                      waterLevelPct: _sensorData.waterLevelPct,
                      pumpStatus: (a || b) ? 'ON' : 'OFF',
                      mode: newMode,
                      isOnline: _sensorData.isOnline,
                      lastUpdated: _sensorData.lastUpdated,
                    );
                    notifyListeners();
                  }
                }
              }
            },
            onError: (error) {
              debugPrint(
                'Firebase Database Error (hydrosmart/kontrol): $error',
              );
            },
          );

      unawaited(loadHistoryRange(_historyRange));

      _predictionSubscription = database
          .ref('hydrosmart/prediksi/terbaru')
          .onValue
          .listen(
            (event) {
              final value = event.snapshot.value;
              if (value is Map) {
                _harvestPrediction = HarvestPrediction.fromMap(value);
                if (_plantingStartDate == null) {
                  _plantingStartDate = _harvestPrediction?.dayZero;
                }
                notifyListeners();
              }
            },
            onError: (error) {
              debugPrint(
                'Firebase Database Error (hydrosmart/prediksi): $error',
              );
            },
          );

      _batchSubscription = database
          .ref('hydrosmart/batch/aktif/mulai')
          .onValue
          .listen(
            (event) {
              final date = _timestamp(event.snapshot.value);
              if (date != null) {
                _plantingStartDate = DateTime(date.year, date.month, date.day);
                notifyListeners();
              }
            },
            onError: (error) {
              debugPrint(
                'Firebase Database Error (hydrosmart/batch/aktif/mulai): $error',
              );
            },
          );
    } catch (e) {
      debugPrint('Error init Firebase listener: $e');
    }
  }

  @override
  void dispose() {
    _thresholdWriteTimer?.cancel();
    _firebaseSubscription?.cancel();
    _kontrolSubscription?.cancel();
    _historyRefreshTimer?.cancel();
    _predictionSubscription?.cancel();
    _batchSubscription?.cancel();
    super.dispose();
  }
}
