import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/main.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MovieBoxTvApp());
  });
}
