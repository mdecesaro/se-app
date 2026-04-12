class Exercise {
  final int? id;
  final int categoryId;
  final String code;
  final String name;
  final String description;
  final int level;
  final String objective;
  final String modality;
  final String parameters;
  final int boardSize;
  final bool active;

  Exercise({
    this.id,
    required this.categoryId,
    required this.code,
    required this.name,
    required this.description,
    this.level = 1,
    required this.objective,
    required this.modality,
    required this.parameters,
    required this.boardSize,
    this.active = true,
  });

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id'],
      categoryId: map['category_id'],
      code: map['code'],
      name: map['name'],
      description: map['description'],
      level: map['level'],
      objective: map['objective'],
      modality: map['modality'],
      parameters: map['parameters'],
      boardSize: map['board_size'],
      active: map['active'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category_id': categoryId,
      'code': code,
      'name': name,
      'description': description,
      'level': level,
      'objective': objective,
      'modality': modality,
      'parameters': parameters,
      'board_size': boardSize,
      'active': active ? 1 : 0,
    };
  }
}
