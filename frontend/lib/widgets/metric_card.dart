import 'package:flutter/material.dart';
import 'glass_card.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color themeColor;
  final double progress;
  final String subtext;
  final bool isPH;
  final String badgeText;
  final DateTime? lastUpdated;
  final double? optimalMin;
  final double? optimalMax;
  final double? rawValue;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.themeColor,
    this.progress = 0.0,
    required this.subtext,
    this.isPH = false,
    this.badgeText = '',
    this.lastUpdated,
    this.optimalMin,
    this.optimalMax,
    this.rawValue,
  });

  bool get _isInOptimal {
    if (optimalMin == null || optimalMax == null || rawValue == null) return true;
    return rawValue! >= optimalMin! && rawValue! <= optimalMax!;
  }

  bool get _isBelowOptimal {
    if (optimalMin == null || rawValue == null) return false;
    return rawValue! < optimalMin!;
  }

  bool get _isAboveOptimal {
    if (optimalMax == null || rawValue == null) return false;
    return rawValue! > optimalMax!;
  }

  Color get _badgeColor {
    if (optimalMin == null || optimalMax == null || rawValue == null) return themeColor;
    if (_isInOptimal) return const Color(0xFF10B981);
    if (_isBelowOptimal) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'Live';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header of card (Icon & Badge)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: themeColor.withOpacity(0.2),
                  ),
                ),
                child: Icon(
                  icon,
                  color: themeColor,
                  size: 18,
                ),
              ),
              if (badgeText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _badgeColor.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rawValue != null && optimalMin != null)
                        Icon(_isInOptimal ? Icons.arrow_upward : Icons.arrow_upward, size: 8, color: _badgeColor),
                      if (rawValue != null && optimalMin != null) const SizedBox(width: 3),
                      Text(
                        badgeText,
                        style: TextStyle(
                          color: _badgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Metric Values
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                softWrap: true,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ]
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar with sweet spot overlay
          if (isPH)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.red[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.blue[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // Sweet spot zone overlay
                      if (optimalMin != null && optimalMax != null)
                        Positioned(
                          left: constraints.maxWidth * optimalMin!.clamp(0.0, 1.0),
                          width: constraints.maxWidth * (optimalMax! - optimalMin!).clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      // Filled progress
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: themeColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: themeColor.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 12),

          // Descriptive Tip Subtext + Timestamp
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 12, color: themeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtext,
                  style: TextStyle(color: Colors.grey[500], fontSize: 10, height: 1.3),
                ),
              ),
              if (lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    _formatTime(lastUpdated),
                    style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: _formatTime(lastUpdated) == 'Live' ? const Color(0xFF10B981) : Colors.grey[400]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
