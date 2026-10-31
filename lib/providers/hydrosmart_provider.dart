import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../firebase_options.dart';
import '../models/sensor_data.dart';

enum UserRole { penampil, operator, admin }

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

class HydroSmartProvider extends ChangeNotifier {
  UserRole _currentRole = UserRole.admin;
  late SensorData _sensorData;
  Timer? _simulationTimer;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;
  StreamSubscription<DatabaseEvent>? _kontrolSubscription;

  double _minWaterLevel = 30.0;
  double _maxWaterLevel = 80.0;
  int _currentHst = 18; // Hari Setelah Tanam

  final List<PlantNote> _plantNotes = [
    PlantNote(date: '2026-10-20', hst: 14, height: 12.5, leaves: 6),
    PlantNote(date: '2026-10-24', hst: 18, height: 16.2, leaves: 8),
  ];

  UserRole get currentRole => _currentRole;
  SensorData get sensorData => _sensorData;
  double get minWaterLevel => _minWaterLevel;
  double get maxWaterLevel => _maxWaterLevel;
  int get currentHst => _currentHst;
  List<PlantNote> get plantNotes => _plantNotes;

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

  void setRole(UserRole role) {
    _currentRole = role;
    notifyListeners();
  }

  void setThresholds(double minLvl, double maxLvl) {
    _minWaterLevel = minLvl;
    _maxWaterLevel = maxLvl;
    notifyListeners();
  }

  void addPlantNote(PlantNote note) {
    _plantNotes.add(note);
    notifyListeners();
  }

  Future<void> toggleMode() async {
    if (_currentRole == UserRole.penampil) return;
    String newMode = _sensorData.mode == 'AUTO' ? 'MANUAL' : 'AUTO';

    // Update UI responsif secara langsung
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      pumpStatus: newMode == 'AUTO' ? 'OFF' : _sensorData.pumpStatus,
      mode: newMode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();

    // Kirim perintah mode ke Firebase node 'hydrosmart/kontrol'
    try {
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      );
      await database.ref('hydrosmart/kontrol').update({
        'mode': newMode.toLowerCase(),
      });
    } catch (e) {
      debugPrint('Error update mode ke Firebase: $e');
    }
  }

  Future<void> togglePump() async {
    if (_currentRole == UserRole.penampil) return;
    if (_sensorData.mode == 'AUTO') return;

    bool targetPompa = _sensorData.pumpStatus != 'ON';
    String newStatus = targetPompa ? 'ON' : 'OFF';

    // Update UI responsif secara langsung
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      pumpStatus: newStatus,
      mode: _sensorData.mode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();

    // Kirim perintah pompa ke Firebase node 'hydrosmart/kontrol'
    try {
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      );
      await database.ref('hydrosmart/kontrol').update({
        'pompa': targetPompa,
      });
    } catch (e) {
      debugPrint('Error update pompa ke Firebase: $e');
    }
  }

  void _startTelemetrySimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final random = Random();
      double newLevel = _sensorData.waterLevelPct;

      if (_sensorData.pumpStatus.contains('ON')) {
        newLevel = min(100, newLevel + 2.0);
        if (newLevel >= _maxWaterLevel && _sensorData.mode == 'AUTO') {
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
        newLevel = max(10, newLevel - 0.1);
      }

      _sensorData = SensorData(
        tdsPpm: 660 + random.nextDouble() * 40,
        waterLevelPct: newLevel,
        pumpStatus: _sensorData.pumpStatus,
        mode: _sensorData.mode,
        isOnline: true,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
    });
  }

  void _initFirebaseListener() {
    try {
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      );

      // 1. Mendengarkan data realtime di node 'hydrosmart/terbaru'
      _firebaseSubscription = database
          .ref('hydrosmart/terbaru')
          .onValue
          .listen((DatabaseEvent event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          final data = event.snapshot.value;
          if (data is Map) {
            final double level = (data['level'] as num?)?.toDouble() ?? _sensorData.waterLevelPct;
            final bool pompa = data['pompa'] == true;
            final double tds = (data['tds'] as num?)?.toDouble() ?? _sensorData.tdsPpm;
            final String? mode = data['mode']?.toString().toUpperCase();

            DateTime updatedTime = DateTime.now();
            if (data['waktu'] != null) {
              final int timestamp = (data['waktu'] as num).toInt();
              if (timestamp > 10000000000) {
                updatedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              } else if (timestamp > 0) {
                updatedTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
              }
            }

            _sensorData = SensorData(
              tdsPpm: tds,
              waterLevelPct: level,
              pumpStatus: pompa ? 'ON' : 'OFF',
              mode: mode ?? _sensorData.mode,
              isOnline: true,
              lastUpdated: updatedTime,
            );
            notifyListeners();
          }
        }
      }, onError: (error) {
        debugPrint('Firebase Database Error (hydrosmart/terbaru): $error');
      });

      // 2. Mendengarkan node 'hydrosmart/kontrol' agar status kontrol di HP selalu sinkron
      _kontrolSubscription = database.ref('hydrosmart/kontrol').onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          final data = event.snapshot.value;
          if (data is Map) {
            final String? kMode = data['mode']?.toString().toUpperCase();
            final bool? kPompa = data['pompa'] == true;

            if (kMode != null && kMode != _sensorData.mode) {
              _sensorData = SensorData(
                tdsPpm: _sensorData.tdsPpm,
                waterLevelPct: _sensorData.waterLevelPct,
                pumpStatus: (kMode == 'MANUAL' && kPompa != null)
                    ? (kPompa ? 'ON' : 'OFF')
                    : _sensorData.pumpStatus,
                mode: kMode,
                isOnline: _sensorData.isOnline,
                lastUpdated: _sensorData.lastUpdated,
              );
              notifyListeners();
            }
          }
        }
      }, onError: (error) {
        debugPrint('Firebase Database Error (hydrosmart/kontrol): $error');
      });
    } catch (e) {
      debugPrint('Error init Firebase listener: $e');
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

