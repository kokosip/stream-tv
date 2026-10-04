
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SafeHttpClient {
  static final Map<String, String> _dnsCache = {};

  static Future<String> resolve(String host) async {
    if (_dnsCache.containsKey(host)) return _dnsCache[host]!;
    try {
      final res = await http.get(
        Uri.parse('https://cloudflare-dns.com/dns-query?name=$host&type=A'),
        headers: {'accept': 'application/dns-json'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['Answer'] != null) {
          for (var a in data['Answer']) {
            if (a['type'] == 1) {
              _dnsCache[host] = a['data'];
              return a['data'];
            }
          }
        }
      }
    } catch (_) {}
    return host;
  }

  static http.Client create() {
    final inner = HttpClient();
    inner.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final ip = await resolve(uri.host);
      final rawSocket = await Socket.connect(ip, uri.port, timeout: const Duration(seconds: 10));
      if (uri.scheme == 'https') {
        final secure = SecureSocket.secure(rawSocket, host: uri.host);
        return ConnectionTask.fromSocket(secure, () {});
      }
      return ConnectionTask.fromSocket(Future.value(rawSocket), () {});
    };
    return IOClient(inner);
  }
}

void main() async {
  final client = SafeHttpClient.create();
  final domains = [
    'https://kisskh.co/api/DramaList/Search?q=Queen',
    'https://dramaday.me/?s=Queen',
    'https://dramacool.com.tr/search?type=movies&keyword=Queen',
    'https://kdramahood.com/?s=Queen',
    'https://goku.sx/search?keyword=Queen',
    'https://rezka.ag/search/?q=Queen',
  ];

  for (var url in domains) {
    try {
      final res = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': url,
        },
      ).timeout(const Duration(seconds: 10));
      print('${Uri.parse(url).host}: ${res.statusCode} (Length: ${res.body.length})');
    } catch (e) {
      print('${Uri.parse(url).host}: Error $e');
    }
  }
  exit(0);
}
