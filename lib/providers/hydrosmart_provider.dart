import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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
      tdsPpm: 680,
      waterLevelPct: 75,
      waterTempC: 27.5,
      pumpStatus: 'OFF',
      mode: 'AUTO',
      isOnline: true,
      lastUpdated: DateTime.now(),
    );
    _startTelemetrySimulation();
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

  void toggleMode() {
    if (_currentRole == UserRole.penampil) return;
    String newMode = _sensorData.mode == 'AUTO' ? 'MANUAL' : 'AUTO';
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      waterTempC: _sensorData.waterTempC,
      pumpStatus: newMode == 'AUTO' ? 'OFF' : _sensorData.pumpStatus,
      mode: newMode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
  }

  void togglePump() {
    if (_currentRole == UserRole.penampil) return;
    if (_sensorData.mode == 'AUTO') return;

    String newStatus = _sensorData.pumpStatus == 'OFF' ? 'ON' : 'OFF';
    _sensorData = SensorData(
      tdsPpm: _sensorData.tdsPpm,
      waterLevelPct: _sensorData.waterLevelPct,
      waterTempC: _sensorData.waterTempC,
      pumpStatus: newStatus,
      mode: _sensorData.mode,
      isOnline: _sensorData.isOnline,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
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
            waterTempC: _sensorData.waterTempC,
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
        waterTempC: 26.8 + random.nextDouble() * 1.5,
        pumpStatus: _sensorData.pumpStatus,
        mode: _sensorData.mode,
        isOnline: true,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}
