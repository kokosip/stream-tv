import 'package:flutter_test/flutter_test.dart';
import '../lib/services/safe_http_client.dart';

void main() {
  test('Inspect DramaDay drama page', () async {
    final resp = await SafeHttpClient.get(
      Uri.parse('https://dramaday.me/a-love-other-than-yours/'),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );
    print('DramaDay page status: ${resp.statusCode}');
    
    // Find links in entry content
    final linkRegex = RegExp(r'<a\s+[^>]*href="([^"]+)"[^>]*>([^<]+)</a>');
    for (final m in linkRegex.allMatches(resp.body)) {
      final href = m.group(1)!;
      final text = m.group(2)!.trim();
      if (text.toLowerCase().contains('episode') || text.toLowerCase().contains('720p') || text.toLowerCase().contains('1080p') || text.toLowerCase().contains('mega') || text.toLowerCase().contains('drive') || text.toLowerCase().contains('gdrive')) {
        print(' - $text -> $href');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

