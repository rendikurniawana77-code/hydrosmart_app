import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../firebase_options.dart';
import '../models/sensor_data.dart';
import '../models/telemetry_sample.dart'; // riwayat untuk grafik

enum UserRole {
  penampil,
  operator,
  admin,
}

class PlantNote {
  final String date;
  final int hst;
  final double height;
  final int leaves;
  final double? harvestWeight;

  PlantNote({
    required this.date,
    required this.hst,
    required this.height,
    required this.leaves,
    this.harvestWeight,
  });
}

class HydroSmartProvider
    extends
        ChangeNotifier {
  UserRole _currentRole = UserRole.admin;
  late SensorData _sensorData;
  Timer? _simulationTimer;
  StreamSubscription<
    DatabaseEvent
  >?
  _firebaseSubscription;
  StreamSubscription<
    DatabaseEvent
  >?
  _kontrolSubscription;

  double _minWaterLevel = 30.0;
  double _maxWaterLevel = 80.0;
  int _currentHst = 18; // Hari Setelah Tanam

  // [BARU] Status masing-masing pompa
  bool _pumpA = false;
  bool _pumpB = false;

  // Riwayat telemetri untuk grafik "Analitik Lingkungan Waktu Nyata".
  // Disimpan di provider (bukan di widget) supaya tidak hilang saat pindah tab.
  static const int _historyMax = 60;
  final List<
    TelemetrySample
  >
  _history = [];
  DateTime? _lastSampleAt;

  final List<
    PlantNote
  >
  _plantNotes = [
    PlantNote(
      date: '2026-10-20',
      hst: 14,
      height: 12.5,
      leaves: 6,
    ),
    PlantNote(
      date: '2026-10-24',
      hst: 18,
      height: 16.2,
      leaves: 8,
    ),
  ];

  UserRole get currentRole => _currentRole;
  SensorData get sensorData => _sensorData;
  double get minWaterLevel => _minWaterLevel;
  double get maxWaterLevel => _maxWaterLevel;
  int get currentHst => _currentHst;
  List<
    PlantNote
  >
  get plantNotes => _plantNotes;

  // [BARU]
  bool get pumpA => _pumpA;
  bool get pumpB => _pumpB;

  List<
    TelemetrySample
  >
  get history => List.unmodifiable(
    _history,
  );
  DateTime? get lastSampleAt => _lastSampleAt;

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
  }

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
  );

  // Catat satu titik grafik dari _sensorData saat ini.
  // Hanya dipanggil saat data sensor BARU masuk (bukan saat toggle/kontrol).
  // Waktu yang dipakai adalah waktu terima, bukan jam ESP32, agar tahan beda jam.
  void _recordSample() {
    final now = DateTime.now();
    _history.add(
      TelemetrySample(
        time: now,
        tds: _sensorData.tdsPpm,
        waterPct: _sensorData.waterLevelPct,
      ),
    );
    if (_history.length >
        _historyMax)
      _history.removeAt(
        0,
      );
    _lastSampleAt = now;
  }

  void setRole(
    UserRole role,
  ) {
    _currentRole = role;
    notifyListeners();
  }

  void setThresholds(
    double minLvl,
    double maxLvl,
  ) {
    _minWaterLevel = minLvl;
    _maxWaterLevel = maxLvl;
    notifyListeners();
  }

  void addPlantNote(
    PlantNote note,
  ) {
    _plantNotes.add(
      note,
    );
    notifyListeners();
  }

  // ───────────────────────── MODE ─────────────────────────
  Future<
    void
  >
  toggleMode() async {
    if (_currentRole ==
        UserRole.penampil)
      return;
    final String newMode =
        _sensorData.mode ==
            'AUTO'
        ? 'MANUAL'
        : 'AUTO';

    // Pindah ke AUTO: matikan semua pompa manual lebih dulu (keamanan)
    if (newMode ==
        'AUTO') {
      _pumpA = false;
      _pumpB = false;
    }

    // Update UI responsif secara langsung
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      pumpStatus:
          newMode ==
              'AUTO'
          ? 'OFF'
          : _sensorData.pumpStatus,
      mode: newMode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();

    // Kirim perintah mode ke Firebase node 'hydrosmart/kontrol'
    try {
      await _db
          .ref(
            'hydrosmart/kontrol',
          )
          .update({
            'mode': newMode.toLowerCase(),
            if (newMode ==
                'AUTO') ...{
              'pompa': false,
              'pompa_a': false,
              'pompa_b': false,
            },
          });
    } catch (
      e
    ) {
      debugPrint(
        'Error update mode ke Firebase: $e',
      );
    }
  }

  // ───────────────────────── POMPA A / B ─────────────────────────
  Future<
    void
  >
  togglePumpA() => _setPumps(
    !_pumpA,
    _pumpB,
  );

  Future<
    void
  >
  togglePumpB() => _setPumps(
    _pumpA,
    !_pumpB,
  );

  /// Jika A dan B sama-sama ON -> matikan keduanya, selain itu nyalakan keduanya.
  Future<
    void
  >
  togglePumpAB() {
    final target =
        !(_pumpA &&
            _pumpB);
    return _setPumps(
      target,
      target,
    );
  }

  /// Kompatibilitas dengan kode lama (layar lain yang masih memanggil togglePump).
  Future<
    void
  >
  togglePump() => togglePumpAB();

  Future<
    void
  >
  _setPumps(
    bool a,
    bool b,
  ) async {
    if (_currentRole ==
        UserRole.penampil)
      return;
    if (_sensorData.mode ==
        'AUTO')
      return;

    // Pengaman: jangan menyalakan pompa kalau air di bawah batas minimum
    final bool turningOn =
        (a &&
            !_pumpA) ||
        (b &&
            !_pumpB);
    if (turningOn &&
        _sensorData.waterLevelPct <
            _minWaterLevel) {
      debugPrint(
        'Pompa ditolak: level air di bawah batas minimum.',
      );
      return;
    }

    _pumpA = a;
    _pumpB = b;

    // Update UI responsif secara langsung
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      pumpStatus:
          (a ||
              b)
          ? 'ON'
          : 'OFF',
      mode: _sensorData.mode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();

    // Kirim ke Firebase. 'pompa' tetap dikirim (A atau B menyala)
    // agar firmware lama tidak rusak.
    try {
      await _db
          .ref(
            'hydrosmart/kontrol',
          )
          .update({
            'pompa':
                a ||
                b,
            'pompa_a': a,
            'pompa_b': b,
          });
    } catch (
      e
    ) {
      debugPrint(
        'Error update pompa ke Firebase: $e',
      );
    }
  }

  // ───────────────────────── SIMULASI (fallback) ─────────────────────────
  void _startTelemetrySimulation() {
    _simulationTimer = Timer.periodic(
      const Duration(
        seconds: 3,
      ),
      (
        timer,
      ) {
        final random = Random();
        double newLevel = _sensorData.waterLevelPct;

        if (_sensorData.pumpStatus.contains(
          'ON',
        )) {
          newLevel = min(
            100,
            newLevel +
                2.0,
          );
          if (newLevel >=
                  _maxWaterLevel &&
              _sensorData.mode ==
                  'AUTO') {
            _pumpA = false;
            _pumpB = false;
            _sensorData = SensorData(
              tdsPpm: _sensorData.tdsPpm,
              waterLevelPct: newLevel,
              pumpStatus: 'OFF',
              mode: _sensorData.mode,
              isOnline: _sensorData.isOnline,
              lastUpdated: DateTime.now(),
            );
          }
        } else {
          newLevel = max(
            10,
            newLevel -
                0.1,
          );
        }

        _sensorData = SensorData(
          tdsPpm:
              660 +
              random.nextDouble() *
                  40,
          waterLevelPct: newLevel,
          pumpStatus: _sensorData.pumpStatus,
          mode: _sensorData.mode,
          isOnline: true,
          lastUpdated: DateTime.now(),
        );
        _recordSample();
        notifyListeners();
      },
    );
  }

  // ───────────────────────── FIREBASE LISTENER ─────────────────────────
  void _initFirebaseListener() {
    try {
      final database = _db;

      // 1. Data realtime di node 'hydrosmart/terbaru'
      _firebaseSubscription = database
          .ref(
            'hydrosmart/terbaru',
          )
          .onValue
          .listen(
            (
              DatabaseEvent event,
            ) {
              if (event.snapshot.exists &&
                  event.snapshot.value !=
                      null) {
                final data = event.snapshot.value;
                if (data
                    is Map) {
                  final double level =
                      (data['level']
                              as num?)
                          ?.toDouble() ??
                      _sensorData.waterLevelPct;
                  final bool pompa =
                      data['pompa'] ==
                      true;
                  final double tds =
                      (data['tds']
                              as num?)
                          ?.toDouble() ??
                      _sensorData.tdsPpm;
                  final String? mode = data['mode']?.toString().toUpperCase();

                  // [BARU] Status pompa A/B dari ESP32 (jika firmware sudah mengirim)
                  final bool? tA =
                      data['pompa_a']
                          is bool
                      ? data['pompa_a']
                            as bool
                      : null;
                  final bool? tB =
                      data['pompa_b']
                          is bool
                      ? data['pompa_b']
                            as bool
                      : null;
                  if (tA !=
                          null ||
                      tB !=
                          null) {
                    _pumpA =
                        tA ??
                        _pumpA;
                    _pumpB =
                        tB ??
                        _pumpB;
                  } else {
                    // Firmware lama: hanya ada satu status 'pompa'
                    if (!pompa) {
                      _pumpA = false;
                      _pumpB = false;
                    } else if (!_pumpA &&
                        !_pumpB) {
                      _pumpA = true;
                      _pumpB = true;
                    }
                  }

                  DateTime updatedTime = DateTime.now();
                  if (data['waktu'] !=
                      null) {
                    final int timestamp =
                        (data['waktu']
                                as num)
                            .toInt();
                    if (timestamp >
                        10000000000) {
                      updatedTime = DateTime.fromMillisecondsSinceEpoch(
                        timestamp,
                      );
                    } else if (timestamp >
                        0) {
                      updatedTime = DateTime.fromMillisecondsSinceEpoch(
                        timestamp *
                            1000,
                      );
                    }
                  }

                  _sensorData = SensorData(
                    tdsPpm: tds,
                    waterLevelPct: level,
                    pumpStatus:
                        (pompa ||
                            _pumpA ||
                            _pumpB)
                        ? 'ON'
                        : 'OFF',
                    mode:
                        mode ??
                        _sensorData.mode,
                    isOnline: true,
                    lastUpdated: updatedTime,
                  );
                  _recordSample();
                  notifyListeners();
                }
              }
            },
            onError:
                (
                  error,
                ) {
                  debugPrint(
                    'Firebase Database Error (hydrosmart/terbaru): $error',
                  );
                },
          );

      // 2. Node 'hydrosmart/kontrol' agar status kontrol di HP selalu sinkron
      _kontrolSubscription = database
          .ref(
            'hydrosmart/kontrol',
          )
          .onValue
          .listen(
            (
              event,
            ) {
              if (event.snapshot.exists &&
                  event.snapshot.value !=
                      null) {
                final data = event.snapshot.value;
                if (data
                    is Map) {
                  final String? kMode = data['mode']?.toString().toUpperCase();
                  final bool kPompa =
                      data['pompa'] ==
                      true;
                  final bool? kA =
                      data['pompa_a']
                          is bool
                      ? data['pompa_a']
                            as bool
                      : null;
                  final bool? kB =
                      data['pompa_b']
                          is bool
                      ? data['pompa_b']
                            as bool
                      : null;

                  final bool modeChanged =
                      kMode !=
                          null &&
                      kMode !=
                          _sensorData.mode;
                  bool a = _pumpA;
                  bool b = _pumpB;

                  if (kA !=
                          null ||
                      kB !=
                          null) {
                    a =
                        kA ??
                        a;
                    b =
                        kB ??
                        b;
                  } else if (modeChanged) {
                    // Data lama tanpa A/B: pakai satu status 'pompa' untuk keduanya
                    a = b =
                        (kMode ==
                            'MANUAL' &&
                        kPompa);
                  }

                  final bool pumpChanged =
                      a !=
                          _pumpA ||
                      b !=
                          _pumpB;

                  if (modeChanged ||
                      pumpChanged) {
                    _pumpA = a;
                    _pumpB = b;
                    final String newMode =
                        kMode ??
                        _sensorData.mode;
                    _sensorData = SensorData(
                      tdsPpm: _sensorData.tdsPpm,
                      waterLevelPct: _sensorData.waterLevelPct,
                      pumpStatus:
                          newMode ==
                              'MANUAL'
                          ? ((a ||
                                    b)
                                ? 'ON'
                                : 'OFF')
                          : _sensorData.pumpStatus,
                      mode: newMode,
                      isOnline: _sensorData.isOnline,
                      lastUpdated: _sensorData.lastUpdated,
                    );
                    notifyListeners();
                  }
                }
              }
            },
            onError:
                (
                  error,
                ) {
                  debugPrint(
                    'Firebase Database Error (hydrosmart/kontrol): $error',
                  );
                },
          );
    } catch (
      e
    ) {
      debugPrint(
        'Error init Firebase listener: $e',
      );
      _startTelemetrySimulation();
    }
  }

  @override
  void dispose() {
    _firebaseSubscription?.cancel();
    _kontrolSubscription?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }
}
