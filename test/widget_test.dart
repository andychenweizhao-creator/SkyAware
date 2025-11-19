// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:skyaware/main.dart';

void main() {
  testWidgets('Renders home page smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the main title is present.
    expect(find.text('SkyAware'), findsOneWidget);

    // Verify that the subtitle is present.
    expect(find.text('Aviation Intelligence System'), findsOneWidget);
  });
}
