import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/history_range.dart';
import '../models/telemetry_sample.dart';

enum _Metric { water, tds }

const _blue = Color(0xFF279FD5);
const _green = Color(0xFF58B77D);
const _ink = Color(0xFF203746);
const _muted = Color(0xFF718493);
const _grid = Color(0xFFE5EDF1);

class HistoryAnalyticsCard extends StatefulWidget {
  const HistoryAnalyticsCard({
    super.key,
    required this.samples,
    required this.range,
    required this.loading,
    required this.error,
    required this.onRangeChanged,
    required this.onRefresh,
  });

  final List<TelemetrySample> samples;
  final HistoryRange range;
  final bool loading;
  final String? error;
  final ValueChanged<HistoryRange> onRangeChanged;
  final VoidCallback onRefresh;

  @override
  State<HistoryAnalyticsCard> createState() => _HistoryAnalyticsCardState();
}

class _HistoryAnalyticsCardState extends State<HistoryAnalyticsCard> {
  _Metric _metric = _Metric.tds;

  List<AggregatedTelemetry> get _points =>
      aggregateTelemetry(widget.samples, widget.range);

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final hasMetricValues = points.any(
      (point) =>
          _metric == _Metric.tds ? point.tds != null : point.waterPct != null,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1F279FD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5FA),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.show_chart, size: 18, color: _blue),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Grafik perkembangan',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang riwayat',
                onPressed: widget.loading ? null : widget.onRefresh,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 19),
                color: _muted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _MetricChip(
                label: 'Air',
                selected: _metric == _Metric.water,
                onTap: () => setState(() => _metric = _Metric.water),
              ),
              _MetricChip(
                label: 'Nutrisi (TDS)',
                selected: _metric == _Metric.tds,
                onTap: () => setState(() => _metric = _Metric.tds),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final range in HistoryRange.values)
                _RangeChip(
                  label: range.label,
                  selected: range == widget.range,
                  onTap: () => widget.onRangeChanged(range),
                ),
            ],
          ),
          if (widget.loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 2,
              color: _blue,
              backgroundColor: Color(0xFFEAF5FA),
            ),
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.cloud_off, size: 15, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    points.isEmpty
                        ? 'Tidak dapat memuat riwayat. Periksa koneksi lalu coba lagi.'
                        : 'Menampilkan cache lokal. Sinkronisasi belum berhasil.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 230,
            child: !hasMetricValues
                ? Center(
                    child: Text(
                      widget.loading
                          ? 'Mengambil riwayat dari Firebase...'
                          : 'Belum ada data pada rentang ini.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  )
                : LineChart(_chartData(points)),
          ),
          if (_metric == _Metric.tds) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.18),
                    border: Border.all(color: _green),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Target nutrisi 600–800 ppm',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${points.length} kelompok · rata-rata ${widget.range.bucketDuration.inMinutes >= 60 ? '${widget.range.bucketDuration.inHours} jam' : '${widget.range.bucketDuration.inMinutes} menit'}',
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }

  LineChartData _chartData(List<AggregatedTelemetry> points) {
    final isTds = _metric == _Metric.tds;
    final color = isTds ? _green : _blue;
    final values = points
        .map((point) => isTds ? point.tds : point.waterPct)
        .whereType<double>()
        .toList();
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final padding = math.max((high - low) * 0.15, isTds ? 20.0 : 2.0);
    final minY = isTds
        ? math.min(low - padding, targetTdsMinimumPpm - 200)
        : math.max(0.0, low - padding);
    final maxY = isTds
        ? math.max(high + padding, targetTdsMaximumPpm + 200)
        : math.min(100.0, high + padding);
    final end = DateTime.now();
    final start = end.subtract(widget.range.duration);
    final minX = start.millisecondsSinceEpoch / 1000;
    final maxX = end.millisecondsSinceEpoch / 1000;
    final interval = (maxX - minX) / 4;

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY <= minY ? minY + 1 : maxY,
      clipData: const FlClipData.all(),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: _grid, strokeWidth: 1),
      ),
      rangeAnnotations: isTds
          ? RangeAnnotations(
              horizontalRangeAnnotations: [
                HorizontalRangeAnnotation(
                  y1: targetTdsMinimumPpm,
                  y2: targetTdsMaximumPpm,
                  color: _green.withValues(alpha: 0.14),
                ),
              ],
            )
          : const RangeAnnotations(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(isTds ? 0 : 0),
              style: const TextStyle(fontSize: 9, color: _muted),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: interval,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                _axisLabel(
                  DateTime.fromMillisecondsSinceEpoch((value * 1000).round()),
                ),
                style: const TextStyle(fontSize: 9, color: _muted),
              ),
            ),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map(
                (spot) => LineTooltipItem(
                  '${_tooltipDate(DateTime.fromMillisecondsSinceEpoch((spot.x * 1000).round()))} · ${spot.y.toStringAsFixed(isTds ? 0 : 1)} ${isTds ? 'ppm' : '%'}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              .toList(),
        ),
      ),
      lineBarsData: _lineSegments(points, isTds, color),
    );
  }

  List<LineChartBarData> _lineSegments(
    List<AggregatedTelemetry> points,
    bool isTds,
    Color color,
  ) {
    final lines = <LineChartBarData>[];
    var segment = <FlSpot>[];

    void addSegment() {
      if (segment.isNotEmpty) {
        lines.add(
          LineChartBarData(
            spots: segment,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: segment.length < 3),
            belowBarData: BarAreaData(show: false),
          ),
        );
        segment = <FlSpot>[];
      }
    }

    for (final point in points) {
      final value = isTds ? point.tds : point.waterPct;
      if (value == null) {
        addSegment();
      } else {
        segment.add(FlSpot(point.time.millisecondsSinceEpoch / 1000, value));
      }
    }
    addSegment();
    return lines;
  }

  String _axisLabel(DateTime date) => widget.range == HistoryRange.hours24
      ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : '${date.day} ${_month(date.month)}';

  String _tooltipDate(DateTime date) =>
      '${date.day} ${_month(date.month)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _month(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ][month - 1];
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        foregroundColor: selected ? const Color(0xFF1874A2) : _ink,
        backgroundColor: selected ? const Color(0xFFEAF5FA) : Colors.white,
        side: BorderSide(color: selected ? _blue : const Color(0xFFDCE8EE)),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        foregroundColor: selected ? const Color(0xFF1874A2) : _ink,
        backgroundColor: selected ? const Color(0xFFEAF5FA) : Colors.white,
        side: BorderSide(color: selected ? _blue : const Color(0xFFDCE8EE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
