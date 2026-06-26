import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';

class SensorNode {
  final String id;
  final String name;
  final LatLng position;
  final double soilMoisture;
  final double temperature;
  final double solarVoltage;
  final String status;
  final List<FlSpot> trendData;

  const SensorNode({
    required this.id,
    required this.name,
    required this.position,
    required this.soilMoisture,
    required this.temperature,
    required this.solarVoltage,
    required this.status,
    required this.trendData,
  });

  Color get markerColor {
    switch (status) {
      case 'optimal': return const Color(0xFF10B981);
      case 'warning': return const Color(0xFFFFA000);
      case 'critical': return const Color(0xFFF43F5E);
      default: return const Color(0xFF00979D);
    }
  }
}

class SensorMapView extends StatefulWidget {
  final List<SensorNode> nodes;
  final double defaultLat;
  final double defaultLng;

  const SensorMapView({
    super.key,
    required this.nodes,
    this.defaultLat = 50.717,
    this.defaultLng = 12.495,
  });

  @override
  State<SensorMapView> createState() => _SensorMapViewState();
}

class _SensorMapViewState extends State<SensorMapView> {
  SensorNode? _selectedNode;
  final MapController _mapController = MapController();
  double _maxWidth = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxWidth = constraints.maxWidth;
        final isCompact = constraints.maxWidth < 500;
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(widget.defaultLat, widget.defaultLng),
                  initialZoom: 16.0,
                  onTap: (_, __) => setState(() => _selectedNode = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.solarsoil.dashboard',
                  ),
                  MarkerLayer(
                    markers: widget.nodes.map((node) {
                      return Marker(
                        point: node.position,
                        width: isCompact ? 80 : 100,
                        height: isCompact ? 80 : 100,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedNode = node),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                                ),
                                child: Text(
                                  node.name,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 2),
                              _PulsingMarker(color: node.markerColor, isSelected: _selectedNode?.id == node.id),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_selectedNode != null)
                    _buildPopupCard(_selectedNode!, isCompact),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopupCard(SensorNode node, bool isCompact) {
    final cardWidth = isCompact ? _maxWidth * 0.9 : 340.0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: cardWidth,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: node.markerColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _selectedNode = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(),
                _sensorRow(Icons.water_drop, 'Soil Moisture', '${node.soilMoisture.toStringAsFixed(0)}%', const Color(0xFF10B981)),
                const SizedBox(height: 8),
                _sensorRow(Icons.thermostat, 'Temperature', '${node.temperature.toStringAsFixed(1)}°C', Colors.orange),
                const SizedBox(height: 8),
                _sensorRow(Icons.solar_power, 'Solar Output', '${node.solarVoltage.toStringAsFixed(1)}V', Colors.amber),
                const SizedBox(height: 16),
                const Text('24-Hour Trend', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 60,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: node.trendData,
                          isCurved: true,
                          color: node.markerColor,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: node.markerColor.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sensorRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}

class _PulsingMarker extends StatefulWidget {
  final Color color;
  final bool isSelected;

  const _PulsingMarker({required this.color, required this.isSelected});

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final pulse = 0.6 + 0.4 * _ctrl.value;
        return SizedBox(
          width: 24, height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.isSelected)
                Transform.scale(
                  scale: 1.0 + 0.4 * _ctrl.value,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.2 * (1 - _ctrl.value)),
                    ),
                  ),
                ),
              Container(
                width: 12 * pulse, height: 12 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: widget.color.withOpacity(0.5), blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
