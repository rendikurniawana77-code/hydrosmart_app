import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HydroSmartProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pengaturan Ambang Batas Air (Admin)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Batas Bawah Pompa Nyala: ${provider.minWaterLevel.toInt()}%'),
                  Slider(
                    value: provider.minWaterLevel,
                    min: 10,
                    max: 50,
                    activeColor: const Color(0xFF0284C7),
                    onChanged: provider.currentRole == UserRole.admin
                        ? (val) => provider.setThresholds(val, provider.maxWaterLevel)
                        : null,
                  ),
                  const Divider(),
                  Text('Batas Atas Pompa Mati: ${provider.maxWaterLevel.toInt()}%'),
                  Slider(
                    value: provider.maxWaterLevel,
                    min: 50,
                    max: 95,
                    activeColor: const Color(0xFF059669),
                    onChanged: provider.currentRole == UserRole.admin
                        ? (val) => provider.setThresholds(provider.minWaterLevel, val)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}