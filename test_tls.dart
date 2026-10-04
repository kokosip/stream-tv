import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test hdrezka tls', () async {
    final host = 'hdrezka.ag';
    final socket = await Socket.connect('179.43.189.163', 443);
    try {
      final secure = await SecureSocket.secure(
        socket,
        host: host,
        supportedProtocols: ['http/1.1'],
        onBadCertificate: (_) => true,
      );
      print('TLS connected successfully: ${secure.selectedProtocol}');
      secure.destroy();
    } catch (e) {
      print('TLS error: $e');
    }
  });
}
