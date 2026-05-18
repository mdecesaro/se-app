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
  StreamSubscription? _pressureSubscription;
  StreamSubscription? _lineSubscription;
  
  // Sensors and Stats
  List<SensorDefinition> _sensorDefinitions = [];
  List<String> executionLog = [];
  final ScrollController _logScrollController = ScrollController();
  
  bool _isSessionStarted = false;
  Stopwatch stopwatch = Stopwatch();
  Timer? _timer;
  String formattedTime = "00:00.0";

  // Stats from Hardware
  int _hits = 0;
  int _misses = 0;
  int _totalSessionMs = 0;
  int _currentRound = 1;
  int _targetHitsPerRound = 10;
  int _hitsInRound = 0;
  int _currentTarget = -1;
  Map<int, String> _activeDistractors = {};
  String _correctColor = "#${0xffffff.toRadixString(16)}";
  List<EvaluationResult> _results = [];
  bool _isFinished = false;
  bool _isWaitingForSet = false;
  String _lastSentCommand = "";
  int _countdownValue = -1; // -1 means no countdown
  String? _athleteName;
  int? _athleteId;

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
    final db = await DatabaseService().database;
    final List<Map<String, dynamic>> maps = await db.query('sensors');
    setState(() {
      _sensorDefinitions = maps.map((m) => SensorDefinition(
        id: m['sensor'],
        x: (m['x_c'] as num).toDouble(),
        y: (m['y_c'] as num).toDouble(),
        sector: m['sector'] ?? "unknown",
        expectedFoot: m['expected_foot'] ?? "unknown",
      )).toList();
    });
  }

  void _setupDataListener() {
    _eventSubscription?.cancel();
    _pressureSubscription?.cancel();
    _lineSubscription?.cancel();

    _eventSubscription = _bluetoothService.eventStream.listen((event) {
      if (event.type == SensorEventType.end && event.totalMs == 0) {
        // Handle structural reset from service
        _resetSessionUI();
        return;
      }
      _handleBinaryEvent(event);
    });
    
    _pressureSubscription = _bluetoothService.pressureStream.listen((pressures) {
      // Pressure is handled via StreamBuilder in _buildCanvas for zero-allocation performance
    });

    _lineSubscription = _bluetoothService.lineStream.listen((line) {
      if (line == "ACK" || line == "SET_OK") {
        if (_isWaitingForSet) {
          _onSetConfirmed();
        } else {
          debugPrint("✔️ SET_OK confirmed.");
        }
      } else if (line == "START_OK") {
        debugPrint("✔️ START confirmed.");
      } else if (line == "DONE") {
        _addLog("🏁 DONE - Execution finished.");
        _finishSession();
      } else if (!line.startsWith("EVT|") && !line.startsWith("DATA:")) {
        debugPrint("📨 [RAW FW LOG]: $line");
      }
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
      _hitsInRound = 0;
      _currentTarget = -1;
      _activeDistractors = {};
      _countdownValue = -1;
    });
    _addLog("⚠️ Connection Reset - Session Cleared");
  }

  void _handleBinaryEvent(SensorEvent event) {
    if (!mounted) return;
    
    switch (event.type) {
      case SensorEventType.on:
        setState(() {
          _currentTarget = event.sensorId;
          _activeDistractors = Map<int, String>.from(event.distractors ?? {});
          final color = event.color;
          if (color != null && color.length >= 3) {
            _correctColor = '#${color[0].toRadixString(16).padLeft(2, '0')}'
                            '${color[1].toRadixString(16).padLeft(2, '0')}'
                            '${color[2].toRadixString(16).padLeft(2, '0')}';
          }
        });
        _addLog("Target ON: Sensor ${event.sensorId}");
        break;

      case SensorEventType.hit:
        _recordResult(_currentRound, event.sensorId, event.reactionTime ?? 0, 
          isHit: true, 
          stimuliStart: event.stimuliStart ?? 0, 
          stimuliEnd: event.stimuliEnd ?? 0
        );

        setState(() {
          _hits++;
          _hitsInRound++;
          if (_hitsInRound >= _targetHitsPerRound) {
            _currentRound++;
            _hitsInRound = 0;
          }
          _currentTarget = -1;
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
          _currentTarget = -1;
          _activeDistractors = {};
        });
        _addLog("MISS! ${event.errorType == 1 ? 'TIMEOUT' : 'WRONG'} at Sensor ${event.sensorId}");
        break;

      case SensorEventType.end:
        _totalSessionMs = event.totalMs ?? 0;
        _addLog("🏁 Session Summary: ${event.hits} hits, ${event.misses} misses");
        _finishSession();
        break;
    }
  }

  String _colorToHex(dynamic color) {
    if (color == null) return "ffffff";
    String c = color.toString().toLowerCase();
    if (c.startsWith('#')) return c.replaceAll('#', '');
    
    const map = {
      'green': '00ff00',
      'red': 'ff0000',
      'yellow': 'ffff00',
      'blue': '0000ff'
    };
    return map[c] ?? 'ffffff';
  }

  void _startSession() async {
    try {
      dynamic data = widget.exercise.parameters;
      if (data is String) data = json.decode(data);
      final params = data['parameters'] ?? {};

      // Prepare UI state
      setState(() {
        _isSessionStarted = true;
        _isFinished = false;
        _isWaitingForSet = true;
        _hits = 0;
        _misses = 0;
        _totalSessionMs = 0;
        _currentRound = 1;
        _hitsInRound = 0;
        _results = [];
        _currentTarget = -1;
        _activeDistractors = {};
        formattedTime = "00:00.0";
        
        _targetHitsPerRound = params['target_qty'] ?? 10;
        _correctColor = params['target_rgb_hex'] ?? "#00FF00";
        
        _addLog("➡️ Sending Binary Configuration...");
      });

      // Send Binary START Command (V1.4.0)
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
      
      _lastSentCommand = "START_BINARY";
    } catch (e) {
      _addLog("❌ Error starting session: $e");
      setState(() => _isSessionStarted = false);
    }
  }

  void _onSetConfirmed() async {
    if (!mounted || !_isWaitingForSet) return;
    
    setState(() {
      _isWaitingForSet = false;
      _countdownValue = 5; // Sync with V1.4.0 5-second visual countdown contract
    });

    _addLog("✔️ Configuration applied. Starting countdown...");

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownValue > 0) {
          _countdownValue--;
        } else {
          _countdownValue = -1; 
          timer.cancel();
          _startLocalSessionLogic();
        }
      });
    });
  }

  void _startLocalSessionLogic() {
    _addLog("🚀 Session GO!");
    
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
      _currentTarget = -1;
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
          ? 0 
          : hitsList.map((e) => e.reactionTime).reduce((a, b) => a + b) / hitsList.length;

      final testData = {
        'athlete_id': _athleteId,
        'exercise_id': widget.exercise.id,
        'device_id': _bluetoothService.connectedDevice?.remoteId.toString(),
        'platform_version': _bluetoothService.firmwareVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'stimuli_count': params['target_qty'],
        'delay_type': params['delay_type']?.toString(),
        'delay_min_ms': params['delay_min_ms'],
        'delay_max_ms': params['delay_max_ms'],
        'execution_rounds': params['game_rounds'],
        'timeout_ms': params['timeout_ms'],
        'repeat_if_wrong': (params['repeat_if_wrong'] == true) ? 1 : 0,
        'total_attempts': _hits + _misses,
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
    setState(() {
      executionLog.add("[${DateTime.now().toString().split(' ').last.substring(0, 8)}] $message");
    });
    // Auto-scroll log
    Future.delayed(const Duration(milliseconds: 100), () {
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
      orElse: () => SensorDefinition(id: sensorId, x: 0, y: 0, sector: "unknown", expectedFoot: "unknown"),
    );

    final result = EvaluationResult(
      roundNum: round,
      stimulusId: sensorId,
      stimulusPosition: sensorDef.sector,
      stimulusType: "color",
      correctColor: _correctColor,
      reactionTime: reactionTimeMs,
      stimulusStart: stimuliStart, 
      stimulusEnd: stimuliEnd,
      error: isHit ? 0 : errType, // 1: TIMEOUT, 2: WRONG
      footUsed: sensorDef.expectedFoot,
      wrongSensorId: wrongSensorId,
      distractorIdColor: _activeDistractors.entries.map((e) => {'id': e.key, 'color': e.value}).toList(),
    );

    _results.add(result);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _eventSubscription?.cancel();
    _pressureSubscription?.cancel();
    _lineSubscription?.cancel();
    _logScrollController.dispose();
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
              // Left Panel: Canvas Area (80%)
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
                              if (_countdownValue >= 0) _buildCountdownOverlay(),
                            ],
                          ),
                        ),
                      ),
                      _buildStatsBar(),
                    ],
                  ),
                ),
              ),
              // Vertical Divider
              Container(width: 1, color: Colors.white10),
              // Right Panel: Log Area (20%)
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
                        child: ListView.builder(
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
            Text(
              _countdownValue == 0 ? "GO!" : "$_countdownValue",
              style: TextStyle(
                color: _countdownValue == 0 ? Colors.greenAccent : Colors.orange,
                fontSize: 180,
                fontWeight: FontWeight.bold,
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
                    currentTarget: _currentTarget,
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
  final int currentTarget;
  final String correctColor;
  final Map<int, String> distractors;

  MatPainter({
    required this.sensors, 
    required this.values, 
    required this.currentTarget,
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

    // Helper to parse hex color
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
      
      int val = sensor.id <= values.length ? values[sensor.id - 1] : 0;
      bool isPressed = val > 100;
      bool isTarget = sensor.id == currentTarget;
      bool isDistractor = distractors.containsKey(sensor.id);
      
      Color activeColor = targetColor;
      if (isDistractor) {
        activeColor = parseColor(distractors[sensor.id]!, Colors.red);
      }

      // 1. Draw the Hexagon (The Pad)
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

      // 2. Draw the "Status Bar" Rectangle (The Real LED)
      final rectPaint = Paint()
        ..color = (isTarget || isDistractor)
            ? activeColor // Brightest when it's the target or distractor
            : isPressed 
                ? activeColor.withOpacity(0.8) 
                : Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.fill;
      
      final rect = Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
        width: rectWidth,
        height: rectHeight,
      );

      // Add a glow effect for the active target/distractor LED
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

      // Draw the LED with rounded corners
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(1.0 * scale)), 
        rectPaint
      );

      // 3. Draw Sensor Number
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
    final double roundingDist = size * 0.1; // Reduced to 10% for a "little" rounding
    
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
  bool shouldRepaint(covariant MatPainter oldDelegate) => true;
}
