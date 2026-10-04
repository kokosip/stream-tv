import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A resilient HTTP client that resolves domain names using Cloudflare DNS-over-HTTPS (DoH)
/// to bypass ISP DNS poisoning and blocks while preserving valid TLS SNI handshakes.
class SafeHttpClient {
  static final Map<String, String> _ipCache = {};
  static http.Client? _clientInstance;

  static http.Client get client {
    _clientInstance ??= _createClient();
    return _clientInstance!;
  }

  static http.Client _createClient() {
    final ioHttpClient = HttpClient();
    ioHttpClient.badCertificateCallback = (cert, host, port) => true;
    ioHttpClient.connectionTimeout = const Duration(seconds: 15);

    ioHttpClient.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final host = uri.host;
      String? targetIp = _ipCache[host];

      if (targetIp == null) {
        try {
          final dohClient = HttpClient();
          dohClient.badCertificateCallback = (c, h, p) => true;
          dohClient.connectionTimeout = const Duration(seconds: 5);
          final req = await dohClient.getUrl(
            Uri.parse('https://cloudflare-dns.com/dns-query?name=$host&type=A'),
          );
          req.headers.set('accept', 'application/dns-json');
          final resp = await req.close();
          final body = await resp.transform(utf8.decoder).join();
          dohClient.close();

          final json = jsonDecode(body) as Map<String, dynamic>;
          final answers = json['Answer'] as List<dynamic>?;
          if (answers != null && answers.isNotEmpty) {
            final aRecord = answers.firstWhere(
              (a) => a['type'] == 1,
              orElse: () => answers.first,
            );
            targetIp = aRecord['data'] as String?;
            if (targetIp != null) {
              _ipCache[host] = targetIp;
            }
          }
        } catch (_) {
          // Fallback to normal DNS
        }
      }

      final connectTarget = targetIp ?? host;
      final port = uri.port != 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final rawSocket = await Socket.connect(
        connectTarget,
        port,
        timeout: const Duration(seconds: 12),
      );

      if (uri.scheme == 'https') {
        final secureSocket = await SecureSocket.secure(
          rawSocket,
          host: host,
          supportedProtocols: ['http/1.1'],
          onBadCertificate: (cert) => true,
        );
        return ConnectionTask.fromSocket(Future.value(secureSocket), () {});
      }

      return ConnectionTask.fromSocket(Future.value(rawSocket), () {});
    };

    return IOClient(ioHttpClient);
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final client = _createClient();
    try {
      return await client.get(url, headers: headers);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final client = _createClient();
    try {
      return await client.post(url, headers: headers, body: body, encoding: encoding);
    } finally {
      client.close();
    }
  }
}
