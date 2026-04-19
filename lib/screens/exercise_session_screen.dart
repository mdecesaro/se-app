import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  StreamSubscription? _dataSubscription;
  String _incomingBuffer = "";
  
  // Sensors and Stats
  List<SensorDefinition> _sensorDefinitions = [];
  List<int> sensorValues = List.filled(14, 0);
  List<String> executionLog = [];
  final ScrollController _logScrollController = ScrollController();
  
  bool _isSessionStarted = false;
  Stopwatch stopwatch = Stopwatch();
  Timer? _timer;
  String formattedTime = "00:00.0";

  // Stats from Hardware
  int _hits = 0;
  int _misses = 0;
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
        setState(() => _athleteName = athletes.first.name);
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
    _dataSubscription?.cancel();
    _dataSubscription = _bluetoothService.lineStream.listen((line) {
      if (line.startsWith("EVT|") || line == "SET_OK" || line == "START_OK" || line == "DONE") {
        _handleHardwareEvent(line);
      } else {
        _parseSensorData(line);
      }
    });
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

  String _buildProtocolCommand() {
    try {
      dynamic data = widget.exercise.parameters;
      if (data is String) data = json.decode(data);
      final params = data['parameters'] ?? {};

      // 1. stimuli_count
      final int count = params['stimuli_count'] ?? 10;

      // 2. stimuli_rounds
      final int rounds = params['stimuli_rounds'] ?? 1;

      // 3. stimuli_mode (1: Random, 2: Pattern)
      final int mode = params['stimuli_mode'] ?? 1;

      // 4. stimuli_color (HEX no #)
      final String color = _colorToHex(params['stimuli_color'] ?? "#00FF00");

      // 5. dist_qty
      final int distQty = params['dist_qty'] ?? 0;

      // 6. dist_colors (comma-separated hex or 0)
      String distColors = "0";
      if (distQty > 0 && params['dist_colors'] is List) {
        distColors = (params['dist_colors'] as List).map((c) => _colorToHex(c)).join(',');
      }

      // 7. delay_type (1: Fixed, 2: Range)
      final int delayType = params['delay_type'] ?? 1;

      // 8. delay_min
      final int delayMin = params['delay_min'] ?? 500;

      // 9. delay_max
      final int delayMax = params['delay_max'] ?? 500;

      // 10. timeout_ms
      final int timeout = params['timeout_ms'] ?? 0;

      // 11. repeat_if_wrong (1 or 0)
      final int repeat = (params['repeat_if_wrong'] == true) ? 1 : 0;

      // Format: SET|count|rounds|mode|color|dist_qty|dist_colors|delay_type|delay_min|delay_max|timeout|repeat
      return "SET|$count|$rounds|$mode|$color|$distQty|$distColors|$delayType|$delayMin|$delayMax|$timeout|$repeat";
    } catch (e) {
      _addLog("Protocol Error: $e");
      return "SET|10|1|1|00FF00|0|0|1|500|500|0|0";
    }
  }

  void _startSession() async {
    String setCommand = _buildProtocolCommand();
    
    // Extract info for UI and tracking
    List<String> parts = setCommand.split('|');
    if (parts.length >= 5) {
      _targetHitsPerRound = int.tryParse(parts[1]) ?? 10;
      _correctColor = "#${parts[4]}";
    }

    setState(() {
      _isSessionStarted = true;
      _isFinished = false;
      _isWaitingForSet = true;
      _hits = 0;
      _misses = 0;
      _currentRound = 1;
      _hitsInRound = 0;
      _results = [];
      _currentTarget = -1;
      _activeDistractors = {};
      formattedTime = "00:00.0";
      _addLog("➡️ Sent: SET");
    });

    // 1. Send SET
    _lastSentCommand = setCommand;
    await _bluetoothService.sendMessage("$setCommand\n");
  }

  void _onSetConfirmed() async {
    if (!mounted || !_isWaitingForSet) return;
    
    setState(() {
      _isWaitingForSet = false;
      _countdownValue = 5;
    });

    _addLog("✔️ SET confirmed. Starting countdown...");

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownValue > 0) {
          _countdownValue--;
        } else {
          _countdownValue = -1; // Hide countdown
          timer.cancel();
          _sendStartCommand();
        }
      });
    });
  }

  void _sendStartCommand() async {
    _addLog("🚀 Sending START...");
    
    // Start the elapsed timer ONLY now
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

    _lastSentCommand = "START";
    await _bluetoothService.sendMessage("START\n");
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

  void _parseSensorData(String data) {
    // Ignore echoes and Handshake noise
    if (data == _lastSentCommand || 
        data == "HANDSHAKE" ||
        (data.startsWith("SET|") && _lastSentCommand.startsWith("SET|"))) {
      return;
    }

    if (data.startsWith("DATA:")) {
      try {
        String valuesPart = data.substring(5);
        List<String> splitValues = valuesPart.split(',');
        setState(() {
          for (int i = 0; i < splitValues.length && i < 14; i++) {
            sensorValues[i] = int.tryParse(splitValues[i]) ?? 0;
          }
        });
      } catch (e) {
        debugPrint("Error parsing sensor data: $e");
      }
    } else {
      _addLog("📨 [RAW]: $data");
    }
  }

  Future<void> _saveResultsToDatabase() async {
    if (_results.isEmpty) return;
    
    try {
      final db = await DatabaseService().database;
      
      // 1. Get current athlete (for now, the first one in DB)
      final List<Map<String, dynamic>> athletes = await db.query('athletes', limit: 1);
      int athleteId = athletes.isNotEmpty ? athletes.first['id'] : 1;

      // 2. Parse parameters from exercise
      Map<String, dynamic> params = json.decode(widget.exercise.parameters);
      if (params.containsKey('parameters')) {
        params = params['parameters'];
      }
      
      final int stimuliCount = params['stimuli_count'] ?? 0;
      final int dType = params['delay_type'] ?? 1;
      final String delayType = dType == 1 ? 'fixed' : 'range';
      final int delayMin = params['delay_min'] ?? 0;
      final int delayMax = params['delay_max'] ?? delayMin;
      final int stimuliRounds = params['stimuli_rounds'] ?? 1;
      final int timeoutMs = params['timeout_ms'] ?? 0;
      final bool repeatIfWrong = params['repeat_if_wrong'] ?? false;

      // 3. Calculate Session Stats
      int totalAttempts = _results.length;
      int hits = _results.where((r) => r.error == 0).length;
      int errors = _results.where((r) => r.error != 0).length;
      
      double avgRT = 0;
      double durationMs = 0;
      if (_results.isNotEmpty) {
        avgRT = _results.map((e) => e.reactionTime).reduce((a, b) => a + b) / _results.length;
        durationMs = _results.map((e) => e.reactionTime).fold(0.0, (a, b) => a + b);
      }

      // 4. Insert into evaluation_tests (The Session Header)
      int testId = await db.insert('evaluation_tests', {
        'athlete_id': athleteId,
        'exercise_id': widget.exercise.id,
        'device_id': 'GRID_AI_DEVICE',
        'platform_version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
        'stimuli_count': stimuliCount,
        'delay_type': delayType,
        'delay_min_ms': delayMin,
        'delay_max_ms': delayMax,
        'execution_rounds': stimuliRounds,
        'timeout_ms': timeoutMs,
        'repeat_if_wrong': repeatIfWrong ? 1 : 0,
        'total_attempts': totalAttempts,
        'hits': hits,
        'errors': errors,
        'avg_reaction_time': avgRT,
        'duration_ms': durationMs,
      });

      // 5. Insert each result into evaluation_test_results
      for (var result in _results) {
        Map<String, dynamic> row = result.toMap();
        row['test_id'] = testId;
        
        // Handle types and complex fields
        row['wrong_stimulus_id'] = row['wrong_stimulus_id'].toString();
        row['distractor_id_color'] = json.encode(row['distractor_id_color']);
        
        await db.insert('evaluation_test_results', row);
      }
      
      _addLog("💾 Data saved successfully (Test ID: $testId).");
    } catch (e) {
      _addLog("❌ Error saving data: $e");
    }
  }

  void _handleHardwareEvent(String evtLine) {
    if (evtLine == "DONE") {
      _addLog("🏁 DONE - Execution finished.");
      _finishSession();
      return;
    }
    if (evtLine == "SET_OK") {
      _onSetConfirmed();
      return;
    }
    if (evtLine == "START_OK") {
      _addLog("✔️ START confirmed.");
      return;
    }

    try {
      List<String> parts = evtLine.split('|');
      if (parts.length < 2) return;

      String evtType = parts[1];

      // EVT|ON|stimuli_mode|sensor_id|stimuli_color|dist_qty|dist_colors
      if (evtType == "ON" && parts.length >= 7) {
        int sensorId = int.tryParse(parts[3]) ?? 0;
        String newCorrectColor = parts[4];
        int distQty = int.tryParse(parts[5]) ?? 0;
        String distColorsRaw = parts[6];
        
        Map<int, String> newDistractors = {};
        if (distQty > 0 && distColorsRaw != "0") {
          // Robust parsing for dist_colors (supports id:color or id)
          List<String> items = distColorsRaw.split(',');
          for (var item in items) {
            if (item.contains(':')) {
              List<String> pair = item.split(':');
              int? id = int.tryParse(pair[0]);
              if (id != null) {
                String color = pair[1];
                newDistractors[id] = color.startsWith('#') ? color : "#$color";
              }
            } else {
              int? id = int.tryParse(item);
              if (id != null) {
                newDistractors[id] = "#FF0000"; // Fallback
              }
            }
          }
        }

        setState(() {
          _currentTarget = sensorId;
          _activeDistractors = newDistractors;
          if (newCorrectColor.isNotEmpty && newCorrectColor != "0") {
            _correctColor = newCorrectColor.startsWith('#') ? newCorrectColor : "#$newCorrectColor";
          }
        });
        _addLog("Target ON: Sensor $sensorId");
      }
      // EVT|HIT|stimuli_mode|sensor_id|reaction_time
      else if (evtType == "HIT" && parts.length >= 5) {
        int sensorId = int.tryParse(parts[3]) ?? 0;
        int ms = int.tryParse(parts[4]) ?? 0;

        _recordResult(_currentRound, sensorId, ms, 0, isHit: true);

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
        _addLog("HIT! Sensor $sensorId - RT: ${ms}ms");
      }
      // EVT|MISS|stimuli_mode|sensor_id|err_type|wrong_sensor_id
      else if (evtType == "MISS" && parts.length >= 6) {
        int sensorId = int.tryParse(parts[3]) ?? 0;
        int errType = int.tryParse(parts[4]) ?? 1; // 1: TIMEOUT, 2: WRONG
        int wrongSensorId = int.tryParse(parts[5]) ?? 0;

        _recordResult(_currentRound, sensorId, 0, 0, isHit: false, errType: errType, wrongSensorId: wrongSensorId);

        setState(() {
          _misses++;
          _currentTarget = -1;
          _activeDistractors = {};
        });
        _addLog("MISS! ${errType == 1 ? 'TIMEOUT' : 'WRONG'} at Sensor $sensorId");
      }
      // EVT|END|total_ms|hits|misses
      else if (evtType == "END" && parts.length >= 5) {
        _addLog("🏁 Session Summary: ${parts[3]} hits, ${parts[4]} misses");
      }
    } catch (e) {
      _addLog("Parse Error: $e");
    }
  }

  void _recordResult(int round, int sensorId, int reactionTimeMs, int delay, 
      {required bool isHit, int errType = 0, int wrongSensorId = 0}) {
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
      stimulusStart: 0, 
      stimulusEnd: reactionTimeMs,
      delayMs: delay,
      elapsedSinceStart: 0, 
      error: isHit ? 0 : errType, // 1: TIMEOUT, 2: WRONG
      footUsed: sensorDef.expectedFoot,
      wrongStimulusId: wrongSensorId,
      distractorIdColor: [],
    );

    _results.add(result);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSubscription?.cancel();
    _logScrollController.dispose();
    if (_isSessionStarted) {
      _bluetoothService.sendMessage("STOP\n");
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
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: MatPainter(
              sensors: _sensorDefinitions,
              values: sensorValues,
              currentTarget: _currentTarget,
              correctColor: _correctColor,
              distractors: _activeDistractors,
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsBar() {
    double avgRT = _results.isEmpty 
        ? 0 
        : _results.map((e) => e.reactionTime).reduce((a, b) => a + b) / _results.length;

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
