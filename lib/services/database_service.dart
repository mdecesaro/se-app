import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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
    String path = join(await getDatabasesPath(), 'flyfeet_v14.db');
    final db = await openDatabase(
      path,
      version: 13, // Bumped to 13 to add preferred_number
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return db;
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
      await db.execute('DROP TABLE IF EXISTS sensors');
      await _upgradeToV3(db);
    }

    if (oldVersion < 7) await _upgradeToV7(db);
    if (oldVersion < 8) await _upgradeToV8(db);
    if (oldVersion < 9) await _upgradeToV9(db);
    if (oldVersion < 10) await _upgradeToV10(db);
    if (oldVersion < 11) await _upgradeToV11(db);
    if (oldVersion < 12) await _upgradeToV12(db);
    if (oldVersion < 13) await _upgradeToV13(db);
    if (oldVersion < 12) await _upgradeToV12(db);

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

  Future<void> _upgradeToV7(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS evaluation_tests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            athlete_id INTEGER,
            exercise_id INTEGER,
            timestamp TEXT,
            total_hits INTEGER,
            total_misses INTEGER,
            avg_reaction_time REAL,
            FOREIGN KEY (athlete_id) REFERENCES athletes(id),
            FOREIGN KEY (exercise_id) REFERENCES exercises(id)
        )
    ''');

    await db.execute('''
        CREATE TABLE IF NOT EXISTS evaluation_test_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_id INTEGER NOT NULL,
            round_num INTEGER NOT NULL,
            stimulus_id INTEGER NOT NULL,
            stimulus_position TEXT,
            stimulus_type TEXT,
            correct_color TEXT,
            reaction_time REAL,
            stimulus_start REAL,
            stimulus_end REAL,
            delay_ms INTEGER,
            elapsed_since_start REAL,
            error INTEGER,
            foot_used TEXT,
            wrong_stimulus_id TEXT,
            distractor_type TEXT,
            distractor_id_color TEXT,
            FOREIGN KEY (test_id) REFERENCES evaluation_tests (id) ON DELETE CASCADE
        )
    ''');
  }

  Future<void> _upgradeToV8(Database db) async {
    await db.execute('DROP TABLE IF EXISTS evaluation_test_results');
    await db.execute('DROP TABLE IF EXISTS evaluation_tests');

    await db.execute('''
        CREATE TABLE evaluation_tests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            athlete_id INTEGER,
            exercise_id INTEGER,
            device_id TEXT,
            platform_version TEXT,
            timestamp TEXT,
            stimuli_count INTEGER,
            delay_type TEXT,
            delay_min_ms INTEGER,
            delay_max_ms INTEGER,
            execution_rounds INTEGER,
            timeout_ms INTEGER,
            repeat_if_wrong INTEGER,
            total_attempts INTEGER,
            hits INTEGER,
            errors INTEGER,
            avg_reaction_time REAL,
            duration_ms REAL,
            FOREIGN KEY (athlete_id) REFERENCES athletes(id),
            FOREIGN KEY (exercise_id) REFERENCES exercises(id)
        )
    ''');

    await db.execute('''
        CREATE TABLE evaluation_test_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_id INTEGER NOT NULL,
            round_num INTEGER NOT NULL,
            stimulus_id INTEGER NOT NULL,
            stimulus_position TEXT,
            stimulus_type TEXT,
            correct_color TEXT,
            reaction_time REAL,
            stimulus_start REAL,
            stimulus_end REAL,
            delay_ms INTEGER,
            elapsed_since_start REAL,
            error INTEGER,
            foot_used TEXT,
            wrong_stimulus_id TEXT,
            distractor_type TEXT,
            distractor_id_color TEXT,
            FOREIGN KEY (test_id) REFERENCES evaluation_tests (id) ON DELETE CASCADE
        )
    ''');

    await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_eval_test_results_test_id
        ON evaluation_test_results (test_id)
    ''');
  }

  Future<void> _upgradeToV9(Database db) async {
    await db.execute('DROP TABLE IF EXISTS evaluation_test_results');
    await db.execute('DROP TABLE IF EXISTS evaluation_tests');
    await db.execute('DROP TABLE IF EXISTS exercises');

    await db.execute('''
      CREATE TABLE exercises (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
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

    await _upgradeToV8(db);
  }

  Future<void> _upgradeToV10(Database db) async {
    // Add UNIQUE constraint to name and refresh exercises
    await db.execute('DROP TABLE IF EXISTS evaluation_test_results');
    await db.execute('DROP TABLE IF EXISTS evaluation_tests');
    await db.execute('DROP TABLE IF EXISTS exercises');

    await db.execute('''
      CREATE TABLE exercises (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          name TEXT UNIQUE NOT NULL,
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

    await _upgradeToV8(db);
  }

  Future<void> _upgradeToV11(Database db) async {
    await db.execute('DELETE FROM exercises');
  }

  Future<void> _upgradeToV12(Database db) async {
    await db.execute('DELETE FROM exercises');
  }

  Future<void> _upgradeToV13(Database db) async {
    await db.execute('ALTER TABLE athletes ADD COLUMN preferred_number INTEGER DEFAULT 0');
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
        preferred_number INTEGER DEFAULT 0,
        profile BLOB NOT NULL,
        timestamp TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE exercises (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          name TEXT UNIQUE NOT NULL,
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

    await _upgradeToV3(db); // sensors
    await _upgradeToV4(db); // movement_ranges
    await _upgradeToV8(db); // evaluation tables
  }

  Future<void> _seedDatabase(Database db) async {
    await db.execute('''
      INSERT OR IGNORE INTO categories (id, code, name, description) VALUES
      (1, 'cognitive', 'Cognitive', 'Exercises that improve decision-making, memory, and attention.'),
      (2, 'performance', 'Performance', 'Exercises focused on reaction time and execution speed.'),
      (3, 'coordination', 'Coordination', 'Exercises that improve precision and motor control.'),
      (4, 'conditioning', 'Conditioning', 'Exercises for endurance, intensity, and training volume.')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO exercises (category_id, name, description, level, objective, modality, parameters, board_size, active) VALUES
      (2, 'Lite Light Tap', 'A gentle introduction to reaction training. Focus on establishing a baseline rhythm and familiarizing yourself with the sensor layout.', 1, 'Rhythm & Response', 'Single-Touch', '{"parameters": {"stimuli_count": 14, "stimuli_generation_mode": "random", "stimuli_sequence": [], "stimulus_type": "color", "correct_color": "#00FF00", "delay_type": "fixed", "delay_range_ms": [1000], "execution_rounds": 1, "timeout_ms": 0, "repeat_if_wrong": false}}', 14, 1),
      (2, 'Rapid Response', 'Step up the pace. The delay between lights is shorter and unpredictable, forcing your nervous system to stay alert and ready for the next strike.', 1, 'Explosive Reaction', 'Single-Touch', '{"parameters": {"stimuli_count": 20, "stimuli_generation_mode": "random", "stimuli_sequence": [], "stimulus_type": "color", "correct_color": "#00FF00", "delay_type": "range", "delay_range_ms": [400, 900], "execution_rounds": 1, "timeout_ms": 1200, "repeat_if_wrong": false}}', 14, 1),
      (2, 'Neural Blitz', 'The ultimate performance test. High-frequency stimuli with tight time windows. You must strike fast or you''ll miss the window. Maximum intensity.', 2, 'Agility', 'Single-Touch', '{"parameters": {"stimuli_count": 30, "stimuli_generation_mode": "random", "stimuli_sequence": [], "stimulus_type": "color", "correct_color": "#00FF00", "delay_type": "range", "delay_range_ms": [200, 600], "execution_rounds": 1, "timeout_ms": 750, "repeat_if_wrong": true}}', 14, 1),
      (2, 'Focus Filter', 'Maintain your focus on the target color while secondary sensors try to pull your attention away. Do not let the noise slow you down.', 3, 'Selective Attention', 'Single-Touch', '{"parameters": {"stimuli_count": 15, "stimuli_generation_mode": "random", "stimulus_type": "color", "correct_color": "#00FF00", "distractor_type": "color", "distractor_colors": ["#FF0000"], "distractor_ncolors_at_time": 1, "delay_type": "fixed", "delay_range_ms": [800], "timeout_ms": 1200, "execution_rounds": 1, "repeat_if_wrong": false}}', 14, 1),
      (2, 'Peripheral Chaos', 'Multiple sensors will light up simultaneously. Your mission is to find and hit the green target while ignoring the blue and red decoys.', 4, 'Peripheral Vision', 'Single-Touch', '{"parameters": {"stimuli_count": 20, "stimuli_generation_mode": "random", "stimulus_type": "color", "correct_color": "#00FF00", "distractor_type": "color", "distractor_colors": ["#FF0000", "#0000FF"], "distractor_ncolors_at_time": 2, "delay_type": "range", "delay_range_ms": [500, 1000], "timeout_ms": 1000, "execution_rounds": 1, "repeat_if_wrong": false}}', 14, 1),
      (2, 'Split-Second Choice', 'The ultimate test of discrimination. Correct and incorrect colors appear with very short windows. Precision is just as important as speed.', 5, 'Discrimination', 'Single-Touch', '{"parameters": {"stimuli_count": 25, "stimuli_generation_mode": "random", "stimulus_type": "color", "correct_color": "#00FF00", "distractor_type": "color", "distractor_colors": ["#FF0000", "#FFFF00", "#FFFFFF"], "distractor_ncolors_at_time": 3, "delay_type": "range", "delay_range_ms": [300, 700], "timeout_ms": 800, "repeat_if_wrong": true, "execution_rounds": 1}}', 14, 1)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO movement_ranges (range_type, angle_min, angle_max, description) VALUES
      ('direct_extension', 0, 60, 'The athlete reaches only with leg/hip extension, no body rotation'),
      ('transition', 60, 120, 'The athlete may choose extension or partial pivot rotation'),
      ('pivot_rotation', 120, 180, 'Requires pivot or body rotation to reach')
    ''');

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

    final List<Map<String, dynamic>> athletes = await db.query('athletes');
    if (athletes.isEmpty) {
      Uint8List profileBytes;
      try {
        final ByteData data = await rootBundle.load('assets/images/michel.png');
        profileBytes = data.buffer.asUint8List();
      } catch (e) {
        profileBytes = Uint8List(0);
      }

      await db.insert('athletes', {
        'name': 'Michel De Cesaro',
        'gender': 'Male',
        'country': 'Brazil',
        'birth': '1980-07-03',
        'dominant_foot': 'Right',
        'position': 'Middlefield',
        'preferred_number': 7,
        'profile': profileBytes,
      });
    }
  }

  Future<List<Athlete>> getAthletes() async {
    final db = await database;
    return (await db.query('athletes')).map((m) => Athlete.fromMap(m)).toList();
  }
}
