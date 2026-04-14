import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

class AppBluetoothService {
  static final AppBluetoothService _instance = AppBluetoothService._internal();
  factory AppBluetoothService() => _instance;
  AppBluetoothService._internal();

  // Bluno / DFRobot Specific UUIDs
  final String blunoDataCharUuid = "0000dfb1-0000-1000-8000-00805f9b34fb";

  final List<fbp.ScanResult> _scanResults = [];
  bool _isScanning = false;
  fbp.BluetoothDevice? _connectedDevice;
  
  String _firmwareVersion = "Checking...";
  String _deviceType = "FlyFeet D-Mat";
  final String _registeredUser = "Michel De Cesaro";
  String _sensorCount = "Unknown";
  
  final _dataController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get dataStream => _dataController.stream;

  final _connectionController = StreamController<fbp.BluetoothConnectionState>.broadcast();
  Stream<fbp.BluetoothConnectionState> get connectionStateStream => _connectionController.stream;

  final _lineController = StreamController<String>.broadcast();
  Stream<String> get lineStream => _lineController.stream;

  fbp.BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionSubscription;
  String _incomingBuffer = "";
  bool _isConnecting = false;

  // For deduplication
  String _lastProcessedChunk = "";
  DateTime _lastProcessedTime = DateTime.now();

  List<fbp.ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  String get firmwareVersion => _firmwareVersion;
  String get deviceType => _deviceType;
  String get registeredUser => _registeredUser;
  String get sensorCount => _sensorCount;

  void init() {
    fbp.FlutterBluePlus.setLogLevel(fbp.LogLevel.none);
  }

  Future<void> startScan({Function? onUpdate}) async {
    await [Permission.location, Permission.bluetoothScan, Permission.bluetoothConnect].request();
    _scanResults.clear();
    _isScanning = true;
    onUpdate?.call();

    var subscription = fbp.FlutterBluePlus.onScanResults.listen((results) {
      _scanResults.clear();
      _scanResults.addAll(results.where((r) {
        final name = (r.advertisementData.advName + r.device.platformName).toLowerCase();
        return name.contains("flyfeet") || name.contains("bluno") || name.contains("dfrobot");
      }));
      onUpdate?.call();
    });

    await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await fbp.FlutterBluePlus.isScanning.where((val) => val == false).first;
    _isScanning = false;
    subscription.cancel();
    onUpdate?.call();
  }

  Future<void> connect(fbp.BluetoothDevice device, {Function? onUpdate}) async {
    if (_isConnecting) return;
    if (_connectedDevice?.remoteId == device.remoteId && _writeCharacteristic != null) {
      debugPrint("Already connected to this device.");
      return;
    }

    try {
      _isConnecting = true;
      _firmwareVersion = "Checking...";
      _sensorCount = "Unknown";
      _incomingBuffer = "";
      
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        _connectionController.add(state);
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _writeCharacteristic = null;
          _dataSubscription?.cancel();
          _dataSubscription = null;
          _incomingBuffer = "";
          _isConnecting = false;
        } else if (state == fbp.BluetoothConnectionState.connected) {
          _connectedDevice = device;
        }
        onUpdate?.call();
      });

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      
      try { await device.requestMtu(223); } catch (_) {}
      
      List<fbp.BluetoothService> services = await device.discoverServices();
      
      _writeCharacteristic = null;
      bool dataCharFound = false;

      for (var service in services) {
        if (dataCharFound) break;
        for (var char in service.characteristics) {
          String uuid = char.uuid.toString().toLowerCase();
          bool isDataChar = uuid.contains("dfb1");
          
          if (isDataChar) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              _writeCharacteristic = char;
            }
            if (char.properties.notify || char.properties.indicate) {
              await char.setNotifyValue(true);
              await _dataSubscription?.cancel();
              _dataSubscription = char.lastValueStream.listen((value) => _processIncomingData(value, onUpdate));
              debugPrint("LISTENING TO DATA CHAR: $uuid");
              dataCharFound = true;
              break; 
            }
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      await performHandshake(onUpdate);
    } catch (e) {
      debugPrint("Connect Error: $e");
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> performHandshake([Function? onUpdate]) async {
    if (_writeCharacteristic == null) {
        debugPrint("Cannot handshake: No write characteristic found.");
        return;
    }
    debugPrint(">>> SENDING HANDSHAKE COMMAND");
    _incomingBuffer = ""; // Clear buffer to start fresh
    await sendMessage("HANDSHAKE\n");
    await Future.delayed(const Duration(milliseconds: 200));
    onUpdate?.call();
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _dataSubscription?.cancel();
        _dataSubscription = null;
        await _connectionSubscription?.cancel();
        _connectionSubscription = null;
        await _connectedDevice!.disconnect();
      } catch (e) {
        debugPrint("Disconnect Error: $e");
      }
    }
  }

  void _processIncomingData(List<int> value, Function? onUpdate) {
    if (value.isEmpty) return;

    // Deduplication logic for rapid identical packets
    final now = DateTime.now();
    final String decoded = utf8.decode(value, allowMalformed: true);
    if (decoded == _lastProcessedChunk && now.difference(_lastProcessedTime).inMilliseconds < 50) {
      return;
    }
    _lastProcessedChunk = decoded;
    _lastProcessedTime = now;

    _dataController.add(value);
    _incomingBuffer += decoded;

    final lines = _incomingBuffer.split(RegExp(r'\r\n|\r|\n'));
    _incomingBuffer = lines.last;

    for (int i = 0; i < lines.length - 1; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;
      
      debugPrint("ARDUINO-RAW: '$line'");

      if (line.contains("DEVICE:")) _deviceType = line.split("DEVICE:").last.trim();
      if (line.contains("SENSORS:")) _sensorCount = line.split("SENSORS:").last.trim();
      if (line.contains("VERSION:")) _firmwareVersion = line.split("VERSION:").last.trim();
      
      _lineController.add(line);
      onUpdate?.call();
    }
  }

  Future<void> sendMessage(String message) async {
    if (_writeCharacteristic != null) {
      try {
        List<int> bytes = utf8.encode(message);
        
        // Standard BLE MTU limit is often 20 bytes. 
        // We chunk the message to ensure it arrives correctly on Arduino.
        const int chunkSize = 20;
        for (int i = 0; i < bytes.length; i += chunkSize) {
          int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
          List<int> chunk = bytes.sublist(i, end);
          
          await _writeCharacteristic!.write(chunk, withoutResponse: true);
          // Small delay between chunks for Arduino to process
          await Future.delayed(const Duration(milliseconds: 10));
        }
      } catch (e) {
        debugPrint("Send Error: $e");
      }
    }
  }
}
