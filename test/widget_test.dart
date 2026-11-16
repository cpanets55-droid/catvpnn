import 'package:flutter_test/flutter_test.dart';
import 'package:catvp/main.dart';

void main() {
  testWidgets('CatVPN Nord renders home UI', (WidgetTester tester) async {
    await tester.pumpWidget(const CatVpnApp());
    expect(find.text('CatVPN Nord'), findsOneWidget);
  });
}
