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
  int _currentTarget = -1;
  String _correctColor = "#${0xffffff.toRadixString(16)}";
  List<EvaluationResult> _results = [];
  bool _isFinished = false;
  bool _isWaitingForSet = false;
  String _lastSentCommand = "";
  int _countdownValue = -1; // -1 means no countdown

  @override
  void initState() {
    super.initState();
    _loadSensors();
    _setupDataListener();
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
    _dataSubscription = _bluetoothService.dataStream.listen((data) {
      String decoded = utf8.decode(data, allowMalformed: true);
      _incomingBuffer += decoded;

      if (_incomingBuffer.contains('\n') || _incomingBuffer.contains('\r')) {
        List<String> lines = _incomingBuffer.split(RegExp(r'\r\n|\r|\n'));
        _incomingBuffer = lines.last;

        for (int i = 0; i < lines.length - 1; i++) {
          String line = lines[i].trim();
          if (line.isNotEmpty) {
            _parseSensorData(line);
          }
        }
      }
    });
  }

  String _buildProtocolCommand() {
    try {
      dynamic params = widget.exercise.parameters;
      if (params is String) {
        params = json.decode(params);
      }
      if (params is Map && params.containsKey('parameters')) {
        params = params['parameters'];
      }

      // Format: SET|stimuli_count|manual|delay_range|rounds|color hex
      
      // 1. stimuli_count
      String count = params['stimuli_count']?.toString() ?? "10";

      // 2. manual (0 = random)
      String manual = (params['stimuli_generation_mode'] == "sequence") ? "1" : "0";

      // 3. delay_range
      String delay;
      if (params['delay_type'] == "range") {
        delay = "${params['delay_range_ms'][0]},${params['delay_range_ms'][1]}";
      } else {
        delay = params['delay_range_ms'][0].toString();
      }

      // 4. rounds
      String rounds = params['execution_rounds']?.toString() ?? "1";

      // 5. color hex (remove #)
      String color = (params['correct_color'] ?? "#${0xffffff.toRadixString(16)}").replaceAll("#", "");

      return "SET|$count|$manual|$delay|$rounds|$color";
    } catch (e) {
      _addLog("Protocol Error: $e");
      return "SET|10|0|500|1|${0xffffff.toRadixString(16)}";
    }
  }

  void _startSession() async {
    String setCommand = _buildProtocolCommand();
    
    // Extract color for UI
    List<String> parts = setCommand.split('|');
    if (parts.length >= 6) {
      _correctColor = "#${parts[5]}";
    }

    setState(() {
      _isSessionStarted = true;
      _isFinished = false;
      _isWaitingForSet = true;
      _hits = 0;
      _misses = 0;
      _results = [];
      _currentTarget = -1;
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
    // Ignore echoes and Handshake noise (Bluetooth feedback loop)
    if (data == _lastSentCommand || 
        data == "HANDSHAKE" ||
        data.startsWith("SET|") && _lastSentCommand.contains("SET|")) {
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
    } else if (data == "SET_OK") {
      _onSetConfirmed();
    } else if (data.startsWith("EVT|")) {
      _handleHardwareEvent(data);
    } else if (data == "DONE") {
      _addLog("🏁 DONE - Execution finished.");
      _saveResultsToDatabase();
      setState(() {
        _isFinished = true;
        _isSessionStarted = false;
        _currentTarget = -1;
        stopwatch.stop();
        _timer?.cancel();
      });
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
      final String delayType = params['delay_type'] ?? 'fixed';
      final List<dynamic> delayRange = params['delay_range_ms'] ?? [700];
      final int delayMin = delayRange.isNotEmpty ? (delayRange.first as num).toInt() : 0;
      final int delayMax = delayRange.length > 1 ? (delayRange.last as num).toInt() : delayMin;
      final int executionRounds = params['execution_rounds'] ?? 1;
      final int timeoutMs = params['timeout_ms'] ?? 0;
      final bool repeatIfWrong = params['repeat_if_wrong'] ?? false;

      // 3. Calculate Session Stats (Mirroring Python Controller)
      int totalAttempts = _results.length;
      int hits = _results.where((r) => r.error == 0).length;
      int errors = _results.where((r) => r.error != 0).length;
      
      double avgRT = 0;
      double durationMs = 0;
      if (_results.isNotEmpty) {
        avgRT = _results.map((e) => e.reactionTime).reduce((a, b) => a + b) / _results.length;
        durationMs = _results.map((e) => e.reactionTime).reduce((a, b) => a + b).toDouble();
      }

      // 4. Insert into evaluation_tests (The Session Header)
      int testId = await db.insert('evaluation_tests', {
        'athlete_id': athleteId,
        'exercise_id': widget.exercise.id,
        'device_id': 'GRID_AI_DEVICE', // Identifier replaced to avoid typo warning
        'platform_version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
        'stimuli_count': stimuliCount,
        'delay_type': delayType,
        'delay_min_ms': delayMin,
        'delay_max_ms': delayMax,
        'execution_rounds': executionRounds,
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
    try {
      List<String> parts = evtLine.split('|');
      if (parts.length < 4) return;

      String evtType = parts[1];
      int round = int.tryParse(parts[2]) ?? 0;
      int sensorId = int.tryParse(parts[3]) ?? 0;

      // EVT|ON|round|sensorIdx
      if (evtType == "ON") {
        setState(() => _currentTarget = sensorId);
        _addLog("Target ON: Sensor $sensorId");
      }
      // EVT|HIT|round|sensorIdx|ms|delay
      else if (evtType == "HIT") {
        int ms = int.tryParse(parts[4]) ?? 0;
        int delay = int.tryParse(parts[5]) ?? 0;

        _recordResult(round, sensorId, ms, delay);

        setState(() {
          _hits++;
          _currentTarget = -1;
        });
        _addLog("HIT! Sensor $sensorId - RT: ${ms}ms");
      }
      // EVT|END|total_ms|hits|misses
      else if (evtType == "END") {
        _addLog("Session Summary: ${parts[3]} hits, ${parts[4]} misses");
      }
    } catch (e) {
      _addLog("Parse Error: $e");
    }
  }

  void _recordResult(int round, int sensorId, int reactionTimeMs, int delay) {
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
      stimulusStart: 0, // Calculated on hardware
      stimulusEnd: 0,   // Calculated on hardware
      delayMs: delay,
      elapsedSinceStart: stopwatch.elapsedMilliseconds,
      error: 0,
      footUsed: sensorDef.expectedFoot,
      wrongStimulusId: 0,
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
            title: Text(widget.exercise.name, style: const TextStyle(fontSize: 18)),
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

  MatPainter({
    required this.sensors, 
    required this.values, 
    required this.currentTarget,
    required this.correctColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double scale = size.shortestSide / 75;
    
    final double hexSize = 7.5 * scale; 
    final double rectWidth = 6.0 * scale; 
    final double rectHeight = 1.2 * scale; 
    final double rectOffsetDeltaY = -4.5 * scale; 

    // Parse correct color
    Color targetColor;
    try {
      targetColor = Color(int.parse(correctColor.replaceAll('#', '0xFF')));
    } catch (_) {
      targetColor = Colors.orange;
    }

    for (var sensor in sensors) {
      final pos = Offset(center.dx + (sensor.x * scale), center.dy + (sensor.y * scale));
      
      int val = sensor.id <= values.length ? values[sensor.id - 1] : 0;
      bool isPressed = val > 100;
      bool isTarget = sensor.id == currentTarget;

      // 1. Draw the Hexagon (The Pad)
      final hexPaint = Paint()
        ..color = isPressed 
            ? targetColor.withOpacity((val / 1023.0).clamp(0.4, 0.9)) 
            : Colors.white.withOpacity(0.02)
        ..style = PaintingStyle.fill;

      final hexOutlinePaint = Paint()
        ..color = isTarget 
            ? Colors.orangeAccent 
            : Colors.orange.withOpacity(0.1) // Even subtler inactive border
        ..style = PaintingStyle.stroke
        ..strokeWidth = isTarget ? 2.0 : 0.8;

      _drawHex(canvas, pos, hexSize, hexPaint, hexOutlinePaint);

      // 2. Draw the "Status Bar" Rectangle (The Real LED)
      final rectPaint = Paint()
        ..color = isTarget 
            ? targetColor // Brightest when it's the target
            : isPressed 
                ? targetColor.withOpacity(0.8) 
                : Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.fill;
      
      final rect = Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
        width: rectWidth,
        height: rectHeight,
      );

      // Add a glow effect for the active target LED (with rounded corners)
      if (isTarget) {
        final shadowPaint = Paint()
          ..color = targetColor.withOpacity(0.4)
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
