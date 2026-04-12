import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/athlete.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'flyfeet_v10.db');
    return await openDatabase(
      path,
      version: 6, // Bumped to 6 to force-fix duplicate sensors
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _seedDatabase(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _upgradeToV2(db);
    if (oldVersion < 3) await _upgradeToV3(db);
    if (oldVersion < 4) await _upgradeToV4(db);
    
    if (oldVersion < 6) {
      // Force clean sensors table to remove duplicates and apply UNIQUE constraint
      await db.execute('DROP TABLE IF EXISTS sensors');
      await _upgradeToV3(db);
    }

    await _seedDatabase(db);
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercises (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          code TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          level INTEGER NOT NULL DEFAULT 1,
          objective TEXT NOT NULL,
          modality TEXT NOT NULL,
          parameters TEXT NOT NULL,
          board_size INTEGER NOT NULL,
          active INTEGER DEFAULT 1,
          FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeToV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sensors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sensor INTEGER UNIQUE,
          layout TEXT,
          sector TEXT,
          expected_foot TEXT,
          dist_center INTEGER,
          dist_center_cm REAL,
          q INTEGER,
          r INTEGER,
          x_c INTEGER,
          y_c INTEGER,
          angle REAL,
          angle_norm REAL,
          range_type TEXT,
          neighbors TEXT
      )
    ''');
  }

  Future<void> _upgradeToV4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movement_ranges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          range_type TEXT UNIQUE,
          angle_min REAL,
          angle_max REAL,
          description TEXT
      )
    ''');
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE athletes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        gender TEXT NOT NULL,
        country TEXT NOT NULL,
        birth TEXT NOT NULL,
        dominant_foot TEXT NOT NULL,
        position TEXT NOT NULL,
        profile BLOB NOT NULL,
        timestamp TEXT DEFAULT (datetime('now'))
      )
    ''');

    await _upgradeToV2(db);
    await _upgradeToV3(db);
    await _upgradeToV4(db);
  }

  Future<void> _seedDatabase(Database db) async {
    // Seed Categories (Use INSERT OR IGNORE to avoid duplicates during upgrade)
    await db.execute('''
      INSERT OR IGNORE INTO categories (id, code, name, description) VALUES
      (1, 'cognitive', 'Cognitive', 'Exercises that improve decision-making, memory, and attention.'),
      (2, 'performance', 'Performance', 'Exercises focused on reaction time and execution speed.'),
      (3, 'coordination', 'Coordination', 'Exercises that improve precision and motor control.'),
      (4, 'conditioning', 'Conditioning', 'Exercises for endurance, intensity, and training volume.')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO exercises (category_id, code, name, description, level, objective, modality, parameters, board_size, active) VALUES
      (2, 'sv_002', 'Lite Light Tap', 'Touch the light that appears.', 1, 'Reaction time', 'Single-Touch', '{"parameters": {"stimuli_count": 14, "stimuli_generation_mode": "random", "stimuli_sequence": [], "delay_type": "fixed", "delay_range_ms": [700], "execution_rounds": 1, "stimulus_type": "color", "correct_color": "#00FF00"}}', 14, 1)
    ''');

    // Seed Movement Ranges
    await db.execute('''
      INSERT OR IGNORE INTO movement_ranges (range_type, angle_min, angle_max, description) VALUES
      ('direct_extension', 0, 60, 'The athlete reaches only with leg/hip extension, no body rotation'),
      ('transition', 60, 120, 'The athlete may choose extension or partial pivot rotation'),
      ('pivot_rotation', 120, 180, 'Requires pivot or body rotation to reach')
    ''');

    // Seed Sensors
    // Clear existing sensors first to avoid duplicates and fix coordinate errors
    await db.delete('sensors');

    final List<Map<String, dynamic>> sensors = [
      {'sensor': 1, 'layout': 'home', 'sector': 'Diagonal Left Up', 'expected_foot': 'Left', 'dist_center': 1, 'dist_center_cm': 29.99, 'q': -2, 'r': 0, 'x_c': -25.97, 'y_c': -14.99, 'angle': 60.0, 'angle_norm': 60.0, 'range_type': 'direct_extension', 'neighbors': '{"2": 4, "4": 2}'},
      {'sensor': 2, 'layout': 'home', 'sector': 'Lateral Left', 'expected_foot': 'Left', 'dist_center': 1, 'dist_center_cm': 25.97, 'q': -2, 'r': 1, 'x_c': -25.97, 'y_c': 0.0, 'angle': 90.0, 'angle_norm': 90.0, 'range_type': 'transition', 'neighbors': '{"1": 1}'},
      {'sensor': 3, 'layout': 'home', 'sector': 'Diagonal Left Down', 'expected_foot': 'Left', 'dist_center': 1, 'dist_center_cm': 29.99, 'q': -2, 'r': 2, 'x_c': -25.97, 'y_c': 14.99, 'angle': 120.0, 'angle_norm': 120.0, 'range_type': 'transition', 'neighbors': '{"1": 2, "4": 3}'},
      {'sensor': 4, 'layout': 'home', 'sector': 'Frontal Left', 'expected_foot': 'Left', 'dist_center': 1, 'dist_center_cm': 14.99, 'q': -1, 'r': -1, 'x_c': -12.98, 'y_c': -22.49, 'angle': 120.0, 'angle_norm': 120.0, 'range_type': 'transition', 'neighbors': '{"2": 6, "3": 7, "5": 1}'},
      {'sensor': 5, 'layout': 'home', 'sector': 'Back Left', 'expected_foot': 'Left', 'dist_center': 1, 'dist_center_cm': 25.97, 'q': -1, 'r': 2, 'x_c': -12.98, 'y_c': 22.49, 'angle': 150.0, 'angle_norm': 150.0, 'range_type': 'pivot_rotation', 'neighbors': '{"2": 8, "3": 9, "6": 3}'},
      {'sensor': 6, 'layout': 'home', 'sector': 'Frontal', 'expected_foot': 'Either', 'dist_center': 2, 'dist_center_cm': 29.99, 'q': 0, 'r': -2, 'x_c': 0.0, 'y_c': -29.99, 'angle': 0.0, 'angle_norm': 0.0, 'range_type': 'direct_extension', 'neighbors': '{"3": 10, "4": 7, "5": 4}'},
      {'sensor': 7, 'layout': 'home', 'sector': 'Frontal', 'expected_foot': 'Either', 'dist_center': 1, 'dist_center_cm': 14.99, 'q': 0, 'r': -1, 'x_c': 0.0, 'y_c': -14.99, 'angle': 0.0, 'angle_norm': 0.0, 'range_type': 'direct_extension', 'neighbors': '{"1": 6, "2": 10, "6": 4}'},
      {'sensor': 8, 'layout': 'home', 'sector': 'Back', 'expected_foot': 'Either', 'dist_center': 1, 'dist_center_cm': 14.99, 'q': 0, 'r': 1, 'x_c': 0.0, 'y_c': 14.99, 'angle': 180.0, 'angle_norm': 180.0, 'range_type': 'pivot_rotation', 'neighbors': '{"3": 11, "4": 9, "5": 5}'},
      {'sensor': 9, 'layout': 'home', 'sector': 'Back', 'expected_foot': 'Either', 'dist_center': 2, 'dist_center_cm': 29.99, 'q': 0, 'r': 2, 'x_c': 0.0, 'y_c': 29.99, 'angle': 180.0, 'angle_norm': 180.0, 'range_type': 'pivot_rotation', 'neighbors': '{"1": 8, "2": 11, "6": 5}'},
      {'sensor': 10, 'layout': 'home', 'sector': 'Frontal Right', 'expected_foot': 'Right', 'dist_center': 1, 'dist_center_cm': 25.97, 'q': 1, 'r': -2, 'x_c': 12.98, 'y_c': -22.49, 'angle': 30.0, 'angle_norm': 30.0, 'range_type': 'direct_extension', 'neighbors': '{"3": 12, "5": 7, "6": 6}'},
      {'sensor': 11, 'layout': 'home', 'sector': 'Back Right', 'expected_foot': 'Right', 'dist_center': 1, 'dist_center_cm': 25.97, 'q': 1, 'r': 1, 'x_c': 12.98, 'y_c': 22.49, 'angle': 150.0, 'angle_norm': 150.0, 'range_type': 'pivot_rotation', 'neighbors': '{"2": 14, "5": 9, "6": 8}'},
      {'sensor': 12, 'layout': 'home', 'sector': 'Diagonal Right Up', 'expected_foot': 'Right', 'dist_center': 1, 'dist_center_cm': 29.99, 'q': 2, 'r': -2, 'x_c': 25.97, 'y_c': -14.99, 'angle': 60.0, 'angle_norm': 60.0, 'range_type': 'direct_extension', 'neighbors': '{"4": 13, "6": 10}'},
      {'sensor': 13, 'layout': 'home', 'sector': 'Lateral Right', 'expected_foot': 'Right', 'dist_center': 1, 'dist_center_cm': 25.97, 'q': 2, 'r': -1, 'x_c': 25.97, 'y_c': 0.0, 'angle': 90.0, 'angle_norm': 90.0, 'range_type': 'transition', 'neighbors': '{"1": 12, "4": 14}'},
      {'sensor': 14, 'layout': 'home', 'sector': 'Diagonal Right Down', 'expected_foot': 'Right', 'dist_center': 1, 'dist_center_cm': 29.99, 'q': 2, 'r': 0, 'x_c': 25.97, 'y_c': 14.99, 'angle': 120.0, 'angle_norm': 120.0, 'range_type': 'transition', 'neighbors': '{"1": 13, "5": 11}'},
    ];

    for (var sensor in sensors) {
      await db.insert('sensors', sensor, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Check if athletes exist before seeding to avoid duplicates
    final List<Map<String, dynamic>> athletes = await db.query('athletes');
    if (athletes.isEmpty) {
      Uint8List profileBytes;
      try {
        final ByteData data = await rootBundle.load('assets/images/michel.png');
        profileBytes = data.buffer.asUint8List();
        debugPrint("✅ DB SEED: Loaded michel.png (\${profileBytes.length} bytes)");
      } catch (e) {
        debugPrint("❌ DB SEED ERROR: assets/images/michel.png not found: \$e");
        profileBytes = Uint8List(0);
      }

      await db.insert('athletes', {
        'name': 'Michel De Cesaro',
        'gender': 'Male',
        'country': 'Brazil',
        'birth': '1980-07-03',
        'dominant_foot': 'Right',
        'position': 'Middlefield',
        'profile': profileBytes,
      });
    }
  }

  Future<List<Athlete>> getAthletes() async {
    final db = await database;
    return (await db.query('athletes')).map((m) => Athlete.fromMap(m)).toList();
  }
}
