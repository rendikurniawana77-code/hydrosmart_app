import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';
import '../widgets/realtime_analytics_card.dart';

class DashboardScreen
    extends
        StatefulWidget {
  const DashboardScreen({
    super.key,
  });

  @override
  State<
    DashboardScreen
  >
  createState() => _DashboardScreenState();
}

class _DashboardScreenState
    extends
        State<
          DashboardScreen
        > {
  static const _green = Color(
    0xFF059669,
  );
  static const _blue = Color(
    0xFF0284C7,
  );
  static const _ink = Color(
    0xFF1E293B,
  );

  // Umur panen kangkung DFT (HST). Sesuaikan dengan data lapangan/penelitianmu.
  static const int _targetPanenHst = 28;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider = context
        .watch<
          HydroSmartProvider
        >();
    final canControl =
        provider.currentRole !=
        UserRole.penampil;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        8,
      ),
      child: LayoutBuilder(
        builder:
            (
              context,
              c,
            ) {
              final status = _buildStatusCard(
                provider,
                canControl: canControl,
              );
              final panel = _buildTopPanel(
                provider,
              );

              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    status,
                    const SizedBox(
                      height: 10,
                    ),
                    panel,
                    const SizedBox(
                      height: 16,
                    ),
                    RealtimeAnalyticsCard(
                      samples: provider.history,
                      lastSampleAt: provider.lastSampleAt,
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    _buildHarvestPrediction(
                      provider,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            _green,
            _blue,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(
              alpha: 0.3,
            ),
            blurRadius: 10,
            offset: const Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(
                  6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  sensor.isOnline
                      ? 'ESP32 ONLINE'
                      : 'ESP32 OFFLINE',
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
                  borderRadius: BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  sensor.mode,
                  style: TextStyle(
                    color:
                        sensor.mode ==
                            'AUTO'
                        ? _green
                        : _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kangkung DFT · ${provider.currentHst} HST',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (canControl) ...[
            const SizedBox(
              height: 10,
            ),
            _buildControlPanel(
              provider,
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── MONITORING SENSOR ─────────────────────────
  Widget _buildTopPanel(
    HydroSmartProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        12,
        6,
        12,
        10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: _blue.withValues(
            alpha: 0.12,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              2,
              4,
              2,
              8,
            ),
            child: Text(
              'Monitoring Sensor DFT',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
          ),
          _buildSensorPage(
            provider,
          ),
        ],
      ),
    );
  }

  Widget _buildSensorPage(
    HydroSmartProvider provider,
  ) {
    final sensor = provider.sensorData;
    final lowWater =
        sensor.waterLevelPct <
        provider.minWaterLevel;
    final pumpOn = sensor.pumpStatus.contains(
      'ON',
    );

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
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: _sensorCard(
                  'Level Air',
                  '${sensor.waterLevelPct.toStringAsFixed(1)}%',
                  Icons.water_drop,
                  lowWater
                      ? Colors.redAccent
                      : _green,
                  'Batas: ${provider.minWaterLevel.toInt()}% - ${provider.maxWaterLevel.toInt()}%',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color:
                (pumpOn
                        ? _green
                        : Colors.grey)
                    .withValues(
                      alpha: 0.08,
                    ),
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.power,
                size: 16,
                color: pumpOn
                    ? _green
                    : Colors.grey,
              ),
              const SizedBox(
                width: 8,
              ),
              const Text(
                'Status Pompa',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              Text(
                sensor.pumpStatus,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: pumpOn
                      ? _green
                      : Colors.grey,
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
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(
              alpha: 0.06,
            ),
            blurRadius: 10,
            offset: const Offset(
              0,
              4,
            ),
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
                padding: const EdgeInsets.all(
                  5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.1,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
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
          Text(
            sub,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── PREDIKSI PANEN ─────────────────────────
  Widget _buildHarvestPrediction(
    HydroSmartProvider provider,
  ) {
    final int hst = provider.currentHst;
    final int sisaHari =
        (_targetPanenHst -
                hst)
            .clamp(
              0,
              _targetPanenHst,
            );
    final bool siapPanen =
        hst >=
        _targetPanenHst;
    final double progress =
        (hst /
                _targetPanenHst)
            .clamp(
              0.0,
              1.0,
            );

    const bulan = [
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
    final tgl = DateTime.now().add(
      Duration(
        days: sisaHari,
      ),
    );
    final tglPanen = '${tgl.day} ${bulan[tgl.month - 1]} ${tgl.year}';

    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: _green.withValues(
            alpha: 0.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.agriculture,
                color: _green,
                size: 18,
              ),
              const SizedBox(
                width: 8,
              ),
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
                  color: _green.withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
                child: Text(
                  siapPanen
                      ? 'Siap Panen'
                      : 'Panen ± $sisaHari Hari',
                  style: const TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              8,
            ),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(
                _green,
              ),
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$hst / $_targetPanenHst HST',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            siapPanen
                ? 'Tanaman sudah mencapai umur panen.'
                : 'Estimasi panen: $tglPanen',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── PANEL KONTROL: AUTO <-> MANUAL ───────────────────
  Widget _buildControlPanel(
    HydroSmartProvider provider,
  ) {
    final sensor = provider.sensorData;
    final isManual =
        sensor.mode ==
        'MANUAL';
    final lowWater =
        sensor.waterLevelPct <
        provider.minWaterLevel;

    final pumpsOn =
        provider.pumpA ||
        provider.pumpB;

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
            const SizedBox(
              width: 8,
            ),
            if (isManual &&
                lowWater)
              const Expanded(
                child: Text(
                  'Air rendah, pompa dikunci',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
          ],
        ),
        const SizedBox(
          height: 6,
        ),
        Row(
          children: [
            Expanded(
              child: _modeButton(
                label: 'AUTO',
                icon: Icons.autorenew,
                selected: !isManual,
                color: _green,
                enabled: true,
                onTap: () => provider.setMode(
                  'AUTO',
                ),
              ),
            ),
            const SizedBox(
              width: 8,
            ),
            Expanded(
              child: _modeButton(
                label: 'MANUAL',
                icon: Icons.touch_app,
                selected: isManual,
                color: _blue,
                enabled: true,
                onTap: () => provider.setMode(
                  'MANUAL',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 6,
        ),
        SizedBox(
          height: 44,
          child: _pumpButton(
            label: 'Pompa A + B',
            icon: Icons.power_settings_new,
            active: pumpsOn,
            enabled:
                isManual &&
                (pumpsOn ||
                    !lowWater),
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
      onPressed: enabled
          ? onTap
          : null,
      icon: Icon(
        icon,
        size: 18,
      ),
      label: Text(
        label,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected
            ? Colors.white
            : color,
        backgroundColor: selected
            ? color
            : Colors.white,
        side: BorderSide(
          color: color,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
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
    final fg = active
        ? Colors.white
        : (enabled
              ? _ink
              : Colors.grey);
    return Container(
      decoration: BoxDecoration(
        color: active
            ? _green
            : (enabled
                  ? Colors.white
                  : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: active
              ? _green
              : Colors.grey.shade300,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(
            14,
          ),
          onTap: enabled
              ? onTap
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: fg,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
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
                  active
                      ? 'ON'
                      : 'OFF',
                  style: TextStyle(
                    color: fg.withValues(
                      alpha: 0.8,
                    ),
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
