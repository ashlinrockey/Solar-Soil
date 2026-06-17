import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/telemetry_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TelemetryProvider()),
      ],
      child: const SolarSoilApp(),
    ),
  );
}

class SolarSoilApp extends StatelessWidget {
  const SolarSoilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solar Soil IoT Dashboard',
      debugShowCheckedModeBanner: false,
      
      // Theme settings to maintain unified design system from original HTML
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF00979D), // Arduino Cyan Theme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00979D),
          primary: const Color(0xFF00979D),
          secondary: const Color(0xFF10B981), // Emerald accent
          background: const Color(0xFFF8FAFC), // slate-50
        ),
        
        // Premium modern system sans-serif typography (robust, high legibility, zero dynamic fetching bugs)
        fontFamily: 'sans-serif',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1E293B)),
          bodyMedium: TextStyle(color: Color(0xFF1E293B)),
        ),
        
        // Customized controls theme
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.grey[400];
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF00979D);
            }
            return Colors.grey[200];
          }),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
