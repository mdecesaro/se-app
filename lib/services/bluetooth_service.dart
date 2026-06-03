import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

enum SensorEventType { on, hit, miss, end, countdown, animationStep, countdownEnded, ack, nack }

class SensorEvent {
  SensorEvent({
    required this.type,
    required this.sensorId,
    required this.mode,
    this.reactionTime,
    this.errorType,
    this.wrongSensorId,
    List<int>? color,
    Map<int, String>? distractors,
    this.stimuliStart,
    this.stimuliEnd,
    this.totalMs,
    this.hits,
    this.misses,
  })  : color       = color       != null ? List.unmodifiable(color)      : null,
        distractors = distractors != null ? Map.unmodifiable(distractors) : null;

  final SensorEventType   type;
  final int               sensorId;
  final int               mode;
  final int?              reactionTime;
  final int?              errorType;
  final int?              wrongSensorId;
  final List<int>?        color;
  final Map<int, String>? distractors;
  final int?              stimuliStart;
  final int?              stimuliEnd;
  final int?              totalMs;
  final int?              hits;
  final int?              misses;
}

// ---------------------------------------------------------------------------
// Protocol constants  (v1.4.0 Binary Aligned)
// ---------------------------------------------------------------------------

abstract final class _Protocol {
  static const int sof            = 0xAA;

  // Host-to-Device Command Codes mirrored perfectly from C++ firmware (V1.4.0)
  static const int cmdConnect     = 0x01;
  static const int cmdDisconnect  = 0x02;
  static const int cmdSetGame     = 0x03; // Config + Start are now one atomic action!
  static const int cmdStopGame    = 0x04; // Emergency Intercept Code

  // Control bytes (device → host)
  static const int msgAck         = 0x06;
  static const int msgNack        = 0x15;

  // Event codes (device → host)
  static const int evtOn               = 0x10;
  static const int evtHit              = 0x11;
  static const int evtMiss             = 0x12;
  static const int evtEnd              = 0x13;
  static const int evtPressure         = 0x14;
  static const int evtCountdownStarted = 0x16;
  static const int evtAnimationStep    = 0x17;
  static const int evtCountdownEnded   = 0x18;

  static const int maxBufferBytes  = 64 * 1024;
  static const int initialBufSize  =  8 * 1024;
  static const int pressureSensors = 14;

  static const String dataCharFragment = 'dfb1';
}

sealed class _HandshakeResult {}
final class _HandshakeSuccess extends _HandshakeResult {
  _HandshakeSuccess(this.consumed);
  final int consumed;
}
final class _HandshakeFragment extends _HandshakeResult {}
final class _HandshakeInvalid  extends _HandshakeResult {}

// ---------------------------------------------------------------------------
// _FrameParser — byte-stream → typed events
// ---------------------------------------------------------------------------

class _FrameParser {
  _FrameParser({
    required this.onLine,
    required this.onEvent,
    required this.onPressure,
    required this.onHandshake,
  });

  final void Function(String line)                                   onLine;
  final void Function(SensorEvent event)                             onEvent;
  final void Function(Int32List snapshot)                            onPressure;
  final void Function(String deviceId, int podCount, String version) onHandshake;

  Uint8List _buf = Uint8List(_Protocol.initialBufSize);
  int       _len = 0;
  bool      _handshakeDone = false;

  // FIX 1 — Reentrance guard: prevents concurrent feed() calls from
  // corrupting _buf/_len when sync StreamControllers fire callbacks
  // mid-parse (e.g. EVT_HIT listener triggering another feed() call).
  bool            _parsing   = false;
  final List<List<int>> _feedQueue = [];

  // Pool of buffers to avoid GC pressure while ensuring shouldRepaint sees reference changes
  final List<Int32List> _pPool = List.generate(8, (_) => Int32List(_Protocol.pressureSensors));
  int _pIdx = 0;

  void reset() {
    _len       = 0;
    _parsing   = false;
    _feedQueue.clear();
    for (final b in _pPool) {
      b.fillRange(0, _Protocol.pressureSensors, 0);
    }
    _pIdx         = 0;
    _handshakeDone = false;
  }

  // FIX 1 — Queue-draining feed() replaces direct buffer manipulation.
  // If a listener callback calls feed() while _parse() is running, the
  // new bytes are enqueued and processed after the current _parse() returns,
  // keeping _buf/_len consistent at all times.
  void feed(List<int> bytes) {
    if (bytes.isEmpty) return;

    _feedQueue.add(List<int>.of(bytes));

    if (_parsing) return; // already inside the drain loop — just enqueue
    _parsing = true;

    while (_feedQueue.isNotEmpty) {
      final next = _feedQueue.removeAt(0);

      if (_len + next.length > _Protocol.maxBufferBytes) {
        debugPrint('[FrameParser] Buffer overflow guard — flushing ${_len}B.');
        _len = 0;
      }

      _ensureCapacity(next.length);
      _buf.setRange(_len, _len + next.length, next);
      _len += next.length;
      _parse();
    }

    _parsing = false;
  }

  void _ensureCapacity(int extra) {
    final needed = _len + extra;
    if (needed <= _buf.length) return;
    final newSize = ((needed + 8191) ~/ 8192) * 8192;
    final next = Uint8List(newSize);
    next.setRange(0, _len, _buf);
    _buf = next;
  }

  void _parse() {
    int cursor = 0;

    while (cursor < _len) {
      final byte = _buf[cursor];

      if (byte == _Protocol.msgAck || byte == _Protocol.msgNack) {
        final bool isAck = (byte == _Protocol.msgAck);
        if (isAck && !_handshakeDone) {
          final result = _tryParseHandshake(cursor);

          if (result is _HandshakeSuccess) {
            _handshakeDone = true;
            cursor += result.consumed;
            continue;
          }
          if (result is _HandshakeFragment) break;
        }
        onLine(isAck ? 'ACK' : 'NACK');
        onEvent(SensorEvent(
          type: isAck ? SensorEventType.ack : SensorEventType.nack,
          sensorId: 0,
          mode: 0,
        ));
        cursor++;
        continue;
      }

      if (byte == _Protocol.sof) {
        final remaining = _len - cursor;
        if (remaining < 4) break;

        final payloadLen = _buf[cursor + 2];
        final totalLen   = 3 + payloadLen + 1;
        if (remaining < totalLen) break;

        int crc = 0;
        for (int i = 0; i < totalLen; i++) {
          crc ^= _buf[cursor + i];
        }

        if (crc == 0) {
          _handleBinaryPacket(_buf[cursor + 1], cursor + 3, payloadLen);
          cursor += totalLen;
        } else {
          cursor = _findNextValidSof(cursor + 1);
        }
        continue;
      }

      // Speculative ASCII parsing (Gated for production performance)
      if (kDebugMode && byte >= 32 && byte <= 126) {
        int end = -1;
        for (int i = cursor; i < _len; i++) {
          if (_buf[i] == 10) { end = i; break; }
          if (_buf[i] < 32 || _buf[i] > 126) { end = i; break; }
        }

        if (end != -1) {
          final isNewline = _buf[end] == 10;
          try {
            final line = utf8
                .decode(Uint8List.sublistView(_buf, cursor, end))
                .trim();
            if (line.isNotEmpty) {
              onLine(line);
            }
          } catch (_) {}
          cursor = isNewline ? end + 1 : end;
          continue;
        } else {
          break;
        }
      }

      cursor++;
    }

    if (cursor > 0) {
      if (cursor < _len) _buf.setRange(0, _len - cursor, _buf, cursor);
      _len -= cursor;
    }
  }

  int _findNextValidSof(int from) {
    int firstRawSof = -1;
    for (int i = from; i < _len; i++) {
      if (_buf[i] != _Protocol.sof) continue;
      if (firstRawSof == -1) firstRawSof = i;

      final remaining = _len - i;
      if (remaining < 4) break;
      final payloadLen = _buf[i + 2];
      final totalLen   = 3 + payloadLen + 1;
      if (remaining < totalLen) break;

      int crc = 0;
      for (int j = 0; j < totalLen; j++) {
        crc ^= _buf[i + j];
      }
      if (crc == 0) return i;
    }
    return firstRawSof != -1 ? firstRawSof : _len;
  }

  void _handleBinaryPacket(int cmd, int offset, int len) {
    // Print every binary frame in hex
    final fullFrame = Uint8List.sublistView(_buf, offset - 3, offset + len + 1);
    final hex = fullFrame.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    String label = 'CMD_0x${cmd.toRadixString(16).toUpperCase()}';
    if (cmd == 0x10) label = 'EVT_SENSOR_ON';
    else if (cmd == 0x11) label = 'EVT_SENSOR_HIT';
    else if (cmd == 0x12) label = 'EVT_SENSOR_MISS';
    else if (cmd == 0x16) label = 'EVT_COUNTDOWN_START';
    else if (cmd == 0x17) label = 'EVT_COUNTDOWN_STEP';
    else if (cmd == 0x18) label = 'EVT_COUNTDOWN_ENDED';

    debugPrint('[FW RX] $label | $hex');

    final data = ByteData.sublistView(_buf, offset, offset + len);

    switch (cmd) {
      case _Protocol.evtCountdownStarted:
      // Payload is 1 byte: The value '5' (initial start)
        final val = len > 0 ? data.getUint8(0) : 5;
        onEvent(SensorEvent(type: SensorEventType.countdown, mode: val, sensorId: 0));
        break;

      case _Protocol.evtAnimationStep:
      // Payload is 1 byte: The current countdown integer (3, 2, 1, 0)
        final val = len > 0 ? data.getUint8(0) : 0;
        onEvent(SensorEvent(type: SensorEventType.animationStep, mode: val, sensorId: 0));
        break;

      case _Protocol.evtCountdownEnded:
        onEvent(SensorEvent(type: SensorEventType.countdownEnded, mode: 0, sensorId: 0));
        break;

      case _Protocol.evtPressure:
        if (len >= _Protocol.pressureSensors * 2) {
          final buf = _pPool[_pIdx];
          _pIdx = (_pIdx + 1) % _pPool.length;
          for (int i = 0; i < _Protocol.pressureSensors; i++) {
            buf[i] = data.getUint16(i * 2, Endian.little);
          }
          onPressure(buf);
        }
        break;

      case _Protocol.evtOn:
        if (len >= 5) {
          final int targetQty = data.getUint8(0);
          final int r = data.getUint8(1);
          final int g = data.getUint8(2);
          final int b = data.getUint8(3);

          int cursor = 4;
          final List<int> targetPods = [];
          for (int i = 0; i < targetQty; i++) {
            if (cursor < len) {
              // Read the raw 0-indexed firmware ID (e.g., 9)
              final int rawPodId = data.getUint8(cursor++);
              // Convert it to a 1-indexed human display ID (9 + 1 = 10)
              targetPods.add(rawPodId + 1);
            }
          }

          int distQty = 0;
          if (cursor < len) {
            distQty = data.getUint8(cursor++);
          }

          final Map<int, String> distractorsMap = {};
          for (int i = 0; i < distQty; i++) {
            if (cursor + 3 < len) {
              final int dRawPodId = data.getUint8(cursor++);
              final int dR = data.getUint8(cursor++);
              final int dG = data.getUint8(cursor++);
              final int dB = data.getUint8(cursor++);

              final String hexColor = '#${dR.toRadixString(16).padLeft(2, '0')}'
                  '${dG.toRadixString(16).padLeft(2, '0')}'
                  '${dB.toRadixString(16).padLeft(2, '0')}';
              // Convert distractor pod IDs to 1-indexed human numbers as well
              distractorsMap[dRawPodId + 1] = hexColor.toUpperCase();
            }
          }

          onEvent(SensorEvent(
            type:        SensorEventType.on,
            mode:        targetQty,
            sensorId:    targetPods.isNotEmpty ? targetPods.first : 0,
            color:       [r, g, b, ...targetPods],
            distractors: distractorsMap,
          ));
        }
        break;

      case _Protocol.evtHit:
        if (len >= 13) {
          // Read the raw 0-indexed firmware hit value (9)
          final int rawClearedPodId = data.getUint8(0);

          final int rt      = data.getUint32(1, Endian.big);
          final int startTS = data.getUint32(5, Endian.big);
          final int endTS   = data.getUint32(9, Endian.big);

          onEvent(SensorEvent(
            type:         SensorEventType.hit,
            mode:         0,
            sensorId:     rawClearedPodId + 1, // Converts 9 to 10 for UI layout parity
            reactionTime: rt,
            stimuliStart: startTS,
            stimuliEnd:   endTS,
          ));
        }
        break;

      case _Protocol.evtMiss:
        if (len >= 9) {
          // Byte 0 is the mis-tapped pod ID, or 0 if a timeout occurred
          final int faultPodId = data.getUint8(0);

          final int startTS = data.getUint32(1, Endian.big);
          final int endTS   = data.getUint32(5, Endian.big);

          onEvent(SensorEvent(
            type:          SensorEventType.miss,
            mode:          0,
            sensorId:      faultPodId,
            errorType:     faultPodId == 0 ? 2 : 1, // 2 = Timeout, 1 = Mis-tap
            wrongSensorId: faultPodId,
            stimuliStart:  startTS,
            stimuliEnd:    endTS,
          ));
        }
        break;

      case _Protocol.evtEnd:
        if (len >= 6) {
          onEvent(SensorEvent(
            type:     SensorEventType.end,
            mode:     0,
            sensorId: 0,
            totalMs:  data.getUint16(0, Endian.little),
            hits:     data.getUint16(2, Endian.little),
            misses:   data.getUint16(4, Endian.little),
          ));
        }
        break;
    }
  }

  _HandshakeResult _tryParseHandshake(int start) {
    if (_len - start <= 1) return _HandshakeInvalid();

    try {
      int pos = start + 1;

      String? readStr() {
        if (pos >= _len) return null;
        final strLen = _buf[pos];
        if (strLen == 0 || strLen > 64) throw 'Invalid string length';
        if (_len < pos + 1 + strLen) return null;
        pos++;
        final s = utf8.decode(Uint8List.sublistView(_buf, pos, pos + strLen));
        pos += strLen;
        return s;
      }

      final deviceId = readStr();
      if (deviceId == null) return _HandshakeFragment();

      if (pos >= _len) return _HandshakeFragment();
      pos++;

      if (pos >= _len) return _HandshakeFragment();
      final podCount = _buf[pos++];

      final version = readStr();
      if (version == null) return _HandshakeFragment();

      final readyMsg = readStr();
      if (readyMsg == null) return _HandshakeFragment();

      onHandshake(deviceId, podCount, version);
      debugPrint('[BLE] Handshake OK — device: $deviceId  pods: $podCount  fw: $version');
      return _HandshakeSuccess(pos - start);
    } catch (_) {
      return _HandshakeInvalid();
    }
  }

  static List<int> _hexToRgb(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length != 6) return [0, 0, 0];
    return [
      int.parse(hex.substring(0, 2), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
    ];
  }

  static List<int> _hexToGrb(String hex) {
    final rgb = _hexToRgb(hex);
    return [rgb[1], rgb[0], rgb[2]];
  }
}

// ---------------------------------------------------------------------------
// AppBluetoothService — BLE lifecycle management
// ---------------------------------------------------------------------------

class AppBluetoothService {
  AppBluetoothService._internal();
  static final AppBluetoothService _instance = AppBluetoothService._internal();
  factory AppBluetoothService() => _instance;

  final List<fbp.ScanResult> _scanResults = [];
  bool _isScanning   = false;
  bool _isConnecting = false;

  fbp.BluetoothDevice?         _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription?          _dataSubscription;
  StreamSubscription?          _connectionSubscription;

  String _firmwareVersion = 'Checking...';
  String _deviceType      = 'FlyFeet-Hexon';
  String _sensorCount     = 'Unknown';
  static const String _registeredUser = 'Michel De Cesaro';

  // FIX 2 — Removed sync: true from _eventController and _dataController.
  // sync: true causes add() to propagate in the same microtask as the caller,
  // which means a listener can call feed() again before _parse() has returned,
  // corrupting the internal buffer state. Async broadcast streams deliver
  // events in the next microtask, after _parse() has fully completed.
  final _dataController       = StreamController<List<int>>.broadcast();
  final _connectionController = StreamController<fbp.BluetoothConnectionState>.broadcast();
  final _lineController       = StreamController<String>.broadcast();
  final _eventController      = StreamController<SensorEvent>.broadcast();
  final _pressureController   = StreamController<Int32List>.broadcast(sync: true); // pressure is hot-path, safe to keep sync
  Int32List _pressureCache    = Int32List(_Protocol.pressureSensors);

  Stream<List<int>>                    get dataStream            => _dataController.stream;
  Stream<fbp.BluetoothConnectionState> get connectionStateStream => _connectionController.stream;
  Stream<String>                       get lineStream            => _lineController.stream;
  Stream<SensorEvent>                  get eventStream           => _eventController.stream;
  Stream<Int32List>                    get pressureStream        => _pressureController.stream;
  Int32List                            get pressureCache         => _pressureCache;

  List<fbp.ScanResult> get scanResults     => List.unmodifiable(_scanResults);
  bool                 get isScanning      => _isScanning;
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  String               get firmwareVersion => _firmwareVersion;
  String               get deviceType      => _deviceType;
  String               get registeredUser  => _registeredUser;
  String               get sensorCount     => _sensorCount;

  late final _FrameParser _parser = _FrameParser(
    onLine: (line) {
      _lineController.add(line);
    },
    onEvent:    _eventController.add,
    onPressure: (data) {
      _pressureCache = data;
      _pressureController.add(data);
    },
    onHandshake: _applyHandshakeResult,
  );

  void _applyHandshakeResult(String deviceId, int podCount, String version) {
    _deviceType      = deviceId;
    _sensorCount     = podCount.toString();
    _firmwareVersion = version;
  }

  void init() => fbp.FlutterBluePlus.setLogLevel(fbp.LogLevel.none);

  Future<void> dispose() async {
    await _dataSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _dataController.close();
    await _connectionController.close();
    await _lineController.close();
    await _eventController.close();
    await _pressureController.close();
  }

  Future<void> startScan({VoidCallback? onUpdate}) async {
    try {
      // 1. Wait for Bluetooth adapter to be ready (up to 2 seconds)
      try {
        await fbp.FlutterBluePlus.adapterState
            .where((s) => s == fbp.BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        debugPrint('[BLE] Cannot start scan: Bluetooth adapter is not ON.');
        return;
      }

      // 2. Request all necessary permissions
      await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      _scanResults.clear();
      _isScanning = true;
      onUpdate?.call();

      final sub = fbp.FlutterBluePlus.onScanResults.listen((results) {
        _scanResults
          ..clear()
          ..addAll(results.where((r) {
            final name = (r.advertisementData.advName + r.device.platformName).toLowerCase();
            final isMatch = name.contains('fly') ||
                name.contains('feet') ||
                name.contains('hexon') ||
                name.contains('bluno') ||
                name.contains('dfrobot');
            if (isMatch && name.isNotEmpty) {
              debugPrint('[BLE] Match found: $name');
            }
            return isMatch;
          }));
        onUpdate?.call();
      });

      await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await fbp.FlutterBluePlus.isScanning.where((v) => !v).first;

      _isScanning = false;
      await sub.cancel();
      onUpdate?.call();
    } catch (e) {
      debugPrint('[BLE] startScan error: $e');
      _isScanning = false;
      onUpdate?.call();
    }
  }

  Future<void> connect(fbp.BluetoothDevice device, {VoidCallback? onUpdate}) async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    if (_isConnecting) return;
    if (_connectedDevice?.remoteId == device.remoteId && _writeCharacteristic != null) {
      debugPrint('[BLE] Already connected to ${device.remoteId}.');
      return;
    }

    _isConnecting = true;

    try {
      _applyHandshakeResult('FlyFeet - Hexon', 0, 'Checking...');
      _sensorCount = 'Unknown';
      _parser.reset();

      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        _connectionController.add(state);
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        } else if (state == fbp.BluetoothConnectionState.connected) {
          _connectedDevice = device;
        }
        onUpdate?.call();
      });

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

      try {
        debugPrint('[BLE] Requesting expanded link layer MTU configuration (512)...');
        final mtu = await device.requestMtu(512, timeout: 4);
        debugPrint('[BLE MTU] Negotiated MTU: $mtu bytes');
      } catch (e) {
        debugPrint('[BLE MTU] Request declined or unhandled by OS layer: $e');
      }

      await _discoverAndSubscribe(device, onUpdate);
      await Future.delayed(const Duration(milliseconds: 1000));
      await performHandshake(onUpdate);
    } catch (e, st) {
      debugPrint('[BLE] connect() error: $e\n$st');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _discoverAndSubscribe(fbp.BluetoothDevice device, VoidCallback? onUpdate) async {
    final services       = await device.discoverServices();
    _writeCharacteristic = null;

    for (final service in services) {
      for (final char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        if (!uuid.contains(_Protocol.dataCharFragment)) continue;

        if (char.properties.write || char.properties.writeWithoutResponse) {
          _writeCharacteristic = char;
        }

        if (char.properties.notify || char.properties.indicate) {
          await char.setNotifyValue(true);
          await _dataSubscription?.cancel();

          // FIX 3 — parser.feed() runs first, then _dataController.add().
          // This ensures the buffer is fully drained before any downstream
          // listener (which may call into the service) receives the event.
          _dataSubscription = char.onValueReceived.listen((bytes) {
            _parser.feed(bytes);
            _dataController.add(bytes);
          });
          debugPrint('[BLE] Subscribed to data characteristic: $uuid');
          return;
        }
      }
    }
    debugPrint('[BLE] WARNING: no notifiable data characteristic found.');
  }

  Future<void> performHandshake([VoidCallback? onUpdate]) async {
    if (_writeCharacteristic == null) return;
    debugPrint('[BLE] Sending CMD_CONNECT (handshake)');
    _parser.reset();
    await _sendBinaryPacket(_Protocol.cmdConnect);
    await Future.delayed(const Duration(milliseconds: 500));
    onUpdate?.call();
  }

  Future<void> disconnect({VoidCallback? onUpdate}) async {
    final device = _connectedDevice;
    if (device == null) return;

    try {
      await _sendBinaryPacket(_Protocol.cmdDisconnect);
      await _dataSubscription?.cancel();        _dataSubscription       = null;
      await _connectionSubscription?.cancel();  _connectionSubscription = null;
      _handleDisconnected();
      onUpdate?.call();
      await device.disconnect();
    } catch (e) {
      debugPrint('[BLE] disconnect() error: $e');
    }
  }

  void _handleDisconnected() {
    _connectedDevice     = null;
    _writeCharacteristic = null;
    _isConnecting        = false;
    _isScanning          = false;
    _scanResults.clear();
    _applyHandshakeResult('FlyFeet - Hexon', 0, 'Checking...');
    _sensorCount = 'Unknown';
    _parser.reset();

    _pressureCache = Int32List(_Protocol.pressureSensors);
    _pressureController.add(_pressureCache);
    _eventController.add(SensorEvent(
      type: SensorEventType.end, sensorId: 0, mode: 0,
      totalMs: 0, hits: 0, misses: 0,
    ));
  }

  // ── Game commands ─────────────────────────────────────────────────────────

  /// ATOMIC TRANSACTION: Packs the strict 28-byte game configuration struct.
  /// Enforces explicit memory boundary guards to ensure 100% C++ struct compliance.
  Future<void> sendStartGame({
    required int          gameMode,
    required int          gameRounds,
    required int          gameAttempts,
    required int          targetQty,
    required int          targetLogic,
    required String       targetRGBHex,
    required int          distMode,
    required int          distQty,
    required int          distBehavior,
    required List<String> distRGBsHex,
    required int          delayType,
    required int          delayMinMs,
    required int          delayMaxMs,
    required int          timeoutMs,
    required bool         repeatIfWrong,
  }) async {
    // 1. Allocate an absolute, unchangeable memory block of exactly 28 bytes
    final payload = ByteData(28);

    // [Bytes 0-2]: Primary Loop Configuration
    payload.setUint8(0, gameMode);
    payload.setUint8(1, gameRounds);
    payload.setUint8(2, gameAttempts);

    // [Bytes 3-7]: Target Matrix Parameters and Color Space (RGB)
    payload.setUint8(3, targetQty);
    payload.setUint8(4, targetLogic);

    final tRGB = _FrameParser._hexToRgb(targetRGBHex);
    payload.setUint8(5, tRGB[0]); // targetR
    payload.setUint8(6, tRGB[1]); // targetG
    payload.setUint8(7, tRGB[2]); // targetB

    // [Bytes 8-10]: Distractor Matrix Parameters
    payload.setUint8(8,  distMode);
    payload.setUint8(9,  distQty);
    payload.setUint8(10, distBehavior);

    // [Bytes 11-19]: Distractor Color Matrix (Normalized to 3 slots x 3 bytes = 9 bytes total)
    // If JSON provides fewer than 3 distractors, remaining registers are safely padded with 0x00
    for (int i = 0; i < 3; i++) {
      final String currentHex = (i < distRGBsHex.length) ? distRGBsHex[i] : '#000000';
      final List<int> dRGB = _FrameParser._hexToRgb(currentHex);
      final int baseOffset = 11 + (i * 3);

      payload.setUint8(baseOffset,     dRGB[0]); // R
      payload.setUint8(baseOffset + 1, dRGB[1]); // G
      payload.setUint8(baseOffset + 2, dRGB[2]); // B
    }

    // [Bytes 20-27]: Timing Window Constraints & Evaluation Loop Directives
    payload.setUint8(20,  delayType);
    payload.setUint16(21, delayMinMs,   Endian.little);
    payload.setUint16(23, delayMaxMs,   Endian.little);
    payload.setUint16(25, timeoutMs,    Endian.little);
    payload.setUint8(27,  repeatIfWrong ? 1 : 0);

    // 2. HARD BOUNDARY GUARD: Extract the raw byte array
    final rawBytes = payload.buffer.asUint8List(0, 28);

    // Throw a structural error in development if the boundary is violated
    assert(rawBytes.length == 28, 'CRITICAL: Outbound BLE payload must be exactly 28 bytes!');

    if (rawBytes.length != 28) {
      debugPrint('[BLE TX ERROR] Blocked malformed payload size: ${rawBytes.length}B');
      return;
    }

    // 3. Diagnostic Stream Output
    final hexString = rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    debugPrint('[BLE TX] Dispatched Verified 28B Payload: $hexString');

    // 4. Dispatch atomic packet (will compile into a perfect 32-byte frame: SOF + CMD + LEN + 28B + CRC)
    await _sendBinaryPacket(_Protocol.cmdSetGame, rawBytes);
  }

  /// Emergency interruption trigger
  Future<void> sendStopGame() => _sendBinaryPacket(_Protocol.cmdStopGame);

  // ── MTU-Aware Paced Link Layer Transmission ───────────────────────────────

  Future<void> _sendBinaryPacket(int cmd, [List<int>? payload]) async {
    final char = _writeCharacteristic;
    if (char == null) {
      debugPrint('[BLE TX ERROR] 0x${cmd.toRadixString(16).toUpperCase()} failed: Missing write characteristic.');
      return;
    }

    final payloadLen = payload?.length ?? 0;
    final frame      = Uint8List(3 + payloadLen + 1);

    // Build perfect hardware header matching SerialManager windows
    frame[0] = _Protocol.sof;
    frame[1] = cmd;
    frame[2] = payloadLen;
    if (payload != null) {
      frame.setRange(3, 3 + payloadLen, payload);
    }

    // Explicit structural XOR checksum calculation matching computedCK
    int crc = 0;
    for (int i = 0; i < frame.length - 1; i++) {
      crc ^= frame[i];
    }
    frame[frame.length - 1] = crc;

    try {
      final bool noResponse = char.properties.writeWithoutResponse;

      // Extract current dynamic negotiated MTU payload capacity (Total MTU size - 3 bytes GATT header)
      final int platformMtuNow = (_connectedDevice?.mtuNow ?? 23) - 3;
      final int chunkSize = platformMtuNow > 0 ? platformMtuNow : 20;

      final fullFrameHex = frame.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
      debugPrint('[BLE TX ATOMIC] Executing frame output: "$fullFrameHex" (Target Segment Limit: ${chunkSize}B)');

      int offset = 0;
      while (offset < frame.length) {
        final end   = (offset + chunkSize).clamp(0, frame.length);
        final chunk = frame.sublist(offset, end);

        await char.write(chunk, withoutResponse: noResponse);
        offset = end;

        if (offset < frame.length) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    } catch (e) {
      debugPrint('[BLE] _sendBinaryPacket exception on CMD 0x${cmd.toRadixString(16).toUpperCase()}: $e');
    }
  }
}