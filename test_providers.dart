import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  print("Testing DoH for Goku and HDRezka and DramaCool...");
  
  final client = HttpClient();
  client.badCertificateCallback = (cert, host, port) => true;
  client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
    final dohClient = HttpClient();
    final req = await dohClient.getUrl(Uri.parse('https://cloudflare-dns.com/dns-query?name=${uri.host}&type=A'));
    req.headers.set('accept', 'application/dns-json');
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    dohClient.close();
    final json = jsonDecode(body);
    final answers = json['Answer'] as List<dynamic>?;
    final ip = answers?.firstWhere((a) => a['type'] == 1, orElse: () => null)?['data'] as String?;
    
    final targetIp = ip ?? uri.host;
    final port = uri.port != 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final rawSocket = await Socket.connect(targetIp, port, timeout: Duration(seconds: 10));
    if (uri.scheme == 'https') {
      final secure = await SecureSocket.secure(rawSocket, host: uri.host);
      return ConnectionTask.fromSocket(Future.value(secure), () {});
    }
    return ConnectionTask.fromSocket(Future.value(rawSocket), () {});
  };

  // Test 1: Goku Search
  try {
    final req = await client.getUrl(Uri.parse('https://goku.sx/ajax/movie/search?keyword=avatar'));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    req.headers.set('X-Requested-With', 'XMLHttpRequest');
    req.headers.set('Referer', 'https://goku.sx/');
    final resp = await req.close().timeout(Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    print("Goku Search Status: ${resp.statusCode}, length: ${body.length}");
    print("Goku snippet: ${body.substring(0, body.length > 200 ? 200 : body.length)}");
  } catch (e) {
    print("Goku search error: $e");
  }

  // Test 2: DramaCool Search
  try {
    final req = await client.getUrl(Uri.parse('https://dramacool.com.tr/?s=A+Love+Other+Than+Yours'));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    final resp = await req.close().timeout(Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    print("DramaCool Search Status: ${resp.statusCode}, length: ${body.length}");
    print("DramaCool snippet: ${body.substring(0, body.length > 200 ? 200 : body.length)}");
  } catch (e) {
    print("DramaCool search error: $e");
  }

  // Test 3: HDRezka Search
  try {
    final req = await client.getUrl(Uri.parse('https://rezka.ag/search/?do=search&subaction=search&q=Avatar'));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    final resp = await req.close().timeout(Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    print("HDRezka Search Status: ${resp.statusCode}, length: ${body.length}");
    print("HDRezka snippet: ${body.substring(0, body.length > 200 ? 200 : body.length)}");
  } catch (e) {
    print("HDRezka search error: $e");
  }
  
  client.close();
}
