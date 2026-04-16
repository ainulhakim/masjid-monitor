class SlideData {
  final String id;
  final String url;
  final String type;
  final String title;
  final int duration;
  final String displayMode;
  final bool isActive;

  SlideData({
    required this.id,
    required this.url,
    required this.type,
    required this.title,
    required this.duration,
    required this.displayMode,
    required this.isActive,
  });

  factory SlideData.fromJson(Map<String, dynamic> json) {
    return SlideData(
      id: json['id'] ?? '',
      url: json['url'] ?? json['fileUrl'] ?? json['downloadUrl'] ?? '',
      type: json['type'] ?? 'image',
      title: json['title'] ?? '',
      duration: json['duration'] ?? 10,
      displayMode: json['displayMode'] ?? 'background',
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'type': type,
      'title': title,
      'duration': duration,
      'displayMode': displayMode,
      'isActive': isActive,
    };
  }

  bool get isVideo => type == 'video';
  bool get isImage => type == 'image';
  bool get isOverlay => displayMode == 'overlay';
  bool get isBackground => displayMode == 'background';
}
