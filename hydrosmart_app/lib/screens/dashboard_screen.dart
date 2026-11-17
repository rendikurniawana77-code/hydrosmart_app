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

  late final PageController _topCtrl; // Sensor <-> Analitik
  late final PageController _ctrlCtrl; // AUTO <-> MANUAL
  int _topPage = 0;
  int _ctrlPage = 0;
  String? _lastMode;

  @override
  void initState() {
    super.initState();
    final mode = context
        .read<
          HydroSmartProvider
        >()
        .sensorData
        .mode;
    _lastMode = mode;
    _ctrlPage =
        mode ==
            'MANUAL'
        ? 1
        : 0;
    _topCtrl = PageController();
    _ctrlCtrl = PageController(
      initialPage: _ctrlPage,
    );
  }

  @override
  void dispose() {
    _topCtrl.dispose();
    _ctrlCtrl.dispose();
    super.dispose();
  }

  // Jika mode berubah dari luar (mis. dari ESP32), halaman kontrol ikut pindah.
  void _syncModePage(
    String mode,
  ) {
    if (_lastMode ==
        mode)
      return;
    _lastMode = mode;
    final target =
        mode ==
            'MANUAL'
        ? 1
        : 0;
    WidgetsBinding.instance.addPostFrameCallback((
      _,
    ) {
      if (!mounted ||
          !_ctrlCtrl.hasClients)
        return;
      final cur =
          _ctrlCtrl.page?.round() ??
          0;
      if (cur !=
          target) {
        _ctrlCtrl.animateToPage(
          target,
          duration: const Duration(
            milliseconds: 300,
          ),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _swapTopPanel() {
    final next =
        _topPage ==
            0
        ? 1
        : 0;
    _topCtrl.animateToPage(
      next,
      duration: const Duration(
        milliseconds: 300,
      ),
      curve: Curves.easeInOut,
    );
  }

  void _onControlPageChanged(
    int i,
  ) {
    setState(
      () => _ctrlPage = i,
    );
    final provider = context
        .read<
          HydroSmartProvider
        >();
    final target =
        i ==
            1
        ? 'MANUAL'
        : 'AUTO';
    if (provider.sensorData.mode !=
        target) {
      provider.toggleMode();
      ScaffoldMessenger.of(
          context,
        )
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Mode $target aktif',
            ),
            duration: const Duration(
              seconds: 1,
            ),
          ),
        );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider = context
        .watch<
          HydroSmartProvider
        >();
    final sensor = provider.sensorData;
    _syncModePage(
      sensor.mode,
    );

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
              // Layar sangat pendek: panel diberi tinggi tetap + boleh scroll
              final compact =
                  c.maxHeight <
                  560;
              final status = _buildStatusCard(
                provider,
              );
              final panel = _buildTopPanel(
                provider,
              );
              final controls = canControl
                  ? _buildControlPanel(
                      provider,
                    )
                  : const SizedBox.shrink();

              if (compact) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      status,
                      const SizedBox(
                        height: 10,
                      ),
                      SizedBox(
                        height: 250,
                        child: panel,
                      ),
                      if (canControl)
                        const SizedBox(
                          height: 10,
                        ),
                      controls,
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  status,
                  const SizedBox(
                    height: 10,
                  ),
                  Expanded(
                    child: panel,
                  ),
                  if (canControl)
                    const SizedBox(
                      height: 10,
                    ),
                  controls,
                ],
              );
            },
      ),
    );
  }

  // ───────────────────────── STATUS CARD (ringkas) ─────────────────────────
  Widget _buildStatusCard(
    HydroSmartProvider provider,
  ) {
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.2,
                  ),
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
                child: const Text(
                  'Panen ± 7 Hari',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────── PANEL TENGAH: SENSOR <-> ANALITIK ───────────────────
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
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _topPage ==
                          0
                      ? 'Monitoring Sensor DFT'
                      : 'Analitik Waktu Nyata',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
              _dots(
                2,
                _topPage,
                _blue,
              ),
              IconButton(
                tooltip:
                    _topPage ==
                        0
                    ? 'Lihat analitik'
                    : 'Lihat sensor',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.swap_horiz,
                  color: _blue,
                ),
                onPressed: _swapTopPanel,
              ),
            ],
          ),
          Expanded(
            child: PageView(
              controller: _topCtrl,
              onPageChanged:
                  (
                    i,
                  ) => setState(
                    () => _topPage = i,
                  ),
              children: [
                _buildSensorPage(
                  provider,
                ),
                // Dibungkus scroll agar tidak overflow bila kartu grafik lebih tinggi
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: RealtimeAnalyticsCard(
                    samples: provider.history,
                    lastSampleAt: provider.lastSampleAt,
                  ),
                ),
              ],
            ),
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
        Expanded(
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

    final pumpA = provider.pumpA;
    final pumpB = provider.pumpB;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Kontrol Pompa',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _ink,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              if (_ctrlPage ==
                      1 &&
                  lowWater)
                const Expanded(
                  child: Text(
                    'Air rendah, pompa dikunci',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              _dots(
                2,
                _ctrlPage,
                _green,
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          SizedBox(
            height: 72,
            child: PageView(
              controller: _ctrlCtrl,
              onPageChanged: _onControlPageChanged,
              children: [
                // Halaman 1: AUTO
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.autorenew,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AUTO AKTIF',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Pompa dikendalikan sensor',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Geser untuk manual',
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: 0.8,
                          ),
                          fontSize: 10,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),

                // Halaman 2: MANUAL (Pompa A, Pompa B, A+B)
                Row(
                  children: [
                    Expanded(
                      child: _pumpButton(
                        label: 'Pompa A',
                        icon: Icons.water,
                        active: pumpA,
                        enabled:
                            isManual &&
                            (pumpA ||
                                !lowWater),
                        onTap: () => provider.togglePumpA(),
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: _pumpButton(
                        label: 'Pompa B',
                        icon: Icons.opacity,
                        active: pumpB,
                        enabled:
                            isManual &&
                            (pumpB ||
                                !lowWater),
                        onTap: () => provider.togglePumpB(),
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: _pumpButton(
                        label: 'A + B',
                        icon: Icons.power_settings_new,
                        active:
                            pumpA &&
                            pumpB,
                        enabled:
                            isManual &&
                            ((pumpA &&
                                    pumpB) ||
                                !lowWater),
                        onTap: () => provider.togglePumpAB(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: fg,
                size: 22,
              ),
              const SizedBox(
                height: 4,
              ),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                active
                    ? 'ON'
                    : 'OFF',
                style: TextStyle(
                  color: fg.withValues(
                    alpha: 0.8,
                  ),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots(
    int count,
    int index,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        count,
        (
          i,
        ) {
          final on =
              i ==
              index;
          return AnimatedContainer(
            duration: const Duration(
              milliseconds: 200,
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 2,
            ),
            width: on
                ? 14
                : 6,
            height: 6,
            decoration: BoxDecoration(
              color: on
                  ? color
                  : color.withValues(
                      alpha: 0.25,
                    ),
              borderRadius: BorderRadius.circular(
                3,
              ),
            ),
          );
        },
      ),
    );
  }
}
