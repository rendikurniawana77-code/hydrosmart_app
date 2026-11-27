import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';
import '../widgets/history_analytics_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _green = Color(0xFF059669);
  static const _blue = Color(0xFF0284C7);
  static const _ink = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HydroSmartProvider>();
    final canControl = provider.currentRole != UserRole.penampil;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final status = _buildStatusCard(provider, canControl: canControl);
          final panel = _buildTopPanel(provider);

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 10),
                _buildHarvestPrediction(provider),
                const SizedBox(height: 10),
                panel,
                const SizedBox(height: 16),
                HistoryAnalyticsCard(
                  samples: provider.history,
                  range: provider.historyRange,
                  loading: provider.historyLoading,
                  error: provider.historyError,
                  onRangeChanged: provider.loadHistoryRange,
                  onRefresh: provider.refreshHistory,
                ),
                const SizedBox(height: 10),
                _buildPlantingDateInput(provider, canEdit: canControl),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── STATUS CARD (ringkas) ─────────────────────────
  Widget _buildStatusCard(
    HydroSmartProvider provider, {
    required bool canControl,
  }) {
    final sensor = provider.sensorData;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_green, _blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sensor.isOnline ? 'ESP32 ONLINE' : 'ESP32 OFFLINE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  sensor.mode,
                  style: TextStyle(
                    color: sensor.mode == 'AUTO' ? _green : _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kangkung DFT · ${provider.currentHst} HST',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (canControl) ...[
            const SizedBox(height: 10),
            _buildControlPanel(provider),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── MONITORING SENSOR ─────────────────────────
  Widget _buildTopPanel(HydroSmartProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Text(
              'Monitoring Sensor DFT',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
          ),
          _buildSensorPage(provider),
        ],
      ),
    );
  }

  Widget _buildSensorPage(HydroSmartProvider provider) {
    final sensor = provider.sensorData;
    final lowWater = sensor.waterLevelPct < provider.minWaterLevel;
    final pumpOn = sensor.pumpStatus.contains('ON');

    return Column(
      children: [
        SizedBox(
          height: 132,
          child: Row(
            children: [
              Expanded(
                child: _sensorCard(
                  'Nutrisi TDS',
                  '${sensor.tdsPpm.toStringAsFixed(0)} ppm',
                  Icons.bolt,
                  _blue,
                  'Target: 600 - 800 ppm',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sensorCard(
                  'Level Air',
                  '${sensor.waterLevelPct.toStringAsFixed(1)}%',
                  Icons.water_drop,
                  lowWater ? Colors.redAccent : _green,
                  'Batas: ${provider.minWaterLevel.toInt()}% - ${provider.maxWaterLevel.toInt()}%',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (pumpOn ? _green : Colors.grey).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.power, size: 16, color: pumpOn ? _green : Colors.grey),
              const SizedBox(width: 8),
              const Text(
                'Status Pompa',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                sensor.pumpStatus,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: pumpOn ? _green : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sensorCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String sub,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // ─────────────────────── PREDIKSI PANEN FIREBASE ───────────────────────
  Widget _buildHarvestPrediction(HydroSmartProvider provider) {
    final prediction = provider.harvestPrediction;
    final day = prediction?.dayIndex ?? provider.currentHst;
    final rangeStart =
        prediction?.rangeStartDay ??
        prediction?.estimatedHarvestDay ??
        day.toDouble();
    final rangeEnd =
        prediction?.rangeEndDay ??
        prediction?.estimatedHarvestDay ??
        day.toDouble();
    final timelineEnd =
        [day.toDouble(), rangeEnd, 1.0].reduce((a, b) => a > b ? a : b) * 1.08;
    final progress = (day / timelineEnd).clamp(0.0, 1.0);
    final rangeStartProgress = (rangeStart / timelineEnd).clamp(0.0, 1.0);
    final rangeEndProgress = (rangeEnd / timelineEnd).clamp(0.0, 1.0);
    final status = switch (prediction?.status) {
      'berjalan' => 'Prediksi aktif',
      'selesai' => 'Siklus selesai',
      'belum_ada_batch' => 'Belum ada batch',
      _ => 'Menunggu data',
    };
    final readiness = prediction?.readinessPercent;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.agriculture, color: _green, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Prediksi Panen',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: prediction == null
                      ? Colors.grey.shade100
                      : _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: prediction == null ? Colors.grey.shade700 : _green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F3F8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 3,
                      bottom: 3,
                      width: width * progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    if (prediction != null)
                      Positioned(
                        left: width * rangeStartProgress,
                        top: 0,
                        bottom: 0,
                        width: (width * (rangeEndProgress - rangeStartProgress))
                            .clamp(5.0, width),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            border: Border.all(
                              color: _green.withValues(alpha: 0.7),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    Positioned(
                      left: (width * progress - 2).clamp(0.0, width - 4),
                      top: -3,
                      bottom: -3,
                      width: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Hari 0',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              Expanded(
                child: Text(
                  'Sekarang\nHari ke-$day HST',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              Expanded(
                child: Text(
                  prediction == null
                      ? 'Rentang panen\nMenunggu'
                      : 'Rentang panen\n${_formatPredictionDate(prediction.rangeStartDate, includeYear: false)} – ${_formatPredictionDate(prediction.rangeEndDate, includeYear: false)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  prediction?.estimatedHarvestDate == null
                      ? prediction == null
                            ? 'Output akan tampil setelah SC mengirim data.'
                            : 'Belum ada estimasi panen dari SC.'
                      : 'Estimasi panen ${_formatPredictionDate(prediction!.estimatedHarvestDate)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              if (readiness != null)
                Text(
                  '${readiness.toStringAsFixed(0)}% siap',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _green,
                  ),
                ),
            ],
          ),
          if (prediction?.channel != null || prediction?.quality != null) ...[
            const SizedBox(height: 5),
            Text(
              [
                prediction?.channel,
                prediction?.quality,
              ].whereType<String>().join(' · '),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlantingDateInput(
    HydroSmartProvider provider, {
    required bool canEdit,
  }) {
    final date = provider.plantingStartDate;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.event, color: _green, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hari Pertama Penanaman',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date == null ? 'Tanggal belum diatur' : _formatDate(date),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pilih tanggal tanam',
            onPressed: canEdit ? () => _selectPlantingDate(provider) : null,
            icon: const Icon(Icons.edit_calendar_outlined),
            color: _green,
          ),
        ],
      ),
    );
  }

  Future<void> _selectPlantingDate(HydroSmartProvider provider) async {
    final today = DateTime.now();
    final lastAllowedDate = DateTime(today.year, today.month, today.day);
    final savedDate = provider.plantingStartDate;
    final initialDate = savedDate != null && !savedDate.isAfter(lastAllowedDate)
        ? savedDate
        : lastAllowedDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: lastAllowedDate,
      helpText: 'Pilih hari pertama penanaman',
      cancelText: 'BATAL',
      confirmText: 'SIMPAN',
    );
    if (selected == null || !mounted) return;

    final saved = await provider.setPlantingDate(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Hari pertama penanaman disimpan.'
              : 'Tanggal tanam gagal disimpan ke Firebase.',
        ),
      ),
    );
  }

  String _formatPredictionDate(String? value, {bool includeYear = true}) {
    final date = value == null ? null : DateTime.tryParse(value);
    if (date == null) return '—';
    if (includeYear) return _formatDate(date);
    const months = [
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
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatDate(DateTime date) {
    const months = [
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
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ─────────────────── PANEL KONTROL: AUTO <-> MANUAL ───────────────────
  Widget _buildControlPanel(HydroSmartProvider provider) {
    final sensor = provider.sensorData;
    final isManual = sensor.mode == 'MANUAL';

    final pumpsOn = provider.pumpA || provider.pumpB;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'Kontrol Pompa',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _modeButton(
                label: 'AUTO',
                icon: Icons.autorenew,
                selected: !isManual,
                color: _green,
                enabled: true,
                onTap: () => provider.setMode('AUTO'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _modeButton(
                label: 'MANUAL',
                icon: Icons.touch_app,
                selected: isManual,
                color: _blue,
                enabled: true,
                onTap: () => provider.setMode('MANUAL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: _pumpButton(
            label: 'Pompa A + B',
            icon: Icons.power_settings_new,
            active: pumpsOn,
            enabled: isManual,
            onTap: () => provider.togglePumpAB(),
          ),
        ),
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : color,
        backgroundColor: selected ? color : Colors.white,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _pumpButton({
    required String label,
    required IconData icon,
    required bool active,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final fg = active ? Colors.white : (enabled ? _ink : Colors.grey);
    return Container(
      decoration: BoxDecoration(
        color: active
            ? _green
            : (enabled ? Colors.white : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? _green : Colors.grey.shade300),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  active ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
