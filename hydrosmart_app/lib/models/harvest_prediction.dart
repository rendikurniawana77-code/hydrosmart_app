  class HarvestPrediction {
  const HarvestPrediction({
    this.status,
    this.channel,
    this.dayIndex,
    this.dayZero,
    this.readinessPercent,
    this.estimatedHarvestDay,
    this.rangeStartDay,
    this.rangeEndDay,
    this.estimatedHarvestDate,
    this.rangeStartDate,
    this.rangeEndDate,
    this.quality,
    this.updatedAt,
  });

  final String? status;
  final String? channel;
  final int? dayIndex;
  final DateTime? dayZero;
  final double? readinessPercent;
  final double? estimatedHarvestDay;
  final double? rangeStartDay;
  final double? rangeEndDay;
  final String? estimatedHarvestDate;
  final String? rangeStartDate;
  final String? rangeEndDate;
  final String? quality;
  final DateTime? updatedAt;

  factory HarvestPrediction.fromMap(Map<dynamic, dynamic> data) {
    return HarvestPrediction(
      status: data['status']?.toString(),
      channel: data['kanal_prediksi']?.toString(),
      dayIndex: _asInt(data['hari_ke']),
      dayZero: _epochDate(data['hari0']),
      readinessPercent: _asDouble(data['indeks_kesiapan']),
      estimatedHarvestDay: _asDouble(data['estimasi_hari']),
      rangeStartDay: _asDouble(data['rentang_hari_min']),
      rangeEndDay: _asDouble(data['rentang_hari_maks']),
      estimatedHarvestDate: data['tanggal_panen']?.toString(),
      rangeStartDate: data['tanggal_min']?.toString(),
      rangeEndDate: data['tanggal_maks']?.toString(),
      quality: data['kualitas']?.toString(),
      updatedAt: _epochDate(data['diperbarui']),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _epochDate(dynamic value) {
    final epoch = _asDouble(value);
    if (epoch == null || epoch <= 0) return null;
    final milliseconds = epoch > 10000000000
        ? epoch.toInt()
        : (epoch * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
