import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.1, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String baseUrl = kIsWeb ? '' : 'https://solarsoil.ashlin.rocks';
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['success'] == true) {
        // Success — navigate to dashboard with smooth slide-up transition
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(
                position: animation.drive(tween),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Invalid username or password.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Cannot connect to server. Is the backend running?';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;
    const primaryColor = Color(0xFF00979D);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Row(
        children: [
          // ── Left Column: Form ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 48 : 24,
                      vertical: 24,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Branding ─────────────────────────────
                                Row(
                                  children: [
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.solar_power, size: 22, color: primaryColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Solar Soil IoT",
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                        Text("FARM MANAGEMENT SYSTEM",
                                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: primaryColor, letterSpacing: 1.2)),
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 40),

                                // ── Welcome text ─────────────────────────
                                const Text("Welcome Back",
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                const SizedBox(height: 6),
                                Text("Sign in to access your IoT metrics dashboard.",
                                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),

                                const SizedBox(height: 32),

                                // ── Error banner (animated) ──────────────
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: _errorMessage != null ? null : 0,
                                  width: double.infinity,
                                  padding: _errorMessage != null
                                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                                      : EdgeInsets.zero,
                                  decoration: BoxDecoration(
                                    color: _errorMessage != null ? Colors.red[50] : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    border: _errorMessage != null ? Border.all(color: Colors.red[200]!) : null,
                                  ),
                                  child: _errorMessage != null
                                      ? Row(
                                          children: [
                                            Icon(Icons.error_outline_rounded, color: Colors.red[600], size: 18),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(_errorMessage!,
                                                  style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.w500)),
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                                if (_errorMessage != null) const SizedBox(height: 16),

                                // ── Username field ───────────────────────
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                                  decoration: _inputDecoration(
                                    label: "Email or Username",
                                    icon: Icons.person_outline_rounded,
                                    primaryColor: primaryColor,
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? "Please enter your email or username" : null,
                                ),

                                const SizedBox(height: 18),

                                // ── Password field ───────────────────────
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _handleLogin(),
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                                  decoration: _inputDecoration(
                                    label: "Password",
                                    icon: Icons.lock_outline_rounded,
                                    primaryColor: primaryColor,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        color: Colors.grey[400], size: 20,
                                      ),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? "Please enter your password" : null,
                                ),

                                const SizedBox(height: 14),

                                // ── Remember me / Forgot password ────────
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 20, height: 20,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            activeColor: primaryColor,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                                            onChanged: (val) => setState(() => _rememberMe = val ?? false),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text("Remember me", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: () {},
                                      child: Text("Forgot Password?",
                                          style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // ── Login button ─────────────────────────
                                SizedBox(
                                  width: double.infinity, height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                        : const Text("Login", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // ── OAuth quick-auth buttons ────────────
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Text("G", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                        label: Text("Google", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          side: BorderSide(color: Colors.grey[200]!),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Text("GH", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                        label: Text("GitHub", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          side: BorderSide(color: Colors.grey[200]!),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Right Column: Dashboard Preview ─────────────────────────
          if (isDesktop)
            Expanded(
              flex: 6,
              child: Container(
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D9488), Color(0xFF0F766E), Color(0xFF134E4A)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Tagline
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text("v2.0 — IoT Dashboard",
                              style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 24),
                        const Text("Monitor Your Farm\nin Real Time",
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2)),
                        const SizedBox(height: 16),
                        Text("Soil moisture, temperature, solar power &\nAI-driven crop health analytics at a glance.",
                            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7), height: 1.5)),
                        const SizedBox(height: 40),

                        // ── Mock dashboard preview cards ────────────────
                        Row(
                          children: [
                            _previewCard("Soil Moisture", "42%", Icons.water_drop, const Color(0xFF3B82F6)),
                            const SizedBox(width: 16),
                            _previewCard("Temperature", "28.5°C", Icons.thermostat, const Color(0xFFF43F5E)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _previewCard("Solar Output", "5.7V", Icons.solar_power, const Color(0xFFF97316)),
                            const SizedBox(width: 16),
                            _previewCard("Humidity", "67%", Icons.opacity, const Color(0xFF10B981)),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Inline mini chart mockup
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text("24-Hour Trend", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.6))),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                    child: const Text("LIVE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Simplified inline chart bars
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [0.3, 0.45, 0.35, 0.55, 0.5, 0.7, 0.65, 0.85, 0.8, 0.95, 0.75, 0.6]
                                    .map((h) => Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        height: 60 * h,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [primaryColor.withOpacity(0.3), primaryColor.withOpacity(0.7)],
                                          ),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    )).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  /// Shared input decoration factory to keep the two text fields DRY.
  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    required Color primaryColor,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
      prefixIcon: Icon(icon, color: primaryColor, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }
}
