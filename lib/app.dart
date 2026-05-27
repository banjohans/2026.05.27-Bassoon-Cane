import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'ui/shell.dart';

class BassoonCaneApp extends StatelessWidget {
  const BassoonCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppController()..initialize(),
      child: MaterialApp(
        title: 'ReedLab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF16697A),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F0E6),
          textTheme: Typography.material2021().black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Color(0xFF1F2933),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          cardTheme: CardThemeData(
            color: Colors.white.withValues(alpha: 0.88),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
          ),
        ),
        home: const ShellPage(),
      ),
    );
  }
}
