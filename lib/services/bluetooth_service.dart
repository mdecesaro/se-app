import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

enum SensorEventType { on, hit, miss, end, countdown, animationStep }

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
  static const int evtOn          = 0x10;
  static const int evtHit         = 0x11;
  static const int evtMiss        = 0x12;
  static const int evtEnd         = 0x13;
  static const int evtPressure    = 0x14;
  static const int evtCountdownStarted = 0x16; // UPDATED: 0x16 per firmware C++
  static const int evtAnimationStep    = 0x17; // UPDATED: 0x17 per firmware C++

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

  final Int32List _pressureCache = Int32List(_Protocol.pressureSensors);

  void reset() {
    _len = 0;
    _pressureCache.fillRange(0, _Protocol.pressureSensors, 0);
  }

  void feed(List<int> bytes) {
    if (bytes.isEmpty) return;

    if (_len + bytes.length > _Protocol.maxBufferBytes) {
      debugPrint('[FrameParser] Buffer overflow guard — flushing ${_len}B.');
      _len = 0;
    }

    _ensureCapacity(bytes.length);
    _buf.setRange(_len, _len + bytes.length, bytes);
    _len += bytes.length;
    _parse();
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
        if (byte == _Protocol.msgAck) {
          final result = _tryParseHandshake(cursor);

          if (result is _HandshakeSuccess) {
            cursor += result.consumed;
            continue;
          }
          if (result is _HandshakeFragment) break;
        }
        onLine(byte == _Protocol.msgAck ? 'ACK' : 'NACK');
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

      if (byte >= 32 && byte <= 126) {
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
              if (line.startsWith('EVT|')) _handleLegacyEvent(line);
              else if (line.startsWith('DATA:')) _handleLegacyData(line);
            }
          } catch (_) { }
          cursor = isNewline ? end + 1 : end; // Do NOT consume SOF or other control bytes
          continue;
        } else {
          break; // Wait for more data or a terminator
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
    final data = ByteData.sublistView(_buf, offset, offset + len);
    // Silent parsing for high-frequency performance
    // debugPrint('[BLE] Binary Packet: cmd=0x${cmd.toRadixString(16)} len=$len');

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

      case _Protocol.evtPressure:
        if (len >= _Protocol.pressureSensors * 2) {
          for (int i = 0; i < _Protocol.pressureSensors; i++) {
            _pressureCache[i] = data.getUint16(i * 2, Endian.little);
          }
          onPressure(Int32List.fromList(_pressureCache));
        }
        break;

      case _Protocol.evtOn:
        if (len >= 5) {
          onEvent(SensorEvent(
            type:     SensorEventType.on,
            mode:     data.getUint8(0),
            sensorId: data.getUint8(1),
            color: [data.getUint8(2), data.getUint8(3), data.getUint8(4)],
          ));
        }
        break;

      case _Protocol.evtHit:
        if (len >= 4) {
          onEvent(SensorEvent(
            type:         SensorEventType.hit,
            mode:         data.getUint8(0),
            sensorId:     data.getUint8(1),
            reactionTime: data.getUint16(2, Endian.little),
          ));
        }
        break;

      case _Protocol.evtMiss:
        if (len >= 4) {
          onEvent(SensorEvent(
            type:          SensorEventType.miss,
            mode:          data.getUint8(0),
            sensorId:      data.getUint8(1),
            errorType:     data.getUint8(2),
            wrongSensorId: data.getUint8(3),
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

      final version  = readStr();
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

  void _handleLegacyData(String line) {
    try {
      final parts = line.substring(5).split(',');
      for (int i = 0; i < parts.length && i < _Protocol.pressureSensors; i++) {
        _pressureCache[i] = int.parse(parts[i]);
      }
      onPressure(Int32List.fromList(_pressureCache));
    } catch (_) {}
  }

  void _handleLegacyEvent(String line) {
    final parts = line.split('|');
    if (parts.length < 4) return;

    final type = parts[1];
    final mode = int.tryParse(parts[2]) ?? 1;

    switch (type) {
      case 'HIT':
        if (parts.length >= 8) {
          onEvent(SensorEvent(
            type:         SensorEventType.hit,
            mode:         mode,
            sensorId:     int.tryParse(parts[5]) ?? 0,
            reactionTime: int.tryParse(parts[7]),
            stimuliStart: int.tryParse(parts[3]),
            stimuliEnd:   int.tryParse(parts[4]),
          ));
        } else if (parts.length >= 5) {
          onEvent(SensorEvent(
            type:         SensorEventType.hit,
            mode:         mode,
            sensorId:     int.tryParse(parts[3]) ?? 0,
            reactionTime: int.tryParse(parts[4]),
          ));
        }

      case 'MISS':
        if (parts.length >= 8) {
          onEvent(SensorEvent(
            type:          SensorEventType.miss,
            mode:          mode,
            sensorId:      int.tryParse(parts[5]) ?? 0,
            errorType:     int.tryParse(parts[6]),
            wrongSensorId: int.tryParse(parts[7]),
            stimuliStart:  int.tryParse(parts[3]),
            stimuliEnd:    int.tryParse(parts[4]),
          ));
        } else if (parts.length >= 6) {
          onEvent(SensorEvent(
            type:          SensorEventType.miss,
            mode:          mode,
            sensorId:      int.tryParse(parts[3]) ?? 0,
            errorType:     int.tryParse(parts[4]),
            wrongSensorId: int.tryParse(parts[5]),
          ));
        }

      case 'ON':
        final sensorId    = int.tryParse(parts[3]) ?? 0;
        final color       = parts.length >= 5 ? _hexToRgb(parts[4]) : null;
        final distractors = <int, String>{};

        if (parts.length >= 7 && parts[5] != '0') {
          for (final item in parts[6].split(',')) {
            if (item.contains(':')) {
              final pair = item.split(':');
              final id   = int.tryParse(pair[0]);
              if (id != null) {
                distractors[id] = pair[1].startsWith('#') ? pair[1] : '#${pair[1]}';
              }
            } else {
              final id = int.tryParse(item);
              if (id != null) distractors[id] = '#FF0000';
            }
          }
        }

        onEvent(SensorEvent(
          type:        SensorEventType.on,
          mode:        mode,
          sensorId:    sensorId,
          color:       color,
          distractors: distractors,
        ));
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
  String _deviceType      = 'FlyFeet - Hexon';
  String _sensorCount     = 'Unknown';
  static const String _registeredUser = 'Michel De Cesaro';

  final _dataController       = StreamController<List<int>>.broadcast(sync: true);
  final _connectionController = StreamController<fbp.BluetoothConnectionState>.broadcast();
  final _lineController       = StreamController<String>.broadcast();
  final _eventController      = StreamController<SensorEvent>.broadcast(sync: true);
  final _pressureController   = StreamController<Int32List>.broadcast(sync: true);
  final Int32List _pressureCache = Int32List(_Protocol.pressureSensors);

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
      // debugPrint(' firmware -> $line'); // Reduced log noise in hot-path
      _lineController.add(line);
    },
    onEvent:     _eventController.add,
    onPressure:  (data) {
      _pressureCache.setAll(0, data);
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
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    _scanResults.clear();
    _isScanning = true;
    onUpdate?.call();

    final sub = fbp.FlutterBluePlus.onScanResults.listen((results) {
      _scanResults
        ..clear()
        ..addAll(results.where((r) {
          final name = (r.advertisementData.advName + r.device.platformName).toLowerCase();
          return name.contains('flyfeet') || name.contains('bluno') || name.contains('dfrobot');
        }));
      onUpdate?.call();
    });

    await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await fbp.FlutterBluePlus.isScanning.where((v) => !v).first;

    _isScanning = false;
    await sub.cancel();
    onUpdate?.call();
  }

  Future<void> connect(fbp.BluetoothDevice device, {VoidCallback? onUpdate}) async {
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

      // Upgraded to maximum headroom to clear full frames automatically on capable chipsets
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
          _dataSubscription = char.onValueReceived.listen((bytes) {
            _dataController.add(bytes);
            _parser.feed(bytes);
            // onUpdate removed from here to prevent UI-thread "Buffer Bloat"
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

    _pressureCache.fillRange(0, _pressureCache.length, 0);
    _pressureController.add(Int32List(_Protocol.pressureSensors));
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
    payload.setUint8(10, distBehavior); // Explicitly maps byte 10 to protect spacing

    // [Bytes 11-19]: Distractor Color Matrix (Normalized to 3 slots x 3 bytes = 9 bytes total)
    // If JSON provides fewer than 3 distractors, remaining registers are safely padded with 0x00
    for (int i = 0; i < 3; i++) {
      final String currentHex = (i < distRGBsHex.length) ? distRGBsHex[i] : '#000000';
      final List<int> dGRB = _FrameParser._hexToGrb(currentHex);
      final int baseOffset = 11 + (i * 3);

      payload.setUint8(baseOffset,     dGRB[0]); // G
      payload.setUint8(baseOffset + 1, dGRB[1]); // R
      payload.setUint8(baseOffset + 2, dGRB[2]); // B
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
    assert(rawBytes.length == 28, "CRITICAL: Outbound BLE payload must be exactly 28 bytes!");

    if (rawBytes.length != 28) {
      debugPrint('[BLE TX ERROR] Blocked malformed payload size: ${rawBytes.length}B');
      return; // Absolute termination to prevent firmware corruption
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

        // Microscopic delay context: If the payload is split across an air link due to a 20-byte MTU barrier,
        // we introduce a tiny pause. This feeds the firmware's serial buffer fast enough to satisfy
        // the 100ms hardware timeout gate while keeping the stack stable.
        if (offset < frame.length) {
          // Reduced delay to keep the pipeline full without choking the pod's RX buffer
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      // Trailing 15ms settling delay removed for V1.4.0 high-speed sync
    } catch (e) {
      debugPrint('[BLE] _sendBinaryPacket exception on CMD 0x${cmd.toRadixString(16).toUpperCase()}: $e');
    }
  }
}