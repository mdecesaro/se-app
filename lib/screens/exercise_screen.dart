import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/category.dart';
import '../models/exercise.dart';
import 'exercise_session_screen.dart'; // Import the session screen

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  List<Category> _categories = [];
  List<Exercise> _exercises = [];
  Category? _selectedCategory;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final db = await DatabaseService().database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
          c.*, 
          COUNT(ex.id) AS exercises_number,
          SUM(CASE WHEN (SELECT COUNT(*) FROM evaluation_tests et WHERE et.exercise_id = ex.id) > 0 THEN 1 ELSE 0 END) AS total_done
      FROM categories c
      LEFT JOIN exercises ex ON c.id = ex.category_id
      GROUP BY c.id
    ''');
    setState(() {
      _categories = maps.map((m) => Category.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  Future<void> _loadExercises(int categoryId) async {
    setState(() => _isLoading = true);
    final db = await DatabaseService().database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      where: 'category_id = ? AND active = 1',
      whereArgs: [categoryId],
      orderBy: 'level ASC, name ASC',
    );
    setState(() {
      _exercises = maps.map((m) => Exercise.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedCategory != null) {
          setState(() {
            _selectedCategory = null;
            _exercises = [];
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _selectedCategory == null ? 'Training Categories' : _selectedCategory!.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: _selectedCategory != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    _selectedCategory = null;
                    _exercises = [];
                  }),
                )
              : null,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _selectedCategory == null
                ? _buildCategoryGrid()
                : _buildExerciseList(),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the ideal aspect ratio to fit 2x2 grid in the available height
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double itemWidth = (width - 16) / 2; // 16 is crossAxisSpacing
        final double itemHeight = (height - 16) / 2; // 16 is mainAxisSpacing
        final double aspectRatio = itemWidth / itemHeight;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(), // Disable scrolling
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: aspectRatio,
            ),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              return _buildCategoryCard(category);
            },
          ),
        );
      },
    );
  }

  Widget _buildExerciseList() {
    if (_exercises.isEmpty) {
      return const Center(
        child: Text(
          'No exercises found for this category.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exercises.length,
      itemBuilder: (context, index) {
        final exercise = _exercises[index];
        return Card(
          color: const Color(0xFF2C2C2C),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${exercise.level}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'LEVEL',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      height: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              exercise.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              exercise.description,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              _showExerciseSetup(context, exercise);
            },
          ),
        );
      },
    );
  }

  void _showExerciseSetup(BuildContext context, Exercise exercise) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Session',
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return ExerciseSessionScreen(exercise: exercise);
      },
    );
  }

  Widget _buildCategoryCard(Category category) {
    IconData icon;
    switch (category.code) {
      case 'cognitive':
        icon = Icons.psychology;
        break;
      case 'performance':
        icon = Icons.speed;
        break;
      case 'coordination':
        icon = Icons.grid_view;
        break;
      case 'conditioning':
        icon = Icons.fitness_center;
        break;
      default:
        icon = Icons.help_outline;
    }

    return Card(
      color: const Color(0xFF2C2C2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () {
          setState(() => _selectedCategory = category);
          _loadExercises(category.id!);
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              category.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${category.exercisesNumber} / ${category.totalDone}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                category.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
