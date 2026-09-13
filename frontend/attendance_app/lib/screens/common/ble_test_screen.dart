import 'package:flutter/material.dart';
import '../../services/ble_mesh_service.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({Key? key}) : super(key: key);

  @override
  _BleTestScreenState createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen> {
  final BleMeshService _bleService = BleMeshService();
  final String _testSessionId = "123e4567-e89b-12d3-a456-426614174000"; // Dummy UUID for testing
  
  List<String> logs = [];
  bool isBroadcasting = false;
  bool isScanning = false;

  void _addLog(String msg) {
    setState(() {
      logs.insert(0, "${DateTime.now().toIso8601String().split('T').last.substring(0,8)} - $msg");
    });
  }

  void _startTeacher() async {
    _addLog("Starting Teacher Broadcast (Hop 0) for session $_testSessionId...");
    setState(() {
      isBroadcasting = true;
      isScanning = false;
    });
    try {
      await _bleService.startTeacherBroadcast(_testSessionId);
      _addLog("Teacher broadcasting successfully!");
    } catch (e) {
      _addLog("Error starting broadcast: $e");
      setState(() => isBroadcasting = false);
    }
  }

  void _startStudent() async {
    _addLog("Starting Student Scan & Relay for session $_testSessionId...");
    setState(() {
      isScanning = true;
      isBroadcasting = false;
    });
    try {
      final result = await _bleService.startStudentScanAndRelay(_testSessionId, timeout: const Duration(seconds: 30));
      _addLog("Match found! Hop Count: ${result['hop_count']}, RSSI: ${result['rssi']}");
      _addLog("Student is now relaying the signal (Hop ${result['hop_count'] + 1}).");
    } catch (e) {
      _addLog("Scan failed/timeout: $e");
      setState(() => isScanning = false);
    }
  }

  void _stopAll() async {
    _addLog("Stopping all BLE activities...");
    await _bleService.stopAll();
    setState(() {
      isBroadcasting = false;
      isScanning = false;
    });
    _addLog("All BLE activities stopped.");
  }

  @override
  void dispose() {
    _bleService.stopAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Mesh Test/Sim'),
        backgroundColor: const Color(0xFF1E1E2C),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Session ID: $_testSessionId",
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isBroadcasting ? null : _startTeacher,
                    icon: const Icon(Icons.podcasts),
                    label: const Text("Act as Teacher\n(Broadcast)", textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isScanning ? null : _startStudent,
                    icon: const Icon(Icons.radar),
                    label: const Text("Act as Student\n(Scan & Relay)", textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (!isBroadcasting && !isScanning) ? null : _stopAll,
              icon: const Icon(Icons.stop),
              label: const Text("Stop All"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Logs:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      logs[index],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
