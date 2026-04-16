import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final _btService = AppBluetoothService();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // No specific listener needed here as we use the onUpdate callback in connect/scan
  }

  void _handleUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Device Settings",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Text(
              "Manage your FlyFeet D-Mat hardware",
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 32),
            
            if (_btService.connectedDevice == null) ...[
              _buildScanButton(colorScheme),
              const SizedBox(height: 32),
              _buildFoundDevicesList(colorScheme),
            ] else ...[
              _buildConnectedDeviceInfo(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _btService.isScanning ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: _btService.isScanning ? null : () => _btService.startScan(onUpdate: _handleUpdate),
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
              _btService.isScanning ? "SCANNING..." : "SEARCH FLYFEET D-MAT",
              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedDeviceInfo(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Device Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF3D3D3D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.bolt, color: colorScheme.primary, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _btService.connectedDevice?.platformName ?? "FlyFeet D-Mat",
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const Text("Status: Connected", style: TextStyle(color: Colors.greenAccent, fontSize: 14)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await _btService.disconnect(onUpdate: _handleUpdate);
                    },
                    icon: const Icon(Icons.link_off, color: Colors.redAccent),
                  )
                ],
              ),
              const Divider(height: 40, color: Colors.white10),
              _buildDetailRow("Device Type", _btService.deviceType),
              _buildDetailRow("Firmware", _btService.firmwareVersion),
              _buildDetailRow("Sensors Found", _btService.sensorCount),
              _buildDetailRow("Registered to", _btService.registeredUser),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _btService.performHandshake(_handleUpdate),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("RETRY HANDSHAKE", style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Connectivity Status Indicator
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_tethering, color: Colors.white54),
              const SizedBox(width: 16),
              const Text("Signal Strength (RSSI)", style: TextStyle(color: Colors.white70)),
              const Spacer(),
              Text("Excellent", style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildFoundDevicesList(ColorScheme colorScheme) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("DEVICES FOUND", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: _btService.scanResults.isEmpty 
              ? const Center(child: Text("No devices found", style: TextStyle(color: Colors.white24)))
              : ListView.builder(
                  itemCount: _btService.scanResults.length,
                  itemBuilder: (context, index) {
                    final r = _btService.scanResults[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        title: Text(
                          r.device.platformName.isEmpty ? "Unknown FlyFeet" : r.device.platformName,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(r.device.remoteId.str, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                        trailing: _isConnecting 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : FilledButton(
                              onPressed: () async {
                          setState(() => _isConnecting = true);
                          await _btService.connect(r.device, onUpdate: _handleUpdate);
                          if (mounted) setState(() => _isConnecting = false);
                        },
                              child: const Text("CONNECT"),
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
