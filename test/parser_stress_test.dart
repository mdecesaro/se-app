import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

// Mocking the behavior of _parseBuffer from AppBluetoothService
class Parser {
  // ignore: constant_identifier_names
  static const int SOF = 0xAA;
  // ignore: constant_identifier_names
  static const int MAX_BUFFER_CAPACITY = 1024;
  final Uint8List _incomingBuffer = Uint8List(MAX_BUFFER_CAPACITY);
  int _bufferLen = 0;

  final List<String> lines = [];
  final List<Map<String, dynamic>> binaryPackets = [];

  void processIncomingData(List<int> value) {
    if (_bufferLen + value.length > MAX_BUFFER_CAPACITY) {
      _bufferLen = 0;
    }
    _incomingBuffer.setRange(_bufferLen, _bufferLen + value.length, value);
    _bufferLen += value.length;
    _parseBuffer();
  }

  void _parseBuffer() {
    int cursor = 0;
    while (cursor < _bufferLen) {
      int first = _incomingBuffer[cursor];

      if (first == SOF) {
        if (_bufferLen - cursor < 4) break;
        int payloadLen = _incomingBuffer[cursor + 2];
        int totalLen = 3 + payloadLen + 1;
        if (_bufferLen - cursor < totalLen) break;

        int crc = 0;
        for (int i = 0; i < totalLen; i++) {
          crc ^= _incomingBuffer[cursor + i];
        }

        if (crc == 0) {
          binaryPackets.add({
            'cmd': _incomingBuffer[cursor + 1],
            'payload': _incomingBuffer.sublist(cursor + 3, cursor + 3 + payloadLen),
          });
          cursor += totalLen;
          continue;
        }
        cursor++;
        continue;
      }

      if (first >= 32 && first <= 126) {
        int newlineIdx = -1;
        int maxScan = (cursor + 128 < _bufferLen) ? cursor + 128 : _bufferLen;
        for (int i = cursor; i < maxScan; i++) {
          if (_incomingBuffer[i] == 10) {
            newlineIdx = i;
            break;
          }
          // Strict protection: if we hit a non-ASCII character (like SOF), stop scanning for newline
          if (_incomingBuffer[i] == SOF) {
             break;
          }
        }

        if (newlineIdx != -1) {
          try {
            String line = utf8.decode(Uint8List.sublistView(_incomingBuffer, cursor, newlineIdx)).trim();
            if (line.isNotEmpty) lines.add(line);
          } catch (_) {}
          cursor = newlineIdx + 1;
          continue;
        } else if (_bufferLen - cursor < 128) {
          // If we haven't found a newline and haven't hit junk limit, wait for more data
          // BUT if we hit SOF, we should probably stop treating this as an ASCII block
          if (cursor < _bufferLen && _incomingBuffer[cursor] == SOF) {
             // Let SOF handler try next iteration
          } else {
             break;
          }
        } else {
          while (cursor < _bufferLen && _incomingBuffer[cursor] >= 32 && _incomingBuffer[cursor] <= 126) {
            cursor++;
          }
          continue;
        }
      }
      cursor++;
    }

    if (cursor > 0) {
      if (cursor < _bufferLen) {
        _incomingBuffer.setRange(0, _bufferLen - cursor, _incomingBuffer, cursor);
      }
      _bufferLen -= cursor;
    }
  }
}

void main() {
  group('Parser Stress Tests', () {
    late Parser parser;

    setUp(() {
      parser = Parser();
    });

    test('Handles fragmented binary packets', () {
      final payload = [0x01, 0x02, 0x03, 0x04];
      final frame = Uint8List(3 + payload.length + 1);
      frame[0] = 0xAA;
      frame[1] = 0x62;
      frame[2] = payload.length;
      frame.setRange(3, 3 + payload.length, payload);
      int crc = 0;
      for (int i = 0; i < frame.length - 1; i++) {
        crc ^= frame[i];
      }
      frame[frame.length - 1] = crc;

      for (int i = 0; i < frame.length; i += 2) {
        int end = (i + 2 < frame.length) ? i + 2 : frame.length;
        parser.processIncomingData(frame.sublist(i, end));
      }

      expect(parser.binaryPackets.length, 1);
      expect(parser.binaryPackets[0]['cmd'], 0x62);
      expect(parser.binaryPackets[0]['payload'], payload);
    });

    test('Handles interleaved ASCII and binary', () {
      final frameCorrect = Uint8List.fromList([0xAA, 0x40, 0x02, 0xAA, 0xBB, 0xF9]);

      parser.processIncomingData(utf8.encode("HEL\n"));
      parser.processIncomingData(frameCorrect);
      parser.processIncomingData(utf8.encode("LO\n"));

      expect(parser.lines, ["HEL", "LO"]);
      expect(parser.binaryPackets.length, 1);
    });

    test('Parser Guard: junk protection', () {
      final junk = List.generate(150, (index) => 65);
      parser.processIncomingData(junk);
      
      final validFrame = [0xAA, 0x10, 0x00, 0xBA];
      parser.processIncomingData(validFrame);
      
      expect(parser.binaryPackets.length, 1);
      expect(parser.binaryPackets[0]['cmd'], 0x10);
    });
  });
}
