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
    String path = join(await getDatabasesPath(), 'flyfeet_v10.db'); // New file name
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
    await _seedDatabase(db);
  }

  Future<void> _seedDatabase(Database db) async {
    Uint8List profileBytes;
    try {
      // Trying to load michel.png
      final ByteData data = await rootBundle.load('assets/images/michel.png');
      profileBytes = data.buffer.asUint8List();
      debugPrint("✅ DB SEED: Loaded michel.png (${profileBytes.length} bytes)");
    } catch (e) {
      debugPrint("❌ DB SEED ERROR: assets/images/michel.png not found: $e");
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

  Future<List<Athlete>> getAthletes() async {
    final db = await database;
    return (await db.query('athletes')).map((m) => Athlete.fromMap(m)).toList();
  }
}
