import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

import '../models/slide_data.dart';

final logger = Logger();

class SyncService {
  static const String BASE_URL = 'http://localhost:3001/api';
  static const String SYNC_INTERVAL = 'sync_interval';
  
  SharedPreferences? _prefs;
  Timer? _syncTimer;
  
  final _slidesController = StreamController<List<SlideData>>.broadcast();
  final _infoSlidesController = StreamController<List<SlideData>>.broadcast();
  final _runningTextController = StreamController<String>.broadcast();
  
  Stream<List<SlideData>> get slidesStream => _slidesController.stream;
  Stream<List<SlideData>> get infoSlidesStream => _infoSlidesController.stream;
  Stream<String> get runningTextStream => _runningTextController.stream;
  
  List<SlideData> _bgSlides = [];
  List<SlideData> _infoSlides = [];
  String _runningText = '';
  
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Start periodic sync
    _startSyncTimer();
    
    // Initial sync
    await syncAll();
  }
  
  void _startSyncTimer() {
    _syncTimer?.cancel();
    // Sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncAll();
    });
  }
  
  Future<void> syncAll() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      logger.w('No internet connection, using cached data');
      _loadCachedData();
      return;
    }
    
    await Future.wait([
      syncSlides(),
      syncInfoSlides(),
      syncRunningText(),
    ]);
  }
  
  Future<void> syncSlides() async {
    try {
      final token = _prefs?.getString('sync_token') ?? 'sample-masjid-001';
      
      final response = await http.get(
        Uri.parse('$BASE_URL/masjids/$token/announcements'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        _bgSlides = data
            .where((s) => s['displayMode'] != 'overlay' && s['isActive'] == true)
            .map((s) => SlideData.fromJson(s))
            .toList();
        
        _slidesController.add(_bgSlides);
        
        // Cache data
        _prefs?.setString('cached_bg_slides', jsonEncode(
          _bgSlides.map((s) => s.toJson()).toList(),
        ));
        
        logger.i('Synced ${_bgSlides.length} background slides');
      }
    } catch (e) {
      logger.e('Error syncing slides: $e');
    }
  }
  
  Future<void> syncInfoSlides() async {
    try {
      final token = _prefs?.getString('sync_token') ?? 'sample-masjid-001';
      
      final response = await http.get(
        Uri.parse('$BASE_URL/sync/data-live/$token'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['infoSlides'] != null) {
          final List<dynamic> slides = data['infoSlides'];
          _infoSlides = slides.map((s) => SlideData.fromJson(s)).toList();
          _infoSlidesController.add(_infoSlides);
          
          _prefs?.setString('cached_info_slides', jsonEncode(slides));
          
          logger.i('Synced ${_infoSlides.length} info slides');
        }
      }
    } catch (e) {
      logger.e('Error syncing info slides: $e');
    }
  }
  
  Future<void> syncRunningText() async {
    try {
      final token = _prefs?.getString('sync_token') ?? 'sample-masjid-001';
      
      final response = await http.get(
        Uri.parse('$BASE_URL/sync/data-live/$token'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['runningText'] != null) {
          _runningText = data['runningText'];
          _runningTextController.add(_runningText);
          
          _prefs?.setString('cached_running_text', _runningText);
          
          logger.i('Synced running text');
        }
      }
    } catch (e) {
      logger.e('Error syncing running text: $e');
    }
  }
  
  void _loadCachedData() {
    // Load cached background slides
    final cachedBg = _prefs?.getString('cached_bg_slides');
    if (cachedBg != null) {
      final List<dynamic> data = jsonDecode(cachedBg);
      _bgSlides = data.map((s) => SlideData.fromJson(s)).toList();
      _slidesController.add(_bgSlides);
    }
    
    // Load cached info slides
    final cachedInfo = _prefs?.getString('cached_info_slides');
    if (cachedInfo != null) {
      final List<dynamic> data = jsonDecode(cachedInfo);
      _infoSlides = data.map((s) => SlideData.fromJson(s)).toList();
      _infoSlidesController.add(_infoSlides);
    }
    
    // Load cached running text
    final cachedText = _prefs?.getString('cached_running_text');
    if (cachedText != null) {
      _runningText = cachedText;
      _runningTextController.add(_runningText);
    }
  }
  
  List<SlideData> get bgSlides => _bgSlides;
  List<SlideData> get infoSlides => _infoSlides;
  String get runningText => _runningText;
  
  void dispose() {
    _syncTimer?.cancel();
    _slidesController.close();
    _infoSlidesController.close();
    _runningTextController.close();
  }
}
