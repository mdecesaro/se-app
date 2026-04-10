import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final _btService = AppBluetoothService();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("FlyFeet D-Mat"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              icon: Icon(_btService.isScanning ? Icons.sync : Icons.bluetooth_searching),
              label: Text(_btService.isScanning ? "Buscando..." : "Buscar FlyFeet"),
              onPressed: _btService.isScanning ? null : () => _btService.startScan(onUpdate: () => setState(() {})),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_btService.connectedDevice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 0,
                color: colorScheme.primaryContainer,
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: colorScheme.primary),
                  title: Text(
                    "Conectado: ${_btService.connectedDevice!.platformName}",
                    style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                  ),
                  subtitle: Text("Dados: ${_btService.lastData}", style: TextStyle(color: colorScheme.onPrimaryContainer)),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Divider(),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _btService.scanResults.length,
              itemBuilder: (context, index) {
                final r = _btService.scanResults[index];
                String name = r.advertisementData.advName.isEmpty
                    ? r.device.platformName
                    : r.advertisementData.advName;

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(r.device.remoteId.str),
                    trailing: OutlinedButton(
                      onPressed: () => _btService.connect(r.device, onUpdate: () => setState(() {})),
                      child: const Text("CONECTAR"),
                    ),
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
