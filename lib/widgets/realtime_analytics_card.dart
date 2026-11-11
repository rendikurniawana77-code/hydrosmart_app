import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/telemetry_sample.dart';

enum _Metric { tds, water }

const _tdsColor = Color(0xFF059669);
const _waterColor = Color(0xFF0284C7);
const _slate100 = Color(0xFFF1F5F9);
const _slate400 = Color(0xFF94A3B8);
const _slate600 = Color(0xFF475569);
const _slate800 = Color(0xFF1E293B);

/// Kartu "Analitik Lingkungan Waktu Nyata".
/// Hanya menampilkan; data dan riwayat dikelola oleh HydroSmartProvider.
class RealtimeAnalyticsCard extends StatefulWidget {
  const RealtimeAnalyticsCard({
    super.key,
    required this.samples,
    this.lastSampleAt,
    this.maxPoints = 15,
    this.staleAfter = const Duration(seconds: 30),
  });

  /// Riwayat dari yang terlama ke terbaru.
  final List<TelemetrySample> samples;

  /// Kapan data terakhir diterima; dipakai untuk tanda "data tertunda" (FR-25).
  final DateTime? lastSampleAt;

  /// Jumlah titik terakhir yang digambar (web: 15).
  final int maxPoints;

  final Duration staleAfter;

  @override
  State<RealtimeAnalyticsCard> createState() => _RealtimeAnalyticsCardState();
}

class _RealtimeAnalyticsCardState extends State<RealtimeAnalyticsCard> {
  _Metric _metric = _Metric.tds;
  Timer? _timer;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _stale = _computeStale();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _computeStale();
      if (s != _stale && mounted) setState(() => _stale = s);
    });
  }

  @override
  void didUpdateWidget(covariant RealtimeAnalyticsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastSampleAt != widget.lastSampleAt) {
      _stale = _computeStale();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _computeStale() {
    final last = widget.lastSampleAt;
    if (last == null) return false;
    return DateTime.now().difference(last) > widget.staleAfter;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmt(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  List<TelemetrySample> get _shown {
    final s = widget.samples;
    return s.length > widget.maxPoints ? s.sublist(s.length - widget.maxPoints) : s;
  }

  String _subtitle(List<TelemetrySample> s) {
    if (s.length < 2) return 'Stream data telemetri dari ESP32';
    final avg = s.last.time.difference(s.first.time).inMilliseconds / (s.length - 1) / 1000;
    final secs = math.max(1, avg.round());
    return 'Stream data telemetri (diperbarui sekitar tiap $secs detik)';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x260284C7)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F0284C7), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analitik Lingkungan Waktu Nyata',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _slate800),
          ),
          const SizedBox(height: 2),
          Text(_subtitle(shown), style: const TextStyle(fontSize: 11, color: _slate400)),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricChip(
                label: 'TDS (PPM)',
                selected: _metric == _Metric.tds,
                activeColor: const Color(0xFF10B981),
                onTap: () => setState(() => _metric = _Metric.tds),
              ),
              const SizedBox(width: 8),
              _MetricChip(
                label: 'Water Level (%)',
                selected: _metric == _Metric.water,
                activeColor: const Color(0xFF0EA5E9),
                onTap: () => setState(() => _metric = _Metric.water),
              ),
            ],
          ),
          if (_stale && widget.lastSampleAt != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF92400E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Data tertunda. Terakhir diterima ${_fmt(widget.lastSampleAt!)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: shown.length < 2
                ? const Center(
                    child: Text('Menunggu data telemetri...',
                        style: TextStyle(fontSize: 12, color: _slate400)),
                  )
                : LineChart(_chartData(shown)),
          ),
          if (shown.length >= 2) ...[
            const SizedBox(height: 12),
            _buildSummary(shown),
          ],
        ],
      ),
    );
  }

  /// Ringkasan angka dari titik yang sedang digambar di grafik.
  Widget _buildSummary(List<TelemetrySample> shown) {
    final isTds = _metric == _Metric.tds;
    final color = isTds ? _tdsColor : _waterColor;
    final values = shown.map((s) => isTds ? s.tds : s.waterPct).toList();

    final last = values.last;
    final avg = values.reduce((a, b) => a + b) / values.length;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);

    final unit = isTds ? 'ppm' : '%';
    String fmtVal(double v) => '${v.toStringAsFixed(isTds ? 0 : 1)} $unit';

    // Tren: nilai terakhir dibanding rata-rata (maks. 4) titik sebelumnya.
    // Ambang dianggap "stabil" (silakan ubah): TDS 3 ppm, level 0,5 %.
    final prev = values.sublist(math.max(0, values.length - 5), values.length - 1);
    final prevAvg = prev.reduce((a, b) => a + b) / prev.length;
    final diff = last - prevAvg;
    final threshold = isTds ? 3.0 : 0.5;

    final IconData trendIcon;
    final String trendLabel;
    if (diff > threshold) {
      trendIcon = Icons.trending_up;
      trendLabel = 'naik';
    } else if (diff < -threshold) {
      trendIcon = Icons.trending_down;
      trendLabel = 'turun';
    } else {
      trendIcon = Icons.trending_flat;
      trendLabel = 'stabil';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SummaryStat(label: 'Terakhir', value: fmtVal(last)),
              _SummaryStat(label: 'Rata-rata', value: fmtVal(avg)),
              _SummaryStat(label: 'Min', value: fmtVal(minV)),
              _SummaryStat(label: 'Maks', value: fmtVal(maxV)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(trendIcon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                'Tren: $trendLabel',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
              const Spacer(),
              Text(
                '${_fmt(shown.first.time)} - ${_fmt(shown.last.time)} (${shown.length} titik)',
                style: const TextStyle(fontSize: 10, color: _slate400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LineChartData _chartData(List<TelemetrySample> shown) {
    final isTds = _metric == _Metric.tds;
    final color = isTds ? _tdsColor : _waterColor;
    final values = shown.map((s) => isTds ? s.tds : s.waterPct).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final pad = math.max((maxV - minV) * 0.15, isTds ? 2.0 : 0.5);

    const labelStyle = TextStyle(fontSize: 10, color: _slate400);

    return LineChartData(
      minX: 0,
      maxX: (values.length - 1).toDouble(),
      minY: minV - pad,
      maxY: maxV + pad,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => const FlLine(color: _slate100, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(meta.formattedValue, style: labelStyle),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            interval: 2, // label selang-seling seperti di web
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= shown.length || (value - i).abs() > 0.001) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Transform.rotate(
                  angle: -0.5,
                  child: Text(_fmt(shown[i].time), style: labelStyle),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: color,
            ),
          ),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _slate400)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _slate800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? activeColor : _slate100,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _slate600,
            ),
          ),
        ),
      ),
    );
  }
}