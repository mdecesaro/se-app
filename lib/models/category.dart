class Category {
  final int? id;
  final String code;
  final String name;
  final String description;
  final int exercisesNumber;
  final int totalDone;

  Category({
    this.id,
    required this.code,
    required this.name,
    required this.description,
    this.exercisesNumber = 0,
    this.totalDone = 0,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      code: map['code'],
      name: map['name'],
      description: map['description'],
      exercisesNumber: map['exercises_number'] ?? 0,
      totalDone: map['total_done'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
    };
  }
}
