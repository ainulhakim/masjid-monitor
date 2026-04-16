enum AdzanState {
  idle,
  adzan,
  iqamah,
  blank,
}

extension AdzanStateExtension on AdzanState {
  bool get isIdle => this == AdzanState.idle;
  bool get isAdzan => this == AdzanState.adzan;
  bool get isIqamah => this == AdzanState.iqamah;
  bool get isBlank => this == AdzanState.blank;
  
  String get displayText {
    switch (this) {
      case AdzanState.idle:
        return '';
      case AdzanState.adzan:
        return 'Waktu Adzan';
      case AdzanState.iqamah:
        return 'Menuju Iqamah';
      case AdzanState.blank:
        return 'Sedang Berlangsung Sholat';
    }
  }
}
