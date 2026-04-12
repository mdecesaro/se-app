class Category {
  final int? id;
  final String code;
  final String name;
  final String description;

  Category({
    this.id,
    required this.code,
    required this.name,
    required this.description,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      code: map['code'],
      name: map['name'],
      description: map['description'],
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
