import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/constants/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Light status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Supabase
  // Uses a dummy URL if env vars are not configured (allows UI testing)
  final url = Env.supabaseUrl.isNotEmpty &&
          Env.supabaseUrl.startsWith('http')
      ? Env.supabaseUrl
      : 'https://localhost.supabase.co';
  final key = Env.supabaseAnonKey.isNotEmpty
      ? Env.supabaseAnonKey
      : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxvY2FsaG9zdCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNjI1MTQ1NjAwLCJleHAiOjE5NDA3MjE2MDB9.placeholder';
  await Supabase.initialize(url: url, anonKey: key);

  runApp(
    const ProviderScope(
      child: LapTimeApp(),
    ),
  );
}
