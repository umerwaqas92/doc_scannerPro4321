import 'package:flutter_test/flutter_test.dart';
import 'package:docts_scanner/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const DocScanApp());
    expect(find.text('DocScan'), findsOneWidget);
  });
}
