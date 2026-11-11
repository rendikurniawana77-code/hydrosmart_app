/// Satu titik data pada grafik riwayat telemetri.
class TelemetrySample {
  const TelemetrySample({
    required this.time,
    required this.tds,
    required this.waterPct,
  });

  /// Waktu data DITERIMA aplikasi (bukan jam ESP32), supaya tidak terpengaruh
  /// beda jam HP/ESP32 (sama seperti pendekatan di ar_monitoring_screen).
  final DateTime time;

  /// TDS dalam ppm.
  final double tds;

  /// Level air dalam persen.
  final double waterPct;
}