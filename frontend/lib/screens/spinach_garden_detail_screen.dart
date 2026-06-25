import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/telemetry_provider.dart';
import '../widgets/glass_card.dart';

class Vector3D {
  final double x;
  final double y;
  final double z;
  Vector3D(this.x, this.y, this.z);

  Vector3D add(Vector3D other) => Vector3D(x + other.x, y + other.y, z + other.z);
  Vector3D multiply(double val) => Vector3D(x * val, y * val, z * val);
}

class SpinachGardenDetailScreen extends StatefulWidget {
  final String gardenName;
  const SpinachGardenDetailScreen({super.key, this.gardenName = 'Spinach Garden'});

  @override
  State<SpinachGardenDetailScreen> createState() => _SpinachGardenDetailScreenState();
}

class _SpinachGardenDetailScreenState extends State<SpinachGardenDetailScreen> with TickerProviderStateMixin {
  late AnimationController _blobController;
  late AnimationController _pulseController;
  late AnimationController _autoRotationController;
  late AnimationController _scanController;
  late AnimationController _visualScanController;
  late TextEditingController _hudChatController;
  
  double _angleY = 0.5; // Initial Y yaw
  double _angleX = 0.15; // Initial X pitch
  bool _isAutoRotating = true;
  bool _showSoil = true;
  int _selectedSensorIndex = -1; // -1 means none, 0: Soil, 1: Temp, 2: Humidity, 3: Light
  String get _plantName => widget.gardenName.split(' ').first;

  Uint8List? _pickedImageBytes;
  String? _pickedImageMime;
  final Set<int> _remedyCheckedIndices = {};

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _autoRotationController = AnimationController(
      duration: const Duration(seconds: 25),
      vsync: this,
    );
    
    _autoRotationController.addListener(() {
      if (_isAutoRotating) {
        setState(() {
          _angleY = _autoRotationController.value * 2 * math.pi;
        });
      }
    });
    
    _autoRotationController.repeat();

    _scanController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..addListener(() {
        setState(() {});
      });

    _visualScanController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _hudChatController = TextEditingController();
  }

  @override
  void dispose() {
    _blobController.dispose();
    _pulseController.dispose();
    _autoRotationController.dispose();
    _scanController.dispose();
    _visualScanController.dispose();
    _hudChatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TelemetryProvider>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    // Extrapolate sensor values from telemetry provider
    final double soilValue = provider.soil;
    final double tempValue = provider.temp;
    final double humidityValue = provider.humidity;
    final double lightValue = 850.0 * (provider.v / 6.0).clamp(0.0, 1.0); // Simulated Lux

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // 1. Unified Glow Background Blobs
          _buildBackgroundMesh(size),

          // 2. Interactive Area & Content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header / Navigation
                _buildHeader(context, provider),

                // Main Workspace Layout
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      children: [
                        if (isDesktop)
                          _buildDesktopLayout(provider, soilValue, tempValue, humidityValue, lightValue)
                        else
                          _buildMobileLayout(provider, soilValue, tempValue, humidityValue, lightValue),
                        
                        const SizedBox(height: 24),
                        // Quick Action Control Panel (Irrigation pump toggle)
                        _buildQuickControlCard(provider),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TelemetryProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Glass back button
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(12),
            child: const GlassCard(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              borderRadius: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 16, color: Color(0xFF00979D)),
                  SizedBox(width: 8),
                  Text(
                    "Back to Overview",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Status tag
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      provider.isConnected ? "LIVE TELEMETRY" : "STANDBY MODE",
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Color(0xFF00979D),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundMesh(Size size) {
    return AnimatedBuilder(
      animation: _blobController,
      builder: (context, child) {
        final val = _blobController.value * 2 * math.pi;
        final x1 = math.sin(val) * 30;
        final y1 = math.cos(val) * 30;
        final x2 = math.cos(val + math.pi / 2) * 40;
        final y2 = math.sin(val + math.pi / 2) * 20;

        return Stack(
          children: [
            Positioned(
              top: -60 + y1,
              left: -40 + x1,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00979D).withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -40 + y2,
              right: -60 + x2,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.06),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _triggerScanAnimation() {
    _scanController.forward(from: 0.0);
  }

  void _handleTap(TapUpDetails details, Size size) {
    final nodeCoords = [
      Vector3D(0, 100, 0),      // Soil Moisture (index 0)
      Vector3D(70, -10, 45),    // Leaf Temp (index 1)
      Vector3D(-70, 40, 50),   // Environment Humidity (index 2)
      Vector3D(0, -170, 0),     // Solar Intensity (index 3)
    ];
    
    final double minDimension = math.min(size.width, size.height);
    final double zoom = 1.6 * (minDimension / 400.0).clamp(0.6, 1.4);
    
    int hitIndex = -1;
    double minDistance = double.infinity;
    
    for (int i = 0; i < nodeCoords.length; i++) {
      final coord = nodeCoords[i];
      
      double x1 = coord.x * math.cos(_angleY) + coord.z * math.sin(_angleY);
      double z1 = -coord.x * math.sin(_angleY) + coord.z * math.cos(_angleY);
      
      double y2 = coord.y * math.cos(_angleX) - z1 * math.sin(_angleX);
      double z2 = coord.y * math.sin(_angleX) + z1 * math.cos(_angleX);
      
      double distance = 400.0;
      double denom = distance + z2;
      if (denom < 20.0) denom = 20.0;
      double scale = distance / denom;
      scale = scale.clamp(0.01, 20.0);
      
      double screenX = size.width / 2 + x1 * scale * zoom;
      double screenY = size.height / 2 + y2 * scale * zoom;
      
      final Offset nodeOffset = Offset(screenX, screenY);
      final double tapDist = (details.localPosition - nodeOffset).distance;
      
      if (tapDist < 35.0 && tapDist < minDistance) {
        minDistance = tapDist;
        hitIndex = i;
      }
    }
    
    if (hitIndex != -1) {
      setState(() {
        _selectedSensorIndex = (_selectedSensorIndex == hitIndex) ? -1 : hitIndex;
        if (_selectedSensorIndex != -1) {
          _triggerScanAnimation();
        }
      });
    }
  }

  Widget _buildAiDiagnosticPanel(TelemetryProvider provider, double soil, double temp, double humidity, double light) {
    final aiMessages = provider.chatMessages.where((msg) => !msg.isUser).toList();
    final String? lastAiAnswer = aiMessages.isNotEmpty ? aiMessages.last.text : null;

    String metricName = "";
    String currentValue = "";
    String statusText = "";
    Color themeColor = const Color(0xFF00979D);
    IconData icon = Icons.info;
    List<String> promptChips = [];

    if (_selectedSensorIndex != -1) {
      switch (_selectedSensorIndex) {
        case 0:
          metricName = "Soil Moisture";
          currentValue = "${soil.toStringAsFixed(0)}%";
          statusText = soil >= 40.0 ? "Optimal Moisture" : "Critical Low Moisture";
          themeColor = const Color(0xFF3B82F6);
          icon = Icons.water_drop;
          promptChips = ["Optimize Moisture", "Soil Best Practices"];
          break;
        case 1:
          metricName = "Leaf Temperature";
          currentValue = "${temp.toStringAsFixed(1)}\u00B0C";
          if (temp < 18.0) {
            statusText = "Too Cold";
            themeColor = const Color(0xFF3B82F6);
          } else if (temp <= 28.0) {
            statusText = "Optimal Temperature";
            themeColor = const Color(0xFF10B981);
          } else if (temp <= 32.0) {
            statusText = "Warning - Warming Trend";
            themeColor = const Color(0xFFFFA000);
          } else {
            statusText = "Warning - Heat Stress";
            themeColor = const Color(0xFFF43F5E);
          }
          icon = Icons.thermostat;
          promptChips = ["Heat Stress Plan", "Ventilation Advice"];
          break;
        case 2:
          metricName = "Environment Humidity";
          currentValue = "${humidity.toStringAsFixed(0)}%";
          statusText = "Stable Environment";
          themeColor = const Color(0xFF10B981);
          icon = Icons.cloud_queue;
          promptChips = ["Mold Prevention", "Stomatal Health"];
          break;
        case 3:
          metricName = "Solar Intensity";
          currentValue = "${light.toStringAsFixed(0)} LUX";
          statusText = light >= 300.0 ? "Optimal PAR Sunlight" : "Low Photosynthesis Light";
          themeColor = const Color(0xFFFFB300);
          icon = Icons.wb_sunny_outlined;
          promptChips = ["Adjust Shade Nets", "Photosynthesis Factor"];
          break;
      }
    }

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedSensorIndex != -1) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: themeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metricName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            currentValue,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _selectedSensorIndex = -1;
                    });
                  },
                ),
              ],
            ),
            const Divider(height: 20, color: Colors.black12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildControlTooltip(),
            ),

          Row(
            children: [
              const Icon(Icons.psychology, size: 16, color: Color(0xFF00979D)),
              const SizedBox(width: 8),
              const Text(
                "RootWise Assistant",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (lastAiAnswer != null)
                TextButton(
                  onPressed: () => provider.clearChat(),
                  child: const Text("Clear Diagnostic", style: TextStyle(fontSize: 10, color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (provider.isAiTyping) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00979D)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Analyzing $_plantName health data with RootWise...",
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ] else if (lastAiAnswer != null) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeColor.withOpacity(0.1)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  lastAiAnswer,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Tap a quick query chip below or ask a custom question to get a real-time plant health diagnostic from RootWise.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: promptChips.map<Widget>((chipText) {
              return ActionChip(
                label: Text(
                  chipText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: themeColor),
                ),
                backgroundColor: themeColor.withOpacity(0.05),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                onPressed: () {
                  String prompt = "";
                  if (chipText == "Optimize Moisture") {
                    prompt = "My soil moisture is currently $currentValue. What is the optimal water volume and scheduling to keep $_plantName happy?";
                  } else if (chipText == "Soil Best Practices") {
                    prompt = "What are the soil conditions, temperature, and nutrients needed for maximum $_plantName growth?";
                  } else if (chipText == "Heat Stress Plan") {
                    prompt = "My $_plantName leaf temperature is at $currentValue. If this is a heat stress situation, what corrective steps should I take?";
                  } else if (chipText == "Ventilation Advice") {
                    prompt = "How does leaf temperature relate to ambient air circulation? How can I improve ventilation in my micro greenhouse?";
                  } else if (chipText == "Mold Prevention") {
                    prompt = "With air humidity at $currentValue, what are the primary mold risks for $_plantName, and how do I prevent downy mildew?";
                  } else if (chipText == "Stomatal Health") {
                    prompt = "Explain how high environment humidity affects $_plantName stomatal conductance and transpiration.";
                  } else if (chipText == "Adjust Shade Nets") {
                    prompt = "Under solar intensity of $currentValue, when should I deploy my solar harvesting array shade net over $_plantName?";
                  } else if (chipText == "Photosynthesis Factor") {
                    prompt = "What is the compensation point and light saturation point for $_plantName in LUX units?";
                  }
                  provider.askAI(prompt);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hudChatController,
                  decoration: InputDecoration(
                    hintText: "Ask RootWise a custom question...",
                    hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: themeColor),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      provider.askAI(val.trim());
                      _hudChatController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  final text = _hudChatController.text.trim();
                  if (text.isNotEmpty) {
                    provider.askAI(text);
                    _hudChatController.clear();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(TelemetryProvider provider, double soil, double temp, double humidity, double light) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Soil & Humidity Cards
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildSensorDetailCard(
                index: 0,
                title: "Soil Moisture",
                value: "${soil.toStringAsFixed(0)}%",
                status: soil >= 40.0 ? "OPTIMAL" : "CRITICAL - NEED WATER",
                statusColor: soil >= 40.0 ? const Color(0xFF10B981) : Colors.redAccent,
                icon: Icons.water_drop,
                themeColor: const Color(0xFF3B82F6),
description: "Measures dielectric permittivity in active root zones. Ideal range is 40% - 70% for $_plantName.",
                diagnose: "Current roots absorption rate is healthy.",
              ),
              const SizedBox(height: 20),
              _buildSensorDetailCard(
                index: 2,
                title: "Environment Humidity",
                value: "${humidity.toStringAsFixed(0)}%",
                status: "STABLE",
                statusColor: const Color(0xFF10B981),
                icon: Icons.cloud_queue,
                themeColor: const Color(0xFF10B981),
description: "Relative air humidity inside $_plantName microclimate zone.",
                diagnose: "Stomatal conductance is normal. No risk of mildew growth.",
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Middle Column: 3D Plant Model
        Expanded(
          flex: 4,
          child: Column(
            children: [
              SizedBox(
                height: (MediaQuery.of(context).size.height * 0.35).clamp(250.0, 500.0),
                child: _buildPlant3DViewer(soil, temp, humidity, light),
              ),
              const SizedBox(height: 8),
              _buildAiDiagnosticPanel(provider, soil, temp, humidity, light),
              const SizedBox(height: 12),
              _buildLeafScannerPanel(provider),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right Column: Leaf Temperature & Solar Intensity
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildSensorDetailCard(
                index: 1,
                title: "Leaf Temperature",
                value: "${temp.toStringAsFixed(1)}\u00B0C",
                status: temp < 18.0 ? "TOO COLD" : (temp <= 28.0 ? "OPTIMAL" : (temp <= 32.0 ? "WARMING" : "HEAT STRESS")),
                statusColor: temp < 18.0 ? const Color(0xFF3B82F6) : (temp <= 28.0 ? const Color(0xFF10B981) : (temp <= 32.0 ? Colors.amber : Colors.redAccent)),
                icon: Icons.thermostat,
                themeColor: temp < 18.0 ? const Color(0xFF3B82F6) : (temp <= 28.0 ? const Color(0xFF10B981) : (temp <= 32.0 ? const Color(0xFFFFA000) : const Color(0xFFF43F5E))),
                description: "Leaf surface temperature from infrared stream. Ideal growth range is 18\u00B0C to 28\u00B0C.",
                diagnose: temp > 30.0 ? "Recommend activating shade netting soon." : "Photosynthetic activity factor at maximum.",
              ),
              const SizedBox(height: 20),
              _buildSensorDetailCard(
                index: 3,
                title: "Solar Intensity (LDR)",
                value: "${light.toStringAsFixed(0)} LUX",
                status: light >= 300.0 ? "SUNNY" : "LOW LIGHT",
                statusColor: light >= 300.0 ? const Color(0xFFFFA000) : Colors.blueGrey,
                icon: Icons.wb_sunny_outlined,
                themeColor: const Color(0xFFFFB300),
                description: "Incoming photosynthetically active radiation (PAR). Essential for chlorophyll activation.",
                diagnose: "Panels generating ${provider.v.toStringAsFixed(1)}V from micro-node solar harvesting array.",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(TelemetryProvider provider, double soil, double temp, double humidity, double light) {
    return Column(
      children: [
        // 3D Plant Model occupies top slot
        SizedBox(
          height: 350,
          child: _buildPlant3DViewer(soil, temp, humidity, light),
        ),
        const SizedBox(height: 8),
        _buildAiDiagnosticPanel(provider, soil, temp, humidity, light),
        const SizedBox(height: 12),
        _buildLeafScannerPanel(provider),
        const SizedBox(height: 20),

        // Scrollable Grid of 4 Cards
        _buildSensorDetailCard(
          index: 0,
          title: "Soil Moisture",
          value: "${soil.toStringAsFixed(0)}%",
          status: soil >= 40.0 ? "OPTIMAL" : "CRITICAL - NEED WATER",
          statusColor: soil >= 40.0 ? const Color(0xFF10B981) : Colors.redAccent,
          icon: Icons.water_drop,
          themeColor: const Color(0xFF3B82F6),
          description: "Measures dielectric permittivity in active root zones. Ideal range is 40% - 70% for $_plantName.",
          diagnose: "Current roots absorption rate is healthy.",
        ),
        const SizedBox(height: 16),
        _buildSensorDetailCard(
          index: 1,
          title: "Leaf Temperature",
          value: "${temp.toStringAsFixed(1)}\u00B0C",
          status: temp < 18.0 ? "TOO COLD" : (temp <= 28.0 ? "OPTIMAL" : (temp <= 32.0 ? "WARMING" : "HEAT STRESS")),
          statusColor: temp < 18.0 ? const Color(0xFF3B82F6) : (temp <= 28.0 ? const Color(0xFF10B981) : (temp <= 32.0 ? Colors.amber : Colors.redAccent)),
          icon: Icons.thermostat,
          themeColor: temp < 18.0 ? const Color(0xFF3B82F6) : (temp <= 28.0 ? const Color(0xFF10B981) : (temp <= 32.0 ? const Color(0xFFFFA000) : const Color(0xFFF43F5E))),
          description: "Leaf surface temperature from infrared stream. Ideal growth range is 18\u00B0C to 28\u00B0C.",
          diagnose: temp > 30.0 ? "Recommend activating shade netting soon." : "Photosynthetic activity factor at maximum.",
        ),
        const SizedBox(height: 16),
        _buildSensorDetailCard(
          index: 2,
          title: "Environment Humidity",
          value: "${humidity.toStringAsFixed(0)}%",
          status: "STABLE",
          statusColor: const Color(0xFF10B981),
          icon: Icons.cloud_queue,
          themeColor: const Color(0xFF10B981),
          description: "Relative air humidity inside $_plantName microclimate zone.",
          diagnose: "Stomatal conductance is normal. No risk of mildew growth.",
        ),
        const SizedBox(height: 16),
        _buildSensorDetailCard(
          index: 3,
          title: "Solar Intensity (LDR)",
          value: "${light.toStringAsFixed(0)} LUX",
          status: light >= 300.0 ? "SUNNY" : "LOW LIGHT",
          statusColor: light >= 300.0 ? const Color(0xFFFFA000) : Colors.blueGrey,
          icon: Icons.wb_sunny_outlined,
          themeColor: const Color(0xFFFFB300),
          description: "Incoming photosynthetically active radiation (PAR).",
          diagnose: "Panels generating ${provider.v.toStringAsFixed(1)}V.",
        ),
      ],
    );
  }

  Widget _buildControlTooltip() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.swipe_outlined, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text(
          "Swipe or drag the plant container to spin in 3D",
          style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildPlant3DViewer(double soil, double temp, double humidity, double light) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width <= 0 || size.height <= 0 || !size.width.isFinite || !size.height.isFinite) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTapUp: (details) => _handleTap(details, size),
          onPanDown: (d) {
            setState(() {
              _isAutoRotating = false;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _angleY += details.delta.dx * 0.007;
              _angleX = (_angleX - details.delta.dy * 0.007).clamp(-math.pi / 4, math.pi / 4);
            });
          },
          onPanEnd: (d) {
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted && !_isAutoRotating) {
                setState(() {
                  _isAutoRotating = true;
                });
              }
            });
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _scanController]),
            builder: (context, child) {
              return GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                borderRadius: 30,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _showSoil ? Icons.grass : Icons.landslide_outlined,
                                  size: 18,
                                ),
                                tooltip: _showSoil ? "Hide Soil" : "Show Soil",
                                color: _showSoil ? const Color(0xFF8D6E63) : const Color(0xFF00E5FF),
                                onPressed: () {
                                  setState(() {
                                    _showSoil = !_showSoil;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _isAutoRotating ? Icons.autorenew : Icons.play_arrow,
                                  size: 18,
                                ),
                                color: _isAutoRotating ? const Color(0xFF00979D) : Colors.grey[400],
                                onPressed: () {
                                  setState(() {
                                    _isAutoRotating = !_isAutoRotating;
                                    if (_isAutoRotating) {
                                      _autoRotationController.repeat();
                                    } else {
                                      _autoRotationController.stop();
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: Plant3DPainter(
                            angleY: _angleY,
                            angleX: _angleX,
                            pulse: _pulseController.value,
                            soil: soil,
                            temp: temp,
                            humidity: humidity,
                            light: light,
                            selectedSensorIndex: _selectedSensorIndex,
                            scanProgress: _scanController.value,
                            isScanning: _scanController.isAnimating,
                            isPumpOn: Provider.of<TelemetryProvider>(context, listen: false).isPumpOn,
                            showSoil: _showSoil,
                            cameraYOffset: _showSoil ? 0.0 : 35.0,
                            onHoverNode: (idx) {
                              setState(() {
                                _selectedSensorIndex = idx;
                              });
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swipe, size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                "Rotate",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.7),
                                  letterSpacing: 0.5,
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
            },
          ),
        );
      },
    );
  }

  Widget _buildSensorDetailCard({
    required int index,
    required String title,
    required String value,
    required String status,
    required Color statusColor,
    required IconData icon,
    required Color themeColor,
    required String description,
    required String diagnose,
  }) {
    final isSelected = _selectedSensorIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSensorIndex = isSelected ? -1 : index;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? themeColor : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: GlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: themeColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value.split(' ')[0],
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (value.contains(' ')) ...[
                    const SizedBox(width: 4),
                    Text(
                      value.split(' ')[1],
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                    ),
                  ] else if (title == "Soil Moisture" || title == "Environment Humidity") ...[
                    const SizedBox(width: 4),
                    const Text("%", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4),
              ),
              const Divider(height: 20, color: Colors.black12),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      diagnose,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickControlCard(TelemetryProvider provider) {
    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF00979D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.water, color: Color(0xFF00979D), size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Irrigation Pump Control",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.isPumpOn ? "PUMP ACTIVE - WATERING SPINACH" : "PUMP STANDBY - SOIL LEVEL NORMAL",
                    style: TextStyle(fontSize: 10, color: provider.isPumpOn ? const Color(0xFF10B981) : Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            ],
          ),
          Switch(
            value: provider.isPumpOn,
            onChanged: (val) => provider.togglePump(),
            activeThumbColor: const Color(0xFF00979D),
            activeTrackColor: const Color(0xFF00979D).withValues(alpha: 0.4),
          )
        ],
      ),
    );
  }

  // ── LEAF IMAGE SCANNER WIDGETS ─────────────────────────────────────────────

  Widget _buildLeafScannerPanel(TelemetryProvider provider) {
    final diagnostic = provider.lastDiagnostic;
    final isScanning = provider.isScanningImage;

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00979D).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.center_focus_strong, color: Color(0xFF00979D), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Visual AI Crop Diagnostics",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Correlate crop vision with live sensor data",
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (diagnostic != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                  onPressed: () {
                    provider.clearDiagnostic();
                    setState(() {
                      _pickedImageBytes = null;
                      _pickedImageMime = null;
                      _remedyCheckedIndices.clear();
                    });
                  },
                ),
            ],
          ),
          const Divider(height: 24, color: Colors.black12),

          if (isScanning) ...[
            _buildScanningOverlay(),
          ] else if (diagnostic != null) ...[
            _buildDiagnosticReport(provider, diagnostic),
          ] else ...[
            _buildUploadPlaceholder(provider),
          ],
        ],
      ),
    );
  }

  Widget _buildScanningOverlay() {
    return Center(
      child: Container(
        height: 220,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black.withOpacity(0.05),
          border: Border.all(color: const Color(0xFF00979D).withOpacity(0.2)),
        ),
        child: Stack(
          children: [
            if (_pickedImageBytes != null)
              Positioned.fill(
                child: Image.memory(
                  _pickedImageBytes!,
                  fit: BoxFit.cover,
                ),
              ),
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.45),
              ),
            ),
            AnimatedBuilder(
              animation: _visualScanController,
              builder: (context, child) {
                final double relativePos = _visualScanController.value;
                return Positioned(
                  top: relativePos * 220,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF00E5FF),
                          blurRadius: 16,
                          spreadRadius: 4,
                        ),
                      ],
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                );
              },
            ),
            const Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.center_focus_weak, color: Color(0xFF00E5FF), size: 44),
                    SizedBox(height: 12),
                    Text(
                      "SYS.ANALYZING_VISUAL_TELEMETRY...",
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
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

  Widget _buildDiagnosticReport(TelemetryProvider provider, LeafDiagnostic diagnostic) {
    final severityColor = diagnostic.severityColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: severityColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: severityColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "SEVERITY: ${diagnostic.severity.toUpperCase()}",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              "Confidence: ${diagnostic.confidence}",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Text(
            diagnostic.diagnosis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (diagnostic.issues.isNotEmpty) ...[
          const Text(
            "Identified Anomalies",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: diagnostic.issues.map((issue) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 10, color: Colors.redAccent),
                    const SizedBox(width: 4),
                    Text(
                      issue,
                      style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        if (diagnostic.remedies.isNotEmpty) ...[
          const Text(
            "Actionable Remedies",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Column(
            children: List.generate(diagnostic.remedies.length, (index) {
              final remedy = diagnostic.remedies[index];
              final isChecked = _remedyCheckedIndices.contains(index);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isChecked) {
                      _remedyCheckedIndices.remove(index);
                    } else {
                      _remedyCheckedIndices.add(index);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isChecked ? const Color(0xFF10B981).withOpacity(0.04) : Colors.black.withOpacity(0.01),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isChecked ? const Color(0xFF10B981).withOpacity(0.2) : Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isChecked ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: isChecked ? const Color(0xFF10B981) : Colors.grey[400],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          remedy,
                          style: TextStyle(
                            fontSize: 11,
                            color: isChecked ? Colors.grey[500] : const Color(0xFF334155),
                            decoration: isChecked ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              provider.clearDiagnostic();
              setState(() {
                _pickedImageBytes = null;
                _pickedImageMime = null;
                _remedyCheckedIndices.clear();
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[600],
              side: const BorderSide(color: Colors.black12),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 14),
            label: const Text("Scan Another Leaf", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder(TelemetryProvider provider) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        color: Colors.black.withOpacity(0.01),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.add_a_photo_outlined, color: Colors.grey[400], size: 40),
          const SizedBox(height: 12),
          const Text(
            "Analyze Leaf Health",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          const Text(
            "Capture a photo of a leaf to inspect disease patterns, discoloration, or pest trails.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(provider, ImageSource.camera),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00979D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text("Take Photo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(provider, ImageSource.gallery),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00979D),
                    side: const BorderSide(color: Color(0xFF00979D), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text("Upload File", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _pickImage(TelemetryProvider provider, ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _pickedImageBytes = bytes;
          _pickedImageMime = file.mimeType ?? 'image/jpeg';
        });
        
        _visualScanController.repeat(reverse: true);
        
        await provider.uploadAndScanLeafImage(bytes, _pickedImageMime!);
        
        _visualScanController.stop();
      }
    } catch (e) {
      provider.addTerminalLog("IMAGE PICKER ERROR: $e");
      _visualScanController.stop();
    }
  }
}

// Custom 3D Plant Painter
class Plant3DPainter extends CustomPainter {
  final double angleY;
  final double angleX;
  final double pulse;
  final double soil;
  final double temp;
  final double humidity;
  final double light;
  final int selectedSensorIndex;
  final double scanProgress;
  final bool isScanning;
  final bool isPumpOn;
  final bool showSoil;
  final double cameraYOffset;
  final Function(int) onHoverNode;

  Plant3DPainter({
    required this.angleY,
    required this.angleX,
    required this.pulse,
    required this.soil,
    required this.temp,
    required this.humidity,
    required this.light,
    required this.selectedSensorIndex,
    required this.scanProgress,
    required this.isScanning,
    required this.isPumpOn,
    required this.showSoil,
    required this.cameraYOffset,
    required this.onHoverNode,
  });

  // Project 3D coordinate to 2D Screen space
  Map<String, dynamic> project(double x, double y, double z, Size size) {
    // 1. Rotate Y (yaw)
    double x1 = x * math.cos(angleY) + z * math.sin(angleY);
    double z1 = -x * math.sin(angleY) + z * math.cos(angleY);
    
    // 2. Rotate X (pitch)
    double y2 = y * math.cos(angleX) - z1 * math.sin(angleX);
    double z2 = y * math.sin(angleX) + z1 * math.cos(angleX);
    
    // Perspective projection
    double distance = 400.0;
    double denom = distance + z2;
    if (denom < 20.0) denom = 20.0;
    double scale = distance / denom;
    scale = scale.clamp(0.01, 20.0);
    
    // Responsive zoom scaling based on minDimension
    // When soil is hidden, zoom out to fit the full root system
    final double minDimension = math.min(size.width, size.height);
    final double baseZoom = 1.6 * (minDimension / 400.0).clamp(0.6, 1.4);
    final double zoom = showSoil ? baseZoom : baseZoom * 0.55;
    
    double screenX = size.width / 2 + x1 * scale * zoom;
    double screenY = size.height / 2 - cameraYOffset + y2 * scale * zoom;
    
    return {
      'offset': Offset(screenX, screenY),
      'depth': z2,
      'scale': scale * zoom / 1.6,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || !size.width.isFinite || !size.height.isFinite) return;
    List<PaintElement> elements = [];

    // 1. Generate Glass Pot base/top ellipses
    _generatePotElements(size, elements);

    // 2. Generate Roots extending downwards
    _generateRootsElements(size, elements);

    // 2b. Subterranean EC/VWC nodes when soil is hidden
    if (!showSoil) {
      _generateRootSensorNodes(size, elements);
    }

    // 3. Generate Main Stem Segments
    List<Vector3D> stemPoints = [
      Vector3D(0, 100, 0),
      Vector3D(0, 50, 0),
      Vector3D(0, 0, 0),
      Vector3D(-5, -50, 5),
      Vector3D(-2, -90, -3),
      Vector3D(0, -130, 0),
    ];

    // 4. Generate Stem Segments
    _generateStemElements(stemPoints, size, elements);

    // 5. Generate Leaves
    _generateLeafElements(stemPoints, size, elements);

    // 6. Generate Sensor Nodes on top of leaves / roots
    _generateSensorNodeElements(stemPoints, size, elements);

    // 7. Generate Water/Nutrient Flow Particles if pump is active
    if (isPumpOn) {
      _generateWaterFlowParticles(stemPoints, size, elements);
    }

    // Depth sort elements (Painters algorithm) so back elements render behind front
    elements.sort((a, b) => b.depth.compareTo(a.depth));

    // Paint all elements
    for (var element in elements) {
      element.paint(canvas, size);
    }

    // 8. Draw holographic scanline overlay on top
    if (isScanning && scanProgress > 0.0) {
      _drawHolographicScanline(canvas, size);
    }
  }

  void _generateWaterFlowParticles(List<Vector3D> stem, Size size, List<PaintElement> elements) {
    List<List<Vector3D>> rootPaths = [
      [Vector3D(-25, 145, -5), Vector3D(-15, 120, -10), Vector3D(0, 100, 0)],
      [Vector3D(30, 140, 10), Vector3D(15, 125, 15), Vector3D(0, 100, 0)],
      [Vector3D(5, 150, 15), Vector3D(-2, 135, 20), Vector3D(0, 100, 0)],
    ];
    
    for (var rootPath in rootPaths) {
      for (int i = 0; i < 2; i++) {
        double t = (pulse + i * 0.5) % 1.0;
        Vector3D pos = _interpolatePath(rootPath, t);
        final proj = project(pos.x, pos.y, pos.z, size);
        final Offset offset = proj['offset'] as Offset;
        final double scale = (proj['scale'] as num).toDouble();
        final double depth = (proj['depth'] as num).toDouble();
        
        elements.add(
          PaintElement(
            depth: depth - 1.0,
            onPaint: (canvas) {
              final particlePaint = Paint()
                ..color = const Color(0xFF00E5FF).withOpacity(0.8 * (1.0 - t * 0.5))
                ..style = PaintingStyle.fill;
              canvas.drawCircle(offset, 2.5 * scale, particlePaint);
            },
          ),
        );
      }
    }
    
    for (int i = 0; i < 4; i++) {
      double t = (pulse + i * 0.25) % 1.0;
      Vector3D pos = _interpolatePath(stem, t);
      final proj = project(pos.x, pos.y, pos.z, size);
      final Offset offset = proj['offset'] as Offset;
      final double scale = (proj['scale'] as num).toDouble();
      final double depth = (proj['depth'] as num).toDouble();
      
      elements.add(
        PaintElement(
          depth: depth - 1.0,
          onPaint: (canvas) {
            final particlePaint = Paint()
              ..color = const Color(0xFF00E5FF).withOpacity(0.9)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, 3.0 * scale, particlePaint);
            
            final glowPaint = Paint()
              ..color = const Color(0xFF00E5FF).withOpacity(0.3)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, 6.0 * scale, glowPaint);
          },
        ),
      );
    }
    
    List<Map<String, dynamic>> leafConfigs = [
      {'attach': stem[1], 'tip': Vector3D(-70, 40, 50)},
      {'attach': stem[2], 'tip': Vector3D(70, -10, 45)},
      {'attach': stem[3], 'tip': Vector3D(-65, -70, -40)},
      {'attach': stem[4], 'tip': Vector3D(55, -110, -30)},
      {'attach': stem[5], 'tip': Vector3D(0, -170, 0)},
    ];
    
    for (var leaf in leafConfigs) {
      final Vector3D attach = leaf['attach'];
      final Vector3D tip = leaf['tip'];
      
      double t = pulse;
      Vector3D pos = Vector3D(
        attach.x + (tip.x - attach.x) * t,
        attach.y + (tip.y - attach.y) * t,
        attach.z + (tip.z - attach.z) * t,
      );
      
      final proj = project(pos.x, pos.y, pos.z, size);
      final Offset offset = proj['offset'] as Offset;
      final double scale = (proj['scale'] as num).toDouble();
      final double depth = (proj['depth'] as num).toDouble();
      
      elements.add(
        PaintElement(
          depth: depth - 2.0,
          onPaint: (canvas) {
            final particlePaint = Paint()
              ..color = const Color(0xFF00E5FF).withOpacity(0.8 * (1.0 - t))
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, 2.0 * scale, particlePaint);
          },
        ),
      );
    }
  }
  
  Vector3D _interpolatePath(List<Vector3D> path, double t) {
    if (path.isEmpty) return Vector3D(0, 0, 0);
    if (path.length == 1) return path[0];
    
    double segmentT = 1.0 / (path.length - 1);
    int segmentIndex = (t / segmentT).floor().clamp(0, path.length - 2);
    double localT = (t - segmentIndex * segmentT) / segmentT;
    
    Vector3D p1 = path[segmentIndex];
    Vector3D p2 = path[segmentIndex + 1];
    
    return Vector3D(
      p1.x + (p2.x - p1.x) * localT,
      p1.y + (p2.y - p1.y) * localT,
      p1.z + (p2.z - p1.z) * localT,
    );
  }

  void _drawHolographicScanline(Canvas canvas, Size size) {
    final double scanY = size.height * scanProgress;
    
    final scanRect = Rect.fromLTWH(0, scanY - 15, size.width, 30);
    final scanPaint = Paint()..strokeWidth = 2.0;
    if (scanY.isFinite && size.width.isFinite) {
      scanPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00FFCC).withOpacity(0.0),
          const Color(0xFF00FFCC).withOpacity(0.4),
          const Color(0xFF00FFCC).withOpacity(0.0),
        ],
      ).createShader(scanRect);
    }
    canvas.drawRect(scanRect, scanPaint);
    
    final linePaint = Paint()
      ..color = const Color(0xFFE0F7FA)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, scanY), Offset(size.width, scanY), linePaint);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: "SYS.AI_DIAGNOSTIC_SCAN... ${(scanProgress * 100).toInt()}%",
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(15, (scanY - 14).clamp(10, size.height - 20)));
  }

  void _generatePotElements(Size size, List<PaintElement> elements) {
    // Pot Top rim: center (0, 95, 0), radius 75
    // Pot Bottom rim: center (0, 155, 0), radius 50
    // Generate ellipses
    final topProj = project(0, 95, 0, size);
    final bottomProj = project(0, 155, 0, size);
    
    final Offset topOffset = topProj['offset'] as Offset;
    final double topScale = (topProj['scale'] as num).toDouble();
    final double topDepth = (topProj['depth'] as num).toDouble();
    
    final Offset bottomOffset = bottomProj['offset'] as Offset;
    final double bottomScale = (bottomProj['scale'] as num).toDouble();
    
    elements.add(
      PaintElement(
        depth: topDepth,
        onPaint: (canvas) {
          final double potAlpha = showSoil ? 0.15 : 0.05;
          final double outlineAlpha = showSoil ? 0.35 : 0.12;

          // Draw Dark Brown Soil ellipse only when visible
          if (showSoil) {
            final soilRect = Rect.fromCenter(
              center: topOffset,
              width: 140.0 * topScale,
              height: 40.0 * topScale,
            );
            final soilPaint = Paint()..style = PaintingStyle.fill;
            if (topOffset.dx.isFinite && topOffset.dy.isFinite &&
                topScale.isFinite && topScale > 0) {
              soilPaint.shader = const LinearGradient(
                colors: [Color(0xFF3E2723), Color(0xFF271A15)],
              ).createShader(soilRect);
            }
            canvas.drawOval(soilRect, soilPaint);
          } else {
            // Subterranean cross-section: show soil ring outline only
            final soilRingPaint = Paint()
              ..color = const Color(0xFF8D6E63).withValues(alpha: 0.2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            canvas.drawOval(
              Rect.fromCenter(
                center: topOffset,
                width: 140.0 * topScale,
                height: 40.0 * topScale,
              ),
              soilRingPaint,
            );

            // Draw cross-hatch grid lines to indicate excavation
            final gridPaint = Paint()
              ..color = const Color(0xFF00E5FF).withValues(alpha: 0.08)
              ..strokeWidth = 0.5;
            for (int g = 0; g < 6; g++) {
              final t = (g / 5.0);
              final gx = topOffset.dx + (-60.0 + t * 120.0) * topScale;
              final topY = topOffset.dy - 18.0 * topScale * math.sqrt(1 - (t - 0.5) * (t - 0.5) * 4);
              final botY = topOffset.dy + 18.0 * topScale * math.sqrt(1 - (t - 0.5) * (t - 0.5) * 4);
              canvas.drawLine(Offset(gx, topY), Offset(gx, botY), gridPaint);
            }
          }

          // Draw the glass pot body (connecting top to bottom)
          final potPaint = Paint()
            ..color = Colors.white.withValues(alpha: potAlpha)
            ..style = PaintingStyle.fill;

          final potOutlinePaint = Paint()
            ..color = Colors.white.withValues(alpha: outlineAlpha)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

          final Path potPath = Path();
          final Offset topL = Offset(topOffset.dx - 70.0 * topScale, topOffset.dy);
          final Offset topR = Offset(topOffset.dx + 70.0 * topScale, topOffset.dy);
          final Offset bottomL = Offset(bottomOffset.dx - 45.0 * bottomScale, bottomOffset.dy);
          final Offset bottomR = Offset(bottomOffset.dx + 45.0 * bottomScale, bottomOffset.dy);

          potPath.moveTo(topL.dx, topL.dy);
          potPath.lineTo(bottomL.dx, bottomL.dy);
          potPath.quadraticBezierTo(bottomOffset.dx, bottomOffset.dy + 15.0 * bottomScale, bottomR.dx, bottomR.dy);
          potPath.lineTo(topR.dx, topR.dy);
          potPath.quadraticBezierTo(topOffset.dx, topOffset.dy + 12.0 * topScale, topL.dx, topL.dy);

          canvas.drawPath(potPath, potPaint);
          canvas.drawPath(potPath, potOutlinePaint);

          // Optional water line inside if pump is active (Procedural fun!)
          final waterLevelPct = (soil / 100.0).clamp(0.0, 1.0);
          if (waterLevelPct > 0.05) {
            final waterPaint = Paint()
              ..color = const Color(0xFF2196F3).withValues(alpha: 0.25 * waterLevelPct)
              ..style = PaintingStyle.fill;

            final Path waterPath = Path();
            final double waterY = topOffset.dy + (bottomOffset.dy - topOffset.dy) * (1.0 - waterLevelPct);
            final double waterScale = topScale + (bottomScale - topScale) * (1.0 - waterLevelPct);
            
            final Offset wTopOffset = Offset(topOffset.dx, waterY);
            final Offset wTopL = Offset(topOffset.dx - (70.0 - 25.0 * (1.0 - waterLevelPct)) * waterScale, waterY);
            final Offset wTopR = Offset(topOffset.dx + (70.0 - 25.0 * (1.0 - waterLevelPct)) * waterScale, waterY);

            waterPath.moveTo(wTopL.dx, wTopL.dy);
            waterPath.lineTo(bottomL.dx, bottomL.dy);
            waterPath.quadraticBezierTo(bottomOffset.dx, bottomOffset.dy + 15.0 * bottomScale, bottomR.dx, bottomR.dy);
            waterPath.lineTo(wTopR.dx, wTopR.dy);
            waterPath.quadraticBezierTo(wTopOffset.dx, wTopOffset.dy + 12.0 * waterScale, wTopL.dx, wTopL.dy);
            canvas.drawPath(waterPath, waterPaint);
          }
        },
      ),
    );
  }

  void _generateRootsElements(Size size, List<PaintElement> elements) {
    final double rootAlpha = showSoil ? 0.6 : 1.0;
    final double rootWidth = showSoil ? 2.0 : 3.5;
    final Color rootColor = showSoil
        ? const Color(0xFF8D6E63)
        : const Color(0xFFA1887F);

    List<List<Vector3D>> roots = [
      [Vector3D(0, 100, 0), Vector3D(-15, 120, -10), Vector3D(-25, 145, -5), Vector3D(-30, 165, 5)],
      [Vector3D(0, 100, 0), Vector3D(15, 125, 15), Vector3D(30, 140, 10), Vector3D(40, 160, -5)],
      [Vector3D(0, 100, 0), Vector3D(-2, 135, 20), Vector3D(5, 150, 15), Vector3D(8, 170, 25)],
      [Vector3D(0, 100, 0), Vector3D(-20, 115, 5), Vector3D(-35, 130, -10), Vector3D(-45, 150, -15)],
      [Vector3D(0, 100, 0), Vector3D(25, 110, -10), Vector3D(40, 125, -20), Vector3D(50, 145, -10)],
    ];

    // Secondary fine root hairs when soil is hidden
    if (!showSoil) {
      roots.addAll([
        [Vector3D(-15, 120, -10), Vector3D(-28, 130, -5), Vector3D(-35, 145, 0)],
        [Vector3D(15, 125, 15), Vector3D(28, 138, 8), Vector3D(38, 152, 12)],
        [Vector3D(-2, 135, 20), Vector3D(-10, 150, 18), Vector3D(-15, 165, 22)],
      ]);
    }

    for (var root in roots) {
      final baseProj = project(root[0].x, root[0].y, root[0].z, size);
      final midProj = project(root[1].x, root[1].y, root[1].z, size);
      final tipProj = project(root[2].x, root[2].y, root[2].z, size);
      
      elements.add(
        PaintElement(
          depth: (baseProj['depth'] + tipProj['depth']) / 2,
          onPaint: (canvas) {
            final paint = Paint()
              ..color = rootColor.withValues(alpha: rootAlpha)
              ..strokeWidth = root.length > 3 ? rootWidth * 0.6 : rootWidth
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke;

            canvas.drawLine(baseProj['offset'], midProj['offset'], paint);
            canvas.drawLine(midProj['offset'], tipProj['offset'], paint);

            if (root.length > 3) {
              final tip2Proj = project(root[3].x, root[3].y, root[3].z, size);
              canvas.drawLine(tipProj['offset'], tip2Proj['offset'], paint);
            }
          },
        ),
      );
    }
  }

  void _generateRootSensorNodes(Size size, List<PaintElement> elements) {
    // EC (Electrical Conductivity) and VWC (Volumetric Water Content) nodes on roots
    final ec = (soil / 100.0 * 2.0).toStringAsFixed(1);
    final vwc = (soil * 0.7).toStringAsFixed(1);

    List<Map<String, dynamic>> rootSensors = [
      {
        'coord': Vector3D(-25, 145, -5),
        'label': 'EC: $ec mS/cm',
        'color': const Color(0xFF00979D),
        'alignRight': false,
      },
      {
        'coord': Vector3D(30, 140, 10),
        'label': 'VWC: $vwc %',
        'color': const Color(0xFF06B6D4),
        'alignRight': true,
      },
      {
        'coord': Vector3D(5, 150, 15),
        'label': 'NPK: Optimal',
        'color': const Color(0xFF22C55E),
        'alignRight': false,
      },
    ];

    for (var sensor in rootSensors) {
      final Vector3D coord = sensor['coord'];
      final String label = sensor['label'];
      final Color color = sensor['color'];
      final bool alignRight = sensor['alignRight'];

      final proj = project(coord.x, coord.y, coord.z, size);
      final Offset offset = proj['offset'] as Offset;
      final double depth = (proj['depth'] as num).toDouble();
      if (offset.dx.isNaN || offset.dy.isNaN) continue;

      elements.add(
        PaintElement(
          depth: depth - 3.0,
          onPaint: (canvas) {
            // Glow ring
            final glowPaint = Paint()
              ..color = color.withOpacity(0.25 * (1.0 - pulse))
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, (pulse * 6.0 + 4.0) * (proj['scale'] as num).toDouble(), glowPaint);

            // Core dot
            final dotPaint = Paint()
              ..color = color
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, 3.0 * (proj['scale'] as num).toDouble(), dotPaint);

            final innerPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, 1.5 * (proj['scale'] as num).toDouble(), innerPaint);

            // Label
            final double margin = 12.0;
            const double cardWidth = 110.0;
            const double cardHeight = 22.0;
            final double targetX = alignRight
                ? (offset.dx + margin).clamp(margin, size.width - cardWidth - margin)
                : (offset.dx - cardWidth - margin).clamp(margin, size.width - cardWidth - margin);
            final double targetY = (offset.dy - 20.0)
                .clamp(cardHeight / 2 + margin, size.height - cardHeight / 2 - margin);
            final Offset cardOffset = Offset(targetX, targetY);

            // Dotted line
            final linePaint = Paint()
              ..color = color.withOpacity(0.35)
              ..strokeWidth = 0.8
              ..style = PaintingStyle.stroke;
            _drawDottedLine(canvas, offset, cardOffset, linePaint);

            // Mini card
            _drawHudCard(canvas, cardOffset, label, color, alignRight, false);
          },
        ),
      );
    }
  }

  void _generateStemElements(List<Vector3D> points, Size size, List<PaintElement> elements) {
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final proj1 = project(p1.x, p1.y, p1.z, size);
      final proj2 = project(p2.x, p2.y, p2.z, size);

      elements.add(
        PaintElement(
          depth: (proj1['depth'] + proj2['depth']) / 2,
          onPaint: (canvas) {
            final paint = Paint()
              ..strokeWidth = (7.0 - i * 0.8) * proj1['scale']
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke;
            final o1 = proj1['offset'] as Offset;
            final o2 = proj2['offset'] as Offset;
            if (o1.dx.isFinite && o1.dy.isFinite && o2.dx.isFinite && o2.dy.isFinite) {
              paint.shader = const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ).createShader(Rect.fromPoints(o1, o2));
            }

            canvas.drawLine(o1, o2, paint);
          },
        ),
      );
    }
  }

  Color _heatColor(double health) {
    final clamped = health.clamp(0.0, 1.0);
    if (clamped > 0.7) {
      final t = (clamped - 0.7) / 0.3;
      return Color.lerp(const Color(0xFF8BC34A), const Color(0xFF2E7D32), t)!;
    } else if (clamped > 0.35) {
      final t = (clamped - 0.35) / 0.35;
      return Color.lerp(const Color(0xFFFFA726), const Color(0xFF8BC34A), t)!;
    } else {
      final t = clamped / 0.35;
      return Color.lerp(const Color(0xFFEF5350), const Color(0xFFFFA726), t)!;
    }
  }

  double _leafHealth(int index) {
    switch (index) {
      case 0:
        return (soil / 100.0).clamp(0.0, 1.0);
      case 1:
        if (temp < 18.0) return (temp / 18.0).clamp(0.0, 1.0) * 0.3;
        if (temp <= 28.0) return 0.8 + (28.0 - temp) / 28.0 * 0.2;
        if (temp <= 32.0) return 0.7 - (temp - 28.0) / 4.0 * 0.3;
        return (1.0 - (temp - 32.0) / 10.0).clamp(0.0, 0.4);
      case 2:
        if (humidity < 30.0) return (humidity / 30.0).clamp(0.0, 1.0) * 0.3;
        if (humidity <= 80.0) return 0.8 + (80.0 - humidity) / 80.0 * 0.2;
        return (1.0 - (humidity - 80.0) / 20.0).clamp(0.0, 0.5);
      case 3:
        if (light < 100.0) return (light / 100.0).clamp(0.0, 1.0) * 0.3;
        if (light <= 600.0) return 0.7 + light / 600.0 * 0.3;
        if (light <= 900.0) return 1.0 - (light - 600.0) / 300.0 * 0.2;
        return (1.0 - (light - 900.0) / 500.0).clamp(0.2, 0.8);
      default:
        return 0.8;
    }
  }

  void _generateLeafElements(List<Vector3D> stem, Size size, List<PaintElement> elements) {
    // Spinach leaves definitions: attachment point on stem, tip point, leaf width
    List<Map<String, dynamic>> leaves = [
      // Leaf 1: Lower left (Humidity Sensor attached here)
      {
        'attach': stem[1],
        'tip': Vector3D(-70, 40, 50),
        'width': 45.0,
        'index': 2,
      },
      // Leaf 2: Lower right (Temp Sensor attached here)
      {
        'attach': stem[2],
        'tip': Vector3D(70, -10, 45),
        'width': 45.0,
        'index': 1,
      },
      // Leaf 3: Mid left (soil + humidity average)
      {
        'attach': stem[3],
        'tip': Vector3D(-65, -70, -40),
        'width': 40.0,
        'index': -1,
      },
      // Leaf 4: Upper right (temp + light average)
      {
        'attach': stem[4],
        'tip': Vector3D(55, -110, -30),
        'width': 35.0,
        'index': -2,
      },
      // Leaf 5: Top (Light LDR Sensor attached here)
      {
        'attach': stem[5],
        'tip': Vector3D(0, -170, 0),
        'width': 40.0,
        'index': 3,
      },
    ];

    for (var leaf in leaves) {
      final Vector3D attach = leaf['attach'];
      final Vector3D tip = leaf['tip'];
      final double width = leaf['width'];
      final int index = leaf['index'];

      // Calc center midpoint
      final Vector3D center = Vector3D(
        (attach.x + tip.x) / 2,
        (attach.y + tip.y) / 2,
        (attach.z + tip.z) / 2,
      );

      // Branch vector
      final dx = tip.x - attach.x;
      final dz = tip.z - attach.z;
      
      // Calculate side coordinates perpendicular to branch direction for 3D leaf width
      // Orthogonal vector in 3D: (-dz, 0, dx)
      double len = math.sqrt(dx * dx + dz * dz);
      if (len == 0) len = 1.0;
      final perpX = (-dz / len) * width * 0.5;
      final perpZ = (dx / len) * width * 0.5;
      
      final left3D = Vector3D(center.x - perpX, center.y, center.z - perpZ);
      final right3D = Vector3D(center.x + perpX, center.y, center.z + perpZ);

      // Project all 4 leaf nodes to 2D
      final baseProj = project(attach.x, attach.y, attach.z, size);
      final tipProj = project(tip.x, tip.y, tip.z, size);
      final leftProj = project(left3D.x, left3D.y, left3D.z, size);
      final rightProj = project(right3D.x, right3D.y, right3D.z, size);

      elements.add(
        PaintElement(
          depth: (baseProj['depth'] + tipProj['depth'] + leftProj['depth'] + rightProj['depth']) / 4,
          onPaint: (canvas) {
            final isHighlighted = selectedSensorIndex == index && index >= 0;

            final double leafHealth;
            if (index == -1) {
              leafHealth = (_leafHealth(0) + _leafHealth(2)) / 2;
            } else if (index == -2) {
              leafHealth = (_leafHealth(1) + _leafHealth(3)) / 2;
            } else {
              leafHealth = _leafHealth(index);
            }
            final Color stressColor = _heatColor(leafHealth);
            final Color darkStress = Color.lerp(stressColor, const Color(0xFF1B5E20), 0.3)!;

            final leafPaint = Paint()..style = PaintingStyle.fill;
            final bp = baseProj['offset'] as Offset;
            final tp = tipProj['offset'] as Offset;
            if (bp.dx.isFinite && bp.dy.isFinite && tp.dx.isFinite && tp.dy.isFinite) {
              leafPaint.shader = LinearGradient(
                colors: [stressColor, darkStress],
              ).createShader(Rect.fromPoints(bp, tp));
            }

            final borderPaint = Paint()
              ..color = isHighlighted ? const Color(0xFF00979D) : stressColor.withValues(alpha: 0.6)
              ..strokeWidth = isHighlighted ? 2.5 : 1.2
              ..style = PaintingStyle.stroke;

            final path = Path();
            path.moveTo(baseProj['offset'].dx, baseProj['offset'].dy);
            path.quadraticBezierTo(leftProj['offset'].dx, leftProj['offset'].dy, tipProj['offset'].dx, tipProj['offset'].dy);
            path.quadraticBezierTo(rightProj['offset'].dx, rightProj['offset'].dy, baseProj['offset'].dx, baseProj['offset'].dy);

            canvas.drawPath(path, leafPaint);
            canvas.drawPath(path, borderPaint);

            // Draw center vein
            final veinPaint = Paint()
              ..color = isHighlighted ? Colors.white.withValues(alpha: 0.9) : stressColor.withValues(alpha: 0.5)
              ..strokeWidth = 1.5 * baseProj['scale']
              ..style = PaintingStyle.stroke;
            canvas.drawLine(baseProj['offset'], tipProj['offset'], veinPaint);

            // Draw micro secondary leaf veins
            final v1 = Offset(
              baseProj['offset'].dx + (tipProj['offset'].dx - baseProj['offset'].dx) * 0.35,
              baseProj['offset'].dy + (tipProj['offset'].dy - baseProj['offset'].dy) * 0.35,
            );
            final v2 = Offset(
              baseProj['offset'].dx + (tipProj['offset'].dx - baseProj['offset'].dx) * 0.65,
              baseProj['offset'].dy + (tipProj['offset'].dy - baseProj['offset'].dy) * 0.65,
            );
            canvas.drawLine(v1, leftProj['offset'], veinPaint);
            canvas.drawLine(v1, rightProj['offset'], veinPaint);
            canvas.drawLine(v2, Offset(
              leftProj['offset'].dx + (tipProj['offset'].dx - leftProj['offset'].dx) * 0.4,
              leftProj['offset'].dy + (tipProj['offset'].dy - leftProj['offset'].dy) * 0.4,
            ), veinPaint);
            canvas.drawLine(v2, Offset(
              rightProj['offset'].dx + (tipProj['offset'].dx - rightProj['offset'].dx) * 0.4,
              rightProj['offset'].dy + (tipProj['offset'].dy - rightProj['offset'].dy) * 0.4,
            ), veinPaint);
          },
        ),
      );
    }
  }

  void _generateSensorNodeElements(List<Vector3D> stem, Size size, List<PaintElement> elements) {
    // Sensor indices: 0: Soil (root), 1: Temp (leaf 2 tip), 2: Humidity (leaf 1 tip), 3: Light (leaf 5 tip)
    List<Map<String, dynamic>> sensors = [
      {
        'index': 0,
        'coord': Vector3D(0, 100, 0), // roots base
        'label': 'Soil: ${soil.toStringAsFixed(0)}%',
        'color': const Color(0xFF3B82F6),
        'verticalOffset': 30.0,
      },
      {
        'index': 1,
        'coord': Vector3D(70, -10, 45), // Leaf 2 tip
        'label': 'Temp: ${temp.toStringAsFixed(1)}\u00B0C',
        'color': temp < 18.0 ? const Color(0xFF3B82F6) : (temp <= 28.0 ? const Color(0xFF10B981) : (temp <= 32.0 ? const Color(0xFFFFA000) : const Color(0xFFF43F5E))),
        'verticalOffset': -10.0,
      },
      {
        'index': 2,
        'coord': Vector3D(-70, 40, 50), // Leaf 1 tip
        'label': 'Humidity: ${humidity.toStringAsFixed(0)}%',
        'color': const Color(0xFF10B981),
        'verticalOffset': -20.0,
      },
      {
        'index': 3,
        'coord': Vector3D(0, -170, 0), // Leaf 5 tip
        'label': 'Light: ${light.toStringAsFixed(0)} LUX',
        'color': const Color(0xFFFFB300),
        'verticalOffset': -40.0,
      },
    ];

    const double cardHeight = 28.0;
    const double cardWidth = 110.0;
    const double margin = 12.0;

    // First pass: project all sensors and compute card target positions
    List<_CardData> cardDataList = [];
    for (var sensor in sensors) {
      final int idx = sensor['index'];
      final Vector3D coord = sensor['coord'];
      final String label = sensor['label'];
      final Color color = sensor['color'];
      final double verticalOffset = sensor['verticalOffset'];

      final proj = project(coord.x, coord.y, coord.z, size);
      final Offset offset = proj['offset'] as Offset;
      final double scale = (proj['scale'] as num).toDouble();
      final double depth = (proj['depth'] as num).toDouble();

      if (offset.dx.isNaN || offset.dy.isNaN) continue;

      // Smart anchoring: flip card side based on node X position
      final bool nodeInRightHalf = offset.dx > size.width / 2;
      final bool effectiveAlignRight = !nodeInRightHalf;

      // Smart vertical: card goes opposite direction from node Y
      final double baseVOffset = verticalOffset.abs();
      final double effectiveVOffset = (offset.dy < size.height * 0.4) ? baseVOffset : -baseVOffset;

      final double targetX = effectiveAlignRight
          ? (offset.dx + margin).clamp(margin, size.width - cardWidth - margin)
          : (offset.dx - cardWidth - margin).clamp(margin, size.width - cardWidth - margin);
      final double targetY = (offset.dy + effectiveVOffset)
          .clamp(cardHeight / 2 + margin, size.height - cardHeight / 2 - margin);

      cardDataList.add(_CardData(
        index: idx,
        label: label,
        color: color,
        offset: offset,
        scale: scale,
        depth: depth,
        targetX: targetX,
        targetY: targetY,
        alignRight: effectiveAlignRight,
      ));
    }

    // Second pass: collision detection — push overlapping cards apart vertically
    const double collisionThreshold = 32.0;
    cardDataList.sort((a, b) => a.targetY.compareTo(b.targetY));
    for (int i = 1; i < cardDataList.length; i++) {
      final prev = cardDataList[i - 1];
      final curr = cardDataList[i];
      final double gap = curr.targetY - prev.targetY;
      if (gap < collisionThreshold) {
        final double push = collisionThreshold - gap;
        final double newY = (curr.targetY + push).clamp(
          cardHeight / 2 + margin,
          size.height - cardHeight / 2 - margin,
        );
        curr.targetY = newY;
      }
    }

    // Third pass: draw all elements with adjusted positions
    for (final card in cardDataList) {
      final int idx = card.index;
      final Offset offset = card.offset;
      final double scale = card.scale;
      final double depth = card.depth;
      final Color color = card.color;
      final Offset targetCardOffset = Offset(card.targetX, card.targetY);

      elements.add(
        PaintElement(
          depth: depth - 5.0,
          onPaint: (canvas) {
            final isSelected = selectedSensorIndex == idx;
            
            // Draw pulsating outer glow circle
            final double glowPulse = isSelected ? (pulse * 15.0 + 8.0) : (pulse * 8.0 + 4.0);
            final double glowOpacity = isSelected ? (0.45 * (1.0 - pulse)) : (0.3 * (1.0 - pulse));
            
            final glowPaint = Paint()
              ..color = color.withOpacity(glowOpacity)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, glowPulse * scale, glowPaint);

            // Draw concentric spinning target reticle if selected
            if (isSelected) {
              final reticlePaint = Paint()
                ..color = color.withOpacity(0.5)
                ..strokeWidth = 1.0
                ..style = PaintingStyle.stroke;
              _drawDashedCircle(canvas, offset, 15.0 * scale, reticlePaint, angleOffset: pulse * 2 * math.pi);
              _drawDashedCircle(canvas, offset, 22.0 * scale, reticlePaint, angleOffset: -pulse * 2 * math.pi);
            }

            // Draw core sensor dot
            final dotPaint = Paint()
              ..color = color
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, (isSelected ? 6.0 : 4.0) * scale, dotPaint);

            final innerPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
            canvas.drawCircle(offset, (isSelected ? 2.5 : 1.5) * scale, innerPaint);

            final bool showHudCard = (size.width > 500) || isSelected;

            if (showHudCard) {
              final linePaint = Paint()
                ..color = color.withOpacity(isSelected ? 0.8 : 0.25)
                ..strokeWidth = isSelected ? 1.5 : 0.8
                ..style = PaintingStyle.stroke;

              _drawDottedLine(canvas, offset, targetCardOffset, linePaint);

              _drawHudCard(canvas, targetCardOffset, card.label, color, card.alignRight, isSelected);
            }
          },
        ),
      );
    }
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 3.0;
    const double dashSpace = 4.0;
    
    double dx = p2.dx - p1.dx;
    double dy = p2.dy - p1.dy;
    double distance = math.sqrt(dx * dx + dy * dy);
    
    double percentStart = 0.0;
    while (percentStart * distance < distance) {
      double percentEnd = (percentStart * distance + dashWidth) / distance;
      if (percentEnd > 1.0) percentEnd = 1.0;
      canvas.drawLine(
        Offset(p1.dx + dx * percentStart, p1.dy + dy * percentStart),
        Offset(p1.dx + dx * percentEnd, p1.dy + dy * percentEnd),
        paint,
      );
      percentStart += (dashWidth + dashSpace) / distance;
    }
  }

  void _drawHudCard(Canvas canvas, Offset position, String label, Color color, bool alignRight, bool isSelected) {
    // Dimensions
    const double width = 110.0;
    const double height = 28.0;

    final double x = alignRight ? position.dx : (position.dx - width);
    final double y = position.dy - height / 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height),
      const Radius.circular(8),
    );

    // Card background (translucent dark or themed light glass)
    final cardBgPaint = Paint()
      ..color = isSelected 
        ? const Color(0xFF1E293B).withValues(alpha: 0.9) 
        : Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, cardBgPaint);

    // Card border
    final cardBorderPaint = Paint()
      ..color = isSelected ? color : Colors.black12
      ..strokeWidth = isSelected ? 1.5 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rect, cardBorderPaint);

    // Anchor visual indicator
    final tagPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(alignRight ? x : (x + width - 3.0), y + 6, 3.0, height - 12),
      tagPaint,
    );

    // Text drawing using TextPainter — constrain layout to card interior width
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    textPainter.layout(maxWidth: width - 14.0);
    // Draw text centered vertically inside the card bounds
    final textX = x + (alignRight ? 8.0 : 6.0);
    final textY = y + (height - textPainter.height) / 2;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {double angleOffset = 0.0}) {
    const int segments = 12;
    final double sweep = (2 * math.pi) / segments;
    for (int i = 0; i < segments; i++) {
      if (i % 2 == 0) {
        final double start = i * sweep + angleOffset;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep * 0.6,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant Plant3DPainter oldDelegate) {
    return oldDelegate.angleY != angleY ||
        oldDelegate.angleX != angleX ||
        oldDelegate.pulse != pulse ||
        oldDelegate.soil != soil ||
        oldDelegate.temp != temp ||
        oldDelegate.humidity != humidity ||
        oldDelegate.light != light ||
        oldDelegate.selectedSensorIndex != selectedSensorIndex ||
        oldDelegate.scanProgress != scanProgress ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.isPumpOn != isPumpOn ||
        oldDelegate.showSoil != showSoil ||
        oldDelegate.cameraYOffset != cameraYOffset;
  }
}

// Wrapper for depth sorted canvas drawing elements
class PaintElement {
  final double depth;
  final Function(Canvas) onPaint;

  PaintElement({
    required this.depth,
    required this.onPaint,
  });

  void paint(Canvas canvas, Size size) {
    onPaint(canvas);
  }
}

// Helper class for sensor HUD card positioning
class _CardData {
  final int index;
  final String label;
  final Color color;
  final Offset offset;
  final double scale;
  final double depth;
  final double targetX;
  double targetY;
  final bool alignRight;

  _CardData({
    required this.index,
    required this.label,
    required this.color,
    required this.offset,
    required this.scale,
    required this.depth,
    required this.targetX,
    required this.targetY,
    required this.alignRight,
  });
}
