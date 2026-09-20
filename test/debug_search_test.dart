import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/moviebox_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('debug moviebox search and getDetails', () async {
    final api = MovieBoxApiService();
    final searchRes = await api.search(query: 'avatar');
    final items = searchRes['items'] as List;
    print('MovieBox search returned ${items.length} items');
    if (items.isNotEmpty) {
      final first = items.first as Map;
      print('First item keys: ${first.keys.toList()}');
      print('First item id: ${first['id']}, subjectId: ${first['subjectId']}, title: ${first['title']}');
      
      final subjectIdToUse = (first['subjectId'] ?? first['id'])?.toString() ?? '';
      print('Calling getDetails with subjectId: "$subjectIdToUse"');
      try {
        final details = await api.getDetails(subjectId: subjectIdToUse);
        print('getDetails success! title: ${details['title'] ?? details['subjectTitle']}');
      } catch (e, st) {
        print('getDetails FAILED: $e\n$st');
      }
    }
  });
}
