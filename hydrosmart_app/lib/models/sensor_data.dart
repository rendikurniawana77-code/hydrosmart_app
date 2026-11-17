class SensorData {
  final double tdsPpm;
  final double waterLevelPct;
  final String pumpStatus;
  final String mode;
  final bool isOnline;
  final DateTime lastUpdated;

  SensorData({
    required this.tdsPpm,
    required this.waterLevelPct,
    required this.pumpStatus,
    required this.mode,
    required this.isOnline,
    required this.lastUpdated,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      tdsPpm: (json['tds_ppm'] ?? 0).toDouble(),
      waterLevelPct: (json['water_level_pct'] ?? 0).toDouble(),
      pumpStatus: json['pump_status'] ?? 'OFF',
      mode: json['mode'] ?? 'AUTO',
      isOnline: json['is_online'] ?? true,
      lastUpdated: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tds_ppm': tdsPpm,
      'water_level_pct': waterLevelPct,
      'pump_status': pumpStatus,
      'mode': mode,
      'is_online': isOnline,
      'timestamp': lastUpdated.toIso8601String(),
    };
  }
}