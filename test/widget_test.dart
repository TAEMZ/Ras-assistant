import 'package:flutter_test/flutter_test.dart';
import 'package:amharic_assistant/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RasApp());
    expect(find.byType(RasApp), findsOneWidget);
  });
}
