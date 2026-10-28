import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';

class ARMonitoringScreen extends StatefulWidget {
  const ARMonitoringScreen({super.key});

  @override
  State<ARMonitoringScreen> createState() => _ARMonitoringScreenState();
}

class _ARMonitoringScreenState extends State<ARMonitoringScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool isMarkerDetected = false;
  String detectedMarkerId = 'Belum ada marker terpindai';

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensor = Provider.of<HydroSmartProvider>(context).sensorData;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Kamera Scanner (Mobile Scanner / Google ML Kit)
          MobileScanner(
            controller: _cameraController,
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? code = barcode.rawValue ?? barcode.displayValue;
                if (code != null) {
                  setState(() {
                    isMarkerDetected = true;
                    detectedMarkerId = code;
                  });
                  break;
                }
              }
            },
          ),

          // 2. Bingkai Panduan Pemindai (Viewfinder Border)
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

          // 4. Floating HUD Panel Data Sensor (Muncul saat marker terdeteksi / Simulasi Aktif)
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildArMetric('TDS', '${sensor.tdsPpm.toStringAsFixed(0)} ppm'),
                        _buildArMetric('Level Air', '${sensor.waterLevelPct.toStringAsFixed(0)}%'),
                        _buildArMetric('Suhu', '${sensor.waterTempC.toStringAsFixed(1)}°C'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // 5. Tombol Reset / Simulasi Toggle untuk Keperluan Testing
          Positioned(
            bottom: isMarkerDetected ? 140 : 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isMarkerDetected = !isMarkerDetected;
                  if (isMarkerDetected) {
                    detectedMarkerId = 'HYDROS-DFT-01 (Simulasi)';
                  }
                });
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