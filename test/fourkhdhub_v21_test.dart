import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieBox-TUI v0.1.21 4KHDHub tests', () {
    test('Decodes greenmotors mediator payload matching MovieBox-TUI test', () {
      // Official test payload from MovieBox-TUI v0.1.21 hubcloud.rs test suite
      const payload =
          "Y214WE0xWjNZbXRhVUdwMmIxQldObFo2ZFRCeFZVOXRRbmxxYVV0UU9XRndla2w1YjNveGFYRlVPV3h3YkRWM2IxVkpka3RRT1dKdk1qRjViMVJUYUUxVVNXeExVRGgyV1ZCWGFWWjNZblpNU0hWR1dsUkJWa2RIVFZweVIzbHBUVk54V0c1NlYxVkNSMU51UkcxSmFreHRRVVZ4ZVdOV1JtRlBlRzlKU1RKTWJVRkNjbnBCYUVwaGVYbHZlWGswU25vMWVISktXbTFIZDFaMmMwUTlQUT09";

      // Step 1: Base64 decode
      final s1 = utf8.decode(base64.decode(payload));
      // Step 2: Base64 decode
      final s2 = utf8.decode(base64.decode(s1));

      // Step 3: ROT13
      final buffer = StringBuffer();
      for (int i = 0; i < s2.length; i++) {
        final code = s2.codeUnitAt(i);
        if (code >= 65 && code <= 90) {
          buffer.writeCharCode((code - 65 + 13) % 26 + 65);
        } else if (code >= 97 && code <= 122) {
          buffer.writeCharCode((code - 97 + 13) % 26 + 97);
        } else {
          buffer.writeCharCode(code);
        }
      }
      final s3 = buffer.toString();
      // Step 4: Base64 decode
      final s4 = utf8.decode(base64.decode(s3));
      // Step 5: JSON parse
      final Map<String, dynamic> data = jsonDecode(s4);
      final oVal = data['o']?.toString();
      expect(oVal, isNotNull);

      // Step 6: Target URL base64 decode
      final targetUrl = utf8.decode(base64.decode(oVal!));
      expect(targetUrl, equals("https://hubcloud.ist/drive/sssrvrzv1fwrssv"));
    });

    test('Unwraps Watch Online pages.dev links', () {
      const rawTarget = "https://cdn.example.com/video.mkv";
      final encodedTarget = base64.encode(utf8.encode(rawTarget));
      final watchOnlineUrl = "https://vdplay.pages.dev/?u=$encodedTarget";

      final uri = Uri.parse(watchOnlineUrl);
      expect(uri.host.contains("pages.dev"), isTrue);
      final u = uri.queryParameters['u'];
      expect(u, isNotNull);
      final decoded = utf8.decode(base64.decode(u!));
      expect(decoded, equals(rawTarget));
    });
  });
}
