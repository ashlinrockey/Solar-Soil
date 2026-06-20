import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/telemetry_provider.dart';

class TelemetryChart extends StatelessWidget {
  final List<TelemetryReading> history;
  final String activeMetric;

  const TelemetryChart({super.key, required this.history, this.activeMetric = 'moisture'});

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

    final displayHistory = history.length > 7
        ? history.sublist(history.length - 7)
        : history;

    ({Color color, String label, String suffix, List<FlSpot> spots, double maxY}) metric;
    switch (activeMetric) {
      case 'temperature':
        final spots = displayHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.temp)).toList();
        metric = (color: const Color(0xFFF43F5E), label: 'Temp', suffix: '\u00B0C', spots: spots, maxY: 60);
      case 'humidity':
        final spots = displayHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.humidity)).toList();
        metric = (color: const Color(0xFF10B981), label: 'Humidity', suffix: '%', spots: spots, maxY: 100);
      case 'light':
        final spots = displayHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.v)).toList();
        metric = (color: const Color(0xFFF59E0B), label: 'Solar', suffix: ' V', spots: spots, maxY: 6);
      default:
        final spots = displayHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.soil)).toList();
        metric = (color: const Color(0xFF3B82F6), label: 'Moisture', suffix: '%', spots: spots, maxY: 100);
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: metric.maxY / 5,
          verticalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.black.withOpacity(0.03), strokeWidth: 1),
          getDrawingVerticalLine: (value) => FlLine(color: Colors.black.withOpacity(0.03), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: metric.maxY / 5,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500, fontSize: 10),
              ),
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
                  final t = displayHistory[idx].time;
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8,
                    child: Text(
                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500, fontSize: 10),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (displayHistory.length - 1).toDouble(),
        minY: 0,
        maxY: metric.maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.white.withOpacity(0.95),
            tooltipBorder: BorderSide(color: Colors.black.withOpacity(0.05)),
            tooltipRoundedRadius: 12,
            tooltipPadding: const EdgeInsets.all(12),
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem(
              '${metric.label}: ${spot.y.toStringAsFixed(1)}${metric.suffix}',
              TextStyle(color: metric.color, fontWeight: FontWeight.bold, fontSize: 11),
            )).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: metric.spots,
            isCurved: true,
            color: metric.color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: metric.color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [metric.color.withOpacity(0.4), metric.color.withOpacity(0.0)],
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
