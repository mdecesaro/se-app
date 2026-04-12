import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../services/bluetooth_service.dart';
import '../services/database_service.dart';

class SensorDefinition {
  final int id;
  final double x;
  final double y;
  final String sector;

  SensorDefinition({required this.id, required this.x, required this.y, required this.sector});
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
        sector: m['sector'],
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

  void _startSession() {
    setState(() {
      _isSessionStarted = true;
      stopwatch.reset();
      stopwatch.start();
      _addLog("Session Started: ${widget.exercise.name}");
    });

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        final duration = stopwatch.elapsed;
        formattedTime = "${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}.${(duration.inMilliseconds % 1000 ~/ 100)}";
      });
    });
    
    _bluetoothService.sendMessage("START:${widget.exercise.code}\n");
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
        _addLog("Error parsing data");
      }
    } else {
      _addLog("Hardware: $data");
    }
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
                          child: _isSessionStarted 
                            ? _buildCanvas() 
                            : _buildStartOverlay(),
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

  Widget _buildStartOverlay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.touch_app, size: 80, color: Colors.white10),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _startSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text("START SESSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        const SizedBox(height: 10),
        const Text("Ensure the device is connected before starting.", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat("HITS", "0"),
          _buildStat("TIME", formattedTime, isPrimary: true),
          _buildStat("AVG SPEED", "0ms"),
          _buildStat("MISS", "0"),
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

  MatPainter({required this.sensors, required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Scale factor to translate CM-based coordinates to Screen Pixels
    // The max coordinates are roughly +/- 30, so a divisor of 70-80 fits well.
    final double scale = size.shortestSide / 75;
    
    // Adjusted sizes to prevent overlap (distance between sensors is ~15 units)
    final double hexSize = 7.5 * scale; 
    final double rectWidth = 6.0 * scale; 
    final double rectHeight = 1.2 * scale; 
    final double rectOffsetDeltaY = -4.5 * scale; 

    for (var sensor in sensors) {
      // Position based on DB coordinates
      final pos = Offset(center.dx + (sensor.x * scale), center.dy + (sensor.y * scale));
      
      int val = sensor.id <= values.length ? values[sensor.id - 1] : 0;
      bool isPressed = val > 100;

      // 1. Draw the Hexagon (The Pad)
      final hexPaint = Paint()
        ..color = isPressed 
            ? Colors.orange.withOpacity((val / 1023.0).clamp(0.3, 1.0)) 
            : Colors.white.withOpacity(0.02)
        ..style = PaintingStyle.fill;

      final hexOutlinePaint = Paint()
        ..color = isPressed ? Colors.orange : Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      _drawHex(canvas, pos, hexSize, hexPaint, hexOutlinePaint);

      // 2. Draw the "Status Bar" Rectangle (LED indicator)
      final rectPaint = Paint()
        ..color = isPressed ? const Color(0xFF5CE65C) : Colors.grey.withOpacity(0.2)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
        width: rectWidth,
        height: rectHeight,
      );
      canvas.drawRect(rect, rectPaint);

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
    for (int i = 0; i < 6; i++) {
      double angle = i * 60 * 3.14159 / 180;
      double px = center.dx + size * math.cos(angle);
      double py = center.dy + size * math.sin(angle);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant MatPainter oldDelegate) => true;
}
