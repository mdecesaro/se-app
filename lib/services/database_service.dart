import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import '../models/athlete.dart';
import '../models/evaluation_result.dart';

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
    String path = join(await getDatabasesPath(), 'flyfeet_v2.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _seedDatabase(db);
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

    await db.execute('''
      CREATE TABLE movement_ranges (
          range_type TEXT PRIMARY KEY,
          angle_min REAL NOT NULL,
          angle_max REAL NOT NULL,
          description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sensors (
          sensor INTEGER PRIMARY KEY,
          layout TEXT NOT NULL,
          sector TEXT NOT NULL,
          expected_foot TEXT NOT NULL,
          dist_center INTEGER NOT NULL,
          dist_center_cm REAL NOT NULL,
          q INTEGER NOT NULL,
          r INTEGER NOT NULL,
          x_c REAL NOT NULL,
          y_c REAL NOT NULL,
          angle REAL NOT NULL,
          angle_norm REAL NOT NULL,
          range_type TEXT NOT NULL,
          neighbors TEXT NOT NULL,
          FOREIGN KEY (range_type) REFERENCES movement_ranges (range_type)
      )
    ''');

    await db.execute('''
        CREATE TABLE evaluation_tests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          athlete_id INTEGER,
          exercise_id INTEGER,
          device_id TEXT,
          platform_version TEXT,
          timestamp INTEGER,
          session_guid TEXT,
          game_mode INTEGER,
          execution_rounds INTEGER,
          total_attempts INTEGER,
          timeout_ms INTEGER,
          repeat_if_wrong INTEGER,
          delay_type TEXT,
          delay_min_ms INTEGER,
          delay_max_ms INTEGER,
          target_logic INTEGER,
          target_qty INTEGER,
          target_rgb_hex TEXT,
          dist_mode INTEGER,
          dist_behavior INTEGER,
          dist_qty INTEGER,
          dist_rgbs_hex TEXT,
          hits INTEGER,
          errors INTEGER,
          avg_reaction_time REAL,
          duration_ms INTEGER,
          
          FOREIGN KEY (athlete_id) REFERENCES athletes(id),
          FOREIGN KEY (exercise_id) REFERENCES exercises(id)
      )
    ''');

    await db.execute('''
        CREATE TABLE evaluation_test_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_id INTEGER NOT NULL,
            round_num INTEGER NOT NULL,
            attempt_num INTEGER NOT NULL,
            stimulus_start INTEGER,
            stimulus_end INTEGER,
            reaction_time INTEGER,
            gct INTEGER,
            targets TEXT NOT NULL,                -- Ex: "1,10,5"
            target_color_hex TEXT NOT NULL,       -- Ex: "#00FF00"
            distractors TEXT NOT NULL,            -- Ex: "11,4,6" (ou "" se não houver)
            distractor_colors_hex TEXT NOT NULL,  -- Ex: "#FF0000,#FF0000,#FF0000" (ou "" se não houver)
            hit_sensor_id INTEGER,                -- ID do pod acionado (0 se for Timeout)
            error_type INTEGER DEFAULT 0,         -- 0 = Hit, 1 = Wrong Sensor, 2 = Timeout
            
            FOREIGN KEY (test_id) REFERENCES evaluation_tests (id) ON DELETE CASCADE
        )
    ''');

    await db.execute('CREATE INDEX idx_eval_test_results_test_id ON evaluation_test_results (test_id)');
    await db.execute('CREATE INDEX idx_eval_tests_session_guid ON evaluation_tests (session_guid)');
  }

  Future<List<Athlete>> getAthletes() async {
    final db = await database;
    return (await db.query('athletes')).map((m) => Athlete.fromMap(m)).toList();
  }

  Future<void> saveEvaluationTest(Map<String, dynamic> testData, List<EvaluationResult> results) async {
    final db = await database;

    await db.transaction((txn) async {
      final testId = await txn.insert('evaluation_tests', testData);
      for (var result in results) {
        final Map<String, dynamic> resultRow = result.toMap();
        resultRow['test_id'] = testId;
        await txn.insert('evaluation_test_results', resultRow);
      }
    });
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
      (2, 'Lite Light Tap', 'A gentle introduction to reaction training. Focus on establishing a baseline rhythm and familiarizing yourself with the sensor layout.', 1, 'Rhythm & Response', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 0, "dist_behavior": 0, "dist_rgbs_hex": [], "delay_type": 1, "delay_min_ms": 1000, "delay_max_ms": 1000, "timeout_ms": 0, "repeat_if_wrong": false, "miss_policy": 0}}', 14, 1),
      (2, 'Rapid Response', 'Step up the pace. The delay between lights is shorter and unpredictable, forcing your nervous system to stay alert and ready for the next strike.', 1, 'Explosive Reaction', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 0, "dist_behavior": 0, "dist_rgbs_hex": [], "delay_type": 2, "delay_min_ms": 400, "delay_max_ms": 900, "timeout_ms": 1200, "repeat_if_wrong": false, "miss_policy": 0}}', 14, 1),
      (2, 'Neural Blitz', 'The ultimate performance test. High-frequency stimuli with tight time windows. You must strike fast or you''ll miss the window. Maximum intensity.', 2, 'Agility', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 0, "dist_behavior": 0, "dist_rgbs_hex": [], "delay_type": 2, "delay_min_ms": 200, "delay_max_ms": 600, "timeout_ms": 750, "repeat_if_wrong": true, "miss_policy": 0}}', 14, 1),
      (2, 'Focus Filter', 'Maintain your focus on the target color while secondary sensors try to pull your attention away. Do not let the noise slow you down.', 3, 'Selective Attention', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 1, "dist_behavior": 0, "dist_rgbs_hex": ["#FF0000"], "delay_type": 1, "delay_min_ms": 800, "delay_max_ms": 800, "timeout_ms": 1200, "repeat_if_wrong": false, "miss_policy": 0}}', 14, 1),
      (2, 'Peripheral Chaos', 'Multiple sensors will light up simultaneously. Your mission is to find and hit the green target while ignoring the blue and red decoys.', 4, 'Peripheral Vision', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 2, "dist_behavior": 0, "dist_rgbs_hex": ["#FF0000", "#0000FF"], "delay_type": 2, "delay_min_ms": 500, "delay_max_ms": 1000, "timeout_ms": 1000, "repeat_if_wrong": false, "miss_policy": 0}}', 14, 1),
      (2, 'Split-Second Choice', 'The ultimate test of discrimination. Correct and incorrect colors appear with very short windows. Precision is just as important as speed.', 5, 'Discrimination', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 1, "game_attempts": 14, "target_qty": 1, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 3, "dist_behavior": 0, "dist_rgbs_hex": ["#FF0000", "#FFFF00", "#FFFFFF"], "delay_type": 2, "delay_min_ms": 300, "delay_max_ms": 700, "timeout_ms": 800, "repeat_if_wrong": true, "miss_policy": 0}}', 14, 1),
	    (2, 'Chaotic Matrix', 'A chaotic battlefield for your brain. Six pods ignite simultaneously—three targets and three distractors. Scan your entire field of view, pick any valid target, and strike before the one-second window slams shut.', 6, 'Peripheral Scan & Selection', 'Single-Touch', '{"parameters": {"game_mode": 1, "game_rounds": 2, "game_attempts": 7, "target_qty": 3, "target_logic": 1, "target_rgb_hex": "#00FF00", "dist_mode": 0, "dist_qty": 3, "dist_behavior": 0, "dist_rgbs_hex": ["#FF0000", "#FFFF00", "#FFFFFF"], "delay_type": 2, "delay_min_ms": 700, "delay_max_ms": 900, "timeout_ms": 1000, "repeat_if_wrong": true, "miss_policy": 0}}', 14, 1)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO movement_ranges (range_type, angle_min, angle_max, description) VALUES
      ('direct_extension', 0, 60, 'The athlete reaches only with leg/hip extension, no body rotation'),
      ('transition', 60, 120, 'The athlete may choose extension or partial pivot rotation'),
      ('pivot_rotation', 120, 180, 'Requires pivot or body rotation to reach')
    ''');

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
}