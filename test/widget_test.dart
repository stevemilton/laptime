import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:laptime/app.dart';

void main() {
  testWidgets('App renders with bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: LapTimeApp()),
    );

    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Sectors'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
