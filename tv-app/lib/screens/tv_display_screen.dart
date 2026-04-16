import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:hijri/hijri_calendar.dart';

import '../services/prayer_service.dart';
import '../services/sync_service.dart';
import '../models/prayer_times.dart';
import '../models/adzan_state.dart';
import '../models/slide_data.dart';
import '../widgets/slideshow_widget.dart';
import '../widgets/adzan_overlay.dart';
import '../widgets/blank_mode.dart';

class TVDisplayScreen extends StatefulWidget {
  final PrayerService prayerService;
  final SyncService syncService;

  const TVDisplayScreen({
    Key? key,
    required this.prayerService,
    required this.syncService,
  }) : super(key: key);

  @override
  State<TVDisplayScreen> createState() => _TVDisplayScreenState();
}

class _TVDisplayScreenState extends State<TVDisplayScreen> {
  PrayerTimesData? _prayerTimes;
  AdzanState _adzanState = AdzanState.idle;
  CountdownData? _countdown;
  List<SlideData> _bgSlides = [];
  List<SlideData> _infoSlides = [];
  String _runningText = '';
  bool _showInfoOverlay = false;
  int _currentInfoSlideIndex = 0;
  
  Timer? _infoOverlayTimer;
  Timer? _mainDisplayTimer;
  
  @override
  void initState() {
    super.initState();
    _setupStreams();
    _startInfoOverlayCycle();
  }

  void _setupStreams() {
    // Prayer times
    widget.prayerService.prayerTimesStream.listen((data) {
      setState(() => _prayerTimes = data);
    });

    // Adzan state
    widget.prayerService.adzanStateStream.listen((state) {
      setState(() => _adzanState = state);
      
      if (state.isAdzan || state.isIqamah || state.isBlank) {
        _stopInfoOverlay();
      } else {
        _startInfoOverlayCycle();
      }
    });

    // Countdown
    widget.prayerService.countdownStream.listen((data) {
      setState(() => _countdown = data);
    });

    // Slides
    widget.syncService.slidesStream.listen((slides) {
      setState(() => _bgSlides = slides);
    });

    widget.syncService.infoSlidesStream.listen((slides) {
      setState(() => _infoSlides = slides);
    });

    // Running text
    widget.syncService.runningTextStream.listen((text) {
      setState(() => _runningText = text);
    });
  }

  void _startInfoOverlayCycle() {
    if (_infoSlides.isEmpty) return;
    
    _stopInfoOverlay();
    
    // Show main display first
    setState(() => _showInfoOverlay = false);
    
    // Then show overlay after delay
    _mainDisplayTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _adzanState.isIdle) {
        _showInfoOverlaySequence();
      }
    });
  }

  void _showInfoOverlaySequence() {
    if (_infoSlides.isEmpty) return;
    
    setState(() {
      _showInfoOverlay = true;
      _currentInfoSlideIndex = 0;
    });

    // Cycle through info slides
    _infoOverlayTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_adzanState.isIdle) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _currentInfoSlideIndex++;
        if (_currentInfoSlideIndex >= _infoSlides.length) {
          // End of sequence, go back to main
          timer.cancel();
          _startInfoOverlayCycle();
        }
      });
    });
  }

  void _stopInfoOverlay() {
    _infoOverlayTimer?.cancel();
    _mainDisplayTimer?.cancel();
    setState(() => _showInfoOverlay = false);
  }

  @override
  void dispose() {
    _infoOverlayTimer?.cancel();
    _mainDisplayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background slideshow
          _buildBackground(),
          
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.6),
                ],
                stops: const [0.0, 0.3, 0.6, 1.0],
              ),
            ),
          ),
          
          // Main content (shown when not in adzan/iqamah/blank mode)
          if (_adzanState.isIdle) _buildMainContent(),
          
          // Adzan overlay
          if (_adzanState.isAdzan)
            AdzanOverlay(
              prayerName: _getCurrentPrayerName(),
              onComplete: () {},
            ),
          
          // Iqamah overlay
          if (_adzanState.isIqamah)
            IqamahOverlay(
              prayerName: _getCurrentPrayerName(),
              durationMinutes: 10,
              onComplete: () {},
            ),
          
          // Blank mode
          if (_adzanState.isBlank)
            BlankMode(
              message: DateTime.now().weekday == DateTime.friday 
                  ? 'Waktu Sholat Jumat' 
                  : 'Sedang Berlangsung Sholat',
            ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    if (_bgSlides.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF0277BD)],
          ),
        ),
      );
    }
    
    return SlideshowWidget(
      slides: _bgSlides,
      interval: const Duration(seconds: 8),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // Header (20%)
        _buildHeader(),
        
        // Middle section with countdown or info overlay
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Countdown (shown when no info overlay)
              if (!_showInfoOverlay) _buildCountdown(),
              
              // Info overlay (shown when active)
              if (_showInfoOverlay && _infoSlides.isNotEmpty)
                _buildInfoOverlay(),
            ],
          ),
        ),
        
        // Prayer bar (15%)
        _buildPrayerBar(),
        
        // Running text (8%)
        _buildRunningText(),
      ],
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final hijri = HijriCalendar.now();
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.20,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.black.withOpacity(0.3),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Masjid info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🕌 ${_prayerTimes?.masjidName ?? 'Masjid'}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 8,
                      color: Colors.black,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _prayerTimes?.masjidAddress ?? 'Alamat',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              Text(
                _prayerTimes?.masjidCity ?? 'Kota',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
          
          // Clock and date
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
                builder: (context, snapshot) {
                  final now = DateTime.now();
                  return Text(
                    DateFormat('HH:mm:ss').format(now),
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                      color: Colors.yellow,
                      shadows: [
                        Shadow(
                          blurRadius: 20,
                          color: Colors.yellow,
                        ),
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 5),
              Text(
                DateFormat('EEEE, d MMMM yyyy', 'id').format(now),
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
              Text(
                '${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} H',
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown() {
    if (_countdown == null) return const SizedBox.shrink();
    
    return AnimatedOpacity(
      opacity: _showInfoOverlay ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 500),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 30),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.yellow.withOpacity(0.4),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _countdown!.isActive 
                  ? 'Sedang Berlangsung' 
                  : 'Menuju Waktu Sholat',
              style: TextStyle(
                fontSize: 28,
                color: Colors.white.withOpacity(0.9),
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _countdown!.prayerName,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.yellow,
                shadows: [
                  Shadow(
                    blurRadius: 20,
                    color: Colors.yellow,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _countdown!.formattedTime,
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
                color: _countdown!.isActive ? Colors.green : Colors.green,
                shadows: const [
                  Shadow(
                    blurRadius: 30,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            if (_countdown!.isActive)
              Text(
                'Menuju Iqamah',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoOverlay() {
    if (_infoSlides.isEmpty) return const SizedBox.shrink();
    
    final slide = _infoSlides[_currentInfoSlideIndex];
    
    return AnimatedOpacity(
      opacity: _showInfoOverlay ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 50),
        height: MediaQuery.of(context).size.height * 0.38,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (slide.isImage)
                Expanded(
                  child: Image.network(
                    slide.url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Colors.white, size: 50),
                      );
                    },
                  ),
                ),
              if (slide.title.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(15),
                  child: Text(
                    slide.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.yellow,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerBar() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.12,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.8),
            const Color(0xFF0D47A1).withOpacity(0.7),
            const Color(0xFF0D47A1).withOpacity(0.7),
            Colors.black.withOpacity(0.8),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.15),
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPrayerItem('Subuh', _prayerTimes?.fajr ?? '--:--', _prayerTimes?.iqamahFajr, 'fajr'),
          _buildPrayerItem('Terbit', _prayerTimes?.sunrise ?? '--:--', null, 'sunrise'),
          _buildPrayerItem('Dzuhur', _prayerTimes?.dhuhr ?? '--:--', _prayerTimes?.iqamahDhuhr, 'dhuhr'),
          _buildPrayerItem('Ashar', _prayerTimes?.asr ?? '--:--', _prayerTimes?.iqamahAsr, 'asr'),
          _buildPrayerItem('Maghrib', _prayerTimes?.maghrib ?? '--:--', _prayerTimes?.iqamahMaghrib, 'maghrib'),
          _buildPrayerItem('Isya', _prayerTimes?.isha ?? '--:--', _prayerTimes?.iqamahIsha, 'isha'),
        ],
      ),
    );
  }

  Widget _buildPrayerItem(String name, String time, String? iqamah, String key) {
    final isNext = _countdown?.prayerName.contains(name) ?? false;
    final isActive = _countdown?.isActive ?? false;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: isNext || (isActive && name == _countdown?.prayerName)
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  if (isActive && name == _countdown?.prayerName)
                    Colors.green.withOpacity(0.6)
                  else
                    Colors.orange.withOpacity(0.5),
                  if (isActive && name == _countdown?.prayerName)
                    Colors.lightGreen.withOpacity(0.5)
                  else
                    Colors.deepOrange.withOpacity(0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? Colors.green : Colors.orange,
                width: isActive ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isActive ? Colors.green : Colors.orange).withOpacity(0.4),
                  blurRadius: isActive ? 30 : 15,
                ),
              ],
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 18,
              color: isActive && name == _countdown?.prayerName
                  ? Colors.white
                  : isNext
                      ? Colors.yellow
                      : Colors.white.withOpacity(0.7),
              fontWeight: isNext || (isActive && name == _countdown?.prayerName)
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            time,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
              color: isActive && name == _countdown?.prayerName
                  ? Colors.yellow
                  : Colors.white,
              shadows: isActive && name == _countdown?.prayerName
                  ? const [
                      Shadow(
                        blurRadius: 15,
                        color: Colors.yellow,
                      ),
                    ]
                  : null,
            ),
          ),
          if (iqamah != null && iqamah.isNotEmpty)
            Text(
              iqamah,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRunningText() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.08,
      color: Colors.black.withOpacity(0.85),
      child: Stack(
        children: [
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black,
                  Colors.black.withOpacity(0.95),
                  Colors.transparent,
                ],
              ),
            ),
            child: const Center(
              child: Text(
                '📢 INFO',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.yellow,
                ),
              ),
            ),
          ),
          
          // Scrolling text
          Padding(
            padding: const EdgeInsets.only(left: 100),
            child: Center(
              child: _runningText.isNotEmpty
                  ? Marquee(
                      text: _runningText,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  String _getCurrentPrayerName() {
    // This should return the current prayer based on time
    // For now, return from countdown
    return _countdown?.prayerName.replaceAll(' (Sedang Berlangsung)', '') ?? 'Sholat';
  }
}

// Simple marquee widget for running text
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;

  const Marquee({
    Key? key,
    required this.text,
    required this.style,
  }) : super(key: key);

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _animation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(-1.0, 0.0),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SlideTransition(
        position: _animation,
        child: Text(
          widget.text,
          style: widget.style,
          softWrap: false,
        ),
      ),
    );
  }
}
