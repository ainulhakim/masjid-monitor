import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:logger/logger.dart';

import 'screens/tv_display_screen.dart';
import 'services/prayer_service.dart';
import 'services/sync_service.dart';

final logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable wakelock to keep screen on
  await WakelockPlus.enable();
  
  // Set preferred orientations (landscape for TV)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Hide system UI (fullscreen)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // Initialize services
  final prayerService = PrayerService();
  final syncService = SyncService();
  
  await prayerService.initialize();
  await syncService.initialize();
  
  // Check if running on Android TV
  final isTV = await _checkIfTV();
  logger.i('Running on TV: $isTV');
  
  runApp(MasjidMonitorApp(
    prayerService: prayerService,
    syncService: syncService,
  ));
}

Future<bool> _checkIfTV() async {
  if (!Platform.isAndroid) return false;
  
  try {
    const platform = MethodChannel('masjid.monitor/device');
    final bool isTV = await platform.invokeMethod('isTV');
    return isTV;
  } catch (e) {
    return false;
  }
}

class MasjidMonitorApp extends StatelessWidget {
  final PrayerService prayerService;
  final SyncService syncService;
  
  const MasjidMonitorApp({
    Key? key,
    required this.prayerService,
    required this.syncService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Masjid Monitor TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: TVDisplayScreen(
        prayerService: prayerService,
        syncService: syncService,
      ),
    );
  }
}
