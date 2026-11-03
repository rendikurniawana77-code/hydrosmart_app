import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ====== KONFIGURASI (sesuai SRS v2.2) ======
const String kRoot = 'hydrosmart'; // node induk (Tabel 3.1)
const String kUnitId = 'HYDROSMART-DFT-001'; // cadangan bila hydrosmart/meta/unit_id belum ada (3.4B)
const int kQrVersion = 1; // QR format v1: {"v":1,"unit":"..."}
const double kLevelLow = 30; // batas bawah pompa (FR-03, nilai awal)
const double kLevelHigh = 60; // batas atas pompa (FR-03, nilai awal)
const double kLevelCritical = 15; // [TBD] di bawah ini dianggap kritis
const double kTdsMin = 500; // [TBD] di bawah ini peringatan
const double kTdsMax = 1200; // [TBD] di atas ini peringatan
const Duration kStaleAfter = Duration(seconds: 30); // FR-25
// ===========================================

enum _Status { normal, warning, critical }

class _QrException implements Exception {
  final String message;
  _QrException(this.message);
}

class _Telemetry {
  final double? level;
  final double? tds;
  final bool? pompa;
  final String? mode;
  final String? waktuRaw;

  _Telemetry({this.level, this.tds, this.pompa, this.mode, this.waktuRaw});

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool? _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'true' || s == 'on' || s == '1') return true;
      if (s == 'false' || s == 'off' || s == '0') return false;
    }
    return null;
  }

  factory _Telemetry.fromMap(Map<dynamic, dynamic> m) => _Telemetry(
        level: _num(m['level']),
        tds: _num(m['tds']),
        pompa: _bool(m['pompa']),
        mode: m['mode']?.toString(),
        waktuRaw: m['waktu']?.toString(),
      );
}

class ARMonitoringScreen extends StatefulWidget {
  const ARMonitoringScreen({super.key});

  @override
  State<ARMonitoringScreen> createState() => _ARMonitoringScreenState();
}

class _ARMonitoringScreenState extends State<ARMonitoringScreen> {
  // FR-21: hanya memindai QR
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  StreamSubscription<DatabaseEvent>? _dataSub;
  StreamSubscription<DatabaseEvent>? _connSub;
  Timer? _ticker;

  String? _unitId;
  String? _error; // pesan penolakan QR (FR-21)
  String? _dataError;
  bool _validating = false;
  bool _simulation = false; // FR-30

  _Telemetry? _data;
  DateTime _lastChange = DateTime.now(); // terakhir data berubah/diterima
  bool _firebaseConnected = true;

  DateTime _lastQrSeen = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _qrRect;
  Size _viewSize = Size.zero;

  bool get _qrVisible =>
      DateTime.now().difference(_lastQrSeen) < const Duration(milliseconds: 1500);
  bool get _active => _unitId != null;

  @override
  void initState() {
    super.initState();
    // Menyegarkan tampilan: menyembunyikan model 2D saat QR hilang (FR-26)
    // dan memeriksa data tertunda (FR-25).
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        if (!_qrVisible && _error != null) _error = null;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopListening(); // FR-28: listener dilepas saat keluar
    _camera.dispose();
    super.dispose();
  }

  // ---------- Validasi QR (FR-21) ----------
  String _parseQr(String raw) {
    dynamic j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      throw _QrException('Format QR tidak dikenali (bukan QR HydroSmart)');
    }
    if (j is! Map) throw _QrException('Format QR tidak dikenali');
    if (j['v'] != kQrVersion) {
      throw _QrException('Versi QR tidak dikenal: ${j['v']}');
    }
    final unit = j['unit'];
    if (unit is! String || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(unit)) {
      throw _QrException('ID unit pada QR tidak valid');
    }
    return unit;
  }

  Future<void> _validateAndStart(String raw) async {
    _validating = true;
    try {
      final unit = _parseQr(raw);

      // Cocokkan dengan hydrosmart/meta/unit_id; bila belum ada, pakai kUnitId.
      String expected = kUnitId;
      try {
        final snap = await FirebaseDatabase.instance
            .ref('$kRoot/meta/unit_id')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snap.exists && snap.value is String) expected = snap.value as String;
      } catch (_) {
        // meta belum ada / belum boleh dibaca: pakai konfigurasi aplikasi
      }
      if (unit != expected) {
        throw _QrException('ID unit "$unit" tidak terdaftar');
      }
      if (!mounted) return;
      _startListening(unit);
    } on _QrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _validating = false;
    }
  }

  // ---------- Listener real time (FR-22, FR-23) ----------
  void _startListening(String unit) {
    _stopListening();
    setState(() {
      _unitId = unit;
      _error = null;
      _dataError = null;
      _data = null;
      _simulation = false;
      _lastChange = DateTime.now();
    });

    // Hanya membaca (FR-27): tidak ada set/update/push ke Firebase.
    _dataSub = FirebaseDatabase.instance.ref('$kRoot/terbaru').onValue.listen(
      (event) {
        if (!mounted) return;
        final v = event.snapshot.value;
        setState(() {
          if (v is Map) {
            final t = _Telemetry.fromMap(v);
            // Data dianggap "baru" bila field waktu berubah (tahan beda jam HP/ESP32)
            if (_data == null || t.waktuRaw == null || t.waktuRaw != _data!.waktuRaw) {
              _lastChange = DateTime.now();
            }
            _data = t;
            _dataError = null;
          } else {
            _data = null;
            _dataError = 'Node $kRoot/terbaru kosong';
          }
        });
      },
      onError: (e) {
        if (mounted) setState(() => _dataError = 'Gagal membaca Firebase: $e');
      },
    );

    _connSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      if (mounted) setState(() => _firebaseConnected = event.snapshot.value == true);
    });
  }

  void _stopListening() {
    _dataSub?.cancel();
    _connSub?.cancel();
    _dataSub = null;
    _connSub = null;
  }

  void _reset() {
    _stopListening();
    setState(() {
      _unitId = null;
      _error = null;
      _dataError = null;
      _data = null;
      _simulation = false;
      _qrRect = null;
      _lastQrSeen = DateTime.fromMillisecondsSinceEpoch(0);
    });
  }

  // Hanya untuk pengembangan (Tabel 6.1); data diberi tanda SIMULASI (FR-30)
  void _startSimulation() {
    _stopListening();
    setState(() {
      _unitId = 'SIMULASI';
      _simulation = true;
      _error = null;
      _dataError = null;
      _data = _Telemetry(level: 45, tds: 850, pompa: false, mode: 'auto', waktuRaw: 'simulasi');
      _lastChange = DateTime.now();
    });
  }

  // ---------- Deteksi QR ----------
  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;

      _lastQrSeen = DateTime.now();
      _updateQrRect(b, capture.size);

      if (!_active && !_validating) {
        _validateAndStart(raw);
      } else if (mounted) {
        setState(() {});
      }
      return;
    }
  }

  // Posisi QR di layar (preview memakai BoxFit.cover)
  void _updateQrRect(Barcode b, Size img) {
    final c = b.corners;
    if (c.isEmpty || _viewSize == Size.zero || img.isEmpty) return;
    final scale = math.max(_viewSize.width / img.width, _viewSize.height / img.height);
    final dx = (_viewSize.width - img.width * scale) / 2;
    final dy = (_viewSize.height - img.height * scale) / 2;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in c) {
      final x = p.dx * scale + dx;
      final y = p.dy * scale + dy;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    _qrRect = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ---------- Status & alarm (FR-23, FR-24, FR-25) ----------
  bool get _stale =>
      !_simulation && DateTime.now().difference(_lastChange) > kStaleAfter;

  List<String> _alarms(_Telemetry d) {
    final a = <String>[];
    if (d.level != null) {
      if (d.level! < kLevelCritical) {
        a.add('Level air kritis (${d.level!.toStringAsFixed(0)}%)');
      } else if (d.level! < kLevelLow) {
        a.add('Level air di bawah batas bawah (${kLevelLow.toStringAsFixed(0)}%)');
      }
    }
    if (d.tds != null) {
      if (d.tds! < kTdsMin) a.add('TDS rendah');
      if (d.tds! > kTdsMax) a.add('TDS tinggi');
    }
    if (_stale) a.add('Data tertunda');
    return a;
  }

  _Status _statusOf(_Telemetry d) {
    if (d.level != null && d.level! < kLevelCritical) return _Status.critical;
    if (_alarms(d).isNotEmpty) return _Status.warning;
    return _Status.normal;
  }

  Color _statusColor(_Status s) => switch (s) {
        _Status.normal => const Color(0xFF059669),
        _Status.warning => const Color(0xFFD97706),
        _Status.critical => const Color(0xFFDC2626),
      };

  String _statusLabel(_Status s) => switch (s) {
        _Status.normal => 'NORMAL',
        _Status.warning => 'PERINGATAN',
        _Status.critical => 'KRITIS',
      };

  IconData _statusIcon(_Status s) => switch (s) {
        _Status.normal => Icons.check_circle,
        _Status.warning => Icons.warning_amber_rounded,
        _Status.critical => Icons.error,
      };

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
          final showPanel = _active && (_qrVisible || _simulation);

          return Stack(
            children: [
              // 1. Kamera (FR-20: pesan bila izin ditolak / pemindai tidak tersedia)
              MobileScanner(
                controller: _camera,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(error: error, onBack: _exit),
              ),

              // 2. Kotak di sekitar QR yang terbaca
              if (_qrVisible && _qrRect != null)
                Positioned.fromRect(
                  rect: _qrRect!.inflate(6),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _active ? const Color(0xFF059669) : const Color(0xFF38BDF8),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              // 3. Petunjuk / status di atas
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: SafeArea(child: _buildTopBar()),
              ),

              // 4. Model 2D di atas posisi QR (FR-22, FR-26)
              if (showPanel) _buildPanelPositioned(),

              // 5. Tombol simulasi hanya di mode debug
              if (kDebugMode && !_active)
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: ElevatedButton.icon(
                    onPressed: _startSimulation,
                    icon: const Icon(Icons.bug_report, size: 18),
                    label: const Text('Simulasi (hanya pengembangan)'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _exit() {
    _reset();
    Navigator.of(context).maybePop();
  }

  Widget _buildTopBar() {
    final String title;
    final String subtitle;
    final IconData icon;
    final Color color;

    if (_error != null) {
      title = 'QR ditolak';
      subtitle = _error!;
      icon = Icons.block;
      color = const Color(0xFFDC2626);
    } else if (_active && _qrVisible) {
      title = 'QR Unit Terdeteksi';
      subtitle = 'Unit: $_unitId';
      icon = Icons.check_circle;
      color = const Color(0xFF059669);
    } else {
      title = 'Arahkan kamera ke QR';
      subtitle = _active ? 'QR tidak terlihat (unit: $_unitId)' : 'Pindai QR pada bak tanam';
      icon = Icons.qr_code_scanner;
      color = const Color(0xFF38BDF8);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ],
            ),
          ),
          // FR-28: keluar kapan saja
          IconButton(
            tooltip: 'Keluar dari Scan QR',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _exit,
          ),
        ],
      ),
    );
  }

  Widget _buildPanelPositioned() {
    const double panelWidth = 290;
    final rect = _qrRect;
    final maxLeft = math.max(8.0, _viewSize.width - panelWidth - 8);

    if (rect == null || _simulation) {
      // QR belum punya posisi (atau simulasi): taruh di bawah layar
      return Positioned(
        bottom: 80,
        left: (_viewSize.width - panelWidth) / 2,
        width: panelWidth,
        child: _buildPanel(),
      );
    }

    final left = (rect.center.dx - panelWidth / 2).clamp(8.0, maxLeft);
    final spaceAbove = rect.top;
    if (spaceAbove > 290) {
      return Positioned(
        bottom: _viewSize.height - rect.top + 12,
        left: left,
        width: panelWidth,
        child: _buildPanel(),
      );
    }
    return Positioned(
      top: rect.bottom + 12,
      left: left,
      width: panelWidth,
      child: _buildPanel(),
    );
  }

  Widget _buildPanel() {
    final d = _data;

    // Badge koneksi (FR-25, FR-30)
    String badge;
    Color badgeColor;
    if (_simulation) {
      badge = 'SIMULASI';
      badgeColor = const Color(0xFF7C3AED);
    } else if (!_firebaseConnected) {
      badge = 'OFFLINE';
      badgeColor = const Color(0xFFDC2626);
    } else if (_stale) {
      badge = 'DATA TERTUNDA';
      badgeColor = const Color(0xFFD97706);
    } else {
      badge = 'LIVE';
      badgeColor = const Color(0xFF0284C7);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text('🌿 HydroSmart Scan QR',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF059669), fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Divider(height: 14),
          if (_dataError != null)
            Text(_dataError!, style: const TextStyle(color: Colors.red, fontSize: 12))
          else if (d == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._buildData(d),
        ],
      ),
    );
  }

  List<Widget> _buildData(_Telemetry d) {
    final status = _statusOf(d);
    final color = _statusColor(status);
    final alarms = _alarms(d);

    return [
      // Status memakai ikon + teks, tidak hanya warna (NFR-20)
      Row(
        children: [
          Icon(_statusIcon(status), color: color, size: 18),
          const SizedBox(width: 6),
          Text(_statusLabel(status),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metric('TDS', d.tds == null ? '-' : '${d.tds!.toStringAsFixed(0)} ppm', color),
          _metric('Level Air', d.level == null ? '-' : '${d.level!.toStringAsFixed(0)}%', color),
          _metric('Pompa', d.pompa == null ? '-' : (d.pompa! ? 'ON' : 'OFF'),
              const Color(0xFF0284C7)),
        ],
      ),
      const SizedBox(height: 8),
      if (d.level != null) _levelBar(d.level!, color), // FR-29
      const SizedBox(height: 6),
      Text('Mode: ${d.mode ?? '-'}',
          style: const TextStyle(fontSize: 11, color: Colors.black54)),
      const SizedBox(height: 4),
      // FR-22: HST dan prediksi menunggu node batch/prediksi (FR-40, FR-38)
      const Text('HST & prediksi panen: belum tersedia',
          style: TextStyle(fontSize: 11, color: Colors.black54)),
      if (alarms.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final a in alarms)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Icon(Icons.notifications_active, size: 13, color: color),
                const SizedBox(width: 4),
                Expanded(child: Text(a, style: TextStyle(fontSize: 11, color: color))),
              ],
            ),
          ),
      ],
      const SizedBox(height: 6),
      Text(
        'Data terakhir: ${_lastDataText(d)}',
        style: const TextStyle(fontSize: 10, color: Colors.black45),
      ),
    ];
  }

  String _lastDataText(_Telemetry d) {
    if (_simulation) return 'simulasi';
    final w = d.waktuRaw;
    if (w != null) {
      final n = num.tryParse(w);
      if (n != null) {
        final ms = n > 1e12 ? n.toInt() : (n * 1000).toInt();
        final t = DateTime.fromMillisecondsSinceEpoch(ms);
        if (t.year >= 2020) {
          return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
        }
      }
      return w;
    }
    final t = _lastChange;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  Widget _levelBar(double level, Color color) {
    final f = (level / 100).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 16,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Container(
              width: w * f,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            // Garis batas bawah dan atas
            Positioned(left: w * kLevelLow / 100, top: 0, bottom: 0,
                child: Container(width: 2, color: Colors.black87)),
            Positioned(left: w * kLevelHigh / 100, top: 0, bottom: 0,
                child: Container(width: 2, color: Colors.black87)),
          ],
        ),
      );
    });
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onBack;
  const _CameraError({required this.error, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(
            denied
                ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan HP untuk memakai Scan QR.'
                : 'Pemindai QR tidak tersedia di perangkat ini.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onBack, child: const Text('Kembali ke aplikasi')),
        ],
      ),
    );
  }
}