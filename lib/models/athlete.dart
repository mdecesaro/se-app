import 'dart:typed_data';

class Athlete {
  final int? id;
  final String name;
  final String gender;
  final String country;
  final String birth;
  final String dominantFoot;
  final String position;
  final Uint8List profile; // Store as BLOB
  final String? timestamp;

  Athlete({
    this.id,
    required this.name,
    required this.gender,
    required this.country,
    required this.birth,
    required this.dominantFoot,
    required this.position,
    required this.profile,
    this.timestamp,
  });

  // Convert an Athlete into a Map. The keys must match the column names in the database.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'gender': gender,
      'country': country,
      'birth': birth,
      'dominant_foot': dominantFoot,
      'position': position,
      'profile': profile,
      // 'timestamp': timestamp, // Let SQLite handle this if default is used
    };
  }

  // Convert a Map into an Athlete
  factory Athlete.fromMap(Map<String, dynamic> map) {
    return Athlete(
      id: map['id'],
      name: map['name'],
      gender: map['gender'],
      country: map['country'],
      birth: map['birth'],
      dominantFoot: map['dominant_foot'],
      position: map['position'],
      profile: map['profile'],
      timestamp: map['timestamp'],
    );
  }
}
