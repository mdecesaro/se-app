import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    this.roundnum = 0,
    this.attempt = 0,
    this.sensorId = 0,
    this.reactionTime,
    this.gct,
    this.delayApplied,
    this.errorType,
    this.wrongSensorId,
    this.countdownValue = 0,
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
  final int               roundnum;
  final int               attempt;
  final int               sensorId;
  final int?              reactionTime;
  final int?              gct;
  final int?              delayApplied;
  final int?              errorType;
  final int?              wrongSensorId;
  final int               countdownValue;
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

  static const int cmdConnect     = 0x01;
  static const int cmdDisconnect  = 0x02;
  static const int cmdSetGame     = 0x03;
  static const int cmdStopGame    = 0x04;

  static const int msgAck         = 0x06;
  static const int msgNack        = 0x15;

  static const int resConnectSuccess = 0x81;

  static const int evtOn               = 0x10;
  static const int evtHit              = 0x11;
  static const int evtMiss             = 0x12;
  static const int evtCountdownStarted = 0x16;
  static const int evtAnimationStep    = 0x17;
  static const int evtCountdownEnded   = 0x18;
  static const int evtGameStarted      = 0x20;
  static const int evtGameEnded        = 0x21;

  static const int maxBufferBytes  = 64 * 1024;
  static const int initialBufSize  =  8 * 1024;
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
    required this.onHandshake,
  });

  final void Function(String line)                                   onLine;
  final void Function(SensorEvent event)                             onEvent;
  final void Function(String deviceId, int podCount, String version) onHandshake;

  int? _firstHardwareEndTS;
  int? _firstDigitalTimestamp;

  Uint8List _buf = Uint8List(_Protocol.initialBufSize);
  int       _len = 0;
  bool      _handshakeDone = false;

  bool            _parsing   = false;
  final List<List<int>> _feedQueue = [];

  void reset() {
    _len       = 0;
    _parsing   = false;
    _feedQueue.clear();
    _handshakeDone = false;

    _firstHardwareEndTS   = null;
    _firstDigitalTimestamp = null;
  }

  void feed(List<int> bytes) {
    if (bytes.isEmpty) return;

    _feedQueue.add(List<int>.of(bytes));

    if (_parsing) return;
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
        onLine(isAck ? 'ACK' : 'NACK');
        onEvent(SensorEvent(type: isAck ? SensorEventType.ack : SensorEventType.nack));
        cursor++;
        continue;
      }

      if (byte == _Protocol.sof) {
        final remaining = _len - cursor;
        if (remaining < 4) break;

        final cmdId      = _buf[cursor + 1];
        final payloadLen = _buf[cursor + 2];
        final totalLen   = 3 + payloadLen + 1;

        if (remaining < totalLen) break;

        int crc = 0;
        for (int i = 0; i < totalLen; i++) {
          crc ^= _buf[cursor + i];
        }

        if (crc == 0) {
          if (cmdId == _Protocol.resConnectSuccess && !_handshakeDone) {
            final result = _tryParseHandshake(cursor);

            if (result is _HandshakeSuccess) {
              _handshakeDone = true;
              cursor += result.consumed;
              continue;
            }
            if (result is _HandshakeFragment) break;

            cursor += totalLen;
            continue;
          }

          _handleBinaryPacket(cmdId, cursor + 3, payloadLen);
          cursor += totalLen;
        } else {
          cursor = _findNextValidSof(cursor + 1);
        }
        continue;
      }

      if (kDebugMode && byte >= 32 && byte <= 126) {
        int end = -1;
        for (int i = cursor; i < _len; i++) {
          if (_buf[i] == 10) { end = i; break; }
          if (_buf[i] < 32 || _buf[i] > 126) { end = i; break; }
        }

        if (end != -1) {
          final isNewline = _buf[end] == 10;
          try {
            final line = utf8.decode(Uint8List.sublistView(_buf, cursor, end)).trim();
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
    final data = ByteData.sublistView(_buf, offset, offset + len);

    switch (cmd) {
      case _Protocol.evtGameStarted:
        _firstHardwareEndTS = null;
        _firstDigitalTimestamp = null;
        break;
      case _Protocol.evtCountdownStarted:
        final val = len > 0 ? data.getUint8(0) : 5;
        onEvent(SensorEvent(type: SensorEventType.countdown, countdownValue: val));
        break;
      case _Protocol.evtAnimationStep:
        final val = len > 0 ? data.getUint8(0) : 0;
        onEvent(SensorEvent(type: SensorEventType.animationStep, countdownValue: val));
        break;
      case _Protocol.evtCountdownEnded:
        onEvent(SensorEvent(type: SensorEventType.countdownEnded, countdownValue: 0));
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
              targetPods.add(data.getUint8(cursor++) + 1);
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
              distractorsMap[dRawPodId + 1] = hexColor.toUpperCase();
            }
          }

          onEvent(SensorEvent(
            type:        SensorEventType.on,
            sensorId:    targetPods.isNotEmpty ? targetPods.first : 0,
            color:       [r, g, b, ...targetPods],
            distractors: distractorsMap,
          ));
        }
        break;

      case _Protocol.evtHit:
        if (len >= 19) {
          final int roundIdx = data.getUint8(0);
          final int attempt  = data.getUint8(1);
          final int podId    = data.getUint8(2);
          final int rt           = data.getUint32(3, Endian.big);
          final int startTS      = data.getUint32(7, Endian.big);
          final int endTS        = data.getUint32(11, Endian.big);
          final int gct          = data.getUint16(15, Endian.big);
          final int delayApplied = data.getUint16(17, Endian.big);

          onEvent(SensorEvent(
            type:         SensorEventType.hit,
            roundnum:     roundIdx,
            attempt:      attempt,
            sensorId:     podId + 1,
            reactionTime: rt,
            gct:          gct,
            delayApplied: delayApplied,
            stimuliStart: startTS,
            stimuliEnd:   endTS,
          ));
        }
        break;

      case _Protocol.evtMiss:
        if (len >= 19) {
          final int roundIdx          = data.getUint8(0);
          final int attempt           = data.getUint8(1);
          final int rawPodId          = data.getUint8(2);
          final int normalizedPodId   = (rawPodId == 255) ? 255 : (rawPodId + 1);
          final int errorTypeResolved    = (rawPodId == 255) ? 2 : 1;
          final int rxTime            = data.getUint32(3, Endian.big);
          final int startTS           = data.getUint32(7, Endian.big);
          final int endTS             = data.getUint32(11, Endian.big);
          final int gct               = data.getUint16(15, Endian.big);
          final int delayApplied      = data.getUint16(17, Endian.big);

          onEvent(SensorEvent(
            type:          SensorEventType.miss,
            roundnum:      roundIdx,
            attempt:       attempt,
            sensorId:      0,
            wrongSensorId: normalizedPodId,
            errorType:     errorTypeResolved,
            stimuliStart:  startTS,
            stimuliEnd:    endTS,
            reactionTime:  rxTime,
            gct:           gct,
            delayApplied:  delayApplied,
          ));
        }
        break;

      case _Protocol.evtGameEnded:
        onEvent(SensorEvent(type: SensorEventType.end));
        break;
    }
  }

  _HandshakeResult _tryParseHandshake(int start) {
    final payloadLen = _buf[start + 2];
    final totalLen   = 3 + payloadLen + 1;

    try {
      int pos = start + 3;
      int endOfPayload = start + 3 + payloadLen;

      String? readStr() {
        if (pos >= endOfPayload) return null;
        final strLen = _buf[pos];
        if (strLen == 0 || strLen > 64) throw 'Invalid string length';
        if (endOfPayload < pos + 1 + strLen) return null;
        pos++;
        final s = utf8.decode(Uint8List.sublistView(_buf, pos, pos + strLen));
        pos += strLen;
        return s;
      }

      final deviceId = readStr();
      if (deviceId == null) return _HandshakeFragment();

      if (pos >= endOfPayload) return _HandshakeFragment();
      final podCount = _buf[pos++];

      final version = readStr();
      if (version == null) return _HandshakeFragment();

      final readyMsg = readStr();
      if (readyMsg == null) return _HandshakeFragment();

      onHandshake(deviceId, podCount, version);
      return _HandshakeSuccess(totalLen);
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

  // Controla se o fluxo do protocolo de Handshake foi concluído com sucesso
  bool _isHandshakeOk = false;

  fbp.BluetoothDevice?         _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription?          _dataSubscription;
  StreamSubscription?          _connectionSubscription;

  String _firmwareVersion = 'Checking...';
  String _deviceType      = 'FlyFeet-Hexon';
  String _sensorCount     = 'Unknown';
  static const String _registeredUser = 'Michel De Cesaro';

  final _dataController       = StreamController<List<int>>.broadcast();
  final _connectionController = StreamController<fbp.BluetoothConnectionState>.broadcast();
  final _lineController       = StreamController<String>.broadcast();
  final _eventController      = StreamController<SensorEvent>.broadcast();

  Stream<List<int>>                    get dataStream            => _dataController.stream;
  Stream<fbp.BluetoothConnectionState> get connectionStateStream => _connectionController.stream;
  Stream<String>                       get lineStream            => _lineController.stream;
  Stream<SensorEvent>                  get eventStream           => _eventController.stream;

  List<fbp.ScanResult> get scanResults     => List.unmodifiable(_scanResults);
  bool                 get isScanning      => _isScanning;
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  String               get firmwareVersion => _firmwareVersion;
  String               get deviceType      => _deviceType;
  String               get registeredUser  => _registeredUser;
  String               get sensorCount     => _sensorCount;

  // Permite que a tela leia se o hardware está pronto operacionalmente
  bool                 get isHandshakeOk   => _isHandshakeOk;
  VoidCallback?        _uiUpdateCallback;

  late final _FrameParser _parser = _FrameParser(
    onLine: (line) {
      _lineController.add(line);
    },
    onEvent:    _eventController.add,
    onHandshake: _applyHandshakeResult,
  );

  void _applyHandshakeResult(String deviceId, int podCount, String version) {
    _deviceType      = deviceId;
    _sensorCount     = podCount.toString();
    _firmwareVersion = version;

    // Sinal Verde: O pacote 0x81 chegou íntegro e foi decodificado
    _isHandshakeOk   = true;
    _uiUpdateCallback?.call(); // Força a UI a redesenhar e exibir "Verified & Ready"
  }

  void init() => fbp.FlutterBluePlus.setLogLevel(fbp.LogLevel.none);

  Future<void> dispose() async {
    await _dataSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _dataController.close();
    await _connectionController.close();
    await _lineController.close();
    await _eventController.close();
  }

  Future<void> startScan({VoidCallback? onUpdate}) async {
    try {
      try {
        await fbp.FlutterBluePlus.adapterState
            .where((s) => s == fbp.BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        debugPrint('[BLE] Cannot start scan: Bluetooth adapter is not ON.');
        return;
      }

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
      return;
    }

    _isConnecting = true;
    _uiUpdateCallback = onUpdate; // Vincula o atualizador de estado da UI ativa

    try {
      _isHandshakeOk = false;
      _firmwareVersion = 'Checking...';
      _deviceType = 'FlyFeet - Hexon';
      _sensorCount = 'Unknown';
      _parser.reset();

      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        _connectionController.add(state);
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        } else if (state == fbp.BluetoothConnectionState.connected) {
          _connectedDevice = device;
          // 🟢 CORREÇÃO: Disparamos o callback aqui! Isso avisa a tela que o link BLE
          // subiu e força a UI a renderizar o Card Laranja ("Verifying Hardware...")
          _uiUpdateCallback?.call();
        }
      });

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

      try {
        if (Platform.isAndroid) {
          await device.requestConnectionPriority(
            connectionPriorityRequest: fbp.ConnectionPriority.high,
          );
        }
      } catch (_) {}

      try {
        final mtu = await device.requestMtu(512, timeout: 4);
        debugPrint('[BLE MTU] Negotiated MTU: $mtu bytes');
      } catch (_) {}

      await _discoverAndSubscribe(device, onUpdate);
      await Future.delayed(const Duration(milliseconds: 1000));
      await performHandshake(onUpdate);
    } catch (e, st) {
      debugPrint('[BLE] connect() error: $e\n$st');
      _isHandshakeOk = false;
      _isConnecting = false;
      _uiUpdateCallback?.call();
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
            _parser.feed(bytes);
            _dataController.add(bytes);
          });
          return;
        }
      }
    }
  }

  Future<void> performHandshake([VoidCallback? onUpdate]) async {
    if (_writeCharacteristic == null) return;
    debugPrint('[BLE] Sending CMD_CONNECT (handshake)');
    _isHandshakeOk = false;
    _parser.reset();
    await _sendBinaryPacket(_Protocol.cmdConnect);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> disconnect({VoidCallback? onUpdate}) async {
    final device = _connectedDevice;
    if (device == null) return;

    try {
      debugPrint('[BLE] Sending CMD_DISCONNECT and waiting for hardware ACK...');

      // 1. Criamos um Completer local para monitorar a chegada do ACK
      final ackCompleter = Completer<void>();

      // 2. Escuta temporariamente o stream de linhas procurando pelo 'ACK'
      final subscription = lineStream.listen((line) {
        if (line == 'ACK' && !ackCompleter.isCompleted) {
          debugPrint('[BLE] Hardware ACK received for disconnect command.');
          ackCompleter.complete();
        }
      });

      // 3. Dispara o pacote binário
      await _sendBinaryPacket(_Protocol.cmdDisconnect);

      // 4. Aguarda o ACK do firmware ou estoura um timeout seguro de 1 segundo
      await ackCompleter.future.timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () {
          debugPrint('[BLE] Timeout waiting for disconnect ACK. Forcing drop.');
        },
      );

      // 5. Cancela a inscrição temporária do ACK
      await subscription.cancel();

    } catch (e) {
      debugPrint('[BLE] Disconnect protocol exception: $e');
    } finally {
      // 6. Limpa o estado interno do app e desliga o link BLE físico
      await _dataSubscription?.cancel();       _dataSubscription = null;
      await _connectionSubscription?.cancel(); _connectionSubscription = null;

      _handleDisconnected();
      if (onUpdate != null) onUpdate();

      try {
        await device.disconnect();
        debugPrint('[BLE] Physical link destroyed cleanly.');
      } catch (e) {
        debugPrint('[BLE] Error forcing core connection drop: $e');
      }
    }
  }

  void _handleDisconnected() {
    _connectedDevice     = null;
    _writeCharacteristic = null;
    _isConnecting        = false;
    _isScanning          = false;
    _isHandshakeOk       = false;
    _scanResults.clear();
    _firmwareVersion     = 'Checking...';
    _deviceType          = 'FlyFeet - Hexon';
    _sensorCount         = 'Unknown';
    _parser.reset();

    _eventController.add(SensorEvent(type: SensorEventType.end));

    // 🟢 CORREÇÃO: Executa e depois limpa a referência para evitar memory leak
    _uiUpdateCallback?.call();
    _uiUpdateCallback = null;
  }

  // ── Game commands ─────────────────────────────────────────────────────────

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
    required int          missPolicy,
  }) async {
    final payload = ByteData(29);

    payload.setUint8(0, gameMode);
    payload.setUint8(1, gameRounds);
    payload.setUint8(2, gameAttempts);
    payload.setUint8(3, targetQty);
    payload.setUint8(4, targetLogic);

    final tRGB = _FrameParser._hexToRgb(targetRGBHex);
    payload.setUint8(5, tRGB[0]);
    payload.setUint8(6, tRGB[1]);
    payload.setUint8(7, tRGB[2]);

    payload.setUint8(8,  distMode);
    payload.setUint8(9,  distQty);
    payload.setUint8(10, distBehavior);

    for (int i = 0; i < 3; i++) {
      final String currentHex = (i < distRGBsHex.length) ? distRGBsHex[i] : '#000000';
      final List<int> dRGB = _FrameParser._hexToRgb(currentHex);
      final int baseOffset = 11 + (i * 3);

      payload.setUint8(baseOffset,     dRGB[0]);
      payload.setUint8(baseOffset + 1, dRGB[1]);
      payload.setUint8(baseOffset + 2, dRGB[2]);
    }

    payload.setUint8(20,  delayType);
    payload.setUint16(21, delayMinMs,   Endian.little);
    payload.setUint16(23, delayMaxMs,   Endian.little);
    payload.setUint16(25, timeoutMs,    Endian.little);
    payload.setUint8(27,  repeatIfWrong ? 1 : 0);
    payload.setUint8(28, missPolicy);

    final rawBytes = payload.buffer.asUint8List(0, 29);
    await _sendBinaryPacket(_Protocol.cmdSetGame, rawBytes);
  }

  Future<void> sendStopGame() => _sendBinaryPacket(_Protocol.cmdStopGame);

  // ── MTU-Aware Paced Link Layer Transmission ───────────────────────────────

  Future<void> _sendBinaryPacket(int cmd, [List<int>? payload]) async {
    final char = _writeCharacteristic;
    if (char == null) return;

    final payloadLen = payload?.length ?? 0;
    final frame      = Uint8List(3 + payloadLen + 1);

    frame[0] = _Protocol.sof;
    frame[1] = cmd;
    frame[2] = payloadLen;
    if (payload != null) {
      frame.setRange(3, 3 + payloadLen, payload);
    }

    int crc = 0;
    for (int i = 0; i < frame.length - 1; i++) {
      crc ^= frame[i];
    }
    frame[frame.length - 1] = crc;

    try {
      final bool noResponse = char.properties.writeWithoutResponse;
      final int platformMtuNow = (_connectedDevice?.mtuNow ?? 23) - 3;
      final int chunkSize = platformMtuNow > 0 ? platformMtuNow : 20;

      int offset = 0;
      while (offset < frame.length) {
        final end   = (offset + chunkSize).clamp(0, frame.length);
        final chunk = frame.sublist(offset, end);

        await char.write(chunk, withoutResponse: noResponse);
        offset = end;
      }
    } catch (e) {
      debugPrint('[BLE] _sendBinaryPacket exception on CMD 0x${cmd.toRadixString(16).toUpperCase()}: $e');
    }
  }
}