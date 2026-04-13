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
  String _registeredUser = "Michel De Cesaro";
  String _sensorCount = "Unknown";
  
  final _dataController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get dataStream => _dataController.stream;

  final _connectionController = StreamController<fbp.BluetoothConnectionState>.broadcast();
  Stream<fbp.BluetoothConnectionState> get connectionStateStream => _connectionController.stream;

  fbp.BluetoothCharacteristic? _writeCharacteristic;
  String _incomingBuffer = "";

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
    try {
      _firmwareVersion = "Checking...";
      _sensorCount = "Unknown";
      
      device.connectionState.listen((state) {
        _connectionController.add(state);
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _writeCharacteristic = null;
        } else if (state == fbp.BluetoothConnectionState.connected) {
          _connectedDevice = device;
        }
        onUpdate?.call();
      });

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      
      try { await device.requestMtu(223); } catch (_) {}
      
      List<fbp.BluetoothService> services = await device.discoverServices();
      
      _writeCharacteristic = null;
      _incomingBuffer = "";

      for (var service in services) {
        for (var char in service.characteristics) {
          String uuid = char.uuid.toString().toLowerCase();
          bool isDataChar = uuid.contains("dfb1");
          
          if (isDataChar) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              _writeCharacteristic = char;
              debugPrint("FOUND WRITE CHAR: $uuid");
            }
            if (char.properties.notify || char.properties.indicate) {
              await char.setNotifyValue(true);
              char.lastValueStream.listen((value) => _processIncomingData(value, onUpdate));
              debugPrint("LISTENING TO DATA CHAR: $uuid");
            }
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 2000));
      await performHandshake(onUpdate);
    } catch (e) {
      debugPrint("Connect Error: $e");
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
        await _connectedDevice!.disconnect();
      } catch (e) {
        debugPrint("Disconnect Error: $e");
      }
    }
  }

  void _processIncomingData(List<int> value, Function? onUpdate) {
    if (value.isEmpty) return;
    _dataController.add(value);

    String decoded = utf8.decode(value, allowMalformed: true);
    _incomingBuffer += decoded;

    while (_incomingBuffer.contains('\n') || _incomingBuffer.contains('\r')) {
      int breakIndex = _incomingBuffer.indexOf(RegExp(r'[\r\n]'));
      String line = _incomingBuffer.substring(0, breakIndex).trim();
      
      String remainder = _incomingBuffer.substring(breakIndex);
      if (remainder.startsWith('\r\n')) {
        _incomingBuffer = remainder.substring(2);
      } else {
        _incomingBuffer = remainder.substring(1);
      }

      if (line.isEmpty) continue;
      debugPrint("ARDUINO-RAW: '$line'");

      if (line.contains("DEVICE:")) _deviceType = line.split("DEVICE:").last.trim();
      if (line.contains("SENSORS:")) _sensorCount = line.split("SENSORS:").last.trim();
      if (line.contains("VERSION:")) _firmwareVersion = line.split("VERSION:").last.trim();
      
      // Always call update when we get ANY string from Arduino to refresh UI
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
