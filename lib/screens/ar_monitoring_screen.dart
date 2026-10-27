import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';

class ARMonitoringScreen extends StatefulWidget {
  const ARMonitoringScreen({super.key});

  @override
  State<ARMonitoringScreen> createState() => _ARMonitoringScreenState();
}

class _ARMonitoringScreenState extends State<ARMonitoringScreen> {
  bool isMarkerTracked = true;

  @override
  Widget build(BuildContext context) {
    final sensor = Provider.of<HydroSmartProvider>(context).sensorData;

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0F172A),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isMarkerTracked ? Icons.center_focus_strong : Icons.camera,
                  size: 80,
                  color: isMarkerTracked ? const Color(0xFF38BDF8) : Colors.white30,
                ),
                const SizedBox(height: 12),
                Text(
                  isMarkerTracked
                      ? 'Marker Tandon Terdeteksi [Unity AR]'
                      : 'Arahkan Kamera ke Marker Tandon',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        if (isMarkerTracked)
          Positioned(
            top: 120,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🌿 HydroSmart AR Panel',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('LIVE 3D', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _arItem('TDS', '${sensor.tdsPpm.toStringAsFixed(0)} ppm'),
                      _arItem('Air', '${sensor.waterLevelPct.toStringAsFixed(0)}%'),
                      _arItem('Suhu', '${sensor.waterTempC.toStringAsFixed(1)}°C'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                isMarkerTracked = !isMarkerTracked;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              padding: const EdgeInsets.all(14),
            ),
            child: Text(isMarkerTracked ? 'Simulasi Hilang Marker' : 'Simulasi Deteksi Marker'),
          ),
        ),
      ],
    );
  }

  Widget _arItem(String title, String val) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
      ],
    );
  }
}