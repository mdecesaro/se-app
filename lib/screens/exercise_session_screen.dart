import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/evaluation_result.dart';
import '../services/bluetooth_service.dart';
import '../services/database_service.dart';

class SensorDefinition {
  final int id;
  final double x;
  final double y;
  final String sector;
  final String expectedFoot;

  SensorDefinition({
    required this.id,
    required this.x,
    required this.y,
    required this.sector,
    required this.expectedFoot
  });
}

class ExerciseSessionScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseSessionScreen({super.key, required this.exercise});

  @override
  State<ExerciseSessionScreen> createState() => _ExerciseSessionScreenState();
}

class _ExerciseSessionScreenState extends State<ExerciseSessionScreen> {
  final AppBluetoothService _bluetoothService = AppBluetoothService();
  StreamSubscription? _eventSubscription;

  // Sensors and Stats
  List<SensorDefinition> _sensorDefinitions = [];
  final List<String> executionLog = [];
  final ScrollController _logScrollController = ScrollController();
  final ValueNotifier<int> _logNotifier = ValueNotifier<int>(0);

  bool _isSessionStarted = false;
  Stopwatch stopwatch = Stopwatch();
  Timer? _timer;
  String formattedTime = "00:00.0";

  // Stats from Hardware
  int _hits = 0;
  int _misses = 0;
  int _totalSessionMs = 0;
  int _currentRound = 1;

  // 🔥 CORREÇÃO: Mudado de int para Set<int> para aguentar múltiplos alvos simultâneos
  final Set<int> _activeTargets = {};
  Map<int, String> _activeDistractors = {};
  String _correctColor = "#${0xffffff.toRadixString(16)}";
  List<EvaluationResult> _results = [];
  bool _isFinished = false;
  bool _isWaitingForSet = false;
  int _countdownValue = -1; // -1 means no countdown
  String? _athleteName;
  int? _athleteId;
  String? _sessionGuid;

  @override
  void initState() {
    super.initState();
    _loadAthlete();
    _loadSensors();
    _setupDataListener();
  }

  Future<void> _loadAthlete() async {
    try {
      final athletes = await DatabaseService().getAthletes();
      if (athletes.isNotEmpty) {
        setState(() {
          _athleteName = athletes.first.name;
          _athleteId = athletes.first.id;
        });
      }
    } catch (e) {
      debugPrint("Error loading athlete: $e");
    }
  }

  Future<void> _loadSensors() async {
    try {
      final db = await DatabaseService().database;
      final List<Map<String, dynamic>> maps = await db.query('sensors');

      // 1. Imprime a quantidade bruta de linhas retornadas pelo banco
      debugPrint('=== 📂 [DATABASE] LENDO TABELA SENSORS ===');
      debugPrint('Total de registros encontrados no SQLite: ${maps.length}');

      final List<SensorDefinition> loadedSensors = [];

      for (var m in maps) {
        final int? sensorId = m['sensor'];
        final String sector = m['sector'] ?? "unknown";
        final String expectedFoot = m['expected_foot'] ?? "unknown";

        // 2. Log detalhado linha por linha para inspecionar os IDs e Pés Esperados
        debugPrint('  📍 Carregado -> ID Físico (sensor): $sensorId | Setor: $sector | Pé Esperado: $expectedFoot');

        if (sensorId != null) {
          loadedSensors.add(SensorDefinition(
            id: sensorId,
            x: (m['x_c'] as num).toDouble(),
            y: (m['y_c'] as num).toDouble(),
            sector: sector,
            expectedFoot: expectedFoot,
          ));
        }
      }

      setState(() {
        _sensorDefinitions = loadedSensors;
      });

      // 3. Resumo final da estrutura na memória da Screen
      debugPrint('✅ [LOAD COMPLETE] _sensorDefinitions populado com ${_sensorDefinitions.length} sensores.');
      debugPrint('=========================================');

    } catch (e) {
      debugPrint('❌ [ERROR] Erro ao carregar sensores: $e');
    }
  }

  void _setupDataListener() {
    _eventSubscription?.cancel();

    _eventSubscription = _bluetoothService.eventStream.listen((event) {
      if (event.type == SensorEventType.end && event.totalMs == 0) {
        _resetSessionUI();
        return;
      }
      _handleBinaryEvent(event);
    });
  }

  void _resetSessionUI() {
    if (!mounted) return;
    _timer?.cancel();
    stopwatch.stop();
    setState(() {
      _isSessionStarted = false;
      _isFinished = false;
      _isWaitingForSet = false;
      _hits = 0;
      _misses = 0;
      _currentRound = 1;
     _activeTargets.clear();
      _activeDistractors = {};
      _countdownValue = -1;
    });
    _addLog("⚠️ Connection Reset - Session Cleared");
  }

  void _handleBinaryEvent(SensorEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case SensorEventType.ack:
        if (_isWaitingForSet) {
          _onSetConfirmed();
        }
        break;

      case SensorEventType.nack:
        _addLog("❌ Hardware NACK - Command Rejected");
        setState(() => _isWaitingForSet = false);
        break;

      case SensorEventType.countdown:
        setState(() {
          _isWaitingForSet = false;
          _countdownValue = event.mode;
        });
        _addLog("⏳ Countdown Sync: ${event.mode}");
        break;

      case SensorEventType.animationStep:
        if (_countdownValue != event.mode) {
          setState(() {
            _countdownValue = event.mode;
          });
          _addLog("⏳ Step: ${event.mode}");
        }
        break;

      case SensorEventType.countdownEnded:
        _addLog("🚀 Session GO!");
        _startLocalSessionLogic();
        setState(() => _countdownValue = -1);
        break;

      case SensorEventType.on:
        setState(() {
          _activeTargets.clear();
          _activeDistractors.clear();

          // Extrai a cor mestra enviada pelo parser
          final color = event.color;
          if (color != null && color.length >= 3) {
            _correctColor = '#${color[0].toRadixString(16).padLeft(2, '0')}'
                '${color[1].toRadixString(16).padLeft(2, '0')}'
                '${color[2].toRadixString(16).padLeft(2, '0')}';
          }

          // 🔥 CORREÇÃO CRÍTICA: Desempacota múltiplos alvos vindos do color payload (do índice 3 em diante)
          if (color != null && color.length > 3) {
            for (int i = 3; i < color.length; i++) {
              _activeTargets.add(color[i]); // Já estão humanizados (+1) condizentes com o banco/painter
            }
          } else if (event.sensorId > 0) {
            _activeTargets.add(event.sensorId);
          }

          // Armazena os distratores mapeando IDs humanizados perfeitamente
          if (event.distractors != null) {
            _activeDistractors = Map<int, String>.from(event.distractors!);
          }
        });
        _addLog("Targets ON: Sensors ${_activeTargets.join(', ')}");
        break;
      case SensorEventType.clearScreen:
        setState(() {
          _activeTargets.clear();
          _activeDistractors = {};
        });
        _addLog("❌ Targets OFF");
        break;
      case SensorEventType.hit:
        _recordResult(_currentRound, event.sensorId, event.reactionTime ?? 0,
            isHit: true,
            stimuliStart: event.stimuliStart ?? 0,
            stimuliEnd: event.stimuliEnd ?? 0
        );

        setState(() {
          _hits++;
          _currentRound++;

          _activeTargets.clear();
          _activeDistractors = {};
        });

        _addLog("HIT! Sensor ${event.sensorId} - RT: ${event.reactionTime}ms");
        break;

      case SensorEventType.miss:
        _recordResult(_currentRound, event.sensorId, 0,
            isHit: false,
            errType: event.errorType ?? 1,
            wrongSensorId: event.wrongSensorId ?? 0,
            stimuliStart: event.stimuliStart ?? 0,
            stimuliEnd: event.stimuliEnd ?? 0
        );

        setState(() {
          _misses++;
          _activeTargets.clear();
          _activeDistractors = {};
        });

        final String errorName = event.errorType == 2 ? 'TIMEOUT' : 'WRONG';
        _addLog("MISS! [$errorName] at Sensor ${event.sensorId}");
        break;

      case SensorEventType.end:
        _totalSessionMs = stopwatch.elapsedMilliseconds;
        _addLog("🏁 Session Summary: ${event.hits} hits, ${event.misses} misses");
        _finishSession();
        break;
    }
  }

  void _startSession() async {
    try {
      dynamic data = widget.exercise.parameters;
      if (data is String) data = json.decode(data);
      final params = data['parameters'] ?? {};

      setState(() {
        _isSessionStarted = true;
        _isFinished = false;
        _isWaitingForSet = true;
        _hits = 0;
        _misses = 0;
        _totalSessionMs = 0;
        _currentRound = 1;
        _results = [];
        _activeTargets.clear();
        _activeDistractors = {};
        _sessionGuid = "${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}";
        formattedTime = "00:00.0";
        _correctColor = params['target_rgb_hex'] ?? "#00FF00";

        _addLog("➡️ Sending Binary Configuration...");
      });

      debugPrint('[SESSION] Starting game with params: $params');
      if (_bluetoothService.connectedDevice == null) {
        _addLog("⚠️ Pod disconnected. Reconnect before starting.");
        setState(() => _isSessionStarted = false);
        return;
      }

      await _bluetoothService.sendStartGame(
        gameMode: params['game_mode'] ?? 1,
        gameRounds: params['game_rounds'] ?? 1,
        gameAttempts: params['game_attempts'] ?? 1,
        targetQty: params['target_qty'] ?? 10,
        targetLogic: params['target_logic'] ?? 1,
        targetRGBHex: params['target_rgb_hex'] ?? "#00FF00",
        distMode: params['dist_mode'] ?? 0,
        distQty: params['dist_qty'] ?? 0,
        distBehavior: params['dist_behavior'] ?? 0,
        distRGBsHex: (params['dist_rgbs_hex'] is List)
            ? List<String>.from(params['dist_rgbs_hex'])
            : [],
        delayType: params['delay_type'] ?? 1,
        delayMinMs: params['delay_min_ms'] ?? 500,
        delayMaxMs: params['delay_max_ms'] ?? 500,
        timeoutMs: params['timeout_ms'] ?? 0,
        repeatIfWrong: params['repeat_if_wrong'] == true,
      );
    } catch (e) {
      _addLog("❌ Error starting session: $e");
      setState(() => _isSessionStarted = false);
    }
  }

  void _onSetConfirmed() {
    if (!mounted || !_isWaitingForSet) return;

    setState(() {
      _isWaitingForSet = false;
      _countdownValue = 5;
    });

    _addLog("✔️ Configuration applied. Starting countdown...");
  }

  void _startLocalSessionLogic() {
    if (stopwatch.isRunning) return;
    stopwatch.reset();
    stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        final duration = stopwatch.elapsed;
        formattedTime = "${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}.${(duration.inMilliseconds % 1000 ~/ 100)}";
      });
    });
  }

  void _finishSession() {
    stopwatch.stop();
    _timer?.cancel();
    setState(() {
      _isSessionStarted = false;
      _isFinished = true;
      _activeTargets.clear();
      _activeDistractors = {};
    });
    _saveResultsToDatabase();
  }

  Future<void> _saveResultsToDatabase() async {
    try {
      dynamic data = widget.exercise.parameters;
      if (data is String) data = json.decode(data);
      final params = data['parameters'] ?? {};

      final hitsList = _results.where((r) => r.error == 0).toList();
      double avgRT = hitsList.isEmpty
          ? 0.0
          : hitsList.map((e) => e.reactionTime).reduce((a, b) => a + b) / hitsList.length;
      avgRT = double.parse(avgRT.toStringAsFixed(1));

      final testData = {
        'athlete_id': _athleteId,
        'exercise_id': widget.exercise.id,
        'device_id': _bluetoothService.connectedDevice?.remoteId.toString() ?? 'unknown_device',
        'platform_version': _bluetoothService.firmwareVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'session_guid': _sessionGuid,

        // Dados de Configuração Básica do Jogo
        'game_mode': params['game_mode'] ?? 1,
        'execution_rounds': params['game_rounds'] ?? 1,
        'total_attempts': _hits + _misses,
        'timeout_ms': params['timeout_ms'] ?? 0,
        'repeat_if_wrong': (params['repeat_if_wrong'] == true) ? 1 : 0,

        // Configuração de Delays
        'delay_type': params['delay_type']?.toString() ?? '1',
        'delay_min_ms': params['delay_min_ms'] ?? 500,
        'delay_max_ms': params['delay_max_ms'] ?? 500,

        // Configuração de Alvos (Targets)
        'target_logic': params['target_logic'] ?? 1,
        'target_qty': params['target_qty'] ?? 10,
        'target_rgb_hex': params['target_rgb_hex'] ?? "#00FF00",

        // Configuração de Distratores
        'dist_mode': params['dist_mode'] ?? 0,
        'dist_behavior': params['dist_behavior'] ?? 0,
        'dist_qty': params['dist_qty'] ?? 0,
        'dist_rgbs_hex': (params['dist_rgbs_hex'] is List)
            ? json.encode(params['dist_rgbs_hex']) // Transforma a lista de string em JSON TEXT para o SQLite
            : json.encode([]),

        // Resultados Globais Consolidados da Sessão
        'hits': _hits,
        'errors': _misses,
        'avg_reaction_time': avgRT,
        'duration_ms': _totalSessionMs,
      };

      await DatabaseService().saveEvaluationTest(testData, _results);
      _addLog("💾 Session saved to database.");
    } catch (e) {
      _addLog("❌ Error saving to database: $e");
      debugPrint("Save Error: $e");
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    executionLog.add("[${DateTime.now().toString().split(' ').last.substring(0, 8)}] $message");
    _logNotifier.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _recordResult(int round, int sensorId, int reactionTimeMs,
      {required bool isHit, int errType = 0, int wrongSensorId = 0, int stimuliStart = 0, int stimuliEnd = 0}) {

    final sensorDef = _sensorDefinitions.firstWhere(
          (s) => s.id == sensorId,
      orElse: () => SensorDefinition(
        id: sensorId,
        x: 0,
        y: 0,
        sector: sensorId == 255 ? "Timeout" : "unknown",
        expectedFoot: sensorId == 255 ? "None" : "unknown",
      ),
    );

    // 🎯 LOG DE VALIDAÇÃO CRUCIAL (Pode apagar depois que comemorar o sucesso)
    debugPrint('--------------------------------------------------');
    debugPrint('💾 [SQLITE PRE-SAVE LOG] Round #$round');
    debugPrint('👉 ID Recebido do Parser: $sensorId');
    debugPrint('📍 Setor Localizado no DB: ${sensorDef.sector}');
    debugPrint('🦵 Pé Vinculado no DB: ${sensorDef.expectedFoot}');
    debugPrint('⏱️ Tempo de Reação: ${reactionTimeMs}ms | Status: ${isHit ? "✅ HIT" : "❌ MISS"}');
    debugPrint('--------------------------------------------------');

    final result = EvaluationResult(
      roundNum: round,
      stimulusId: sensorId,
      wrongSensorId: wrongSensorId,
      stimulusPosition: sensorDef.sector,
      stimulusType: "color",
      correctColor: _correctColor,
      reactionTime: reactionTimeMs,
      stimulusStart: stimuliStart,
      stimulusEnd: stimuliEnd,
      error: isHit ? 0 : errType,
      footUsed: sensorDef.expectedFoot,
      distractorIdColor: _activeDistractors.entries.map((e) => {'id': e.key, 'color': e.value}).toList(),
    );

    _results.add(result);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _eventSubscription?.cancel();
    _logScrollController.dispose();
    _logNotifier.dispose();
    if (_isSessionStarted) {
      _bluetoothService.sendStopGame();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.exercise.name, style: const TextStyle(fontSize: 18)),
                if (_athleteName != null)
                  Text("Athlete: $_athleteName", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            backgroundColor: const Color(0xFF1A1A1A),
            elevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          body: Row(
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  color: Colors.black12,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Stack(
                            children: [
                              _isSessionStarted
                                  ? _buildCanvas()
                                  : _buildStartOverlay(),
                              if (_isSessionStarted && !stopwatch.isRunning && !_isFinished)
                                _buildCountdownOverlay(),
                            ],
                          ),
                        ),
                      ),
                      _buildStatsBar(),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: Colors.white10),
              Expanded(
                flex: 2,
                child: Container(
                  color: const Color(0xFF1A1A1A),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text("EXECUTION LOG",
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _logNotifier,
                          builder: (context, _, __) {
                            return ListView.builder(
                              controller: _logScrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: executionLog.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    executionLog[index],
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Container(
      color: Colors.black54,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "GET READY",
              style: TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 20),
            Visibility(
              visible: _countdownValue >= 0,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(
                _countdownValue == 0 ? "GO!" : "${_countdownValue > 0 ? _countdownValue : 5}",
                style: TextStyle(
                  color: _countdownValue == 0 ? Colors.greenAccent : Colors.orange,
                  fontSize: 180,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_countdownValue < 0)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text("WAITING FOR SENSORS...",
                    style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12, letterSpacing: 2)
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
            _isFinished ? Icons.check_circle_outline : Icons.touch_app,
            size: 80,
            color: _isFinished ? Colors.green.withOpacity(0.2) : Colors.white10
        ),
        const SizedBox(height: 20),
        if (_isFinished) ...[
          const Text("SESSION COMPLETE",
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 10),
          Text("$_hits Hits | $_misses Misses", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
        ],
        ElevatedButton(
          onPressed: _startSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent.shade400,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: Text(_isFinished ? "RESTART SESSION" : "START SESSION",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        const SizedBox(height: 10),
        Text(
            _isFinished ? "Data has been saved to the database." : "Ensure the device is connected before starting.",
            style: const TextStyle(color: Colors.grey, fontSize: 12)
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return RepaintBoundary(
            child: StreamBuilder<Int32List>(
              stream: _bluetoothService.pressureStream,
              initialData: _bluetoothService.pressureCache,
              builder: (context, snapshot) {
                final values = snapshot.data ?? _bluetoothService.pressureCache;
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: MatPainter(
                    sensors: _sensorDefinitions,
                    values: values,
                    activeTargets: _activeTargets, // 🔥 Passa o Set de múltiplos alvos atualizado
                    correctColor: _correctColor,
                    distractors: _activeDistractors,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsBar() {
    final hits = _results.where((r) => r.error == 0).length;
    double avgRT = hits == 0
        ? 0
        : _results.where((r) => r.error == 0).map((e) => e.reactionTime).reduce((a, b) => a + b) / hits;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat("HITS", "$_hits"),
          _buildStat("TIME", formattedTime, isPrimary: true),
          _buildStat("AVG SPEED", "${avgRT.toStringAsFixed(0)}ms"),
          _buildStat("MISS", "$_misses"),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, {bool isPrimary = false}) {
    return Column(
      children: [
        Text(value, style: TextStyle(
          color: isPrimary ? Colors.orange : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: isPrimary ? 20 : 14,
          fontFamily: isPrimary ? 'monospace' : null,
        )),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }
}

class MatPainter extends CustomPainter {
  final List<SensorDefinition> sensors;
  final List<int> values;
  final Set<int> activeTargets; // 🔥 CORREÇÃO: Mudado de int para Set<int> para dar suporte à renderização múltipla
  final String correctColor;
  final Map<int, String> distractors;

  MatPainter({
    required this.sensors,
    required this.values,
    required this.activeTargets,
    required this.correctColor,
    required this.distractors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double scale = size.shortestSide / 75;

    final double hexSize = 7.5 * scale;
    final double rectWidth = 6.0 * scale;
    final double rectHeight = 1.2 * scale;
    final double rectOffsetDeltaY = -4.5 * scale;

    Color parseColor(String colorStr, Color fallback) {
      try {
        String hex = colorStr.replaceAll('#', '');
        if (hex.length == 6) {
          return Color(int.parse("0xFF$hex"));
        }
        return fallback;
      } catch (_) {
        return fallback;
      }
    }

    final Color targetColor = parseColor(correctColor, Colors.orange);

    for (var sensor in sensors) {
      final pos = Offset(center.dx + (sensor.x * scale), center.dy + (sensor.y * scale));

      // Mapeamento puro de pressão física baseado na fiação do sensor (id 1 mapeia índice 0)
      int val = sensor.id <= values.length ? values[sensor.id - 1] : 0;
      bool isPressed = val > 100;

      // 🔥 CORREÇÃO VISUAL: Checa se o ID humanizado do banco está contido no Set de alvos ativos
      bool isTarget = activeTargets.contains(sensor.id);
      bool isDistractor = distractors.containsKey(sensor.id);

      Color activeColor = targetColor;
      if (isDistractor) {
        activeColor = parseColor(distractors[sensor.id]!, Colors.red);
      }

      // 1. Desenha o Hexágono do Pod
      final hexPaint = Paint()
        ..color = isPressed
            ? activeColor.withOpacity((val / 1023.0).clamp(0.4, 0.9))
            : Colors.white.withOpacity(0.02)
        ..style = PaintingStyle.fill;

      final hexOutlinePaint = Paint()
        ..color = isTarget
            ? Colors.orangeAccent
            : isDistractor
            ? activeColor.withOpacity(0.5)
            : Colors.orange.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (isTarget || isDistractor) ? 2.0 : 0.8;

      _drawHex(canvas, pos, hexSize, hexPaint, hexOutlinePaint);

      // 2. Desenha a barra do LED físico do Pod
      final rectPaint = Paint()
        ..color = (isTarget || isDistractor)
            ? activeColor
            : isPressed
            ? activeColor.withOpacity(0.8)
            : Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
        width: rectWidth,
        height: rectHeight,
      );

      // Efeito Glow nos LEDs ativos (Alvos e Distratores)
      if (isTarget || isDistractor) {
        final shadowPaint = Paint()
          ..color = activeColor.withOpacity(0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * scale);

        canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
                width: rectWidth + (1.0 * scale),
                height: rectHeight + (1.0 * scale),
              ),
              Radius.circular(1.5 * scale),
            ),
            shadowPaint
        );
      }

      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(1.0 * scale)),
          rectPaint
      );

      // 3. Número do Pod
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${sensor.id}',
          style: TextStyle(
              color: isPressed ? Colors.white : Colors.white24,
              fontSize: 4.5 * scale,
              fontWeight: FontWeight.bold
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, pos - Offset(textPainter.width / 2, -textPainter.height / 6));
    }
  }

  void _drawHex(Canvas canvas, Offset center, double size, Paint fill, Paint stroke) {
    final path = Path();
    final double roundingDist = size * 0.1;

    List<Offset> vertices = [];
    for (int i = 0; i < 6; i++) {
      double angle = i * 60 * math.pi / 180;
      vertices.add(Offset(
        center.dx + size * math.cos(angle),
        center.dy + size * math.sin(angle),
      ));
    }

    for (int i = 0; i < 6; i++) {
      Offset pPrev = vertices[(i + 5) % 6];
      Offset pCurr = vertices[i];
      Offset pNext = vertices[(i + 1) % 6];

      Offset p1 = pCurr + (pPrev - pCurr) * (roundingDist / size);
      Offset p2 = pCurr + (pNext - pCurr) * (roundingDist / size);

      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(pCurr.dx, pCurr.dy, p2.dx, p2.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant MatPainter oldDelegate) {
    return oldDelegate.activeTargets != activeTargets ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.values != values ||
        oldDelegate.distractors != distractors ||
        oldDelegate.sensors != sensors;
  }
}