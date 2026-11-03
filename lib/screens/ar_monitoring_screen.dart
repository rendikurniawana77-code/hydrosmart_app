import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_database/firebase_database.dart';

// ====== SESUAIKAN BAGIAN INI DENGAN STRUKTUR FIREBASE ANDA ======
const String kBasePath = 'tandon'; // node induk di Realtime Database
const String kFieldTds = 'tds_ppm'; // nama field TDS
const String kFieldLevel = 'water_level_pct'; // nama field level air
const String kSimulationId = 'HYDROS-DFT-01'; // ID untuk tombol simulasi
// ================================================================

class ARMonitoringScreen extends StatefulWidget {
  const ARMonitoringScreen({super.key});

  @override
  State<ARMonitoringScreen> createState() => _ARMonitoringScreenState();
}

class _ARMonitoringScreenState extends State<ARMonitoringScreen> {
  final MobileScannerController _cameraController = MobileScannerController();

  bool isMarkerDetected = false;
  String detectedMarkerId = 'Belum ada marker terpindai';

  String? _activeId;
  Stream<DatabaseEvent>? _sensorStream;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  // Aktifkan marker: simpan ID dan buka listener real time ke Firebase
  void _setMarker(String code) {
    setState(() {
      _activeId = code;
      isMarkerDetected = true;
      detectedMarkerId = code;
      _sensorStream = FirebaseDatabase.instance.ref('$kBasePath/$code').onValue;
    });
  }

  void _resetMarker() {
    setState(() {
      _activeId = null;
      isMarkerDetected = false;
      detectedMarkerId = 'Belum ada marker terpindai';
      _sensorStream = null;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (code == null || code.isEmpty) continue;

      // Abaikan jika ID sama, supaya tidak rebuild berulang
      if (code == _activeId) return;

      // Path Firebase tidak boleh mengandung . # $ [ ] /
      if (RegExp(r'[.#$\[\]/]').hasMatch(code)) {
        setState(() {
          _activeId = null;
          _sensorStream = null;
          isMarkerDetected = false;
          detectedMarkerId = 'QR tidak valid: $code';
        });
        return;
      }

      _setMarker(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Kamera Scanner
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
          ),

          // 2. Bingkai Panduan Pemindai
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isMarkerDetected ? const Color(0xFF059669) : const Color(0xFF0284C7),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // 3. Status Deteksi di Bagian Atas
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(
                    isMarkerDetected ? Icons.check_circle : Icons.qr_code_scanner,
                    color: isMarkerDetected ? const Color(0xFF059669) : const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMarkerDetected ? 'Marker Tandon Terdeteksi!' : 'Arahkan ke QR/Barcode Tandon',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'ID: $detectedMarkerId',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. HUD Data Sensor Real Time dari Firebase
          if (isMarkerDetected)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '🌿 HydroSmart AR Digital Twin',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669), fontSize: 14),
                        ),
                        Text('LIVE HUD', style: TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    _buildSensorContent(),
                  ],
                ),
              ),
            ),

          // 5. Tombol Reset / Simulasi
          Positioned(
            bottom: isMarkerDetected ? 170 : 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: () {
                if (isMarkerDetected) {
                  _resetMarker();
                } else {
                  _setMarker(kSimulationId);
                }
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(isMarkerDetected ? 'Reset / Scan Ulang' : 'Simulasi Deteksi Marker'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorContent() {
    return StreamBuilder<DatabaseEvent>(
      stream: _sensorStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            'Error: ${snap.error}',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final value = snap.data!.snapshot.value;
        if (value == null || value is! Map) {
          return Text(
            'Data untuk "$detectedMarkerId" tidak ditemukan di Firebase',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          );
        }

        final data = Map<String, dynamic>.from(value);
        final tds = (data[kFieldTds] as num?)?.toDouble() ?? 0;
        final level = (data[kFieldLevel] as num?)?.toDouble() ?? 0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildArMetric('TDS', '${tds.toStringAsFixed(0)} ppm'),
            _buildArMetric('Level Air', '${level.toStringAsFixed(0)}%'),
          ],
        );
      },
    );
  }

  Widget _buildArMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
      ],
    );
  }
}