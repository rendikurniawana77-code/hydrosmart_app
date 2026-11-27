import 'telemetry_sample.dart';

enum HistoryRange {
  hours24(Duration(hours: 24), '24 jam', Duration(minutes: 5)),
  days5(Duration(days: 5), '5 hari', Duration(minutes: 15)),
  days7(Duration(days: 7), '7 hari', Duration(minutes: 30)),
  days14(Duration(days: 14), '14 hari', Duration(hours: 1)),
  days30(Duration(days: 30), '30 hari', Duration(hours: 2));

  const HistoryRange(this.duration, this.label, this.bucketDuration);

  final Duration duration;
  final String label;
  final Duration bucketDuration;
}

const double minimumValidTdsPpm = 50;
const double targetTdsMinimumPpm = 600;
const double targetTdsMaximumPpm = 800;

class AggregatedTelemetry {
  const AggregatedTelemetry({required this.time, this.tds, this.waterPct});

  final DateTime time;
  final double? tds;
  final double? waterPct;
}

List<AggregatedTelemetry> aggregateTelemetry(
  Iterable<TelemetrySample> samples,
  HistoryRange range,
) {
  final bucketMilliseconds = range.bucketDuration.inMilliseconds;
  final buckets = <int, _TelemetryBucket>{};

  for (final sample in samples) {
    final bucket = sample.time.millisecondsSinceEpoch ~/ bucketMilliseconds;
    final values = buckets.putIfAbsent(bucket, _TelemetryBucket.new);
    final tds = sample.tds;
    if (tds != null && tds >= minimumValidTdsPpm) {
      values.tdsTotal += tds;
      values.tdsCount++;
    }
    final water = sample.waterPct;
    if (water != null) {
      values.waterTotal += water;
      values.waterCount++;
    }
    values.timeTotal += sample.time.millisecondsSinceEpoch.toDouble();
    values.timeCount++;
  }

  return buckets.values
      .where((bucket) => bucket.tdsCount > 0 || bucket.waterCount > 0)
      .map(
        (bucket) => AggregatedTelemetry(
          time: DateTime.fromMillisecondsSinceEpoch(
            (bucket.timeTotal / bucket.timeCount).round(),
          ),
          tds: bucket.tdsCount == 0 ? null : bucket.tdsTotal / bucket.tdsCount,
          waterPct: bucket.waterCount == 0
              ? null
              : bucket.waterTotal / bucket.waterCount,
        ),
      )
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
}

class _TelemetryBucket {
  double tdsTotal = 0;
  int tdsCount = 0;
  double waterTotal = 0;
  int waterCount = 0;
  double timeTotal = 0;
  int timeCount = 0;
}
