#!/usr/bin/env python3
"""
Masjid Monitor - Backend API (Python/Flask)
Equivalent to Node.js/Express backend
"""

import os
import json
from datetime import datetime, timedelta
from functools import wraps
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['SECRET_KEY'] = 'masjid-monitor-secret-key'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///masjid.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JWT_SECRET_KEY'] = 'jwt-secret-key'
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50MB

CORS(app)
db = SQLAlchemy(app)
jwt = JWTManager(app)

# Create upload folder
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'announcements'), exist_ok=True)

# Import after db initialization
from prayer_times import calculate_prayer_times

# ============== MODELS ==============

class User(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    name = db.Column(db.String(100), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class Masjid(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    name = db.Column(db.String(200), nullable=False)
    address = db.Column(db.String(500))
    city = db.Column(db.String(100), nullable=False)
    country = db.Column(db.String(100), default='Indonesia')
    latitude = db.Column(db.Float, nullable=False)
    longitude = db.Column(db.Float, nullable=False)
    timezone = db.Column(db.String(50), default='Asia/Jakarta')
    
    calculation_method = db.Column(db.String(50), default='MUHAMMADIYAH')
    madhab = db.Column(db.String(50), default='SHAFI')
    adjustments = db.Column(db.String(500), default='{"fajr":0,"dhuhr":0,"asr":0,"maghrib":0,"isha":0}')
    
    iqamah_fajr = db.Column(db.Integer, default=5)
    iqamah_dhuhr = db.Column(db.Integer, default=5)
    iqamah_asr = db.Column(db.Integer, default=5)
    iqamah_maghrib = db.Column(db.Integer, default=5)
    iqamah_isha = db.Column(db.Integer, default=5)
    
    # Blank mode settings (minutes)
    blank_after_iqamah = db.Column(db.Integer, default=10)  # Default 10 menit blank
    blank_jumat_duration = db.Column(db.Integer, default=30)  # Default 30 menit untuk Jumat
    
    # Info overlay settings (seconds)
    main_display_duration = db.Column(db.Integer, default=10)  # Durasi tampilan utama
    info_slide_duration = db.Column(db.Integer, default=10)    # Durasi per slide info
    
    theme = db.Column(db.String(50), default='default')
    logo_url = db.Column(db.String(500))
    
    # Template system
    template_html = db.Column(db.Text, default='')
    template_enabled = db.Column(db.Boolean, default=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    announcements = db.relationship('Announcement', backref='masjid', lazy=True, cascade='all, delete-orphan')
    running_texts = db.relationship('RunningText', backref='masjid', lazy=True, cascade='all, delete-orphan')

class Announcement(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    masjid_id = db.Column(db.String(36), db.ForeignKey('masjid.id'), nullable=False)
    title = db.Column(db.String(200), nullable=False)
    type = db.Column(db.String(20), default='image')  # image or video
    file_url = db.Column(db.String(500), nullable=False)
    file_path = db.Column(db.String(500), nullable=False)
    duration = db.Column(db.Integer, default=10)
    order = db.Column(db.Integer, default=0)
    is_active = db.Column(db.Boolean, default=True)
    display_mode = db.Column(db.String(20), default='background')  # 'background' or 'overlay'
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class RunningText(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    masjid_id = db.Column(db.String(36), db.ForeignKey('masjid.id'), nullable=False)
    text = db.Column(db.String(500), nullable=False)
    order = db.Column(db.Integer, default=0)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class SyncToken(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    masjid_id = db.Column(db.String(36), db.ForeignKey('masjid.id'), nullable=False)
    token = db.Column(db.String(64), unique=True, nullable=False)
    device_name = db.Column(db.String(100))
    last_sync = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

# ============== ADZAN FEATURE MODELS ==============

class AudioAdzan(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    masjid_id = db.Column(db.String(36), db.ForeignKey('masjid.id'), nullable=False)
    name = db.Column(db.String(100), nullable=False)
    file_url = db.Column(db.String(500), nullable=False)
    file_path = db.Column(db.String(500), nullable=False)
    qari_name = db.Column(db.String(100))
    is_default = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class IqamahDuration(db.Model):
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(__import__('uuid').uuid4()))
    masjid_id = db.Column(db.String(36), db.ForeignKey('masjid.id'), nullable=False, unique=True)
    fajr = db.Column(db.Integer, default=10)
    dhuhr = db.Column(db.Integer, default=5)
    asr = db.Column(db.Integer, default=5)
    maghrib = db.Column(db.Integer, default=5)
    isha = db.Column(db.Integer, default=5)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

# ============== SEED DATA ==============

def seed_data():
    # Create admin user
    if not User.query.filter_by(email='admin@masjid.monitor').first():
        admin = User(
            email='admin@masjid.monitor',
            password=generate_password_hash('admin123'),
            name='Administrator'
        )
        db.session.add(admin)
        
        # Create sample masjid
        masjid = Masjid(
            id='sample-masjid-001',
            name='Masjid Al-Ikhlas',
            address='Jl. Contoh No. 123',
            city='Semarang',
            latitude=-6.9667,
            longitude=110.4167
        )
        db.session.add(masjid)
        db.session.flush()
        
        # Add sample running texts
        texts = [
            'Selamat datang di Masjid Al-Ikhlas',
            'Jangan lupa sholat berjamaah',
            'Infaq dan shadaqah dapat disalurkan ke kotak amal',
            'Kajian malam Jumat setelah sholat Isya'
        ]
        for i, text in enumerate(texts):
            rt = RunningText(masjid_id=masjid.id, text=text, order=i)
            db.session.add(rt)
        
        # Create default iqamah durations
        iqamah = IqamahDuration(
            masjid_id=masjid.id,
            fajr=10,
            dhuhr=5,
            asr=5,
            maghrib=5,
            isha=5
        )
        db.session.add(iqamah)
        
        db.session.commit()
        print('✅ Seed data created (with Adzan feature)')

# ============== API ROUTES ==============

@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'ok', 'timestamp': datetime.utcnow().isoformat()})

# Auth Routes
@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data.get('email')).first()
    
    if not user or not check_password_hash(user.password, data.get('password')):
        return jsonify({'error': 'Invalid credentials'}), 401
    
    access_token = create_access_token(identity=user.id)
    return jsonify({
        'token': access_token,
        'user': {
            'id': user.id,
            'email': user.email,
            'name': user.name
        }
    })

@app.route('/api/auth/register', methods=['POST'])
def register():
    data = request.get_json()
    
    if User.query.filter_by(email=data.get('email')).first():
        return jsonify({'error': 'Email already registered'}), 400
    
    user = User(
        email=data.get('email'),
        password=generate_password_hash(data.get('password')),
        name=data.get('name')
    )
    db.session.add(user)
    db.session.commit()
    
    access_token = create_access_token(identity=user.id)
    return jsonify({
        'token': access_token,
        'user': {
            'id': user.id,
            'email': user.email,
            'name': user.name
        }
    })

# Masjid Routes
@app.route('/api/masjids', methods=['GET'])
@jwt_required()
def get_masjids():
    masjids = Masjid.query.all()
    result = []
    for m in masjids:
        result.append({
            'id': m.id,
            'name': m.name,
            'address': m.address,
            'city': m.city,
            'country': m.country,
            'latitude': m.latitude,
            'longitude': m.longitude,
            'theme': m.theme,
            'calculation_method': m.calculation_method,
            '_count': {
                'announcements': len(m.announcements),
                'runningTexts': len(m.running_texts)
            }
        })
    return jsonify(result)

@app.route('/api/masjids', methods=['POST'])
@jwt_required()
def create_masjid():
    data = request.get_json()
    
    # Map camelCase to snake_case for model fields
    field_mapping = {
        'calculationMethod': 'calculation_method',
        'iqamahFajr': 'iqamah_fajr',
        'iqamahDhuhr': 'iqamah_dhuhr',
        'iqamahAsr': 'iqamah_asr',
        'iqamahMaghrib': 'iqamah_maghrib',
        'iqamahIsha': 'iqamah_isha'
    }
    
    # Convert field names
    model_data = {}
    for key, value in data.items():
        model_key = field_mapping.get(key, key)
        model_data[model_key] = value
    
    masjid = Masjid(**model_data)
    db.session.add(masjid)
    db.session.commit()
    
    # Create default iqamah durations
    iqamah = IqamahDuration(
        masjid_id=masjid.id,
        fajr=data.get('iqamahFajr', 10),
        dhuhr=data.get('iqamahDhuhr', 5),
        asr=data.get('iqamahAsr', 5),
        maghrib=data.get('iqamahMaghrib', 5),
        isha=data.get('iqamahIsha', 5)
    )
    db.session.add(iqamah)
    db.session.commit()
    
    # Auto-generate sync token for TV access
    token = create_sync_token(masjid.id)
    
    return jsonify({'id': masjid.id, 'name': masjid.name, 'token': token}), 201

@app.route('/api/masjids/<id>', methods=['GET'])
@jwt_required()
def get_masjid(id):
    m = Masjid.query.get_or_404(id)
    return jsonify({
        'id': m.id,
        'name': m.name,
        'address': m.address,
        'city': m.city,
        'country': m.country,
        'latitude': m.latitude,
        'longitude': m.longitude,
        'timezone': m.timezone,
        'calculationMethod': m.calculation_method,
        'madhab': m.madhab,
        'iqamahFajr': m.iqamah_fajr,
        'iqamahDhuhr': m.iqamah_dhuhr,
        'iqamahAsr': m.iqamah_asr,
        'iqamahMaghrib': m.iqamah_maghrib,
        'iqamahIsha': m.iqamah_isha,
        'theme': m.theme,
        'announcements': [{'id': a.id, 'title': a.title, 'type': a.type, 'fileUrl': a.file_url, 'duration': a.duration} for a in m.announcements if a.is_active],
        'runningTexts': [{'id': rt.id, 'text': rt.text} for rt in m.running_texts if rt.is_active]
    })

@app.route('/api/masjids/<id>', methods=['PUT'])
@jwt_required()
def update_masjid(id):
    m = Masjid.query.get_or_404(id)
    data = request.get_json()
    
    # Update fields
    m.name = data.get('name', m.name)
    m.address = data.get('address', m.address)
    m.city = data.get('city', m.city)
    m.country = data.get('country', m.country)
    m.latitude = data.get('latitude', m.latitude)
    m.longitude = data.get('longitude', m.longitude)
    m.timezone = data.get('timezone', m.timezone)
    m.calculation_method = data.get('calculationMethod', m.calculation_method)
    m.madhab = data.get('madhab', m.madhab)
    m.theme = data.get('theme', m.theme)
    
    # Update iqamah if provided
    if 'iqamahFajr' in data:
        m.iqamah_fajr = data['iqamahFajr']
    if 'iqamahDhuhr' in data:
        m.iqamah_dhuhr = data['iqamahDhuhr']
    if 'iqamahAsr' in data:
        m.iqamah_asr = data['iqamahAsr']
    if 'iqamahMaghrib' in data:
        m.iqamah_maghrib = data['iqamahMaghrib']
    if 'iqamahIsha' in data:
        m.iqamah_isha = data['iqamahIsha']
    
    db.session.commit()
    return jsonify({'success': True, 'message': 'Masjid updated successfully'})

@app.route('/api/masjids/<id>', methods=['DELETE'])
@jwt_required()
def delete_masjid(id):
    m = Masjid.query.get_or_404(id)
    db.session.delete(m)
    db.session.commit()
    return jsonify({'success': True, 'message': 'Masjid deleted successfully'})

@app.route('/api/masjids/<id>/prayer-times', methods=['GET'])
def get_prayer_times_route(id):
    m = Masjid.query.get_or_404(id)
    
    # Parse adjustments from JSON string
    try:
        adjustments = json.loads(m.adjustments or '{}')
    except:
        adjustments = {}
    
    # Calculate times with adjustments
    times = calculate_prayer_times(m.latitude, m.longitude, m.calculation_method, adjustments=adjustments)
    
    def add_minutes(time_str, minutes):
        h, min_val = map(int, time_str.split(':'))
        total = h * 60 + min_val + minutes
        return f"{total // 60:02d}:{total % 60:02d}"
    
    return jsonify({
        **times,
        'iqamah': {
            'fajr': add_minutes(times['fajr'], m.iqamah_fajr),
            'dhuhr': add_minutes(times['dhuhr'], m.iqamah_dhuhr),
            'asr': add_minutes(times['asr'], m.iqamah_asr),
            'maghrib': add_minutes(times['maghrib'], m.iqamah_maghrib),
            'isha': add_minutes(times['isha'], m.iqamah_isha)
        },
        'date': datetime.now().strftime('%Y-%m-%d'),
        'hijriDate': '14 Ramadan 1446 H'  # Simplified
    })

@app.route('/api/masjids/<id>/prayer-settings', methods=['GET', 'PUT'])
@jwt_required()
def prayer_settings(id):
    m = Masjid.query.get_or_404(id)
    
    if request.method == 'GET':
        # Parse adjustments
        try:
            adjustments = json.loads(m.adjustments or '{}')
        except:
            adjustments = {'fajr': 0, 'dhuhr': 0, 'asr': 0, 'maghrib': 0, 'isha': 0}
        
        return jsonify({
            'adjustments': adjustments,
            'iqamah': {
                'fajr': m.iqamah_fajr,
                'dhuhr': m.iqamah_dhuhr,
                'asr': m.iqamah_asr,
                'maghrib': m.iqamah_maghrib,
                'isha': m.iqamah_isha
            },
            'blankSettings': {
                'blankAfterIqamah': m.blank_after_iqamah,
                'blankJumatDuration': m.blank_jumat_duration
            },
            'overlaySettings': {
                'mainDisplayDuration': m.main_display_duration,
                'infoSlideDuration': m.info_slide_duration
            }
        })
    
    else:  # PUT
        data = request.get_json()
        
        # Update adjustments
        if 'adjustments' in data:
            m.adjustments = json.dumps(data['adjustments'])
        
        # Update iqamah durations
        if 'iqamah' in data:
            iqamah = data['iqamah']
            m.iqamah_fajr = iqamah.get('fajr', m.iqamah_fajr)
            m.iqamah_dhuhr = iqamah.get('dhuhr', m.iqamah_dhuhr)
            m.iqamah_asr = iqamah.get('asr', m.iqamah_asr)
            m.iqamah_maghrib = iqamah.get('maghrib', m.iqamah_maghrib)
            m.iqamah_isha = iqamah.get('isha', m.iqamah_isha)
        
        # Update blank settings
        if 'blankSettings' in data:
            blank = data['blankSettings']
            m.blank_after_iqamah = blank.get('blankAfterIqamah', m.blank_after_iqamah)
            m.blank_jumat_duration = blank.get('blankJumatDuration', m.blank_jumat_duration)
        
        # Update overlay settings
        if 'overlaySettings' in data:
            overlay = data['overlaySettings']
            m.main_display_duration = overlay.get('mainDisplayDuration', m.main_display_duration)
            m.info_slide_duration = overlay.get('infoSlideDuration', m.info_slide_duration)
        
        db.session.commit()
        return jsonify({'success': True, 'message': 'Prayer settings updated'})

# Template Routes
@app.route('/api/masjids/<masjid_id>/template', methods=['GET', 'PUT'])
@jwt_required()
def masjid_template(masjid_id):
    m = Masjid.query.get_or_404(masjid_id)
    
    if request.method == 'GET':
        return jsonify({
            'templateHtml': m.template_html or '',
            'templateEnabled': m.template_enabled or False
        })
    
    else:  # PUT
        data = request.get_json()
        if 'templateHtml' in data:
            m.template_html = data['templateHtml']
        if 'templateEnabled' in data:
            m.template_enabled = data['templateEnabled']
        
        db.session.commit()
        return jsonify({'success': True, 'message': 'Template updated'})

# Announcement Routes
@app.route('/api/masjids/<masjid_id>/announcements', methods=['GET'])
@jwt_required()
def get_announcements(masjid_id):
    anns = Announcement.query.filter_by(masjid_id=masjid_id).order_by(Announcement.order).all()
    return jsonify([{
        'id': a.id,
        'title': a.title,
        'type': a.type,
        'fileUrl': a.file_url,
        'duration': a.duration,
        'order': a.order,
        'isActive': a.is_active,
        'displayMode': a.display_mode
    } for a in anns])

@app.route('/api/masjids/<masjid_id>/announcements', methods=['POST'])
@jwt_required()
def create_announcement(masjid_id):
    if 'file' not in request.files:
        return jsonify({'error': 'File required'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    filename = secure_filename(file.filename)
    unique_name = f"{datetime.now().timestamp()}_{filename}"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], 'announcements', unique_name)
    file.save(filepath)
    
    file_type = 'video' if filename.lower().endswith(('.mp4', '.avi', '.mov', '.webm')) else 'image'
    
    ann = Announcement(
        masjid_id=masjid_id,
        title=request.form.get('title', filename),
        type=file_type,
        file_url=f'/uploads/announcements/{unique_name}',
        file_path=filepath,
        duration=int(request.form.get('duration', 10)),
        order=int(request.form.get('order', 0)),
        display_mode=request.form.get('displayMode', 'background')
    )
    db.session.add(ann)
    db.session.commit()
    
    return jsonify({'id': ann.id, 'title': ann.title, 'type': ann.type}), 201

@app.route('/api/masjids/<masjid_id>/announcements/<ann_id>', methods=['PUT'])
@jwt_required()
def update_announcement(masjid_id, ann_id):
    ann = Announcement.query.filter_by(id=ann_id, masjid_id=masjid_id).first_or_404()
    
    if request.is_json:
        data = request.get_json()
    else:
        data = request.form.to_dict()
    
    if 'title' in data:
        ann.title = data['title']
    if 'displayMode' in data:
        ann.display_mode = data['displayMode']
    if 'order' in data:
        ann.order = int(data['order'])
    if 'duration' in data:
        ann.duration = int(data['duration'])
    if 'isActive' in data:
        ann.is_active = bool(data['isActive'])
    
    db.session.commit()
    return jsonify({'message': 'Announcement updated', 'id': ann.id})

@app.route('/api/masjids/<masjid_id>/announcements/<ann_id>', methods=['DELETE'])
@jwt_required()
def delete_announcement(masjid_id, ann_id):
    ann = Announcement.query.filter_by(id=ann_id, masjid_id=masjid_id).first_or_404()
    
    # Delete file if exists
    if ann.file_path and os.path.exists(ann.file_path):
        try:
            os.remove(ann.file_path)
        except:
            pass
    
    db.session.delete(ann)
    db.session.commit()
    return jsonify({'message': 'Announcement deleted'})

# Running Text Routes
@app.route('/api/masjids/<masjid_id>/running-texts', methods=['GET'])
@jwt_required()
def get_running_texts(masjid_id):
    texts = RunningText.query.filter_by(masjid_id=masjid_id).order_by(RunningText.order).all()
    return jsonify([{
        'id': rt.id,
        'text': rt.text,
        'order': rt.order,
        'isActive': rt.is_active
    } for rt in texts])

@app.route('/api/masjids/<masjid_id>/running-texts', methods=['POST'])
@jwt_required()
def create_running_text(masjid_id):
    data = request.get_json()
    rt = RunningText(
        masjid_id=masjid_id,
        text=data.get('text'),
        order=data.get('order', 0)
    )
    db.session.add(rt)
    db.session.commit()
    return jsonify({'id': rt.id, 'text': rt.text}), 201

@app.route('/api/masjids/<masjid_id>/running-texts/<rt_id>', methods=['PUT'])
@jwt_required()
def update_running_text(masjid_id, rt_id):
    rt = RunningText.query.filter_by(id=rt_id, masjid_id=masjid_id).first_or_404()
    data = request.get_json()
    
    if 'text' in data:
        rt.text = data['text']
    if 'order' in data:
        rt.order = data['order']
    if 'isActive' in data:
        rt.is_active = data['isActive']
    
    db.session.commit()
    return jsonify({'message': 'Running text updated', 'id': rt.id})

@app.route('/api/masjids/<masjid_id>/running-texts/<rt_id>', methods=['DELETE'])
@jwt_required()
def delete_running_text(masjid_id, rt_id):
    rt = RunningText.query.filter_by(id=rt_id, masjid_id=masjid_id).first_or_404()
    db.session.delete(rt)
    db.session.commit()
    return jsonify({'message': 'Running text deleted'})

def create_sync_token(masjid_id, device_name='TV Monitor'):
    """Generate a unique sync token for TV access"""
    import secrets
    token = secrets.token_hex(32)
    
    sync = SyncToken(
        masjid_id=masjid_id,
        token=token,
        device_name=device_name
    )
    db.session.add(sync)
    db.session.commit()
    
    return token

# Sync Routes
@app.route('/api/sync/<masjid_id>/token', methods=['POST'])
@jwt_required()
def generate_sync_token_route(masjid_id):
    """API endpoint to generate a new sync token"""
    device_name = request.json.get('deviceName', 'Unknown')
    token = create_sync_token(masjid_id, device_name)
    return jsonify({'token': token, 'masjidId': masjid_id})

@app.route('/api/sync/data/<token>', methods=['GET'])
def sync_data(token):
    sync = SyncToken.query.filter_by(token=token).first_or_404()
    m = Masjid.query.get_or_404(sync.masjid_id)
    
    # Parse adjustments
    try:
        adjustments = json.loads(m.adjustments or '{}')
    except:
        adjustments = {}
    
    # Calculate times with adjustments
    times = calculate_prayer_times(m.latitude, m.longitude, m.calculation_method, adjustments=adjustments)
    
    # Calculate iqamah times
    def add_minutes(time_str, minutes):
        h, min_val = map(int, time_str.split(':'))
        total = h * 60 + min_val + minutes
        return f"{total // 60:02d}:{total % 60:02d}"
    
    times_with_iqamah = {
        **times,
        'iqamah': {
            'fajr': add_minutes(times['fajr'], m.iqamah_fajr),
            'dhuhr': add_minutes(times['dhuhr'], m.iqamah_dhuhr),
            'asr': add_minutes(times['asr'], m.iqamah_asr),
            'maghrib': add_minutes(times['maghrib'], m.iqamah_maghrib),
            'isha': add_minutes(times['isha'], m.iqamah_isha)
        }
    }
    
    base_url = request.host_url.rstrip('/')
    
    sync.last_sync = datetime.utcnow()
    db.session.commit()
    
    return jsonify({
        'masjid': {
            'id': m.id,
            'name': m.name,
            'city': m.city,
            'latitude': m.latitude,
            'longitude': m.longitude,
            'calculationMethod': m.calculation_method,
            'iqamah': {
                'fajr': m.iqamah_fajr,
                'dhuhr': m.iqamah_dhuhr,
                'asr': m.iqamah_asr,
                'maghrib': m.iqamah_maghrib,
                'isha': m.iqamah_isha
            }
        },
        'prayerTimes': times_with_iqamah,
        'announcements': [{
            'id': a.id,
            'title': a.title,
            'type': a.type,
            'url': f"{base_url}{a.file_url}",
            'downloadUrl': f"{base_url}{a.file_url}",
            'duration': a.duration
        } for a in m.announcements if a.is_active],
        'runningTexts': [{
            'id': rt.id,
            'text': rt.text
        } for rt in m.running_texts if rt.is_active],
        'syncDate': datetime.utcnow().isoformat()
    })

@app.route('/api/sync/template/<token>')
def sync_template(token):
    """Render custom HTML template with prayer data variables"""
    sync = SyncToken.query.filter_by(token=token).first_or_404()
    m = Masjid.query.get_or_404(sync.masjid_id)
    
    # If template not enabled or empty, return error
    if not m.template_enabled or not m.template_html:
        return jsonify({'error': 'Template not enabled or empty'}), 404
    
    # Parse adjustments
    try:
        adjustments = json.loads(m.adjustments or '{}')
    except:
        adjustments = {}
    
    # Calculate times
    times = calculate_prayer_times(m.latitude, m.longitude, m.calculation_method, adjustments=adjustments)
    
    # Calculate iqamah times
    def add_minutes(time_str, minutes):
        h, min_val = map(int, time_str.split(':'))
        total = h * 60 + min_val + minutes
        return f"{total // 60:02d}:{total % 60:02d}"
    
    iqamah_times = {
        'fajr': add_minutes(times['fajr'], m.iqamah_fajr),
        'dhuhr': add_minutes(times['dhuhr'], m.iqamah_dhuhr),
        'asr': add_minutes(times['asr'], m.iqamah_asr),
        'maghrib': add_minutes(times['maghrib'], m.iqamah_maghrib),
        'isha': add_minutes(times['isha'], m.iqamah_isha)
    }
    
    # Get running texts
    running_texts = [rt.text for rt in m.running_texts if rt.is_active]
    running_text = ' • '.join(running_texts) if running_texts else 'Selamat datang di Masjid'
    
    # Get slides - split by display_mode
    bg_slides = []
    info_slides = []
    for a in m.announcements:
        if a.is_active:
            slide_data = {
                'url': request.host_url.rstrip('/') + a.file_url,
                'type': a.type,
                'title': a.title
            }
            if a.display_mode == 'overlay':
                info_slides.append(slide_data)
            else:
                bg_slides.append(slide_data)
    
    # Default to all as background if no separation
    slides = bg_slides if bg_slides else info_slides
    if not slides:
        slides = info_slides
    
    # Current date/time
    now = datetime.now()
    
    # Replace template variables
    html = m.template_html
    
    # Prayer times
    html = html.replace('[WAKTU_SUBUH]', times['fajr'])
    html = html.replace('[WAKTU_TERBIT]', times['sunrise'])
    html = html.replace('[WAKTU_DZUHUR]', times['dhuhr'])
    html = html.replace('[WAKTU_ASHAR]', times['asr'])
    html = html.replace('[WAKTU_MAGHRIB]', times['maghrib'])
    html = html.replace('[WAKTU_ISYA]', times['isha'])
    
    # Iqamah times
    html = html.replace('[IQAMAH_SUBUH]', iqamah_times['fajr'])
    html = html.replace('[IQAMAH_DZUHUR]', iqamah_times['dhuhr'])
    html = html.replace('[IQAMAH_ASHAR]', iqamah_times['asr'])
    html = html.replace('[IQAMAH_MAGHRIB]', iqamah_times['maghrib'])
    html = html.replace('[IQAMAH_ISYA]', iqamah_times['isha'])
    
    # Iqamah durations (minutes)
    html = html.replace('[DURASI_IQAMAH_SUBUH]', str(m.iqamah_fajr))
    html = html.replace('[DURASI_IQAMAH_DZUHUR]', str(m.iqamah_dhuhr))
    html = html.replace('[DURASI_IQAMAH_ASHAR]', str(m.iqamah_asr))
    html = html.replace('[DURASI_IQAMAH_MAGHRIB]', str(m.iqamah_maghrib))
    html = html.replace('[DURASI_IQAMAH_ISYA]', str(m.iqamah_isha))
    
    # Masjid info
    html = html.replace('[NAMA_MASJID]', m.name or '')
    html = html.replace('[KOTA_MASJID]', m.city or '')
    html = html.replace('[ALAMAT_MASJID]', m.address or '')
    
    # Date/time
    html = html.replace('[TANGGAL]', now.strftime('%d %B %Y'))
    html = html.replace('[JAM]', now.strftime('%H:%M:%S'))
    html = html.replace('[HARI]', now.strftime('%A'))
    
    # Running text
    html = html.replace('[RUNNING_TEXT]', running_text)
    
    # Slides (JSON array for JS processing)
    html = html.replace('[SLIDES_JSON]', json.dumps(slides))
    html = html.replace('[INFO_SLIDES_JSON]', json.dumps(info_slides))
    
    # API Token for JS fetch
    html = html.replace('[SYNC_TOKEN]', token)
    html = html.replace('[API_BASE_URL]', request.host_url.rstrip('/') + '/api')
    
    # Add real-time update script
    # Slides data for JS
    slides_json = json.dumps(slides)
    info_slides_json = json.dumps(info_slides)
    
    # Settings data for JS
    overlay_settings_json = json.dumps({
        'mainDisplayDuration': m.main_display_duration or 10,
        'infoSlideDuration': m.info_slide_duration or 10
    })
    blank_settings_json = json.dumps({
        'blankAfterIqamah': m.blank_after_iqamah or 10,
        'blankJumatDuration': m.blank_jumat_duration or 30
    })
    
    realtime_script = '''
<script>
// Slides data from server
const SLIDES_DATA = ''' + slides_json + ''';
const INFO_SLIDES_DATA = ''' + info_slides_json + ''';
const OVERLAY_SETTINGS = ''' + overlay_settings_json + ''';
const BLANK_SETTINGS = ''' + blank_settings_json + ''';

// Real-time data updater
const API_BASE_URL = window.location.protocol + '//' + window.location.host + '/api';
const SYNC_TOKEN = window.location.pathname.split('/').pop();
const API_URL = API_BASE_URL + '/sync/data-live/' + SYNC_TOKEN;
let prayerData = null;
let nextPrayerInfo = null;

// Initialize slides if container exists
function initSlides() {
    const container = document.getElementById('slidesContainer') || document.querySelector('.slides-container');
    if (!container || !SLIDES_DATA || SLIDES_DATA.length === 0) return;
    
    let currentSlide = 0;
    
    function showSlide(index) {
        const slide = SLIDES_DATA[index];
        if (slide.type === 'video') {
            container.innerHTML = '<video src="' + slide.url + '" autoplay muted loop style="width:100%;height:100%;object-fit:contain;"></video>';
        } else {
            container.innerHTML = '<img src="' + slide.url + '" style="width:100%;height:100%;object-fit:contain;" alt="' + slide.title + '">';
        }
    }
    
    // Show first slide
    showSlide(0);
    
    // Rotate slides every 10 seconds
    setInterval(function() {
        currentSlide = (currentSlide + 1) % SLIDES_DATA.length;
        showSlide(currentSlide);
    }, 10000);
}

// Initialize slides on load
initSlides();

// Fetch data from API
async function fetchData() {
    try {
        const res = await fetch(API_URL);
        if (res.ok) {
            const data = await res.json();
            prayerData = data;
            updateDisplay();
        }
    } catch (error) {
        console.log('Fetch error:', error);
    }
}

// Update all display elements
function updateDisplay() {
    if (!prayerData) return;
    
    // Update prayer times - look for elements by structure
    const times = prayerData.prayerTimes;
    updatePrayerCard('Subuh', times.fajr, prayerData.iqamahTimes.fajr);
    updatePrayerCard('Terbit', times.sunrise, null);
    updatePrayerCard('Dzuhur', times.dhuhr, prayerData.iqamahTimes.dhuhr);
    updatePrayerCard('Ashar', times.asr, prayerData.iqamahTimes.asr);
    updatePrayerCard('Maghrib', times.maghrib, prayerData.iqamahTimes.maghrib);
    updatePrayerCard('Isya', times.isha, prayerData.iqamahTimes.isha);
    
    // Update running text (preserve animation)
    const rtContent = document.querySelector('.running-text-content');
    if (rtContent) {
        // Update content inside animated element
        const text = prayerData.runningText;
        // Duplicate text 3 times for seamless loop
        rtContent.textContent = text + ' • ' + text + ' • ' + text + ' • ';
    } else {
        // Fallback: try old selectors
        const rtEl = document.querySelector('.running-text');
        if (rtEl) {
            const marquee = rtEl.querySelector('marquee');
            if (marquee) {
                marquee.textContent = '📢 ' + prayerData.runningText;
            }
        }
    }
    
    // Calculate next prayer
    calculateNextPrayer(times);
}

// Helper to update prayer card
function updatePrayerCard(name, time, iqamah) {
    // Find card by h3 text content
    const cards = document.querySelectorAll('.prayer-card');
    for (let card of cards) {
        const h3 = card.querySelector('h3');
        if (h3 && h3.textContent.trim() === name) {
            const timeEl = card.querySelector('.time');
            if (timeEl) timeEl.textContent = time;
            const iqamahEl = card.querySelector('.iqamah');
            if (iqamahEl && iqamah) iqamahEl.textContent = 'Iqamah: ' + iqamah;
            break;
        }
    }
}

// Helper to update element
function updateElement(selector, value) {
    const el = document.querySelector(selector);
    if (el) el.textContent = value;
}

// Calculate next prayer and update countdown
function calculateNextPrayer(times) {
    const prayers = [
        { name: 'Subuh', time: times.fajr },
        { name: 'Terbit', time: times.sunrise },
        { name: 'Dzuhur', time: times.dhuhr },
        { name: 'Ashar', time: times.asr },
        { name: 'Maghrib', time: times.maghrib },
        { name: 'Isya', time: times.isha }
    ];
    
    const now = new Date();
    const currentMin = now.getHours() * 60 + now.getMinutes();
    
    for (let p of prayers) {
        const [h, m] = p.time.split(':').map(Number);
        const prayerMin = h * 60 + m;
        if (prayerMin > currentMin) {
            nextPrayerInfo = { name: p.name, minutes: prayerMin };
            updateElement('.next-prayer-name, #nextPrayerName', p.name);
            return;
        }
    }
    // If all prayers passed, next is tomorrow's Fajr
    nextPrayerInfo = { name: 'Subuh (Besok)', minutes: prayers[0].minutes + 24 * 60 };
    updateElement('.next-prayer-name, #nextPrayerName', 'Subuh (Besok)');
}

// Update clock and countdown
function updateClock() {
    const now = new Date();
    
    // Update clock - find by ID
    const clockEl = document.getElementById('liveClock');
    if (clockEl) {
        const timeStr = now.toLocaleTimeString('id-ID', { hour12: false });
        clockEl.textContent = timeStr;
    }
    
    // Update date
    const dateEl = document.querySelector('.live-date') || document.querySelector('.header p');
    if (dateEl) {
        const dateStr = now.toLocaleDateString('id-ID', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
        });
        // Only update if contains date-like content
        if (dateEl.textContent.includes('202') || dateEl.textContent.includes('Jan') || dateEl.textContent.includes('Feb')) {
            dateEl.textContent = dateStr;
        }
    }
    
    // Update countdown
    if (nextPrayerInfo) {
        const currentMin = now.getHours() * 60 + now.getMinutes();
        const diff = nextPrayerInfo.minutes - currentMin;
        if (diff > 0) {
            const h = Math.floor(diff / 60);
            const m = diff % 60;
            const s = 59 - now.getSeconds();
            const countdown = `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
            const countdownEl = document.getElementById('countdown');
            if (countdownEl) countdownEl.textContent = countdown;
        }
    }
}

// Initialize
fetchData();
setInterval(fetchData, 30000); // Fetch every 30 seconds
setInterval(updateClock, 1000); // Update clock every second
updateClock();
</script>
</body>'''
    
    # Inject before closing body tag or append at end
    if '</body>' in html.lower():
        html = html.replace('</body>', realtime_script)
        html = html.replace('</BODY>', realtime_script)
    else:
        html += realtime_script
    
    return html, 200, {'Content-Type': 'text/html'}

# ============== ADZAN ROUTES ==============

@app.route('/api/masjids/<masjid_id>/adzan-settings', methods=['GET'])
def get_adzan_settings(masjid_id):
    m = Masjid.query.get_or_404(masjid_id)
    audio = AudioAdzan.query.filter_by(masjid_id=masjid_id, is_default=True).first()
    iqamah = IqamahDuration.query.filter_by(masjid_id=masjid_id).first()
    
    if not iqamah:
        iqamah = IqamahDuration(masjid_id=masjid_id)
        db.session.add(iqamah)
        db.session.commit()
    
    return jsonify({
        'enabled': True,  # TODO: add to model
        'audio': {
            'id': audio.id if audio else None,
            'name': audio.name if audio else 'Default',
            'qari': audio.qari_name if audio else 'Ali Mullah',
            'url': audio.file_url if audio else None
        } if audio else None,
        'iqamahDurations': {
            'fajr': iqamah.fajr,
            'dhuhr': iqamah.dhuhr,
            'asr': iqamah.asr,
            'maghrib': iqamah.maghrib,
            'isha': iqamah.isha
        }
    })

@app.route('/api/masjids/<masjid_id>/adzan-settings', methods=['PUT'])
@jwt_required()
def update_adzan_settings(masjid_id):
    data = request.get_json()
    iqamah = IqamahDuration.query.filter_by(masjid_id=masjid_id).first()
    
    if not iqamah:
        iqamah = IqamahDuration(masjid_id=masjid_id)
        db.session.add(iqamah)
    
    durations = data.get('iqamahDurations', {})
    iqamah.fajr = durations.get('fajr', iqamah.fajr)
    iqamah.dhuhr = durations.get('dhuhr', iqamah.dhuhr)
    iqamah.asr = durations.get('asr', iqamah.asr)
    iqamah.maghrib = durations.get('maghrib', iqamah.maghrib)
    iqamah.isha = durations.get('isha', iqamah.isha)
    
    db.session.commit()
    return jsonify({'success': True})

@app.route('/api/masjids/<masjid_id>/adzan-audio', methods=['GET'])
@jwt_required()
def get_adzan_audio_list(masjid_id):
    audios = AudioAdzan.query.filter_by(masjid_id=masjid_id).all()
    return jsonify([{
        'id': a.id,
        'name': a.name,
        'qari': a.qari_name,
        'url': a.file_url,
        'isDefault': a.is_default
    } for a in audios])

@app.route('/api/masjids/<masjid_id>/adzan-audio', methods=['POST'])
@jwt_required()
def upload_adzan_audio(masjid_id):
    if 'file' not in request.files:
        return jsonify({'error': 'File required'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    if not file.filename.endswith('.mp3'):
        return jsonify({'error': 'Only MP3 files allowed'}), 400
    
    filename = secure_filename(file.filename)
    unique_name = f"adzan_{datetime.now().timestamp()}_{filename}"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], 'adzan', unique_name)
    file.save(filepath)
    
    # If this is the first audio, set as default
    existing = AudioAdzan.query.filter_by(masjid_id=masjid_id).count()
    
    audio = AudioAdzan(
        masjid_id=masjid_id,
        name=request.form.get('name', filename),
        qari_name=request.form.get('qariName', 'Unknown'),
        file_url=f'/uploads/adzan/{unique_name}',
        file_path=filepath,
        is_default=(existing == 0)
    )
    db.session.add(audio)
    db.session.commit()
    
    return jsonify({
        'id': audio.id,
        'name': audio.name,
        'url': audio.file_url
    }), 201

# ============== FILE SERVING ==============

@app.route('/uploads/<path:filename>')
def serve_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

# ============== SYNC TOKEN ROUTES ==============

@app.route('/api/masjids/<masjid_id>/sync-tokens', methods=['GET'])
@jwt_required()
def get_sync_tokens(masjid_id):
    tokens = SyncToken.query.filter_by(masjid_id=masjid_id).all()
    return jsonify([{
        'id': t.id,
        'token': t.token,
        'deviceName': t.device_name,
        'createdAt': t.created_at.isoformat() if t.created_at else None,
        'lastSync': t.last_sync.isoformat() if t.last_sync else None
    } for t in tokens])

@app.route('/api/masjids/<masjid_id>/sync-tokens', methods=['POST'])
@jwt_required()
def create_sync_token_for_masjid(masjid_id):
    import secrets
    token = secrets.token_hex(32)
    
    sync = SyncToken(
        masjid_id=masjid_id,
        token=token,
        device_name='TV Monitor'
    )
    db.session.add(sync)
    db.session.commit()
    
    return jsonify({'token': token, 'masjidId': masjid_id}), 201


@app.route('/api/sync/data-live/<token>', methods=['GET'])
def sync_data_live(token):
    """Return JSON data for real-time template updates"""
    sync = SyncToken.query.filter_by(token=token).first()
    if not sync:
        return jsonify({'error': 'Token not found', 'token': token}), 404
    m = Masjid.query.get(sync.masjid_id)
    if not m:
        return jsonify({'error': 'Masjid not found'}), 404
    
    # Parse adjustments
    try:
        adjustments = json.loads(m.adjustments or '{}')
    except:
        adjustments = {}
    
    # Calculate times
    times = calculate_prayer_times(m.latitude, m.longitude, m.calculation_method, adjustments=adjustments)
    
    # Calculate iqamah times
    def add_minutes(time_str, minutes):
        h, min_val = map(int, time_str.split(':'))
        total = h * 60 + min_val + minutes
        return f"{total // 60:02d}:{total % 60:02d}"
    
    iqamah_times = {
        'fajr': add_minutes(times['fajr'], m.iqamah_fajr),
        'dhuhr': add_minutes(times['dhuhr'], m.iqamah_dhuhr),
        'asr': add_minutes(times['asr'], m.iqamah_asr),
        'maghrib': add_minutes(times['maghrib'], m.iqamah_maghrib),
        'isha': add_minutes(times['isha'], m.iqamah_isha)
    }
    
    # Get running texts
    running_texts = [rt.text for rt in m.running_texts if rt.is_active]
    
    # Get info slides for overlay
    info_slides = [{
        'url': request.host_url.rstrip('/') + a.file_url,
        'type': a.type,
        'title': a.title
    } for a in m.announcements if a.is_active and a.display_mode == 'overlay']
    
    # Current time
    now = datetime.now()
    
    return jsonify({
        'masjid': {
            'name': m.name,
            'city': m.city,
            'address': m.address
        },
        'prayerTimes': times,
        'iqamahTimes': iqamah_times,
        'iqamahConfig': {
            'fajr': m.iqamah_fajr,
            'dhuhr': m.iqamah_dhuhr,
            'asr': m.iqamah_asr,
            'maghrib': m.iqamah_maghrib,
            'isha': m.iqamah_isha
        },
        'runningText': ' • '.join(running_texts) if running_texts else 'Selamat datang di Masjid',
        'infoSlides': info_slides,
        'blankSettings': {
            'blankAfterIqamah': m.blank_after_iqamah,
            'blankJumatDuration': m.blank_jumat_duration
        },
        'overlaySettings': {
            'mainDisplayDuration': m.main_display_duration,
            'infoSlideDuration': m.info_slide_duration
        },
        'serverTime': now.isoformat()
    })

# ============== MAIN ==============

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        seed_data()
    
    print("🚀 Masjid Monitor Backend (Python)")
    print("   API: http://localhost:3001")
    print("   Admin: admin@masjid.monitor / admin123")
    
    app.run(host='0.0.0.0', port=3001, debug=False)
