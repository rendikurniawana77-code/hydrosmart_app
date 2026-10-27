import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hydrosmart_provider.dart';

class PlantNotesScreen extends StatelessWidget {
  const PlantNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HydroSmartProvider>(context);

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: provider.plantNotes.length,
        itemBuilder: (context, index) {
          final note = provider.plantNotes[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF059669),
                child: Icon(Icons.eco, color: Colors.white),
              ),
              title: Text('${note.hst} HST - ${note.date}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Tinggi: ${note.height} cm | Daun: ${note.leaves} lembar'),
            ),
          );
        },
      ),
      floatingActionButton: provider.currentRole != UserRole.penampil
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF059669),
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                provider.addPlantNote(
                  PlantNote(date: '2026-10-24', hst: provider.currentHst, height: 18.0, leaves: 10),
                );
              },
            )
          : null,
    );
  }
}