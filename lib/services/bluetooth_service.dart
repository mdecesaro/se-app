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
  final String blunoServiceUuid = "0000dfb0-0000-1000-8000-00805f9b34fb";
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
  List<int> _lastData = [];
  String _incomingBuffer = "";

  List<fbp.ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  List<int> get lastData => _lastData;
  String get firmwareVersion => _firmwareVersion;
  String get deviceType => _deviceType;
  String get registeredUser => _registeredUser;
  String get sensorCount => _sensorCount;

  void init() {
    fbp.FlutterBluePlus.adapterState.listen((state) => debugPrint("BT Adapter: $state"));
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
      List<fbp.BluetoothService> services = await device.discoverServices();
      
      for (var service in services) {
        for (var char in service.characteristics) {
          bool isBlunoData = char.uuid.toString().toLowerCase().contains("dfb1");
          
          // Setup Notifications
          if (char.properties.notify || char.properties.indicate) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) => _processIncomingData(value, onUpdate));
            debugPrint("Listening to: ${char.uuid}");
          }
          
          // Setup Write - Prioritize dfb1 for Bluno
          if (char.properties.write || char.properties.writeWithoutResponse) {
            if (_writeCharacteristic == null || isBlunoData) {
              _writeCharacteristic = char;
              debugPrint("Selected Write Char: ${char.uuid}");
            }
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      await sendMessage("HANDSHAKE\n");
      onUpdate?.call();
    } catch (e) {
      debugPrint("Connect Error: $e");
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
        _writeCharacteristic = null;
        _firmwareVersion = "Unknown";
        _sensorCount = "Unknown";
      } catch (e) {
        debugPrint("Disconnect Error: $e");
      }
    }
  }

  void _processIncomingData(List<int> value, Function? onUpdate) {
    _lastData = value;
    _dataController.add(value);

    String decoded = utf8.decode(value, allowMalformed: true);
    _incomingBuffer += decoded;

    if (_incomingBuffer.contains('\n') || _incomingBuffer.contains('\r')) {
      List<String> lines = _incomingBuffer.split(RegExp(r'\r\n|\r|\n'));
      _incomingBuffer = lines.last;
      
      for (int i = 0; i < lines.length - 1; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;
        debugPrint("ARDUINO SAYS: $line");

        if (line.contains("DEVICE:")) _deviceType = line.split("DEVICE:").last.trim();
        if (line.contains("SENSORS:")) _sensorCount = line.split("SENSORS:").last.trim();
        if (line.contains("VERSION:")) _firmwareVersion = line.split("VERSION:").last.trim();
      }
      onUpdate?.call();
    }
  }

  Future<void> sendMessage(String message) async {
    if (_writeCharacteristic != null) {
      try {
        await _writeCharacteristic!.write(utf8.encode(message), 
          withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse);
      } catch (e) {
        debugPrint("Send Error: $e");
      }
    }
  }
}
