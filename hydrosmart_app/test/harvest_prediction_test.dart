import 'package:flutter_test/flutter_test.dart';
import 'package:hydrosmart_app/models/harvest_prediction.dart';

void main() {
  test('parses the SC latest prediction payload', () {
    final prediction = HarvestPrediction.fromMap({
      'status': 'berjalan',
      'kanal_prediksi': 'level+tds (gabungan)',
      'hari_ke': 14,
      'hari0': 1800000000,
      'indeks_kesiapan': 46.5,
      'estimasi_hari': 31.0,
      'rentang_hari_min': 28.0,
      'rentang_hari_maks': 36.0,
      'tanggal_panen': '2026-12-13',
      'tanggal_min': '2026-12-10',
      'tanggal_maks': '2026-12-17',
      'kualitas': 'sedang',
      'diperbarui': 1800100000,
    });

    expect(prediction.status, 'berjalan');
    expect(prediction.channel, 'level+tds (gabungan)');
    expect(prediction.dayIndex, 14);
    expect(prediction.dayZero?.millisecondsSinceEpoch, 1800000000000);
    expect(prediction.readinessPercent, 46.5);
    expect(prediction.estimatedHarvestDay, 31.0);
    expect(prediction.rangeStartDay, 28.0);
    expect(prediction.rangeEndDay, 36.0);
    expect(prediction.rangeStartDate, '2026-12-10');
    expect(prediction.rangeEndDate, '2026-12-17');
  });

  test('accepts numeric strings and missing prediction fields', () {
    final prediction = HarvestPrediction.fromMap({
      'hari_ke': '14',
      'indeks_kesiapan': '46.5',
    });

    expect(prediction.dayIndex, 14);
    expect(prediction.readinessPercent, 46.5);
    expect(prediction.estimatedHarvestDay, isNull);
  });
}
