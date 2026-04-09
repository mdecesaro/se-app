import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(
    home: FlyFeetApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class FlyFeetApp extends StatefulWidget {
  const FlyFeetApp({super.key});

  @override
  State<FlyFeetApp> createState() => _FlyFeetAppState();
}

class _FlyFeetAppState extends State<FlyFeetApp> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  List<int> lastData = [];

  @override
  void initState() {
    super.initState();
    // Monitorar estado do Bluetooth
    FlutterBluePlus.adapterState.listen((state) {
      print("Status do Bluetooth: $state");
    });
  }

  // 1. Função para Pedir Permissões e Buscar
  Future<void> startScan() async {
    // Pedir permissões necessárias para Android 12+
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    setState(() {
      scanResults = [];
      isScanning = true;
    });

    // Iniciar Scan com filtro de 15 segundos
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    // Ouvir resultados
    FlutterBluePlus.scanResults.listen((results) {
      // Filtrar apenas dispositivos que contenham "FlyFeet" no nome
      var filtered = results.where((r) {
        return r.advertisementData.advName.contains("FlyFeet") ||
            r.device.platformName.contains("FlyFeet");
      }).toList();

      setState(() {
        scanResults = filtered;
      });
    });

    // Quando o scan parar
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    setState(() => isScanning = false);
  }

  // 2. Função para Conectar e Ouvir o Tapete
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => connectedDevice = device);
      print("Conectado ao: ${device.platformName}");

      // Descobrir Serviços
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          // Ativar notificações para receber os dados do tapete (passos)
          if (characteristic.properties.notify || characteristic.properties.indicate) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              setState(() {
                lastData = value; // Aqui chegam os dados do sensor!
              });
              print("Dados do FlyFeet: $value");
            });
          }
        }
      }
    } catch (e) {
      print("Erro na conexão: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FlyFeet D-Mat Connector"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // Botão de Busca
          Center(
            child: ElevatedButton.icon(
              icon: Icon(isScanning ? Icons.sync : Icons.search),
              label: Text(isScanning ? "Buscando..." : "Buscar FlyFeet"),
              onPressed: isScanning ? null : startScan,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)),
            ),
          ),

          // Status da Conexão
          if (connectedDevice != null)
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Card(
                color: Colors.green.shade100,
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text("Conectado a: ${connectedDevice!.platformName}"),
                  subtitle: Text("Dados recebidos: $lastData"),
                ),
              ),
            ),

          const Divider(),

          // Lista de Dispositivos Encontrados
          Expanded(
            child: ListView.builder(
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                final r = scanResults[index];
                String name = r.advertisementData.advName.isEmpty
                    ? r.device.platformName
                    : r.advertisementData.advName;

                return ListTile(
                  title: Text(name),
                  subtitle: Text(r.device.remoteId.str),
                  trailing: ElevatedButton(
                    onPressed: () => connectToDevice(r.device),
                    child: const Text("CONECTAR"),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}