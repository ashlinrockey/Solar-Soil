import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/telemetry_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/rootwise_assistant_sheet.dart';
import '../widgets/telemetry_chart.dart';
import '../widgets/terminal_monitor.dart';
import '../utils/redirect.dart';
import 'login_screen.dart';
import 'spinach_garden_detail_screen.dart';
import 'dart:ui' as ui;
import 'package:lottie/lottie.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  late AnimationController _blobController;
  int _activeNavIndex = 0;
  String _logSearchQuery = "";
  String _selectedStatusFilter = "All";
  String _selectedTimeFilter = "24h";

  // Garden zone editing state
  String _gardenName = "Spinach Garden";
  String _gardenNumber = "08";
  String _zoneId = "PL-02J";
  String _coverageArea = "200 m²";
  bool _gardenConfigLoaded = false;
  bool _editClicked = false; // tracks if edit button was just tapped

  // Notifications
  final List<Map<String, String>> _notifications = [
    { 'type': 'warning', 'message': 'Sensor-005-E high moisture: 81.9%', 'time': '2 min ago' },
    { 'type': 'critical', 'message': 'Sensor-007-G offline', 'time': '15 min ago' },
    { 'type': 'info', 'message': 'Battery low: Sensor-003-C (18.2%)', 'time': '1 hour ago' },
  ];

  String _activeChartMetric = 'moisture';

  // AI Config state
  bool _aiConfigLoaded = false;
  Map<String, dynamic> _aiMetrics = {};
  bool _aiMetricsLoaded = false;
  Timer? _metricsTimer;

  Future<void> _loadAIMetrics(TelemetryProvider provider) async {
    final m = await provider.getAIMetrics();
    if (mounted) setState(() { _aiMetrics = m; _aiMetricsLoaded = true; });
  }

  void _startMetricsPolling(TelemetryProvider provider) {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_activeNavIndex == 5) {
        provider.getAIMetrics().then((m) {
          if (mounted) setState(() => _aiMetrics = m);
        });
      }
    });
  }

  void _stopMetricsPolling() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }
  String _aiProvider = 'gemini';
  final TextEditingController _aiApiKeyController = TextEditingController();
  final TextEditingController _aiModelController = TextEditingController();
  final TextEditingController _aiBaseUrlController = TextEditingController();
  bool _aiKeyVisible = false;
  bool _aiConfigSaving = false;
  String? _aiConfigStatus;
  bool _aiHasSavedKey = false;
  String _aiKeyMasked = '';
  bool _aiEditingKey = false;

  // Password change state
  bool _passwordChangeEnabled = false;
  bool _usernameChangeEnabled = false;
  bool _usernameSaving = false;
  String? _usernameStatus;
  final _newUsernameController = TextEditingController();
  final _usernamePasswordController = TextEditingController();
  bool _usernamePasswordVisible = false;
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _oldPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _passwordSaving = false;
  String? _passwordStatus;

  // Preferences state
  String _tempUnit = 'Celsius';
  int _refreshInterval = 5;
  String _themeMode = 'System';

  // Export state
  String _exportState = 'idle'; // idle, loading, done
  String _exportRange = '24h';
  bool _exportIncludeAI = false;
  String _exportStartDate = '';
  String _exportEndDate = '';

  Future<void> _loadAIConfig(TelemetryProvider provider) async {
    final cfg = await provider.getAIConfig();
    setState(() {
      _aiProvider = cfg['provider'] ?? 'gemini';
      _aiModelController.text = cfg['model'] ?? '';
      _aiBaseUrlController.text = cfg['baseUrl'] ?? '';
      _aiApiKeyController.text = '';
      _aiHasSavedKey = cfg['hasApiKey'] == true;
      _aiKeyMasked = cfg['apiKeyMasked'] ?? '';
      _aiEditingKey = false;
      _aiConfigLoaded = true;
    });
  }

  Future<void> _saveAIConfig(TelemetryProvider provider) async {
    setState(() => _aiConfigSaving = true);
    final keyValue = _aiHasSavedKey && !_aiEditingKey ? '' : _aiApiKeyController.text.trim();
    _aiApiKeyController.text = '';
    final config = <String, dynamic>{
      'provider': _aiProvider,
      'model': _aiModelController.text.trim(),
      'baseUrl': _aiBaseUrlController.text.trim(),
      'apiKey': keyValue,
    };
    final ok = await provider.saveAIConfig(config);
    setState(() {
      _aiConfigSaving = false;
      _aiConfigStatus = ok ? '✓ Configuration saved!' : '✗ Failed to save configuration.';
    });
    if (ok) {
      _loadAIConfig(provider);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _aiConfigStatus = null);
    }
  }

  Future<void> _changePassword(TelemetryProvider provider) async {
    final oldPw = _oldPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;

    if (oldPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
      setState(() => _passwordStatus = '✗ All fields are required.');
      return;
    }
    if (newPw != confirmPw) {
      setState(() => _passwordStatus = '✗ New passwords do not match.');
      return;
    }
    if (newPw.length < 4) {
      setState(() => _passwordStatus = '✗ Password must be at least 4 characters.');
      return;
    }

    setState(() { _passwordSaving = true; _passwordStatus = null; });
    final result = await provider.changePassword(oldPw, newPw);
    setState(() {
      _passwordSaving = false;
      _passwordStatus = result['success'] == true ? '✓ Password updated!' : '✗ ${result['message']}';
    });
    if (result['success'] == true) {
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _passwordChangeEnabled = false);
    }
  }

  Future<void> _changeUsername(TelemetryProvider provider) async {
    final newUsername = _newUsernameController.text;
    final password = _usernamePasswordController.text;

    if (newUsername.isEmpty || password.isEmpty) {
      setState(() => _usernameStatus = '✗ All fields are required.');
      return;
    }
    if (newUsername.length < 3) {
      setState(() => _usernameStatus = '✗ Username must be at least 3 characters.');
      return;
    }

    setState(() { _usernameSaving = true; _usernameStatus = null; });
    final result = await provider.changeUsername(newUsername, password);
    setState(() {
      _usernameSaving = false;
      _usernameStatus = result['success'] == true ? '✓ Username updated!' : '✗ ${result['message']}';
    });
    if (result['success'] == true) {
      _newUsernameController.clear();
      _usernamePasswordController.clear();
      setState(() => _usernameChangeEnabled = false);
      if (result['newUsername'] != null) {
        provider.loggedInUsername = result['newUsername'];
      }
    }
  }

  Future<void> _testAIConnection(TelemetryProvider provider) async {
    setState(() => _aiConfigStatus = 'Testing connection...');
    final result = await provider.testAIConnection();
    setState(() {
      _aiConfigStatus = result['ok'] == true
          ? '✓ ${result['message'] ?? 'Connection successful!'}'
          : '✗ ${result['message'] ?? 'Connection failed.'}';
    });
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _aiConfigStatus = null);
  }

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _stopMetricsPolling();
    _blobController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newUsernameController.dispose();
    _usernamePasswordController.dispose();
    super.dispose();
  }

  void _handleLogout(BuildContext context) {
    if (kIsWeb) {
      // Redirect to the HTML login page for web
      redirectTo('/');
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, -1.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TelemetryProvider>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1024;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      bottomNavigationBar: !isDesktop ? _buildMobileBottomNavBar(provider) : null,
      body: Stack(
        children: [
          // 1. Background Mesh Animations
          _buildBackgroundMesh(size),

          // 2. Main Interface Layout
          SafeArea(
            child: Row(
              children: [
                // Desktop Sidebar Navigation
                if (isDesktop) _buildSidebar(provider),

                // Central Scrollable Workspace
                Expanded(
                  child: Column(
                    children: [
                      // Mobile Header (Sticky)
                      if (!isDesktop) _buildMobileHeader(provider),

                      // Main Content Area
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                          child: _buildActiveBody(provider, isDesktop),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // AI Chat FAB
          Positioned(
            right: isDesktop ? 24 : 16,
            bottom: isDesktop ? 24 : 4,
            child: FloatingActionButton(
              onPressed: () => _openAIChat(provider),
              backgroundColor: const Color(0xFF00979D),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            ),
          ),

        ],
      ),
    );
  }

  // --- BACKGROUND BLOB BUILDER ---
  Widget _buildBackgroundMesh(Size size) {
    return AnimatedBuilder(
      animation: _blobController,
      builder: (context, child) {
        final val = _blobController.value * 2 * math.pi;
        final x1 = math.sin(val) * 40;
        final y1 = math.cos(val) * 40;
        final x2 = math.cos(val + math.pi / 2) * 50;
        final y2 = math.sin(val + math.pi / 2) * 30;

        return Stack(
          children: [
            // Top Left Aqua/Arduino Blob
            Positioned(
              top: -50 + y1,
              left: -50 + x1,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00979D).withOpacity(0.08),
                ),
              ),
            ),
            // Top Right Green Blob
            Positioned(
              top: 50 + y2,
              right: -50 + x2,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withOpacity(0.07),
                ),
              ),
            ),
            // Bottom Center Blue Blob
            Positioned(
              bottom: -50 + y1,
              left: size.width * 0.3 + x2,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.06),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── CHART METRIC TOGGLE ──────────────────────────────────────────────
  Widget _buildMetricToggle(String metric, String label) {
    final isActive = _activeChartMetric == metric;
    final Map<String, Color> colors = {
      'moisture': const Color(0xFF3B82F6),
      'temperature': const Color(0xFFF43F5E),
      'humidity': const Color(0xFF10B981),
      'light': const Color(0xFFF59E0B),
    };
    final color = colors[metric] ?? const Color(0xFF00979D);
    return GestureDetector(
      onTap: () => setState(() => _activeChartMetric = metric),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.12) : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? color.withOpacity(0.4) : Colors.black12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? color : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  // ── NOTIFICATION BELL ──────────────────────────────────────────────────
  Widget _buildNotificationBell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Color(0xFF1E293B), size: 22),
          onPressed: () => _showNotificationPanel(context),
          tooltip: "Notifications",
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${_notifications.length}',
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  void _showNotificationPanel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 80),
        contentPadding: EdgeInsets.zero,
        content: GlassCard(
          padding: const EdgeInsets.all(20),
          borderRadius: 20,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Notifications", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(),
                if (_notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text("No notifications", style: TextStyle(color: Colors.grey))),
                  )
                else
                  ..._notifications.map((n) => _buildNotificationItem(n)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, String> n) {
    IconData icon;
    Color color;
    switch (n['type']) {
      case 'critical':
        icon = Icons.error_outline;
        color = const Color(0xFFEF4444);
        break;
      case 'warning':
        icon = Icons.warning_amber_rounded;
        color = const Color(0xFFF59E0B);
        break;
      default:
        icon = Icons.info_outline;
        color = const Color(0xFF3B82F6);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n['message'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(n['time'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── DESKTOP SIDEBAR ────────────────────────────────────────────────────
  Widget _buildSidebar(TelemetryProvider provider) {
    return Container(
      width: 260,
      margin: const EdgeInsets.all(16.0),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sidebar Header (Logo and Node Status Badge)
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00979D).withOpacity(0.1),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      'assets/newlogo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Icon(
                        Icons.eco,
                        color: Color(0xFF00979D),
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "SOLAR SOIL",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: provider.isConnected ? const Color(0xFF10B981) : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            provider.isConnected ? "ESP32 ONLINE" : "OFFLINE",
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFF00979D),
                              letterSpacing: 0.8,
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.black12),
            const SizedBox(height: 12),
            
            // Navigation Links
            _buildSidebarNavItem(0, Icons.pie_chart_outline, "Dashboard"),
            _buildSidebarNavItem(1, Icons.solar_power_outlined, "Solar Power"),
            _buildSidebarNavItem(2, Icons.grass_outlined, "Soil & Env"),
            _buildSidebarNavItem(3, Icons.history_outlined, "Data Logs"),
            _buildSidebarNavItem(4, Icons.tune_outlined, "Sensor Config"),
            _buildSidebarNavItem(5, Icons.settings_outlined, "Settings"),
            
            const Spacer(),
            
            // Sync Banner info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sync,
                    size: 16,
                    color: const Color(0xFF00979D),
                    // Keep dynamic spin simulation matching HTML
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Connection Status",
                          style: TextStyle(color: Colors.grey[400], fontSize: 9, fontWeight: FontWeight.w300),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider.isConnected ? "Active Feed" : "Connecting...",
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: provider.isMqttConnected ? const Color(0xFF10B981) : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              provider.isMqttConnected ? "MQTT Broker Live" : "MQTT Offline",
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w500,
                                color: provider.isMqttConnected ? const Color(0xFF10B981) : Colors.redAccent,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _handleLogout(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.logout_outlined,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Log Out",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem(int index, IconData icon, String label) {
    final isActive = _activeNavIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _activeNavIndex = index),
          hoverColor: const Color(0xFF00979D).withOpacity(0.04),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF00979D).withOpacity(0.08) : Colors.transparent,
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 24,
                  color: isActive ? const Color(0xFF00979D) : Colors.transparent,
                ),
                const SizedBox(width: 13),
                Icon(
                  icon,
                  color: isActive ? const Color(0xFF00979D) : const Color(0xFF64748B),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      color: isActive ? const Color(0xFF1E293B) : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- MOBILE HEADER ---
  Widget _buildMobileHeader(TelemetryProvider provider) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      borderOpacity: 0.4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset(
                    'assets/newlogo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.eco,
                      color: Color(0xFF00979D),
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Solar Soil IoT",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  Text(
                    provider.isConnected ? "CONNECTED" : "OFFLINE",
                    style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Color(0xFF00979D)),
                  )
                ],
              )
            ],
          ),
          Row(
            children: [
              _buildNotificationBell(),
              IconButton(
                icon: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                onPressed: () => _handleLogout(context),
                tooltip: "Log Out",
              ),
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1E293B)),
                onPressed: () {},
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- HEADER TITLE DETAILS ---
  Widget _buildDashboardHeader() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Farm Overview",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 4),
            Text(
              "Real-time sensor streams and local database logs",
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Feature is under development"),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text("Add Node", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00979D),
                elevation: 3,
                shadowColor: const Color(0xFF00979D).withOpacity(0.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.logout, color: Color(0xFFEF4444)),
              onPressed: () => _handleLogout(context),
              tooltip: "Log Out",
            ),
          ],
        )
      ],
    );
  }

  // ── EXPORT CSV DIALOG ──────────────────────────────────────────────────────
  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String range = _exportRange;
        bool includeAI = _exportIncludeAI;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: EdgeInsets.all(MediaQuery.of(ctx).size.width < 500 ? 16 : 24),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width < 500 ? null : 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: const Color(0xFF00979D).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.download_outlined, size: 18, color: Color(0xFF00979D)),
                      ),
                      const SizedBox(width: 12),
                      const Text("Export Data", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("Select Range", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 10),
                  // Quick range pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ['24h', 'Last 24 Hours'],
                      ['7d', 'Current Week'],
                      ['30d', 'Last 30 Days'],
                      ['custom', 'Custom Range...'],
                    ].map((r) {
                      final sel = range == r[0];
                      return GestureDetector(
                        onTap: () => setDialogState(() {
                          range = r[0];
                          if (r[0] != 'custom') { _exportStartDate = ''; _exportEndDate = ''; }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFF00979D) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? const Color(0xFF00979D) : Colors.grey[200]!),
                          ),
                          child: Text(r[1], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : Color(0xFF1E293B))),
                        ),
                      );
                    }).toList(),
                  ),
                  // Custom date pickers
                  if (range == 'custom') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _dateField("Start", _exportStartDate, (v) => _exportStartDate = v),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dateField("End", _exportEndDate, (v) => _exportEndDate = v),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  // AI Summary toggle
                  Row(
                    children: [
                      SizedBox(
                        height: 20, width: 20,
                        child: Checkbox(
                          value: includeAI,
                          activeColor: const Color(0xFF00979D),
                          onChanged: (v) => setDialogState(() => includeAI = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.auto_awesome, size: 14, color: includeAI ? const Color(0xFF00979D) : Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text("Include AI Health Summary", style: TextStyle(fontSize: 12, color: includeAI ? const Color(0xFF00979D) : Colors.grey[600], fontWeight: includeAI ? FontWeight.w600 : FontWeight.normal)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _exportRange = range;
                        _exportIncludeAI = includeAI;
                        Navigator.of(ctx).pop();
                        _generateAndDownloadCSV();
                      },
                      icon: const Icon(Icons.file_download_outlined, size: 16, color: Colors.white),
                      label: const Text("Download CSV", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00979D),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dateField(String label, String value, void Function(String) onSet) {
    final ctrl = TextEditingController(text: value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: label == "Start" ? "2026-06-01" : "2026-06-16",
            hintStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
            filled: true, fillColor: Colors.white, isDense: true,
          ),
          onChanged: onSet,
        ),
      ],
    );
  }

  Future<void> _generateAndDownloadCSV() async {
    setState(() => _exportState = 'loading');

    // Build query params
    final params = <String, String>{
      'range': _exportRange == 'custom' ? '90d' : _exportRange,
      'includeAI': _exportIncludeAI ? 'true' : 'false',
    };
    if (_exportRange == 'custom') {
      if (_exportStartDate.isNotEmpty) params['start'] = _exportStartDate;
      if (_exportEndDate.isNotEmpty) params['end'] = _exportEndDate;
    }
    final qs = params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');

    final baseUrl = Provider.of<TelemetryProvider>(context, listen: false).baseHttpUrl;
    redirectTo('$baseUrl/api/telemetry/export-excel?$qs');

    setState(() => _exportState = 'done');
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _exportState = 'idle');
  }

  // --- ZONE INFO PANEL ---
  Widget _buildGardenInfoPanel(TelemetryProvider provider) {
    if (!_gardenConfigLoaded) {
      Future.microtask(() async {
        final cfg = await provider.getGardenConfig();
        if (mounted) setState(() {
          _gardenName = cfg['name'] ?? 'Spinach Garden';
          _gardenNumber = cfg['number'] ?? '08';
          _zoneId = cfg['zoneId'] ?? 'PL-02J';
          _coverageArea = cfg['coverage'] ?? '200 m²';
          _gardenConfigLoaded = true;
        });
      });
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        provider.addTerminalLog("GARDEN CARD: pointerDown fired");
      },
      onPointerUp: (_) {
        if (_editClicked) { _editClicked = false; provider.addTerminalLog("GARDEN CARD: Edit clicked, skipping nav"); return; }
        provider.addTerminalLog("GARDEN CARD: Navigation triggered via MaterialPageRoute");
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => SpinachGardenDetailScreen(gardenName: _gardenName),
          settings: RouteSettings(name: '/garden/${_gardenName.toLowerCase().replaceAll(' ', '-')}'),
        ));
      },
      child: GlassCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 500;
            return Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.grass, color: Color(0xFF10B981)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$_gardenName $_gardenNumber",
                              softWrap: true,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "ACTIVE MONITORING ZONE",
                              softWrap: true,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (_) { _editClicked = true; },
                        onTap: () => _showGardenEditDialog(provider),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00979D).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF00979D)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoBadge("ZONE ID", _zoneId),
                      _buildInfoBadge("COVERAGE AREA", _coverageArea),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00979D).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_forward_ios, color: Color(0xFF00979D), size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDataStatusBar(TelemetryProvider provider) {
    final isLive = provider.isConnected;
    final lastTime = provider.lastMqttTime;
    final isStale = lastTime != null && DateTime.now().difference(lastTime).inSeconds > 300;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              boxShadow: [
                BoxShadow(
                  color: (isLive ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLive ? '📡 Live Data' : '🔄 Demo Mode (Sensor Offline)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isLive ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
                if (!isLive)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '⚠️ Sensor-007-G is offline. Attempting to reconnect...',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ),
                _buildNotificationBell(),
              ],
            ),
          ),
          if (lastTime != null)
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(lastTime),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: isLive ? const Color(0xFF1E293B) : Colors.grey[500],
                    ),
                  ),
                  if (isStale)
                    Text(
                      '* Simulated data',
                      style: TextStyle(fontSize: 8, color: const Color(0xFFF59E0B)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showGardenEditDialog(TelemetryProvider provider) {
    final nameCtrl = TextEditingController(text: _gardenName);
    final numCtrl = TextEditingController(text: _gardenNumber);
    final zoneCtrl = TextEditingController(text: _zoneId);
    final areaCtrl = TextEditingController(text: _coverageArea);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(20),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF00979D)),
                  ),
                  const SizedBox(width: 10),
                  const Text("Edit Zone", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 20),
              _editField("Zone Name", nameCtrl, Icons.grass_outlined),
              const SizedBox(height: 12),
              _editField("Zone Number", numCtrl, Icons.tag_outlined),
              const SizedBox(height: 12),
              _editField("Zone ID", zoneCtrl, Icons.qr_code_outlined),
              const SizedBox(height: 12),
              _editField("Coverage Area", areaCtrl, Icons.straighten_outlined),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim().isEmpty ? "Spinach Garden" : nameCtrl.text.trim();
                        final number = numCtrl.text.trim().isEmpty ? "08" : numCtrl.text.trim();
                        final zoneId = zoneCtrl.text.trim().isEmpty ? "PL-02J" : zoneCtrl.text.trim().toUpperCase();
                        final coverage = areaCtrl.text.trim().isEmpty ? "200 m²" : areaCtrl.text.trim();
                        await provider.saveGardenConfig({
                          'name': name, 'number': number,
                          'zoneId': zoneId, 'coverage': coverage,
                        });
                        setState(() {
                          _gardenName = name;
                          _gardenNumber = number;
                          _zoneId = zoneId;
                          _coverageArea = coverage;
                        });
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00979D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Save", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
        prefixIcon: Icon(icon, size: 16, color: Colors.grey[400]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildInfoBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            softWrap: true,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[500], fontSize: 8, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            softWrap: true,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.bold),
          )
        ],
      ),
    );
  }

  // --- KEY METRICS GRID ---
  Widget _buildMetricsGrid(TelemetryProvider provider, bool isDesktop) {
    final cards = [
      MetricCard(
        title: "Avg Soil Moisture",
        value: provider.soil.toStringAsFixed(0),
        unit: "%",
        icon: Icons.water_drop,
        themeColor: const Color(0xFF3B82F6),
        progress: provider.soil / 100,
        badgeText: "↑ 12%",
        subtext: "Keep monitoring to ensure it remains consistent above 40%.",
        lastUpdated: provider.lastMqttTime,
        rawValue: provider.soil,
        optimalMin: 40,
        optimalMax: 70,
      ),
      MetricCard(
        title: "Solar Panel Output",
        value: provider.v.toStringAsFixed(1),
        unit: "V",
        icon: Icons.solar_power,
        themeColor: Colors.amber[500]!,
        progress: provider.v / 6.0,
        badgeText: "↑ 0.2v",
        subtext: "Max generation efficiency reached. Battery charging normal.",
        lastUpdated: provider.lastMqttTime,
        rawValue: provider.v,
        optimalMin: 2.0,
        optimalMax: 6.0,
      ),
      MetricCard(
        title: "Ambient Temp",
        value: provider.temp.toStringAsFixed(0),
        unit: "\u00B0C",
        icon: Icons.thermostat,
        themeColor: const Color(0xFFF43F5E),
        progress: provider.temp / 50.0,
        badgeText: "↑ 1.5°",
        subtext: "Temp slightly high. Ensure shade netting is deployed.",
        lastUpdated: provider.lastMqttTime,
        rawValue: provider.temp,
        optimalMin: 18,
        optimalMax: 28,
      ),
      MetricCard(
        title: "Air Humidity",
        value: provider.humidity.toStringAsFixed(0),
        unit: "%",
        icon: Icons.opacity,
        themeColor: const Color(0xFF10B981),
        progress: provider.humidity / 100.0,
        badgeText: "↑ 3%",
        subtext: "Ambient relative humidity within safe agricultural bands.",
        lastUpdated: provider.lastMqttTime,
        rawValue: provider.humidity,
        optimalMin: 40,
        optimalMax: 80,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 4;
        if (constraints.maxWidth < 600) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1000) {
          crossAxisCount = 2;
        }
        final childWidth = (constraints.maxWidth - (crossAxisCount - 1) * 16) / crossAxisCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((card) => SizedBox(width: childWidth, child: card)).toList(),
        );
      },
    );
  }

  // --- SPLIT DASHBOARD LAYOUT ---
  Widget _buildMainSplitLayout(TelemetryProvider provider, bool isDesktop) {
    // Dynamically calculate auxiliary solar/energy details based on telemetry provider
    final solarPower = (provider.v * (provider.current / 1000.0)).clamp(0.0, 5.0); // 5W max monocrystalline
    final systemLoad = 0.8 + (provider.isPumpOn ? 2.2 : 0.0); // 0.8W idle + 2.2W pump load
    final batteryPercent = (65.0 + (provider.v / 6.0) * 30.0 - (provider.isPumpOn ? 4.0 : 0.0)).clamp(0.0, 100.0);

    final mainWidgets = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. History Spline Chart Card
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Daily Sensor Readings",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Node: ESP-WROOM-32 / Zone A",
                        style: TextStyle(color: Colors.grey[400], fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)
                            ],
                          ),
                          child: const Text("Today", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 4),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text("Week", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16),
              // Metric toggle buttons
              Row(
                children: [
                  _buildMetricToggle('moisture', '\u{1F4A7} Moisture'),
                  const SizedBox(width: 6),
                  _buildMetricToggle('temperature', '\u{1F321}\uFE0F Temp'),
                  const SizedBox(width: 6),
                  _buildMetricToggle('humidity', '\u{1F4A8} Humidity'),
                  const SizedBox(width: 6),
                  _buildMetricToggle('light', '\u{2600}\uFE0F Light'),
                ],
              ),
              const SizedBox(height: 16),
              // Render fl_chart widget
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: constraints.maxWidth < 600 ? 220 : 280,
                  child: TelemetryChart(history: provider.history, activeMetric: _activeChartMetric),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),

        // 2. Extra Grid Cards (Energy System, Env details)
        LayoutBuilder(
          builder: (context, constraints) {
            final cardsWidth = constraints.maxWidth;
            final isNarrow = cardsWidth < 600;
            
            final energyCard = Expanded(
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Energy System", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Icon(Icons.battery_5_bar, color: Color(0xFF00979D), size: 20),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            // Circular Battery Percentage Donut Indicator
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: CircularProgressIndicator(
                                    value: batteryPercent / 100.0,
                                    strokeWidth: 6,
                                    backgroundColor: Colors.black.withOpacity(0.05),
                                    color: const Color(0xFF00979D),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text("${batteryPercent.toStringAsFixed(0)}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const Text("BATTERY", style: TextStyle(fontSize: 7, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(width: 20),
                            // System loads specifications
                            Expanded(
                              child: Column(
                                children: [
                                  _buildEnergyIndicatorRow("Solar Charge", "${solarPower.toStringAsFixed(1)}W", Colors.amber[500]!, (solarPower / 5.0).clamp(0.0, 1.0)),
                                  const SizedBox(height: 12),
                                  _buildEnergyIndicatorRow("System Load", "${systemLoad.toStringAsFixed(1)}W", const Color(0xFFF43F5E), (systemLoad / 5.0).clamp(0.0, 1.0)),
                                ],
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
            
            final envCard = Expanded(
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Environment Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 16),
                        _buildEnvRow(Icons.light_mode, "Light Intensity (LDR)", "850 LUX", "Direct Sun"),
                        const SizedBox(height: 12),
                        _buildEnvRow(Icons.cloudy_snowing, "Rain Sensor Status", "CLEAR", "Analog: 1023"),
                      ],
                    ),
                  ),
                );
            
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  energyCard,
                  const SizedBox(height: 16),
                  envCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                energyCard,
                const SizedBox(width: 16),
                envCard,
              ],
            );
          },
        )
      ],
    );

    final sidebarWidgets = Column(
      children: [
        // Connected devices log list
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Connected Devices", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("3 Active", style: TextStyle(color: Color(0xFF00979D), fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const SizedBox(height: 16),
              _buildDeviceItem(Icons.water_drop, "Soil Moisture Sensor", "Capacitive Probe A", "Active Reading: ${provider.soil.toStringAsFixed(0)}%", Colors.blue, false),
              const SizedBox(height: 12),
              _buildDeviceItem(Icons.thermostat, "DHT22 Temp & Humidity", "Air Sensor Zone 1", "Temp: ${provider.temp.toStringAsFixed(1)}\u00B0C / Humidity: ${provider.humidity.toStringAsFixed(0)}%", Colors.orange, false),
              const SizedBox(height: 12),
              _buildDeviceItem(Icons.solar_power, "Solar Power Monitor", "INA219 Sensor Module", "Solar Output: ${provider.v.toStringAsFixed(2)}V / Load: ${provider.current.toStringAsFixed(0)}mA", const Color(0xFF00979D), false),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── AI FEATURE 1: Plant Health Score Card ────────────────────────────
        _buildHealthScoreCard(provider),

        const SizedBox(height: 24),

        // Serial monitor logs
        TerminalMonitor(logs: provider.terminalLogs),

        const SizedBox(height: 24),

        // ── AI FEATURE 2: Smart Irrigation Advisor ───────────────────────────
        _buildIrrigationAdvisorCard(provider),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: mainWidgets),
          const SizedBox(width: 24),
          Expanded(flex: 1, child: sidebarWidgets),
        ],
      );
    } else {
      return Column(
        children: [
          mainWidgets,
          const SizedBox(height: 24),
          sidebarWidgets,
        ],
      );
    }
  }

  Widget _buildEnergyIndicatorRow(String label, String value, Color color, double percentage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500)),
            Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(height: 4, decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(2))),
            FractionallySizedBox(
              widthFactor: percentage,
              child: Container(height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            )
          ],
        )
      ],
    );
  }

  Widget _buildEnvRow(IconData icon, String label, String value, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Icon(icon, color: const Color(0xFF00979D), size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                const SizedBox(height: 1),
                Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 9)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
              if (value == "CLEAR")
                Text("OPTIMAL", style: TextStyle(color: const Color(0xFF10B981), fontSize: 7, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDeviceItem(IconData icon, String name, String sub, String status, Color color, bool isAlert) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAlert ? Colors.red[50]!.withOpacity(0.6) : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isAlert ? Colors.red[100]! : Colors.white),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isAlert ? Colors.white : color.withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(color: isAlert ? Colors.red[100]! : Colors.transparent),
            ),
            child: Icon(icon, color: isAlert ? Colors.red : color, size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isAlert ? Colors.red[800] : const Color(0xFF1E293B)),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isAlert ? Colors.red : Colors.green,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub, softWrap: true, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: isAlert ? Colors.red[300] : Colors.grey[500], fontSize: 9)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAlert ? Colors.white : const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isAlert ? Colors.red[100]! : const Color(0xFF10B981).withOpacity(0.2)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: isAlert ? Colors.red : const Color(0xFF10B981), fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI FEATURE 1 — PLANT HEALTH SCORE CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHealthScoreCard(TelemetryProvider provider) {
    final health = provider.healthScore;
    final score = health.score;
    final color = health.dartColor;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.eco_rounded, color: color, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text('Plant Health Score',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(health.label,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Score ring
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: score / 100.0,
                        strokeWidth: 7,
                        backgroundColor: Colors.black.withOpacity(0.05),
                        color: color,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$score',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                        Text('/100', style: TextStyle(fontSize: 8, color: Colors.grey[500])),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (health.issues.isEmpty)
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: color, size: 13),
                          const SizedBox(width: 6),
                          Text('All conditions optimal', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        ],
                      )
                    else
                      ...health.issues.take(3).map((issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: color, size: 11),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(issue,
                                  style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                                  maxLines: 2),
                            ),
                          ],
                        ),
                      )),
                    if (health.tips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lightbulb_outline, color: color, size: 11),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(health.tips.first,
                                  style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
                                  maxLines: 2),
                            ),
                          ],
                        ),
                      )
                    ]
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI FEATURE 2 — SMART IRRIGATION ADVISOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIrrigationAdvisorCard(TelemetryProvider provider) {
    final advice = provider.irrigationAdvice;
    final urgencyColor = advice.urgencyColor;
    final isIrrigateNow = advice.action == 'irrigate_now';
    final isScheduled = advice.action == 'schedule_for_dusk';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.water, color: Color(0xFF00979D), size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text('Irrigation Control', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              // AI badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [const Color(0xFF00979D), const Color(0xFF02C39A)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 9),
                    SizedBox(width: 3),
                    Text('AI Advisor', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Recommendation chip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: urgencyColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: urgencyColor.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(advice.actionIcon, color: urgencyColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(advice.actionLabel,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: urgencyColor)),
                      const SizedBox(height: 3),
                      Text(advice.reason,
                          style: TextStyle(fontSize: 10, color: Colors.grey[700], height: 1.4),
                          maxLines: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Manual override pump toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Water Pump Relay',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                    Text('GPIO 23 / Manual override',
                        style: TextStyle(color: Colors.grey[500], fontSize: 9)),
                  ],
                ),
                Row(
                  children: [
                    if (isIrrigateNow && !provider.isPumpOn)
                      GestureDetector(
                        onTap: () => provider.togglePump(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: urgencyColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Follow AI',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    Switch(
                      value: provider.isPumpOn,
                      activeColor: const Color(0xFF00979D),
                      onChanged: (_) => provider.togglePump(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI CHAT — Opens as Modal Bottom Sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _openAIChat(TelemetryProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RootWiseAssistantSheet(
        gardenName: _gardenName,
      ),
    );
  }

  // --- MOBILE BOTTOM NAV BAR ---
  Widget _buildMobileBottomNavBar(TelemetryProvider provider) {
    final size = MediaQuery.of(context).size;
    final isVeryNarrow = size.width < 600;

    return GlassCard(
      borderRadius: 0,
      padding: EdgeInsets.symmetric(vertical: isVeryNarrow ? 6 : 8),
      borderOpacity: 0.1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMobileNavItem(0, Icons.pie_chart_outline, isVeryNarrow ? "" : "Home", isVeryNarrow),
          _buildMobileNavItem(1, Icons.solar_power_outlined, isVeryNarrow ? "" : "Power", isVeryNarrow),
          _buildMobileNavItem(2, Icons.grass_outlined, isVeryNarrow ? "" : "Soil", isVeryNarrow),
          _buildMobileNavItem(3, Icons.history_outlined, isVeryNarrow ? "" : "Logs", isVeryNarrow),
          _buildMobileNavItem(4, Icons.settings_outlined, isVeryNarrow ? "" : "Settings", isVeryNarrow),
          InkWell(
            onTap: () => _handleLogout(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.logout, color: Color(0xFFEF4444), size: 20),
                const SizedBox(height: 2),
                if (!isVeryNarrow)
                  const Text("Logout", style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNavItem(int idx, IconData icon, String label, bool veryNarrow) {
    final isSel = _activeNavIndex == idx;
    return InkWell(
      onTap: () => setState(() => _activeNavIndex = idx),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSel ? const Color(0xFF00979D) : Colors.grey, size: veryNarrow ? 22 : 20),
          const SizedBox(height: 2),
          if (label.isNotEmpty)
            Text(
              label,
              style: TextStyle(color: isSel ? const Color(0xFF00979D) : Colors.grey, fontSize: 9, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  // --- SUB-DASHBOARD PAGE ROUTER ---
  Widget _buildActiveBody(TelemetryProvider provider, bool isDesktop) {
    switch (_activeNavIndex) {
      case 0:
        return _buildOverviewDashboard(provider, isDesktop);
      case 1: // Solar Power yield sub-dashboard
        return _buildSolarPowerDashboard(provider, isDesktop);
      case 2: // Soil & Environment sub-dashboard
        return _buildSoilAndEnvironmentDashboard(provider, isDesktop);
      case 3: // Data Logs sub-dashboard
        return _buildDataLogsDashboard(provider, isDesktop);
      case 4: // Sensor Config & Invoice sub-dashboard
        return _buildSensorConfigDashboard(provider, isDesktop);
      case 5: // Settings
        return _buildSettingsDashboard(provider, isDesktop);
      default:
        return _buildOverviewDashboard(provider, isDesktop);
    }
  }

  Widget _buildOverviewDashboard(TelemetryProvider provider, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting & Quick Actions (Desktop only)
        if (isDesktop) _buildDashboardHeader(),
        
        const SizedBox(height: 16),

        // Active Garden Monitoring Zone Panel
        _buildGardenInfoPanel(provider),

        const SizedBox(height: 12),

        // Data source indicator + timestamp
        _buildDataStatusBar(provider),

        const SizedBox(height: 24),

        // Grid of 4 Key Indicators
        _buildMetricsGrid(provider, isDesktop),

        const SizedBox(height: 24),

        // Complex split layout (Chart / Device Control status columns)
        _buildMainSplitLayout(provider, isDesktop),
        
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSolarPowerDashboard(TelemetryProvider provider, bool isDesktop) {
    final voltage = provider.v;
    
    // Dynamically calculate auxiliary solar details to present state-of-the-art telemetry
    // Simulated load matching expected 6V/5W monocrystalline specifications
    final currentMA = voltage > 0.5 ? (voltage / 6.0) * 800 + (math.Random().nextDouble() * 15 - 7) : 0.0;
    final powerWatts = (voltage * (currentMA / 1000.0)).clamp(0.0, 5.0);
    final efficiency = ((voltage / 6.0) * 100.0).clamp(0.0, 100.0);
    
    // Battery state based on panel output
    final isCharging = voltage > 3.4;
    final batteryPercent = (80.0 + (voltage / 6.0) * 18.0).clamp(0.0, 100.0);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Solar Power Yield",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  "Real-time solar panel outputs and power management logs",
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isCharging ? const Color(0xFF10B981).withOpacity(0.1) : Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCharging ? const Color(0xFF10B981).withOpacity(0.3) : Colors.amber.withOpacity(0.3)
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCharging ? Icons.bolt_outlined : Icons.wb_sunny_outlined, 
                    size: 14, 
                    color: isCharging ? const Color(0xFF10B981) : Colors.amber[700]
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCharging ? "BATTERY CHARGING" : "BATTERY STANDBY",
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.bold, 
                      color: isCharging ? const Color(0xFF10B981) : Colors.amber[700]
                    ),
                  )
                ],
              ),
            )
          ],
        ),
        
        const SizedBox(height: 24),

        // Power Trend Charts (replaces static stat cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;

            final history = provider.history;
            final recent = history.length > 30 ? history.sublist(history.length - 30) : history;
            final hasData = recent.length >= 2;

            List<FlSpot> buildTrendSpots() {
              return List.generate(recent.length, (i) {
                final r = recent[i];
                final cur = r.v > 0.5 ? (r.v / 6.0) * 800 : 0.0;
                final watts = (r.v * (cur / 1000.0)).clamp(0.0, 5.0);
                return FlSpot(i.toDouble(), watts);
              });
            }

            List<FlSpot> buildBatterySpots() {
              return List.generate(recent.length, (i) {
                final r = recent[i];
                final base = 80.0 + (r.v / 6.0) * 18.0;
                return FlSpot(i.toDouble(), base.clamp(0, 100));
              });
            }

            final spots = hasData ? buildTrendSpots() : <FlSpot>[];
            final batterySpots = hasData ? buildBatterySpots() : <FlSpot>[];

            String timeLabel(int i) {
              final t = recent[i].time;
              return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
            }

            final trendChart = GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.trending_up, size: 16, color: Color(0xFFF97316)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Solar Power Generation Trend", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          Text("${powerWatts.toStringAsFixed(2)}W now", style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: !hasData
                        ? Center(child: Text("No history data yet", style: TextStyle(fontSize: 11, color: Colors.grey[400])))
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: 1,
                                getDrawingHorizontalLine: (v) => FlLine(
                                  color: Colors.grey[200]!,
                                  strokeWidth: 0.5,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 26,
                                    interval: 1,
                                    getTitlesWidget: (value, meta) {
                                      if (value == 0 || value == 2.5 || value == 5) {
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Text("${value.toInt()}W", style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: Colors.grey[400])),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 16,
                                    getTitlesWidget: (value, meta) {
                                      final i = value.toInt();
                                      if (i >= 0 && i < recent.length && (i == 0 || i == recent.length - 1 || (recent.length > 4 && i == recent.length ~/ 2))) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(timeLabel(i), style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: Colors.grey[400])),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: const Color(0xFFF97316),
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFFF97316).withOpacity(0.08),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            );

            final batteryChart = GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.battery_charging_full, size: 16, color: Color(0xFF10B981)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Battery Charge / Discharge", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          Text("${batteryPercent.toStringAsFixed(0)}% capacity", style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: !hasData
                        ? Center(child: Text("No history data yet", style: TextStyle(fontSize: 11, color: Colors.grey[400])))
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: 20,
                                getDrawingHorizontalLine: (v) => FlLine(
                                  color: Colors.grey[200]!,
                                  strokeWidth: 0.5,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 26,
                                    interval: 20,
                                    getTitlesWidget: (value, meta) {
                                      if (value == 0 || value == 50 || value == 100) {
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Text("${value.toInt()}%", style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: Colors.grey[400])),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 16,
                                    getTitlesWidget: (value, meta) {
                                      final i = value.toInt();
                                      if (i >= 0 && i < recent.length && (i == 0 || i == recent.length - 1 || (recent.length > 4 && i == recent.length ~/ 2))) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(timeLabel(i), style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: Colors.grey[400])),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              minY: 0,
                              maxY: 100,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: batterySpots,
                                  isCurved: true,
                                  color: const Color(0xFF10B981),
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFF10B981).withOpacity(0.08),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            );

            if (isNarrow) {
              return Column(
                children: [trendChart, const SizedBox(height: 16), batteryChart],
              );
            }
            return Row(
              children: [
                Expanded(child: trendChart),
                const SizedBox(width: 16),
                Expanded(child: batteryChart),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Double column split layout: Live Intensity Gauge & Specifications Panel
        LayoutBuilder(
          builder: (context, constraints) {
            final column1 = Column(
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Solar Peak Intensity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 16),
                      
                      // Refined gradient progress bar with tick marks
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          return SizedBox(
                            height: 32,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(child: Container(color: Colors.grey[100])),
                                        Expanded(child: Container(color: Colors.grey[50])),
                                        Expanded(child: Container(color: Colors.grey[100])),
                                        Expanded(child: Container(color: Colors.grey[50])),
                                      ],
                                    ),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: (efficiency / 100.0).clamp(0.0, 1.0),
                                  child: Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFBBF24), Color(0xFFF97316), Color(0xFFEA580C)],
                                        stops: [0.0, 0.6, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                // Tick marks at 25%, 50%, 75%
                                ...([0.25, 0.5, 0.75]).map((pct) {
                                  final filled = (efficiency / 100.0) > pct;
                                  return Positioned(
                                    left: w * pct - 0.5,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 1,
                                      height: 32,
                                      color: filled ? Colors.white.withOpacity(0.5) : Colors.grey[300],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            efficiency < 30
                                ? "Overcast / Dusk (Low Yield)"
                                : (efficiency < 75 ? "Partial Sun (Charging)" : "Direct Sunlight (Peak Generation)"),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                          ),
                          Text(
                            "${efficiency.toStringAsFixed(0)}% Intensity",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Battery Storage Management", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.battery_charging_full_outlined, 
                            size: 44, 
                            color: isCharging ? const Color(0xFF10B981) : const Color(0xFF3B82F6)
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Capacity: ${batteryPercent.toStringAsFixed(0)}%",
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isCharging 
                                      ? "Receiving +${powerWatts.toStringAsFixed(2)}W of power from Solar array" 
                                      : "Panel output low. Operating on local LiFePO4 battery pack",
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                )
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ],
            );

            final column2 = GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Solar Node Hardware Specs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                  const Divider(color: Colors.black12),
                  const SizedBox(height: 12),
                  
                  _buildSpecRow("Panel Model", "Spinach-Solar Micro-Node A"),
                  _buildSpecRow("Photovoltaic Type", "Monocrystalline Silicon"),
                  _buildSpecRow("Peak Capacity", "6.0 Volts / 5 Watts max"),
                  _buildSpecRow("Power Controller", "ESP32 MPPT Simulated Regulator"),
                  _buildSpecRow("Battery Pack Type", "LiFePO4 3.2V / 1200mAh Cell"),
                  _buildSpecRow("Node Load Profile", "120 mA (ESP32 active telemetry sleep cycles)"),
                  
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00979D).withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Color(0xFF00979D)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Monocrystalline cells offer top-tier photoelectric conversion under partial shade conditions.",
                            style: TextStyle(fontSize: 10, color: Color(0xFF00979D), height: 1.4),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );

            if (constraints.maxWidth > 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: column1),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: column2),
                ],
              );
            } else {
              return Column(
                children: [
                  column1,
                  const SizedBox(height: 16),
                  column2,
                ],
              );
            }
          },
        ),
        
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, softWrap: true, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(value, softWrap: true, textAlign: TextAlign.end, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorHistoryCharts(TelemetryProvider provider) {
    final hist = provider.history;
    final recent = hist.length > 20 ? hist.sublist(hist.length - 20) : hist;
    if (recent.length < 2) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text("Collecting historical data...", style: TextStyle(fontSize: 12, color: Colors.grey[400]))),
      );
    }

    double maxVal(List<double> vals) => vals.reduce((a, b) => a > b ? a : b);

    List<({String label, Color color, IconData icon, List<FlSpot> spots, double maxY, String latest})> charts = [
      (label: 'Soil Moisture', color: const Color(0xFF3B82F6), icon: Icons.water_drop, spots: List.generate(recent.length, (i) => FlSpot(i.toDouble(), recent[i].soil)), maxY: 100, latest: '${recent.last.soil.toStringAsFixed(0)}%'),
      (label: 'Ambient Temp', color: const Color(0xFFF43F5E), icon: Icons.thermostat, spots: List.generate(recent.length, (i) => FlSpot(i.toDouble(), recent[i].temp)), maxY: 50, latest: '${recent.last.temp.toStringAsFixed(1)}°C'),
      (label: 'Air Humidity', color: const Color(0xFF10B981), icon: Icons.opacity, spots: List.generate(recent.length, (i) => FlSpot(i.toDouble(), recent[i].humidity)), maxY: 100, latest: '${recent.last.humidity.toStringAsFixed(0)}%'),
      (label: 'Solar Voltage', color: const Color(0xFFF97316), icon: Icons.solar_power, spots: List.generate(recent.length, (i) => FlSpot(i.toDouble(), recent[i].v)), maxY: 6, latest: '${recent.last.v.toStringAsFixed(2)}V'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final items = charts.map((c) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 24, height: 24, decoration: BoxDecoration(color: c.color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Icon(c.icon, size: 12, color: c.color)),
                    const SizedBox(width: 6),
                    Text(c.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                    const Spacer(),
                    Text(c.latest, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.color)),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: LineChart(LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    minX: 0, maxX: (c.spots.length - 1).toDouble(), minY: 0, maxY: c.maxY,
                    lineBarsData: [LineChartBarData(spots: c.spots, isCurved: true, color: c.color, barWidth: 1.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: c.color.withOpacity(0.08)))],
                  )),
                ),
              ],
            ),
          ),
        )).toList();

        if (isNarrow) {
          return Column(
            children: [
              Row(children: items.take(2).toList()),
              const SizedBox(height: 12),
              Row(children: items.skip(2).toList()),
            ],
          );
        }
        return Row(children: items);
      },
    );
  }

  Widget _buildSoilAndEnvironmentDashboard(TelemetryProvider provider, bool isDesktop) {
    final soilMoisture = provider.soil;
    final temp = provider.temp;
    final humidity = provider.humidity;
    final current = provider.current;
    
    // Soil moisture classifications
    final isWaterlogged = soilMoisture > 70;
    final isDry = soilMoisture < 30;
    final isOptimal = !isWaterlogged && !isDry;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Soil & Env Analytics",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  "Real-time environment reading from Capacitive Soil Probe, DHT22 & INA219",
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOptimal ? const Color(0xFF10B981).withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOptimal ? const Color(0xFF10B981).withOpacity(0.3) : Colors.red.withOpacity(0.3)
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOptimal ? Icons.check_circle_outline : Icons.warning_amber_outlined, 
                    size: 14, 
                    color: isOptimal ? const Color(0xFF10B981) : Colors.red[700]
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOptimal ? "OPTIMAL HUMUS" : (isDry ? "DESICCATION RISK" : "SATURATION ALARM"),
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.bold, 
                      color: isOptimal ? const Color(0xFF10B981) : Colors.red[700]
                    ),
                  )
                ],
              ),
            )
          ],
        ),
        
        const SizedBox(height: 24),

        Text("Crop Thresholds", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text("$_gardenName $_gardenNumber · $_zoneId · Spinacia oleracea",
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _thresholdBar("Temperature", "18–28°C", "<18°C or >32°C", provider.temp, 18, 28, Icons.thermostat_outlined, "°C")),
            const SizedBox(width: 16),
            Expanded(child: _thresholdBar("Soil Moisture", "40–70%", "<20% or >85%", provider.soil, 40, 70, Icons.water_drop_outlined, "%")),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _thresholdBar("Humidity", "40–80%", "<35% or >90%", provider.humidity, 40, 80, Icons.cloud_outlined, "%")),
            const SizedBox(width: 16),
            Expanded(child: _thresholdBar("Solar Voltage", ">2.0V", "<1.0V", provider.v, 2.0, 5.5, Icons.solar_power_outlined, "V")),
          ],
        ),
        const SizedBox(height: 24),

        // 4 Mini Historical Trend Charts
        _buildSensorHistoryCharts(provider),

        const SizedBox(height: 24),

        // Interactive Spectrum, Texture Diagnostics
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final column1 = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("DHT22 Ambient Humidity Spectrum", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Text("Typical crops thrive between 30% and 65% relative air humidity.", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 16),
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                            colors: [Colors.amber, Color(0xFF10B981), Colors.blueAccent],
                          ),
                        ),
                      ),
                      LayoutBuilder(
                        builder: (ctx, con) {
                          final pct = (humidity / 100.0).clamp(0.0, 1.0);
                          return Row(
                            children: [
                              SizedBox(width: (con.maxWidth * pct - 8).clamp(0.0, con.maxWidth - 16)),
                              const Icon(Icons.arrow_drop_up, color: Color(0xFF1E293B), size: 16),
                            ],
                          );
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            humidity < 35 ? "Dry (transpiration strain)" : (humidity < 70 ? "Optimal Comfort Zone" : "Saturated Air"),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                          ),
                          Text("Current: ${humidity.toStringAsFixed(0)}% RH", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF00979D))),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Physical Hardware Sensor Diagnostic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.developer_board, size: 40, color: Color(0xFF00979D)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Physical Microprocessor: ESP32 DevKit V1", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                const SizedBox(height: 4),
                                Text("DHT22 sensor reads temperature & humidity on Pin GPIO 4. Capacitive soil probe uses Pin GPIO 36 (ADC1) to bypass chemical electrode corrosion.", style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.4)),
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ],
            );

            final column2 = GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Active Telemetry Parameters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                  const Divider(color: Colors.black12),
                  const SizedBox(height: 12),
                  _buildSpecRow("Capacitive soil pin", "GPIO 36 (ADC1)"),
                  _buildSpecRow("DHT22 Sensor Pin", "GPIO 4"),
                  _buildSpecRow("INA219 I2C SDA", "GPIO 21"),
                  _buildSpecRow("INA219 I2C SCL", "GPIO 22"),
                  _buildSpecRow("LM2596 Regulator input", "6.0V (Solar panel)"),
                  _buildSpecRow("LM2596 stable output", "5.0V (AA batteries charge)"),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00979D).withOpacity(0.1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Color(0xFF00979D)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Using the LM2596 board allows stepping down 6V solar input to a safe 5V for battery charging.",
                            style: TextStyle(fontSize: 10, color: Color(0xFF00979D), height: 1.4),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: column1),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: column2),
                ],
              );
            } else {
              return Column(
                children: [
                  column1,
                  const SizedBox(height: 16),
                  column2,
                ],
              );
            }
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }


  Widget _buildSensorConfigDashboard(TelemetryProvider provider, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Hardware & Sensor Config",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  "ESP32 Pin mappings, sensor calibration offsets, and component bill-of-materials",
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00979D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00979D).withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal_outlined, size: 14, color: Color(0xFF00979D)),
                  SizedBox(width: 4),
                  Text(
                    "FIRMWARE V2.4",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00979D)),
                  )
                ],
              ),
            )
          ],
        ),
        
        const SizedBox(height: 24),

        // MQTT Connection Monitoring
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi_tethering_outlined, color: Color(0xFF00979D), size: 20),
                  const SizedBox(width: 10),
                  Text("$_gardenName $_gardenNumber · MQTT Link",
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.swap_horiz_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 10),
                  Text("MQTT Broker", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isMqttConnected ? const Color(0xFF10B981) : Colors.redAccent,
                      boxShadow: provider.isMqttConnected
                          ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 4)]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text("broker.emqx.io:1883",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                ],
              ),
              const Divider(color: Colors.black12, height: 20),
              Row(
                children: [
                  Icon(Icons.inbox_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 10),
                  Text("Packets Received", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const Spacer(),
                  Text("${provider.mqttPacketCount}",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                ],
              ),
              const Divider(color: Colors.black12, height: 20),
              Row(
                children: [
                  Icon(Icons.access_time_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 10),
                  Text("Last Packet", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const Spacer(),
                  Text(
                    provider.lastMqttTime != null
                        ? _formatTime(provider.lastMqttTime!)
                        : "---",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: provider.lastMqttTime != null && DateTime.now().difference(provider.lastMqttTime!).inSeconds < 120
                            ? const Color(0xFF10B981)
                            : Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Split Layout: Pin config table vs node specs — responsive via LayoutBuilder
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 860;

            final nodeSpecsCard = GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Node Specifications", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      Icon(Icons.memory_outlined, color: Color(0xFF00979D), size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("Physical device properties and operating parameters", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const Divider(color: Colors.black12),
                  const SizedBox(height: 12),
                  _buildSpecRow("Microcontroller", "ESP32-WROOM-32E"),
                  _buildSpecRow("ADC Resolution", "12-bit (0 - 4095)"),
                  _buildSpecRow("I2C Protocol Address", "0x40 (INA219)"),
                  _buildSpecRow("LoRa Transceiver Module", "RFM95W (868 MHz)"),
                  _buildSpecRow("Battery Storage", "4x Mignon AA NiMH"),
                  _buildSpecRow("Voltage Step-Down", "LM2596 Regulator"),
                  _buildSpecRow("Peak Solar Rating", "5 Watts (6V Monocrystalline)"),
                  const Divider(color: Colors.black12),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Node Operating State", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                      Text("ACTIVE TELEMETRY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF10B981))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00979D).withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00979D).withOpacity(0.1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Color(0xFF00979D)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Hardware node operates on a cyclic 15-minute deep sleep window to optimize power storage yield.",
                            style: TextStyle(fontSize: 10, color: Color(0xFF00979D), height: 1.4),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );

            final leftColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("ESP32 Sensor Pin Connections", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Text("Active GPIO configurations and protocol buses on the microprocessor board", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 48,
                          columns: const [
                            DataColumn(label: Text("Component", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text("GPIO Pin", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text("Protocol", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text("Voltage Supply", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                          rows: [
                            _buildPinConfigRow("Capacitive Soil Moisture", "GPIO 36 (ADC1)", "Analog Input", "3.3V (VCC)"),
                            _buildPinConfigRow("DHT22 Temp & Humidity", "GPIO 4", "One-Wire Digital", "3.3V (VCC)"),
                            _buildPinConfigRow("INA219 Current Breakout", "GPIO 21 (SDA) / 22 (SCL)", "I2C Bus (0x40)", "3.3V (VCC)"),
                            _buildPinConfigRow("Solar Panel Monocrystalline", "LM2596 Regulator IN", "V-Solar Feed", "6.0V Peak"),
                            _buildPinConfigRow("LM2596 Regulator Board", "Battery Clip Input", "DC-DC Step Down", "5.0V Regulated"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Sensor Software Calibration Coefficients", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                      const Divider(color: Colors.black12),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildCalibrationField("Soil Dry Value (ADC)", "3200", "Sensor in open air")),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCalibrationField("Soil Wet Value (ADC)", "1100", "Sensor fully immersed")),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildCalibrationField("INA219 Shunt Resistor", "0.1 Ω", "Current board resistor size")),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCalibrationField("INA219 Max Expected Current", "833 mA", "Matches 5W solar peak capacity")),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: leftColumn),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: nodeSpecsCard),
                ],
              );
            } else {
              return Column(
                children: [
                  leftColumn,
                  const SizedBox(height: 16),
                  nodeSpecsCard,
                ],
              );
            }
          },
        ),
        
        const SizedBox(height: 80),
      ],
    );
  }

  DataRow _buildPinConfigRow(String sensor, String pin, String protocol, String power) {
    return DataRow(
      cells: [
        DataCell(Text(sensor, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
        DataCell(Text(pin, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueAccent))),
        DataCell(Text(protocol, style: const TextStyle(fontSize: 11))),
        DataCell(Text(power, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)))),
      ],
    );
  }

  Widget _buildCalibrationField(String label, String value, String helper) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF00979D), fontWeight: FontWeight.bold)),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(helper, style: TextStyle(fontSize: 9, color: Colors.grey[400])),
      ],
    );
  }

  Widget _buildDataLogsDashboard(TelemetryProvider provider, bool isDesktop) {
    final history = provider.history;
    
    // Filter history in real-time by status alerts and query strings
    final filteredHistory = history.where((reading) {
      // 1. Status Alert Filter
      final isDry = reading.soil < 30;
      final isHot = reading.temp > 35;
      final hasAlert = isDry || isHot;
      
      if (_selectedStatusFilter != "All") {
        if (_selectedStatusFilter == "Optimal" && hasAlert) return false;
        if (_selectedStatusFilter == "Dry" && !isDry) return false;
        if (_selectedStatusFilter == "Hot" && !isHot) return false;
        if (_selectedStatusFilter == "Alerts" && !hasAlert) return false;
      }
      
      // 2. Search Query Text Filter
      if (_logSearchQuery.isNotEmpty) {
        final timeStr = "${reading.time.year}-${reading.time.month.toString().padLeft(2, '0')}-${reading.time.day.toString().padLeft(2, '0')} ${reading.time.hour.toString().padLeft(2, '0')}:${reading.time.minute.toString().padLeft(2, '0')}:${reading.time.second.toString().padLeft(2, '0')}";
        return timeStr.contains(_logSearchQuery);
      }
      
      return true;
    }).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Database Logs",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  "Time-stamped history fetched from InfluxDB bucket 'solarsoil'",
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => provider.fetchHistory(range: _selectedTimeFilter),
              icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
              label: const Text("Refresh DB", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00979D),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _exportState == 'loading' ? null : () => _showExportDialog(),
              icon: Icon(
                _exportState == 'done' ? Icons.check_circle_outlined : (_exportState == 'loading' ? Icons.hourglass_top : Icons.download),
                size: 16,
                color: _exportState == 'done' ? const Color(0xFF10B981) : (_exportState == 'loading' ? Colors.grey : const Color(0xFF00979D)),
              ),
              label: Text(
                _exportState == 'done' ? "Exported!" : (_exportState == 'loading' ? "Compiling Records..." : "Export CSV"),
                style: TextStyle(color: _exportState == 'done' ? const Color(0xFF10B981) : (_exportState == 'loading' ? Colors.grey : const Color(0xFF1E293B))),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _exportState == 'done' ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.8),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _exportState == 'done' ? const Color(0xFF10B981).withOpacity(0.3) : Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Summary Bar Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            final totalLogsCard = _buildStatSummaryCard(
              "Total Logs",
              (_logSearchQuery.isEmpty && _selectedStatusFilter == "All")
                  ? "${history.length} records"
                  : "${filteredHistory.length} of ${history.length} match",
              Icons.analytics_outlined,
              const Color(0xFF3B82F6),
              bgColor: const Color(0xFFEFF6FF),
            );
            final lastSyncCard = _buildStatSummaryCard(
              "Last Sync",
              history.isNotEmpty
                  ? "${history.last.time.hour.toString().padLeft(2, '0')}:${history.last.time.minute.toString().padLeft(2, '0')}:${history.last.time.second.toString().padLeft(2, '0')}"
                  : "N/A",
              Icons.schedule_outlined,
              const Color(0xFF10B981),
              bgColor: const Color(0xFFE0F2F1),
            );
            if (isNarrow) {
              return Column(
                children: [
                  totalLogsCard,
                  const SizedBox(height: 12),
                  lastSyncCard,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: totalLogsCard),
                const SizedBox(width: 16),
                Expanded(child: lastSyncCard),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Dynamic Filtering & Dropdown Selector Controls Bar
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Search Input Box
            SizedBox(
              width: isDesktop ? 300 : double.infinity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey[400], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (val) => setState(() => _logSearchQuery = val),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                        decoration: InputDecoration(
                          hintText: "Search timestamp...",
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Status Select Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedStatusFilter,
                  icon: Icon(Icons.arrow_drop_down, color: Colors.grey[500], size: 20),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                  onChanged: (String? newVal) {
                    if (newVal != null) {
                      setState(() => _selectedStatusFilter = newVal);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: "All", child: Text("All Statuses")),
                    DropdownMenuItem(value: "Optimal", child: Text("Optimal Only")),
                    DropdownMenuItem(value: "Dry", child: Text("Low Moisture Alerts")),
                    DropdownMenuItem(value: "Hot", child: Text("High Temp Alerts")),
                    DropdownMenuItem(value: "Alerts", child: Text("Alarms Only")),
                  ],
                ),
              ),
            ),

            // Time Window Duration Dropdown (Triggers backend InfluxDB query)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTimeFilter,
                  icon: Icon(Icons.arrow_drop_down, color: Colors.grey[500], size: 20),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                  onChanged: (String? newVal) {
                    if (newVal != null) {
                      setState(() => _selectedTimeFilter = newVal);
                      provider.fetchHistory(range: newVal);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: "10m", child: Text("Last 10 Min")),
                    DropdownMenuItem(value: "30m", child: Text("Last 30 Min")),
                    DropdownMenuItem(value: "1h", child: Text("Last 1 Hour")),
                    DropdownMenuItem(value: "24h", child: Text("Last 24 Hours")),
                    DropdownMenuItem(value: "7d", child: Text("Last 7 Days")),
                    DropdownMenuItem(value: "30d", child: Text("Last 30 Days")),
                    DropdownMenuItem(value: "90d", child: Text("Last 3 Months")),
                  ],
                ),
              ),
            ),

            // Reset Filters Button
            if (_logSearchQuery.isNotEmpty || _selectedStatusFilter != "All" || _selectedTimeFilter != "24h")
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _logSearchQuery = "";
                    _selectedStatusFilter = "All";
                    _selectedTimeFilter = "24h";
                  });
                  provider.fetchHistory(range: "24h");
                },
                icon: const Icon(Icons.clear, size: 14, color: Colors.redAccent),
                label: const Text(
                  "Reset",
                  style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)
                ),
                )
              ],
            ),
        const SizedBox(height: 24),

        // Table Panel Card
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text("Time-Series Telemetry Table", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
              ),
              const Divider(color: Colors.black12),
              const SizedBox(height: 12),
              
              if (filteredHistory.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Text(
                      "No records match your active search filters.",
                      style: const TextStyle(color: Colors.grey, fontSize: 13)
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: isDesktop ? 48 : 16,
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 36,
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey[200]!, width: 0.5),
                      bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
                    ),
                    headingRowColor: WidgetStateProperty.all(Colors.grey[50]),
                    columns: const [
                      DataColumn(label: Text("", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("TIMESTAMP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("TEMP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("SOIL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("SOLAR V", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("HUMIDITY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("CURRENT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                      DataColumn(label: Text("STATUS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF94A3B8)))),
                    ],
                    rows: filteredHistory.reversed.map((reading) {
                      final timeStr = "${reading.time.year}-${reading.time.month.toString().padLeft(2, '0')}-${reading.time.day.toString().padLeft(2, '0')} ${reading.time.hour.toString().padLeft(2, '0')}:${reading.time.minute.toString().padLeft(2, '0')}:${reading.time.second.toString().padLeft(2, '0')}";

                      final isDry = reading.soil < 30;
                      final isHot = reading.temp > 35;
                      final hasAlert = isDry || isHot;

                      Color dotColor;
                      if (hasAlert) {
                        dotColor = isDry ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
                      } else {
                        dotColor = const Color(0xFF22C55E);
                      }

                      return DataRow(
                        cells: [
                          DataCell(
                            Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(timeStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF475569)))),
                          DataCell(Text("${reading.temp.toStringAsFixed(1)}\u00B0C", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)))),
                          DataCell(Text("${reading.soil.toStringAsFixed(0)}%", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)))),
                          DataCell(Text("${reading.v.toStringAsFixed(2)}V", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)))),
                          DataCell(Text("${reading.humidity.toStringAsFixed(0)}%", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)))),
                          DataCell(Text("${reading.current.toStringAsFixed(0)}mA", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hasAlert ? Colors.red[50] : const Color(0xFF22C55E).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                hasAlert ? (isDry ? "LOW MOISTURE" : "HIGH TEMP") : "OPTIMAL",
                                style: TextStyle(
                                  color: hasAlert ? Colors.red[700] : const Color(0xFF16A34A),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            )
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSettingsDashboard(TelemetryProvider provider, bool isDesktop) {
    if (!_aiConfigLoaded) {
      Future.microtask(() => _loadAIConfig(provider));
    }
    if (!_aiMetricsLoaded) {
      Future.microtask(() { _loadAIMetrics(provider); _startMetricsPolling(provider); });
    }
    final providers = ['gemini', 'openrouter', 'ollama', 'nvidia'];
    final providerLabels = {'gemini': 'Google Gemini', 'openrouter': 'OpenRouter', 'ollama': 'Ollama (Local)', 'nvidia': 'NVIDIA AI'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Settings", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text("Configure your system preferences and connections",
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: isDesktop ? 320 : double.infinity,
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_outlined, color: Color(0xFF00979D), size: 20),
                        const SizedBox(width: 10),
                        const Text("AI Model",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Provider dropdown
                    Row(
                      children: [
                        Icon(Icons.cloud_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("Provider", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: PopupMenuButton<String>(
                            initialValue: _aiProvider,
                            offset: const Offset(0, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 4,
                            color: Colors.white,
                            onSelected: (v) => setState(() => _aiProvider = v),
                            itemBuilder: (_) => providers.map((p) {
                              final sel = p == _aiProvider;
                              return PopupMenuItem<String>(
                                value: p,
                                height: 36,
                                child: Row(
                                  children: [
                                    Icon(_providerIcon(p), size: 15, color: sel ? const Color(0xFF00979D) : Colors.grey[600]),
                                    const SizedBox(width: 10),
                                    Text(providerLabels[p] ?? p,
                                      style: TextStyle(fontSize: 12,
                                        color: sel ? const Color(0xFF00979D) : const Color(0xFF1E293B),
                                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                      )),
                                    if (sel) ...[const Spacer(), const Icon(Icons.check, size: 14, color: Color(0xFF00979D))],
                                  ],
                                ),
                              );
                            }).toList(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_providerIcon(_aiProvider), size: 14, color: const Color(0xFF00979D)),
                                const SizedBox(width: 6),
                                Text(providerLabels[_aiProvider] ?? _aiProvider,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                                Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[500]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    // API Key — read-only badge if saved, editable field otherwise
                    Row(
                      children: [
                        Icon(Icons.vpn_key_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("API Key", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        if (_aiHasSavedKey && !_aiEditingKey)
                          GestureDetector(
                            onTap: () => setState(() => _aiEditingKey = true),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00979D).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF00979D).withOpacity(0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock_outlined, size: 12, color: Color(0xFF00979D)),
                                  const SizedBox(width: 6),
                                  Text(_aiKeyMasked, style: const TextStyle(fontSize: 11, color: Color(0xFF00979D), fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  Text("change", style: TextStyle(fontSize: 9, color: Colors.grey[500], decoration: TextDecoration.underline)),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: 160,
                            height: 32,
                            child: TextField(
                              controller: _aiApiKeyController,
                              obscureText: !_aiKeyVisible,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
                                filled: true, fillColor: Colors.white,
                                isDense: true,
                                suffixIcon: GestureDetector(
                                  onTap: () => setState(() => _aiKeyVisible = !_aiKeyVisible),
                                  child: Icon(_aiKeyVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14, color: Colors.grey[400]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    // Model name — dropdown matching provider style
                    Row(
                      children: [
                        Icon(Icons.model_training_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("Model", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: PopupMenuButton<String>(
                            initialValue: _aiModelController.text,
                            offset: const Offset(0, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 4,
                            color: Colors.white,
                            onSelected: (v) => setState(() => _aiModelController.text = v),
                            itemBuilder: (_) {
                              final models = _modelOptions(_aiProvider);
                              return models.map((m) {
                                final sel = m == _aiModelController.text;
                                return PopupMenuItem<String>(
                                  value: m,
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Icon(Icons.smart_toy_outlined, size: 14, color: sel ? const Color(0xFF00979D) : Colors.grey[400]),
                                      const SizedBox(width: 8),
                                      Text(m, style: TextStyle(fontSize: 12, color: sel ? const Color(0xFF00979D) : const Color(0xFF1E293B), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                                      if (sel) ...[const Spacer(), const Icon(Icons.check, size: 14, color: Color(0xFF00979D))],
                                    ],
                                  ),
                                );
                              }).toList();
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_aiModelController.text.isNotEmpty ? _aiModelController.text : (_aiProvider == 'gemini' ? 'gemini-2.5-flash' : _aiProvider == 'ollama' ? 'llama3.2' : 'auto'),
                                    style: TextStyle(fontSize: 12, color: _aiModelController.text.isNotEmpty ? const Color(0xFF1E293B) : Colors.grey[400])),
                                Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[500]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    // Base URL (shown for Ollama)
                    if (_aiProvider == 'ollama')
                      Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.link_outlined, size: 14, color: Colors.grey[400]),
                              const SizedBox(width: 10),
                              Text("Base URL", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              const Spacer(),
                              SizedBox(
                                width: 160,
                                height: 32,
                                child: TextField(
                                  controller: _aiBaseUrlController,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
                                    filled: true, fillColor: Colors.white,
                                    isDense: true,
                                    hintText: 'http://localhost:11434',
                                    hintStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.black12, height: 20),
                        ],
                      ),
                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: OutlinedButton.icon(
                              onPressed: _aiConfigSaving ? null : () => _saveAIConfig(provider),
                              icon: Icon(Icons.save_outlined, size: 13, color: _aiConfigSaving ? Colors.grey : const Color(0xFF00979D)),
                              label: Text(_aiConfigSaving ? "Saving..." : "Save", style: TextStyle(fontSize: 11, color: _aiConfigSaving ? Colors.grey : const Color(0xFF00979D))),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: _aiConfigSaving ? Colors.grey[300]! : const Color(0xFF00979D)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              onPressed: _aiConfigSaving ? null : () => _testAIConnection(provider),
                              icon: const Icon(Icons.wifi_find_outlined, size: 13, color: Colors.white),
                              label: const Text("Test", style: TextStyle(fontSize: 11, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00979D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 18,
                      child: _aiConfigStatus != null
                          ? Row(
                              children: [
                                Icon(_aiConfigStatus!.startsWith('✓') ? Icons.check_circle_outlined : Icons.error_outline, size: 12, color: _aiConfigStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent),
                                const SizedBox(width: 4),
                                Text(_aiConfigStatus!, style: TextStyle(fontSize: 10, color: _aiConfigStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent)),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: isDesktop ? 320 : double.infinity,
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: _buildModelPerformanceCard(provider),
              ),
            ),
            SizedBox(
              width: isDesktop ? 320 : double.infinity,
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.palette_outlined, color: Color(0xFF00979D), size: 20),
                        const SizedBox(width: 10),
                        const Text("Preferences",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Temperature Unit — segmented toggle
                    Row(
                      children: [
                        Icon(Icons.thermostat_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("Temperature Unit", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: ['Celsius', 'Fahrenheit'].map((u) {
                              final sel = u == _tempUnit;
                              return GestureDetector(
                                onTap: () => setState(() => _tempUnit = u),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: sel ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: sel ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))] : null,
                                  ),
                                  child: Text(u, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.normal, color: sel ? const Color(0xFF1E293B) : Colors.grey[500])),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    // Refresh Interval — dropdown
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("Refresh Interval", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _refreshInterval,
                              icon: Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[500]),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                              onChanged: (v) { if (v != null) setState(() => _refreshInterval = v); },
                              items: [2, 5, 10, 30, 60].map((s) => DropdownMenuItem(value: s, child: Text("${s}s"))).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    // Theme — segmented toggle
                    Row(
                      children: [
                        Icon(Icons.dark_mode_outlined, size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Text("Theme", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: ['Light', 'Dark', 'System'].map((t) {
                              final sel = t == _themeMode;
                              return GestureDetector(
                                onTap: () => setState(() => _themeMode = t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: sel ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: sel ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))] : null,
                                  ),
                                  child: Text(t, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.normal, color: sel ? const Color(0xFF1E293B) : Colors.grey[500])),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: isDesktop ? 320 : double.infinity,
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outlined, color: Color(0xFF00979D), size: 20),
                        const SizedBox(width: 10),
                        const Text("Account",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSettingRow("Username", provider.loggedInUsername.isNotEmpty ? provider.loggedInUsername : "username", Icons.person_outlined),
                    const SizedBox(height: 12),
                    if (!_usernameChangeEnabled)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _usernameChangeEnabled = true),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text("Change Username", style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00979D),
                            side: const BorderSide(color: Color(0xFF00979D)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    if (_usernameChangeEnabled) ...[
                      _buildPasswordField("New Username", _newUsernameController, false, (_) {}),
                      const SizedBox(height: 12),
                      _buildPasswordField("Enter Password", _usernamePasswordController, _usernamePasswordVisible, (v) => setState(() => _usernamePasswordVisible = v)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _newUsernameController.clear();
                                _usernamePasswordController.clear();
                                setState(() { _usernameChangeEnabled = false; _usernameStatus = null; });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text("Cancel", style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _usernameSaving ? null : () => _changeUsername(provider),
                              icon: _usernameSaving
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_circle_outline, size: 16),
                              label: Text(_usernameSaving ? "Saving..." : "Save", style: const TextStyle(fontSize: 12, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00979D),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_usernameStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Icon(
                                _usernameStatus!.startsWith('✓') ? Icons.check_circle_outlined : Icons.error_outline,
                                size: 14,
                                color: _usernameStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _usernameStatus!.replaceFirst('✓ ', '').replaceFirst('✗ ', ''),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _usernameStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Divider(color: Colors.black12, height: 24),
                    if (!_passwordChangeEnabled)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _passwordChangeEnabled = true),
                          icon: const Icon(Icons.lock_reset_outlined, size: 16),
                          label: const Text("Change Password", style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00979D),
                            side: const BorderSide(color: Color(0xFF00979D)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    if (_passwordChangeEnabled) ...[
                      _buildPasswordField("Current Password", _oldPasswordController, _oldPasswordVisible, (v) => setState(() => _oldPasswordVisible = v)),
                      const SizedBox(height: 12),
                      _buildPasswordField("New Password", _newPasswordController, _newPasswordVisible, (v) => setState(() => _newPasswordVisible = v)),
                      const SizedBox(height: 12),
                      _buildPasswordField("Confirm New Password", _confirmPasswordController, false, (_) {}),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _oldPasswordController.clear();
                                _newPasswordController.clear();
                                _confirmPasswordController.clear();
                                setState(() { _passwordChangeEnabled = false; _passwordStatus = null; });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text("Cancel", style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _passwordSaving ? null : () => _changePassword(provider),
                              icon: _passwordSaving
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check, size: 16, color: Colors.white),
                              label: Text(_passwordSaving ? "Saving..." : "Save", style: const TextStyle(fontSize: 12, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00979D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_passwordStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Icon(
                              _passwordStatus!.startsWith('✓') ? Icons.check_circle_outlined : Icons.error_outline,
                              size: 14,
                              color: _passwordStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _passwordStatus!.replaceFirst('✓ ', '').replaceFirst('✗ ', ''),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _passwordStatus!.startsWith('✓') ? const Color(0xFF10B981) : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
      ],
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool visible, void Function(bool) onToggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: !visible,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[200]!)),
            suffixIcon: label != "Confirm New Password"
                ? IconButton(
                    icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
                    onPressed: () => onToggle(!visible),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _thresholdBar(String label, String optimal, String critical, double current, double min, double max, IconData icon, String unit) {
    final inOptimal = current >= min && current <= max;
    final inWarning = (current < min && current >= min * 0.7) || (current > max && current <= max * 1.15);
    final statusColor = inOptimal ? const Color(0xFF10B981) : (inWarning ? const Color(0xFFD97706) : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[600])),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("${current.toStringAsFixed(1)}$unit",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(width: c.maxWidth, color: Colors.grey[200]),
                    Positioned(
                      left: (min / max) * c.maxWidth,
                      width: ((max - min) / max) * c.maxWidth,
                      child: Container(height: 4, color: const Color(0xFF10B981).withOpacity(0.5)),
                    ),
                    Positioned(
                      left: (current / max).clamp(0.0, 1.0) * c.maxWidth - 3,
                      top: -1,
                      child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text("Critical", style: TextStyle(fontSize: 7, color: Colors.grey[400])),
              const Spacer(),
              Text("Optimal $optimal", style: TextStyle(fontSize: 7, color: const Color(0xFF10B981))),
              const Spacer(),
              Text("Critical", style: TextStyle(fontSize: 7, color: Colors.grey[400])),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  IconData _providerIcon(String provider) {
    switch (provider) {
      case 'gemini': return Icons.auto_awesome_outlined;
      case 'openrouter': return Icons.hub_outlined;
      case 'ollama': return Icons.computer_outlined;
      case 'nvidia': return Icons.flash_on_outlined;
      default: return Icons.cloud_outlined;
    }
  }

  List<String> _modelOptions(String provider) {
    switch (provider) {
      case 'gemini': return ['gemini-2.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash'];
      case 'openrouter': return ['auto', 'openai/gpt-4o', 'anthropic/claude-3.5-sonnet'];
      case 'ollama': return ['llama3.2', 'llama3.1', 'mistral', 'qwen2.5'];
      case 'nvidia': return ['meta/llama-3.1-405b-instruct', 'mistralai/mixtral-8x22b'];
      default: return ['auto'];
    }
  }

  Widget _buildModelPerformanceCard(TelemetryProvider provider) {
    final m = _aiMetrics;
    final uptime = m['uptimeSeconds'] ?? 0;
    final uptimeStr = uptime >= 3600
        ? '${(uptime / 3600).toStringAsFixed(1)}h'
        : uptime >= 60
            ? '${(uptime / 60).toStringAsFixed(0)}m'
            : '${uptime}s';
    final latency = m['lastLatencyMs'] ?? 0;
    final avgLatency = m['avgLatencyMs'] ?? 0;
    final totalCalls = m['totalCalls'] ?? 0;
    final successRate = totalCalls > 0 ? ((m['successfulCalls'] ?? 0) / totalCalls * 100).toStringAsFixed(0) : '--';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF00979D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.speed_outlined, size: 14, color: Color(0xFF00979D)),
            ),
            const SizedBox(width: 10),
            const Text("Model Performance",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _metricTile("Uptime", uptimeStr, Icons.timer_outlined),
            const SizedBox(width: 8),
            _metricTile("Total Calls", "${totalCalls}", Icons.call_made_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metricTile("Last Latency", latency > 0 ? "${latency}ms" : "---", Icons.flash_on_outlined),
            const SizedBox(width: 8),
            _metricTile("Avg Latency", avgLatency > 0 ? "${avgLatency}ms" : "---", Icons.trending_up_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metricTile("Success Rate", "${successRate}%", Icons.check_circle_outlined),
            const SizedBox(width: 8),
            _metricTile("Provider", m['lastProvider'] ?? '---', Icons.cloud_outlined),
          ],
        ),
        if (!_aiMetricsLoaded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text("Waiting for first AI call...", style: TextStyle(fontSize: 9, color: Colors.grey[400])),
          ),
      ],
    );
  }

  Widget _metricTile(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 8, color: Colors.grey[500])),
                Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatSummaryCard(String title, String value, IconData icon, Color color, {Color? bgColor}) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor ?? color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      ),
    );
  }
}
