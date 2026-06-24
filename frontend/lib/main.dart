import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/telemetry_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/spinach_garden_detail_screen.dart';

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
      
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF00979D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00979D),
          primary: const Color(0xFF00979D),
          secondary: const Color(0xFF10B981),
          background: const Color(0xFFF8FAFC),
        ),
        
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1E293B), fontFamily: 'Inter'),
          bodyMedium: TextStyle(color: Color(0xFF1E293B), fontFamily: 'Inter'),
        ),
        
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
      onGenerateRoute: (settings) {
        if (settings.name == '/garden/spinach') {
          final gardenName = settings.arguments as String? ?? 'Spinach Garden';
          return MaterialPageRoute(
            builder: (_) => SpinachGardenDetailScreen(gardenName: gardenName),
            settings: settings,
          );
        }
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      },
    );
  }
}
