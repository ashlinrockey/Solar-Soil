import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/telemetry_provider.dart';

class TelemetryChart extends StatelessWidget {
  final List<TelemetryReading> history;

  const TelemetryChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00979D)),
            SizedBox(height: 16),
            Text(
              "Synchronizing database time-series logs...",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            )
          ],
        ),
      );
    }

    // Limit display to the last 7 readings (similar to the HTML chart's 7 tick marks)
    final displayHistory = history.length > 7 
        ? history.sublist(history.length - 7) 
        : history;

    // Convert list to spots
    List<FlSpot> soilSpots = [];
    List<FlSpot> solarSpots = [];
    for (int i = 0; i < displayHistory.length; i++) {
      soilSpots.add(FlSpot(i.toDouble(), displayHistory[i].soil));
      solarSpots.add(FlSpot(i.toDouble(), displayHistory[i].v));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: 20,
          verticalInterval: 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.black.withOpacity(0.03),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.black.withOpacity(0.03),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                );
              },
              reservedSize: 28,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (idx >= 0 && idx < displayHistory.length) {
                  final time = displayHistory[idx].time;
                  final timeStr = "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8.0,
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: false,
        ),
        minX: 0,
        maxX: (displayHistory.length - 1).toDouble(),
        minY: 0,
        maxY: 100, // percentage and voltage normalized safely
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.white.withOpacity(0.95),
            tooltipBorder: BorderSide(color: Colors.black.withOpacity(0.05)),
            tooltipRoundedRadius: 12,
            tooltipPadding: const EdgeInsets.all(12),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final isSoil = touchedSpot.barIndex == 0;
                final suffix = isSoil ? '%' : ' V';
                final label = isSoil ? 'Moisture' : 'Solar';
                return LineTooltipItem(
                  '$label: ${touchedSpot.y.toStringAsFixed(1)}$suffix',
                  TextStyle(
                    color: isSoil ? const Color(0xFF3B82F6) : const Color(0xFF00979D),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          // 1. Soil Moisture Line
          LineChartBarData(
            spots: soilSpots,
            isCurved: true,
            color: const Color(0xFF3B82F6),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: const Color(0xFF3B82F6),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.4),
                  const Color(0xFF3B82F6).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          // 2. Solar Output Line
          LineChartBarData(
            spots: solarSpots.map((spot) {
              // Scale voltage 0-6V up to 0-100 grid for dual axis overlay
              final scaledY = (spot.y / 6.0) * 100.0;
              return FlSpot(spot.x, scaledY.clamp(0.0, 100.0));
            }).toList(),
            isCurved: true,
            color: const Color(0xFF00979D),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: const Color(0xFF00979D),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00979D).withOpacity(0.4),
                  const Color(0xFF00979D).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
