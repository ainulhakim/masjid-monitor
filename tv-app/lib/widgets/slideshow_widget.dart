import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../models/slide_data.dart';

class SlideshowWidget extends StatefulWidget {
  final List<SlideData> slides;
  final Duration interval;

  const SlideshowWidget({
    Key? key,
    required this.slides,
    this.interval = const Duration(seconds: 8),
  }) : super(key: key);

  @override
  State<SlideshowWidget> createState() => _SlideshowWidgetState();
}

class _SlideshowWidgetState extends State<SlideshowWidget> {
  int _currentIndex = 0;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _startSlideshow();
  }

  @override
  void didUpdateWidget(SlideshowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides != widget.slides) {
      _currentIndex = 0;
      _disposeVideoController();
      _startSlideshow();
    }
  }

  void _startSlideshow() {
    if (widget.slides.isEmpty) return;

    final currentSlide = widget.slides[_currentIndex];

    if (currentSlide.isVideo) {
      _initVideoController(currentSlide.url);
    } else {
      // Image slideshow timer
      Future.delayed(widget.interval, () {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.slides.length;
          });
          _startSlideshow();
        }
      });
    }
  }

  Future<void> _initVideoController(String url) async {
    _disposeVideoController();

    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();

      if (mounted) {
        setState(() {});
      }

      // Video duration timer for switching
      final duration = _videoController!.value.duration;
      Future.delayed(duration, () {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.slides.length;
          });
          _startSlideshow();
        }
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
      // Skip to next slide on error
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.slides.length;
        });
        _startSlideshow();
      }
    }
  }

  void _disposeVideoController() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      return Container(
        color: Colors.black,
      );
    }

    final currentSlide = widget.slides[_currentIndex];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1000),
      child: currentSlide.isVideo
          ? _buildVideoPlayer(currentSlide)
          : _buildImage(currentSlide),
    );
  }

  Widget _buildImage(SlideData slide) {
    return CachedNetworkImage(
      key: ValueKey(slide.id),
      imageUrl: slide.url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.black,
        child: const Center(
          child: Icon(
            Icons.error,
            color: Colors.white,
            size: 50,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(SlideData slide) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        key: ValueKey(slide.id),
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return SizedBox.expand(
      key: ValueKey(slide.id),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }
}
