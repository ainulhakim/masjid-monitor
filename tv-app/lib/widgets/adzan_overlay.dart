import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class AdzanOverlay extends StatefulWidget {
  final String prayerName;
  final VoidCallback onComplete;

  const AdzanOverlay({
    Key? key,
    required this.prayerName,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<AdzanOverlay> createState() => _AdzanOverlayState();
}

class _AdzanOverlayState extends State<AdzanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _playAdzan();
  }

  Future<void> _playAdzan() async {
    try {
      // Try to play from assets first
      await _audioPlayer.play(AssetSource('audio/adzan.mp3'));
      _isPlaying = true;
    } catch (e) {
      // If no local file, play from network or skip
      debugPrint('Could not play adzan audio: $e');
    }

    // Auto close after 3 minutes
    Future.delayed(const Duration(minutes: 3), () {
      if (mounted) {
        _audioPlayer.stop();
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D47A1).withOpacity(0.98),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.15),
                child: const Text(
                  '🕌',
                  style: TextStyle(fontSize: 150),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          const Text(
            'Waktu Adzan',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.prayerName,
            style: const TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.bold,
              color: Colors.yellow,
              shadows: [
                Shadow(
                  blurRadius: 40,
                  color: Colors.yellow,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Hayya \'alas Sholah',
            style: TextStyle(
              fontSize: 28,
              color: Colors.white70,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 50),
          if (_isPlaying)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.volume_up,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Memainkan Adzan...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class IqamahOverlay extends StatefulWidget {
  final String prayerName;
  final int durationMinutes;
  final VoidCallback onComplete;

  const IqamahOverlay({
    Key? key,
    required this.prayerName,
    required this.durationMinutes,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<IqamahOverlay> createState() => _IqamahOverlayState();
}

class _IqamahOverlayState extends State<IqamahOverlay> {
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationMinutes * 60;

    // Countdown timer
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;

      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        widget.onComplete();
        return false;
      }
      return true;
    });
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B5E20).withOpacity(0.98),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Menuju Iqamah',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.prayerName,
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 3,
              ),
            ),
            child: Text(
              _formattedTime,
              style: const TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
                color: Colors.yellow,
                shadows: [
                  Shadow(
                    blurRadius: 40,
                    color: Colors.yellow,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'Persiapkan diri untuk sholat berjamaah',
            style: TextStyle(
              fontSize: 22,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class BlankMode extends StatefulWidget {
  final String message;

  const BlankMode({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  State<BlankMode> createState() => _BlankModeState();
}

class _BlankModeState extends State<BlankMode> {
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();

    // Update clock every second
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _currentTime = DateTime.now());
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0A0A),
            Color(0xFF1A1A2E),
            Color(0xFF0F0F23),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '🤲',
            style: TextStyle(fontSize: 80),
          ),
          const SizedBox(height: 30),
          Text(
            '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 100,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
              color: Colors.green,
              shadows: [
                Shadow(
                  blurRadius: 30,
                  color: Colors.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${_currentTime.day}/${_currentTime.month}/${_currentTime.year}',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.yellow.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Text(
              widget.message,
              style: const TextStyle(
                fontSize: 32,
                color: Colors.yellow,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
