import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XOR Checksum robustness test', () {
    // Ported from AppBluetoothService logic
    bool validateChecksum(Uint8List frame) {
      int crc = 0;
      for (int i = 0; i < frame.length; i++) {
        crc ^= frame[i];
      }
      return crc == 0;
    }

    Uint8List createFrame(int cmd, List<int> payload) {
      int payloadLen = payload.length;
      final Uint8List frame = Uint8List(3 + payloadLen + 1);
      frame[0] = 0xAA; // SOF
      frame[1] = cmd;
      frame[2] = payloadLen;
      frame.setRange(3, 3 + payloadLen, payload);

      int crc = 0;
      for (int i = 0; i < frame.length - 1; i++) {
        crc ^= frame[i];
      }
      frame[frame.length - 1] = crc;
      return frame;
    }

    // Test case 1: Basic valid frame
    final frame1 = createFrame(0x01, [0x02, 0x03]);
    expect(validateChecksum(frame1), isTrue);

    // Test case 2: Single bit flip
    final frame2 = Uint8List.fromList(frame1);
    frame2[1] ^= 0x01;
    expect(validateChecksum(frame2), isFalse);

    // Test case 3: Swap two identical bytes (XOR is blind to position, but SOF/CMD/LEN help)
    // Note: XOR checksum doesn't catch position swaps if values are same, 
    // but usually sufficient for simple BLE link layer errors.
    final frame3 = createFrame(0x05, [10, 20, 10]);
    expect(validateChecksum(frame3), isTrue);
  });
}
