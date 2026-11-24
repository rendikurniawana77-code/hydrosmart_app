import 'package:firebase_database/firebase_database.dart';

import '../models/hydro_control.dart';
import '../models/hydro_latest.dart';

class HydroRepository {
  HydroRepository(this._database);

  final FirebaseDatabase _database;

  Stream<HydroLatest?> get latestStream => _database
      .ref('hydrosmart/terbaru')
      .onValue
      .map((event) => _parseLatest(event.snapshot.value));

  Stream<HydroControl?> get controlStream => _database
      .ref('hydrosmart/kontrol')
      .onValue
      .map((event) => _parseControl(event.snapshot.value));

  Future<HydroControl?> bacaKontrol() async {
    final snapshot = await _database.ref('hydrosmart/kontrol').get();
    return _parseControl(snapshot.value);
  }

  Future<void> kirimReset() async {
    await _database.ref('hydrosmart/kontrol/reset').set(true);
  }

  Future<void> kirimKalibrasi(String perintah) async {
    if (!const {'kering', 'basah', 'reset'}.contains(perintah)) {
      throw ArgumentError.value(perintah, 'perintah', 'Perintah tidak valid');
    }
    await _database.ref('hydrosmart/kontrol/kalibrasi').set(perintah);
  }

  HydroLatest? _parseLatest(Object? value) {
    if (value is Map) return HydroLatest.fromMap(value);
    return null;
  }

  HydroControl? _parseControl(Object? value) {
    if (value is Map) return HydroControl.fromMap(value);
    return null;
  }
}
