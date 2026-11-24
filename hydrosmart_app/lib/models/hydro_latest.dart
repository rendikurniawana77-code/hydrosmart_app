class HydroLatest {
  const HydroLatest({
    this.galat,
    this.alasan,
    this.kalLengkap,
    this.kalKeringOk,
    this.kalBasahOk,
    this.kalPesan,
    this.pompa,
    this.waktu,
  });

  final bool? galat;
  final String? alasan;
  final bool? kalLengkap;
  final bool? kalKeringOk;
  final bool? kalBasahOk;
  final String? kalPesan;
  final bool? pompa;
  final int? waktu;

  factory HydroLatest.fromMap(Map<dynamic, dynamic> data) {
    return HydroLatest(
      galat: _asBool(data['galat']),
      alasan: data['alasan']?.toString(),
      kalLengkap: _asBool(data['kal_lengkap']),
      kalKeringOk: _asBool(data['kal_kering_ok']),
      kalBasahOk: _asBool(data['kal_basah_ok']),
      kalPesan: data['kal_pesan']?.toString(),
      pompa: _asBool(data['pompa']),
      waktu: _asInt(data['waktu']),
    );
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
        case 'on':
          return true;
        case 'false':
        case '0':
        case 'off':
          return false;
      }
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
