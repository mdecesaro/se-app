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
      backgroundColor: Colors.transparent, // Let the main background show through
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "FlyFeet Connection",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Text(
              "Connect your FlyFeet to start training",
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 32),
            
            // Main Scan Button
            Center(
              child: Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D3D), // Matching Sidebar "Heller" color
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _btService.isScanning ? colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: _btService.isScanning ? null : () => _btService.startScan(onUpdate: () => setState(() {})),
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _btService.isScanning ? Icons.sync : Icons.bluetooth_searching,
                        color: colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _btService.isScanning ? "SCANNING FOR DEVICES..." : "SEARCH FLYFEET D-MAT",
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Connected Device Section
            if (_btService.connectedDevice != null) ...[
              const Text(
                "CONNECTED DEVICE",
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: colorScheme.primary.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.bolt, color: Colors.yellow),
                  title: Text(
                    _btService.connectedDevice!.platformName.isEmpty 
                        ? "FlyFeet D-Mat" 
                        : _btService.connectedDevice!.platformName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  subtitle: Text("Real-time data: ${_btService.lastData}", 
                      style: const TextStyle(color: Colors.white70)),
                  trailing: TextButton(
                    onPressed: () {
                      // Add disconnect logic in service if needed
                    },
                    child: const Text("DISCONNECT", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            const Text(
              "DEVICES FOUND",
              style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            Expanded(
              child: _btService.scanResults.isEmpty 
                ? Center(
                    child: Text(
                      _btService.isScanning ? "Scanning surroundings..." : "No devices found",
                      style: const TextStyle(color: Colors.white24),
                    ),
                  )
                : ListView.builder(
                    itemCount: _btService.scanResults.length,
                    itemBuilder: (context, index) {
                      final r = _btService.scanResults[index];
                      String name = r.advertisementData.advName.isEmpty
                          ? (r.device.platformName.isEmpty ? "Unknown Device" : r.device.platformName)
                          : r.advertisementData.advName;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2C), // Slightly darker than the main button
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: ListTile(
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                          subtitle: Text(r.device.remoteId.str, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          trailing: FilledButton(
                            onPressed: () => _btService.connect(r.device, onUpdate: () => setState(() {})),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text("CONNECT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
