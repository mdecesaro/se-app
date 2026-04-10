import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

class AppBluetoothService {
  // Singleton pattern
  static final AppBluetoothService _instance = AppBluetoothService._internal();
  factory AppBluetoothService() => _instance;
  AppBluetoothService._internal();

  final List<fbp.ScanResult> _scanResults = [];
  bool _isScanning = false;
  fbp.BluetoothDevice? _connectedDevice;
  List<int> _lastData = [];

  // Getters
  List<fbp.ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  List<int> get lastData => _lastData;

  void init() {
    fbp.FlutterBluePlus.adapterState.listen((state) {
      debugPrint("Status do Bluetooth: $state");
    });
  }

  Future<void> startScan({required Function onUpdate}) async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    _scanResults.clear();
    _isScanning = true;
    onUpdate();

    await fbp.FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    fbp.FlutterBluePlus.scanResults.listen((results) {
      _scanResults.clear();
      _scanResults.addAll(results.where((r) {
        return r.advertisementData.advName.contains("FlyFeet") ||
            r.device.platformName.contains("FlyFeet");
      }));
      onUpdate();
    });

    await fbp.FlutterBluePlus.isScanning.where((val) => val == false).first;
    _isScanning = false;
    onUpdate();
  }

  Future<void> connect(fbp.BluetoothDevice device, {required Function onUpdate}) async {
    try {
      await device.connect();
      _connectedDevice = device;
      onUpdate();

      List<fbp.BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify || characteristic.properties.indicate) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              _lastData = value;
              onUpdate();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Erro na conexão: $e");
    }
  }
}
