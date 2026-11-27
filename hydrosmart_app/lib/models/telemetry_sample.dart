/// Satu titik data pada grafik riwayat telemetri.
class TelemetrySample {
  const TelemetrySample({required this.time, this.tds, this.waterPct});

  /// Timestamp sensor ESP32, dipakai untuk mengurutkan rekam riwayat.
  final DateTime time;

  /// TDS dalam ppm; null jika probe tidak valid.
  final double? tds;

  /// Level air dalam persen; null jika sensor tidak valid.
  final double? waterPct;
}
