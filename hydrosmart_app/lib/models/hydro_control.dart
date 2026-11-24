class HydroControl {
  const HydroControl({this.reset, this.kalibrasi});

  final bool? reset;
  final String? kalibrasi;

  bool get resetDiproses => reset == true;

  bool get kalibrasiIdle => kalibrasiDiproses == null;

  String? get kalibrasiDiproses {
    final value = kalibrasi?.trim().toLowerCase();
    if (value == 'kering' || value == 'basah' || value == 'reset') {
      return value;
    }
    return null;
  }

  factory HydroControl.fromMap(Map<dynamic, dynamic> data) {
    return HydroControl(
      reset: _asBool(data['reset']),
      kalibrasi: data['kalibrasi']?.toString(),
    );
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    return null;
  }
}
