import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:laptime/core/theme/app_theme.dart';
import 'package:laptime/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('App shows login screen when not authenticated', (
    WidgetTester tester,
  ) async {
    // When not authenticated, the app should show the login screen.
    // We test the LoginScreen directly since the router requires Supabase.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LoginScreen(),
        ),
      ),
    );

    expect(find.text('LapTime'), findsOneWidget);
    expect(find.text('Track your track days'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
  });
}
