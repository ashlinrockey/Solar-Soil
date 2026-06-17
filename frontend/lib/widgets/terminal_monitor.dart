import 'package:flutter/material.dart';

class TerminalMonitor extends StatefulWidget {
  final List<String> logs;

  const TerminalMonitor({super.key, required this.logs});

  @override
  State<TerminalMonitor> createState() => _TerminalMonitorState();
}

class _TerminalMonitorState extends State<TerminalMonitor> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant TerminalMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new logs are received
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // slate-800 matching server terminal bg
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Terminal Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      "Serial Monitor",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                // Colored Mac-style dots
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.amberAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                  ],
                )
              ],
            ),
          ),
          
          // Terminal Console Text Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.logs.isEmpty ? 1 : widget.logs.length,
                itemBuilder: (context, index) {
                  if (widget.logs.isEmpty) {
                    return const Text(
                      "> Awaiting incoming packets from ESP32 nodes...",
                      style: TextStyle(
                        color: Color(0xFF00979D),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    );
                  }
                  
                  final log = widget.logs[index];
                  // Contextual coloring for log entries
                  Color textColor = Colors.grey[300]!;
                  if (log.contains("DISCONNECTED") || log.contains("ERR")) {
                    textColor = Colors.redAccent;
                  } else if (log.contains("Connecting") || log.contains("COMMAND")) {
                    textColor = const Color(0xFF00979D);
                  } else if (log.contains("Received")) {
                    textColor = Colors.blue[300]!;
                  } else if (log.contains("Loaded")) {
                    textColor = Colors.greenAccent;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      log,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
