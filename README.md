# 🕌 Masjid Monitor TV Display System

Sistem monitoring jadwal sholat untuk TV Box masjid dengan tampilan digital yang elegan.

## 📱 Fitur Utama

### TV Display (Flutter Android App)
- ✅ Jadwal sholat realtime dengan perhitungan otomatis
- ✅ Auto-startup saat TV Box dinyalakan
- ✅ Background slideshow dengan gambar masjid
- ✅ Adzan popup dengan countdown iqamah
- ✅ Info overlay berjalan (pengumuman masjid)
- ✅ Running text di bagian bawah
- ✅ Blank mode setelah iqamah (layar gelap dengan jam kecil)
- ✅ Highlight sholat aktif (hijau) & berikutnya (oranye)
- ✅ Tanggal Hijriyah otomatis

### Admin Panel (Web)
- ✅ Manajemen slide (upload gambar, atur urutan)
- ✅ Mode display: Background / Overlay
- ✅ Pengaturan jadwal sholat & iqamah
- ✅ Running text CRUD
- ✅ Generate sync token untuk TV

### Backend (Python Flask)
- ✅ API jadwal sholat dengan library `adhan`
- ✅ Database SQLite
- ✅ Template HTML dengan variable injection
- ✅ Real-time sync endpoint

## 📁 Struktur Project

```
masjid-monitor/
├── tv-app/                     # Flutter TV App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   ├── services/
│   │   ├── models/
│   │   └── widgets/
│   ├── android/
│   │   └── app/src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/masjid/monitor/
│   │           ├── MainActivity.kt
│   │           ├── BootReceiver.kt
│   │           ├── PrayerService.kt
│   │           └── ScreenOnReceiver.kt
│   └── pubspec.yaml
├── backend-python/             # Flask Backend
│   ├── app.py
│   └── requirements.txt
├── .github/
│   └── workflows/
│       └── build-apk.yml       # GitHub Actions
├── template-monitor-fixed.html # Template TV Display
├── admin-panel.html            # Panel Admin
└── README.md                   # File ini
```

## 🚀 Quick Start

### 1. Setup Backend
```bash
cd backend-python
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

Backend akan berjalan di `http://localhost:3001`

### 2. Buka Admin Panel
```
Buka browser → http://localhost:3000/admin.html
```

### 3. Install TV App
Download APK dari [Releases](../../releases) dan install ke TV Box.

## 📲 Install TV App ke Android TV Box

### Via ADB
```bash
# Connect ke TV Box
adb connect 192.168.1.xxx:5555

# Install APK
adb install -r masjid-monitor-tv-arm64.apk

# Jalankan
adb shell am start -n com.masjid.monitor/.MainActivity
```

### Via USB Flashdisk
1. Copy APK ke flashdisk
2. Colok ke TV Box
3. Buka File Manager → Install APK

### Setting TV Box (Wajib!)
- ✅ Enable "Unknown Sources" (Settings → Security)
- ✅ Enable "USB Debugging" (Settings → Developer Options)

## 🛠️ Build APK dari Source

### GitHub Actions (Otomatis)
1. Push kode ke GitHub
2. Buka tab "Actions"
3. Download APK dari Artifacts/Releases

### Manual Build
```bash
cd tv-app
flutter pub get
flutter build apk --target-platform android-arm64 --release
```

## 📡 API Endpoints

| Endpoint | Method | Deskripsi |
|----------|--------|-----------|
| `/api/prayer-times/<id>` | GET | Jadwal sholat |
| `/api/masjids/<id>/slides` | GET/POST | Kelola slide |
| `/api/masjids/<id>/running-texts` | GET/POST/PUT/DELETE | Running text |
| `/api/sync/data-live/<token>` | GET | Real-time sync |

## 🎨 Konfigurasi

### TV App
Edit file konfigurasi di `lib/services/sync_service.dart`:
```dart
static const String defaultBaseUrl = 'http://YOUR_IP:3001';
```

### Backend
Environment variables di `.env`:
```
FLASK_PORT=3001
FLASK_HOST=0.0.0.0
```

## 📋 Persyaratan

### Backend
- Python 3.9+
- SQLite

### TV App
- Flutter SDK 3.19+
- Android SDK (API 21+)
- TV Box dengan Android 5.0+

### Admin Panel
- Browser modern (Chrome/Firefox/Safari)

## 🤝 Kontribusi

Pull request dipersilakan! Untuk perubahan besar, harap buka issue dulu.

## 📄 Lisensi

MIT License - lihat file [LICENSE](LICENSE)

---

**Dibuat dengan ❤️ untuk kemudahan umat**
