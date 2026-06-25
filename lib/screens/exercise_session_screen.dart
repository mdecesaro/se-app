import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/evaluation_result.dart';
import '../services/bluetooth_service.dart';
import '../services/database_service.dart';
import 'mat_painter.dart';

class ExerciseSessionScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseSessionScreen({super.key, required this.exercise});

  @override
  State<ExerciseSessionScreen> createState() => _ExerciseSessionScreenState();
}

class _ExerciseSessionScreenState extends State<ExerciseSessionScreen> {
  final AppBluetoothService _bluetoothService = AppBluetoothService();
  StreamSubscription? _eventSubscription;

  List<SensorDefinition> _sensorDefinitions = [];
  final List<String> executionLog = [];
  final ScrollController _logScrollController = ScrollController();
  final ValueNotifier<int> _logNotifier = ValueNotifier<int>(0);

  bool _isSessionStarted = false;
  Stopwatch stopwatch = Stopwatch();
  Timer? _timer;
  String formattedTime = "00:00.0";

  int _hits = 0;
  int _misses = 0;
  int _totalSessionMs = 0;

  Set<int> _activeTargets = {};
  Map<int, String> _activeDistractors = {};
  String _correctColor = "#00FF00";

  List<int> _currentAttemptTargets = [];
  String _currentAttemptTargetColor = "#00FF00";
  List<int> _currentAttemptDistractors = [];
  List<String> _currentAttemptDistractorColors = [];

  List<EvaluationResult> _results = [];
  bool _isFinished = false;
  bool _isWaitingForSet = false;
  int _countdownValue = -1;
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
      final List<SensorDefinition> loadedSensors = [];

      for (var m in maps) {
        final int? sensorId = m['sensor'];
        if (sensorId != null) {
          loadedSensors.add(SensorDefinition(
            id: sensorId,
            x: (m['x_c'] as num).toDouble(),
            y: (m['y_c'] as num).toDouble(),
            sector: m['sector'] ?? "unknown",
            expectedFoot: m['expected_foot'] ?? "unknown",
          ));
        }
      }
      setState(() => _sensorDefinitions = loadedSensors);
    } catch (e) {
      debugPrint('Error loading sensors: $e');
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
      _activeTargets = {};
      _activeDistractors = {};
      _currentAttemptTargets.clear();
      _currentAttemptDistractors.clear();
      _currentAttemptDistractorColors.clear();
      _countdownValue = -1;
    });
    _addLog("⚠️ Connection Reset - Session Cleared");
  }

  void _handleBinaryEvent(SensorEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case SensorEventType.ack:
      // 🟢 Correção: Se o hardware mandou ACK e estávamos esperando a config subir
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
          _countdownValue = event.countdownValue;
        });
        _addLog("⏳ Countdown Sync: ${event.countdownValue}");
        break;

      case SensorEventType.animationStep:
        if (_countdownValue != event.countdownValue) {
          setState(() => _countdownValue = event.countdownValue);
          _addLog("⏳ Step: ${event.countdownValue}");
        }
        break;

      case SensorEventType.countdownEnded:
        _addLog("🚀 Session GO!");
        _startLocalSessionLogic();
        setState(() => _countdownValue = -1);
        break;

      case SensorEventType.on:
        setState(() {
          _activeTargets = {};
          _activeDistractors = {};

          final color = event.color;
          if (color != null && color.length >= 3) {
            _correctColor = '#${color[0].toRadixString(16).padLeft(2, '0')}'
                '${color[1].toRadixString(16).padLeft(2, '0')}'
                '${color[2].toRadixString(16).padLeft(2, '0')}'.toUpperCase();
          }

          if (color != null && color.length > 3) {
            for (int i = 3; i < color.length; i++) {
              _activeTargets.add(color[i]);
            }
          } else if (event.sensorId > 0) {
            _activeTargets.add(event.sensorId);
          }

          if (event.distractors != null) {
            _activeDistractors.addAll(Map<int, String>.from(event.distractors!));
          }

          _currentAttemptTargets = _activeTargets.toList();
          _currentAttemptTargetColor = _correctColor;
          _currentAttemptDistractors = _activeDistractors.keys.toList();
          _currentAttemptDistractorColors = _activeDistractors.values.toList();
        });
        _addLog("Targets ON: Sensors ${_activeTargets.join(', ')}");
        break;

      case SensorEventType.hit:
        _recordResult(
            round: event.roundnum,
            attempt: event.attempt,
            hitSensorId: event.sensorId,
            reactionTimeMs: event.reactionTime ?? 0,
            gct: event.gct ?? 0,
            delayApplied: event.delayApplied ?? false,
            errorType: 0,
            stimuliStart: event.stimuliStart ?? 0,
            stimuliEnd: event.stimuliEnd ?? 0
        );
        _addLog("HIT! Sensor ${event.sensorId} - RT: ${event.reactionTime}ms");
        setState(() {
          _hits++;
          _activeTargets = {};
          _activeDistractors = {};
        });
        break;

      case SensorEventType.miss:
        _recordResult(
            round: event.roundnum,
            attempt: event.attempt,
            hitSensorId: event.wrongSensorId ?? 0,
            reactionTimeMs: event.reactionTime ?? 0,
            gct: event.gct ?? 0,
            delayApplied: event.delayApplied ?? false,
            errorType: event.errorType ?? 1,
            stimuliStart: event.stimuliStart ?? 0,
            stimuliEnd: event.stimuliEnd ?? 0
        );
        final String errorName = event.errorType == 2 ? 'TIMEOUT' : 'WRONG SENSOR';
        _addLog("MISS! [$errorName] at Pod: ${event.wrongSensorId}");
        setState(() {
          _misses++;
          _activeTargets = {};
          _activeDistractors = {};
        });
        break;

      case SensorEventType.end:
        _totalSessionMs = stopwatch.elapsedMilliseconds;
        _addLog("🏁 Session Summary: ${event.hits} hits, ${event.misses} misses");
        _finishSession();
        break;
      default:
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
        _results = [];
        _activeTargets = {};
        _activeDistractors = {};
        _currentAttemptTargets = [];
        _currentAttemptTargetColor = params['target_rgb_hex'] ?? "#00FF00";
        _currentAttemptDistractors = [];
        _currentAttemptDistractorColors = [];
        _sessionGuid = "${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}";
        formattedTime = "00:00.0";
        _countdownValue = -1; // 🟢 Inicializa limpo
        _correctColor = params['target_rgb_hex'] ?? "#00FF00";
        _addLog("➡️ Sending Binary Configuration...");
      });

      if (_bluetoothService.connectedDevice == null) {
        _addLog("⚠️ Pod disconnected. Reconnect before starting.");
        setState(() => _isSessionStarted = false);
        return;
      }

      // 🟢 IMPORTANTE: Força o barramento do service a saber que a janela ativa de UI
      // para handshakes e retornos agora pertence a ESTA instância de tela!
      _bluetoothService.performHandshake(() {
        if (mounted) setState(() {});
      });

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
        distRGBsHex: (params['dist_rgbs_hex'] is List) ? List<String>.from(params['dist_rgbs_hex']) : [],
        delayType: params['delay_type'] ?? 1,
        delayMinMs: params['delay_min_ms'] ?? 500,
        delayMaxMs: params['delay_max_ms'] ?? 500,
        timeoutMs: params['timeout_ms'] ?? 0,
        repeatIfWrong: params['repeat_if_wrong'] == true,
        missPolicy: params['miss_policy'] ?? 0,
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
      _activeTargets = {};
      _activeDistractors = {};
    });
    _saveResultsToDatabase();
  }

  Future<void> _saveResultsToDatabase() async {
    try {
      dynamic data = widget.exercise.parameters;
      if (data is String) data = json.decode(data);
      final params = data['parameters'] ?? {};
      final hitsList = _results.where((r) => r.errorType == 0).toList();
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
        'game_mode': params['game_mode'] ?? 1,
        'execution_rounds': params['game_rounds'] ?? 1,
        'total_attempts': _hits + _misses,
        'timeout_ms': params['timeout_ms'] ?? 0,
        'repeat_if_wrong': (params['repeat_if_wrong'] == true) ? 1 : 0,
        'delay_type': params['delay_type']?.toString() ?? '1',
        'delay_min_ms': params['delay_min_ms'] ?? 500,
        'delay_max_ms': params['delay_max_ms'] ?? 500,
        'target_logic': params['target_logic'] ?? 1,
        'target_qty': params['target_qty'] ?? 10,
        'target_rgb_hex': params['target_rgb_hex'] ?? "#00FF00",
        'dist_mode': params['dist_mode'] ?? 0,
        'dist_behavior': params['dist_behavior'] ?? 0,
        'dist_qty': params['dist_qty'] ?? 0,
        'dist_rgbs_hex': (params['dist_rgbs_hex'] is List) ? json.encode(params['dist_rgbs_hex']) : json.encode([]),
        'hits': _hits,
        'errors': _misses,
        'avg_reaction_time': avgRT,
        'duration_ms': _totalSessionMs,
      };

      await DatabaseService().saveEvaluationTest(testData, _results);
      _addLog("💾 Session saved to database.");
    } catch (e) {
      _addLog("❌ Error saving to database: $e");
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

  void _recordResult({
    required int round,
    required int attempt,
    required int hitSensorId,
    required int reactionTimeMs,
    required int gct,
    required delayApplied,
    required int errorType,
    required int stimuliStart,
    required int stimuliEnd
  }) {
    _results.add(EvaluationResult(
      roundNum: round,
      attemptNum: attempt,
      stimulusStart: stimuliStart,
      stimulusEnd: stimuliEnd,
      reactionTime: reactionTimeMs,
      gct: gct,
      delayApplied: delayApplied,
      targets: _currentAttemptTargets,
      targetColorHex: _currentAttemptTargetColor,
      distractors: _currentAttemptDistractors,
      distractorColorsHex: _currentAttemptDistractorColors,
      hitSensorId: hitSensorId,
      errorType: errorType,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 🟢 CRÍTICO: Cancela explicitamente a escuta do stream BLE. Isso impede
    // que esta tela continue rodando e interceptando respostas fantasiadas em background!
    _eventSubscription?.cancel();
    _eventSubscription = null;

    _logScrollController.dispose();
    _logNotifier.dispose();
    if (_isSessionStarted) _bluetoothService.sendStopGame();
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
                              _isSessionStarted ? _buildCanvas() : _buildStartOverlay(),
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
            child: StreamBuilder<SensorEvent>(
              stream: _bluetoothService.eventStream,
              builder: (context, snapshot) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: MatPainter(
                    sensors: _sensorDefinitions,
                    activeTargets: _activeTargets,
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
    final hitsList = _results.where((r) => r.errorType == 0).toList();
    double avgRT = hitsList.isEmpty
        ? 0
        : hitsList.map((e) => e.reactionTime).reduce((a, b) => a + b) / hitsList.length;

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