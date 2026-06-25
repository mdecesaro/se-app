import 'package:flutter/material.dart';
import 'dart:convert';
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
    // 🟡 REMOVA OU COMENTE ESSA LINHA ABAIXO:
    // setState(() => _isLoading = true);

    try {
      final db = await DatabaseService().database;
      final List<Map<String, dynamic>> maps = await db.query(
        'exercises',
        where: 'category_id = ? AND active = 1',
        whereArgs: [categoryId],
        orderBy: 'level ASC, name ASC',
      );

      if (!mounted) return;

      setState(() {
        _exercises = maps.map((m) => Exercise.fromMap(m)).toList();
        _isLoading = false; // Garante que se estivesse carregando algo, agora parou
      });
    } catch (e) {
      debugPrint("Erro ao carregar exercícios: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
        // 🟢 LÓGICA CORRIGIDA AQUI:
        body: _selectedCategory == null
            ? (_isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
            : _buildCategoryGrid())
            : _buildExerciseList(),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double itemWidth = (width - 16) / 2;
        final double itemHeight = (height - 16) / 2;
        final double aspectRatio = itemWidth / itemHeight;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
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
    // 1. Se o banco ainda está processando a busca
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.orangeAccent),
            SizedBox(height: 16),
            Text(
              'Loading exercises...',
              style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    // 2. Se a busca terminou e realmente não voltou nada
    if (_exercises.isEmpty) {
      return const Center(
        child: Text(
          'No exercises found for this category.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // 3. Se achou os exercícios, renderiza a Grid normalmente
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 348,
      ),
      itemCount: _exercises.length,
      itemBuilder: (context, index) {
        final exercise = _exercises[index];
        return _buildExerciseCard(exercise);
      },
    );
  }

  Widget _buildExerciseCard(Exercise exercise) {
    Map<String, dynamic> params = {};
    try {
      final decoded = json.decode(exercise.parameters);
      params = decoded['parameters'] ?? {};
    } catch (_) {}

    final int gameAttempts = params['game_attempts'] ?? 0;
    final int gameRounds = params['game_rounds'] ?? 1;
    final int targetQty = params['target_qty'] ?? 1;
    final String targetColor = params['target_rgb_hex'] ?? '#00FF00';
    final int distQty = params['dist_qty'] ?? 0;
    final List<dynamic> distColors = params['dist_rgbs_hex'] ?? [];
    final int delayMax = params['delay_max_ms'] ?? 0;
    final int delayMin = params['delay_min_ms'] ?? 0;
    final int timeout = params['timeout_ms'] ?? 0;
    final bool repeatIfWrong = params['repeat_if_wrong'] ?? false;

    return Card(
      color: const Color(0xFF2C2C2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showExerciseSetup(context, exercise),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge de Level
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                    ),
                    child: Text(
                      'Level ${exercise.level}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const Icon(Icons.speed, color: Colors.white24, size: 12),
                ],
              ),
              const SizedBox(height: 6),

              Text(
                exercise.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              SizedBox(
                height: 55,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    exercise.description,
                    style: const TextStyle(color: Colors.grey, fontSize: 11, height: 1.3),
                  ),
                ),
              ),

              // Separador
              const Column(
                children: [
                  SizedBox(height: 16),
                  Divider(color: Colors.white24, height: 1, thickness: 1),
                  SizedBox(height: 14),
                ],
              ),

              // INFO AREA - Tabela maior e centralizada via Padding simétrico
              Padding(
                padding: const EdgeInsets.only(left: 17.0, right: 0.0, bottom: 12.0),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.0),
                    1: FixedColumnWidth(16),
                    2: FlexColumnWidth(1.0),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(children: [
                      _buildCompactStat('ATTEMPTS', '$gameAttempts', Icons.play_arrow),
                      const SizedBox(),
                      _buildCompactStat('ROUNDS', '$gameRounds', Icons.loop),
                    ]),
                    const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                    TableRow(children: [
                      _buildCompactStat('TARGETS', '$targetQty', Icons.ads_click),
                      const SizedBox(),
                      _buildCompactStat('COLORS', '', Icons.palette, trailing: _buildColorDots(targetColor)),
                    ]),
                    const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                    TableRow(children: [
                      _buildCompactStat('DISTRACTORS', '$distQty', Icons.visibility),
                      const SizedBox(),
                      _buildCompactStat('COLORS', '', Icons.palette, trailing: _buildColorDots(distColors)),
                    ]),
                    const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                    TableRow(children: [
                      _buildCompactStat('DELAY MIN', '$delayMin', Icons.history),
                      const SizedBox(),
                      _buildCompactStat('DELAY MAX', '$delayMax', Icons.history),
                    ]),
                    const TableRow(children: [SizedBox(height: 4), SizedBox(), SizedBox()]),
                    TableRow(children: [
                      _buildCompactStat('TIMEOUT', timeout > 0 ? '$timeout' : '∞', Icons.timer),
                      const SizedBox(),
                      _buildCompactStat('REPEAT', repeatIfWrong ? 'YES' : 'NO', Icons.replay),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStat(String label, String value, IconData icon, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              child: Icon(icon, size: 12, color: Colors.orangeAccent.withOpacity(0.9)),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),

        Padding(
          padding: const EdgeInsets.only(left: 18.0), // Margem fixa que você configurou
          child: Row(
            mainAxisSize: MainAxisSize.max, // Alterado para MAX para forçar a linha a usar todo o espaço da coluna
            children: [
              if (value.isNotEmpty)
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              if (trailing != null) ...[
                if (value.isNotEmpty) const SizedBox(width: 4),
                // Removemos o Flexible daqui para o Wrap não ser esmagado
                trailing,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorDots(dynamic colors) {
    List<String> colorList = [];

    if (colors is String && colors.trim().isNotEmpty) {
      colorList.add(colors);
    } else if (colors is List) {
      colorList.addAll(colors.where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString()));
    }

    if (colorList.isEmpty) {
      return const Text(
        'none',
        style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold),
      );
    }

    // Envelopado em um SizedBox para forçar espaço horizontal na tabela
    return SizedBox(
      width: 70,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: colorList.take(6).map((hex) {
          Color color = Colors.white;
          try {
            color = Color(int.parse(hex.replaceFirst('#', '0xFF')));
          } catch (_) {}
          return Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 0.5),
            ),
          );
        }).toList(),
      ),
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
          setState(() {
            _selectedCategory = category;
            _exercises = []; // Limpa a lista anterior
            _isLoading = true; // 🟢 Ativa o loading local para a lista de exercícios
          });
          _loadExercises(category.id!);
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0), // Padding interno para proteger as bordas
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,        // Centraliza tudo VERTICALMENTE
            crossAxisAlignment: CrossAxisAlignment.center,      // Centraliza tudo HORIZONTALMENTE
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),

              Text(
                category.name,
                textAlign: TextAlign.center, // Centraliza o texto do título
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
                  textAlign: TextAlign.center, // Centraliza o indicador interno
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Removemos o Expanded/Padding assimétrico e controlamos a caixa da descrição
              SizedBox(
                height: 60, // Limita uma altura fixa igual para todos os cards
                child: Center( // Força o scroll horizontal/vertical a se alinhar pelo centro geométrico
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(
                      category.description,
                      textAlign: TextAlign.center, // Centraliza as quebras de linha do parágrafo
                      style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}