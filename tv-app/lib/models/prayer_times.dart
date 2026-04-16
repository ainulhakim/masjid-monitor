class PrayerTimesData {
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;
  
  final String iqamahFajr;
  final String iqamahDhuhr;
  final String iqamahAsr;
  final String iqamahMaghrib;
  final String iqamahIsha;
  
  final int blankAfterIqamah;
  final int blankJumatDuration;
  
  final String masjidName;
  final String masjidCity;
  final String masjidAddress;

  PrayerTimesData({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.iqamahFajr,
    required this.iqamahDhuhr,
    required this.iqamahAsr,
    required this.iqamahMaghrib,
    required this.iqamahIsha,
    required this.blankAfterIqamah,
    required this.blankJumatDuration,
    required this.masjidName,
    required this.masjidCity,
    required this.masjidAddress,
  });

  factory PrayerTimesData.fromJson(Map<String, dynamic> json) {
    final prayerTimes = json['prayerTimes'] ?? {};
    final iqamahTimes = json['iqamahTimes'] ?? {};
    final masjid = json['masjid'] ?? {};
    final blankSettings = json['blankSettings'] ?? {};

    return PrayerTimesData(
      fajr: prayerTimes['fajr'] ?? '04:30',
      sunrise: prayerTimes['sunrise'] ?? '05:45',
      dhuhr: prayerTimes['dhuhr'] ?? '12:00',
      asr: prayerTimes['asr'] ?? '15:30',
      maghrib: prayerTimes['maghrib'] ?? '18:15',
      isha: prayerTimes['isha'] ?? '19:30',
      iqamahFajr: iqamahTimes['fajr'] ?? '04:50',
      iqamahDhuhr: iqamahTimes['dhuhr'] ?? '12:10',
      iqamahAsr: iqamahTimes['asr'] ?? '15:40',
      iqamahMaghrib: iqamahTimes['maghrib'] ?? '18:22',
      iqamahIsha: iqamahTimes['isha'] ?? '19:40',
      blankAfterIqamah: blankSettings['blankAfterIqamah'] ?? 10,
      blankJumatDuration: blankSettings['blankJumatDuration'] ?? 30,
      masjidName: masjid['name'] ?? 'Masjid',
      masjidCity: masjid['city'] ?? 'Kota',
      masjidAddress: masjid['address'] ?? 'Alamat',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'prayerTimes': {
        'fajr': fajr,
        'sunrise': sunrise,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      },
      'iqamahTimes': {
        'fajr': iqamahFajr,
        'dhuhr': iqamahDhuhr,
        'asr': iqamahAsr,
        'maghrib': iqamahMaghrib,
        'isha': iqamahIsha,
      },
      'blankSettings': {
        'blankAfterIqamah': blankAfterIqamah,
        'blankJumatDuration': blankJumatDuration,
      },
      'masjid': {
        'name': masjidName,
        'city': masjidCity,
        'address': masjidAddress,
      },
    };
  }
}
