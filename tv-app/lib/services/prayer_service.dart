import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhan/adhan.dart';
import 'package:logger/logger.dart';

import '../models/prayer_times.dart';
import '../models/adzan_state.dart';

final logger = Logger();

class PrayerService {
  static const String BASE_URL = 'http://localhost:3001/api';
  static const String SYNC_TOKEN_KEY = 'sync_token';
  static const String LAST_SYNC_KEY = 'last_sync';
  
  SharedPreferences? _prefs;
  PrayerTimesData? _currentPrayerTimes;
  AdzanState _adzanState = AdzanState.idle;
  
  final _prayerTimesController = StreamController<PrayerTimesData>.broadcast();
  final _adzanStateController = StreamController<AdzanState>.broadcast();
  final _countdownController = StreamController<CountdownData>.broadcast();
  
  Stream<PrayerTimesData> get prayerTimesStream => _prayerTimesController.stream;
  Stream<AdzanState> get adzanStateStream => _adzanStateController.stream;
  Stream<CountdownData> get countdownStream => _countdownController.stream;
  
  PrayerTimesData? get currentPrayerTimes => _currentPrayerTimes;
  AdzanState get adzanState => _adzanState;
  
  Timer? _prayerCheckTimer;
  Timer? _countdownTimer;
  
  Set<String> _announcedPrayers = {};
  
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _announcedPrayers = _prefs!.getStringList('announced_prayers')?.toSet() ?? {};
    
    // Clear old announcements on new day
    _clearOldAnnouncements();
    
    // Start prayer time checking
    _startPrayerCheckTimer();
    _startCountdownTimer();
    
    // Initial sync
    await syncPrayerTimes();
  }
  
  void _clearOldAnnouncements() {
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    
    _announcedPrayers.removeWhere((key) => !key.startsWith(today));
    _saveAnnouncedPrayers();
  }
  
  void _saveAnnouncedPrayers() {
    _prefs?.setStringList('announced_prayers', _announcedPrayers.toList());
  }
  
  Future<void> syncPrayerTimes() async {
    try {
      final token = _prefs?.getString(SYNC_TOKEN_KEY) ?? 'sample-masjid-001';
      
      final response = await http.get(
        Uri.parse('$BASE_URL/sync/data-live/$token'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentPrayerTimes = PrayerTimesData.fromJson(data);
        _prayerTimesController.add(_currentPrayerTimes!);
        
        _prefs?.setString(LAST_SYNC_KEY, DateTime.now().toIso8601String());
        
        logger.i('Prayer times synced successfully');
      } else {
        logger.w('Failed to sync: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('Error syncing prayer times: $e');
      // Use cached data if available
      _loadCachedPrayerTimes();
    }
  }
  
  void _loadCachedPrayerTimes() {
    // Load from SharedPreferences if available
    final cached = _prefs?.getString('cached_prayer_times');
    if (cached != null) {
      try {
        final data = jsonDecode(cached);
        _currentPrayerTimes = PrayerTimesData.fromJson(data);
        _prayerTimesController.add(_currentPrayerTimes!);
      } catch (e) {
        logger.e('Error loading cached data: $e');
      }
    }
  }
  
  void _startPrayerCheckTimer() {
    _prayerCheckTimer?.cancel();
    _prayerCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkPrayerTimes();
    });
  }
  
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }
  
  void _checkPrayerTimes() {
    if (_currentPrayerTimes == null || _adzanState != AdzanState.idle) return;
    
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final today = '${now.year}-${now.month}-${now.day}';
    
    final prayers = [
      PrayerCheck('fajr', 'Subuh', _currentPrayerTimes!.fajr),
      PrayerCheck('dhuhr', 'Dzuhur', _currentPrayerTimes!.dhuhr),
      PrayerCheck('asr', 'Ashar', _currentPrayerTimes!.asr),
      PrayerCheck('maghrib', 'Maghrib', _currentPrayerTimes!.maghrib),
      PrayerCheck('isha', 'Isya', _currentPrayerTimes!.isha),
    ];
    
    for (final prayer in prayers) {
      if (prayer.time == timeStr) {
        final uniqueKey = '${prayer.key}-$today-$timeStr';
        
        if (!_announcedPrayers.contains(uniqueKey)) {
          _announcedPrayers.add(uniqueKey);
          _saveAnnouncedPrayers();
          
          final isJumat = prayer.key == 'dhuhr' && now.weekday == DateTime.friday;
          
          _triggerAdzan(prayer.name, isJumat);
          break;
        }
      }
    }
  }
  
  void _triggerAdzan(String prayerName, bool isJumat) {
    _adzanState = AdzanState.adzan;
    _adzanStateController.add(_adzanState);
    
    // Schedule iqamah after 3 minutes
    Future.delayed(const Duration(minutes: 3), () {
      _adzanState = AdzanState.iqamah;
      _adzanStateController.add(_adzanState);
      
      // Schedule blank mode after iqamah
      final blankDuration = isJumat ? 30 : (_currentPrayerTimes?.blankAfterIqamah ?? 10);
      
      Future.delayed(const Duration(minutes: 10), () {
        _adzanState = AdzanState.blank;
        _adzanStateController.add(_adzanState);
        
        // End blank mode after duration
        Future.delayed(Duration(minutes: blankDuration), () {
          _adzanState = AdzanState.idle;
          _adzanStateController.add(_adzanState);
        });
      });
    });
  }
  
  void _updateCountdown() {
    if (_currentPrayerTimes == null) return;
    
    final now = DateTime.now();
    final currentMin = now.hour * 60 + now.minute;
    final currentSeconds = now.second;
    
    final prayers = [
      TimeCheck('Subuh', _currentPrayerTimes!.fajr, _currentPrayerTimes!.iqamahFajr),
      TimeCheck('Dzuhur', _currentPrayerTimes!.dhuhr, _currentPrayerTimes!.iqamahDhuhr),
      TimeCheck('Ashar', _currentPrayerTimes!.asr, _currentPrayerTimes!.iqamahAsr),
      TimeCheck('Maghrib', _currentPrayerTimes!.maghrib, _currentPrayerTimes!.iqamahMaghrib),
      TimeCheck('Isya', _currentPrayerTimes!.isha, _currentPrayerTimes!.iqamahIsha),
    ];
    
    // Find active prayer (between prayer time and iqamah)
    for (final prayer in prayers) {
      final prayerMin = _timeToMinutes(prayer.time);
      final iqamahMin = _timeToMinutes(prayer.iqamah);
      
      if (currentMin >= prayerMin && currentMin < iqamahMin) {
        final diffMin = iqamahMin - currentMin;
        final totalSeconds = diffMin * 60 - currentSeconds;
        _countdownController.add(CountdownData(
          prayerName: '${prayer.name} (Sedang Berlangsung)',
          totalSeconds: totalSeconds,
          isActive: true,
        ));
        return;
      }
    }
    
    // Find next prayer
    for (final prayer in prayers) {
      final prayerMin = _timeToMinutes(prayer.time);
      if (prayerMin > currentMin) {
        final diffMin = prayerMin - currentMin;
        final totalSeconds = diffMin * 60 - currentSeconds;
        _countdownController.add(CountdownData(
          prayerName: prayer.name,
          totalSeconds: totalSeconds,
          isActive: false,
        ));
        return;
      }
    }
    
    // Tomorrow Fajr
    final fajrMin = _timeToMinutes(prayers[0].time);
    final diffMin = (24 * 60) - currentMin + fajrMin;
    final totalSeconds = diffMin * 60 - currentSeconds;
    _countdownController.add(CountdownData(
      prayerName: 'Subuh (Besok)',
      totalSeconds: totalSeconds,
      isActive: false,
    ));
  }
  
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  
  void setSyncToken(String token) {
    _prefs?.setString(SYNC_TOKEN_KEY, token);
    syncPrayerTimes();
  }
  
  String? getSyncToken() {
    return _prefs?.getString(SYNC_TOKEN_KEY);
  }
  
  void dispose() {
    _prayerCheckTimer?.cancel();
    _countdownTimer?.cancel();
    _prayerTimesController.close();
    _adzanStateController.close();
    _countdownController.close();
  }
}

class PrayerCheck {
  final String key;
  final String name;
  final String time;
  
  PrayerCheck(this.key, this.name, this.time);
}

class TimeCheck {
  final String name;
  final String time;
  final String iqamah;
  
  TimeCheck(this.name, this.time, this.iqamah);
}

class CountdownData {
  final String prayerName;
  final int totalSeconds;
  final bool isActive;
  
  CountdownData({
    required this.prayerName,
    required this.totalSeconds,
    required this.isActive,
  });
  
  String get formattedTime {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
