import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeapp/main.dart';

void main() {
  testWidgets('App launches to the plug list screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeControllerApp());

    expect(find.text('Smart Plugs'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
