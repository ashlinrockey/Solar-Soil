import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import '../providers/telemetry_provider.dart';
import 'speech_helper.dart';

class RootWiseAssistantSheet extends StatefulWidget {
  final String gardenName;

  const RootWiseAssistantSheet({
    super.key,
    this.gardenName = 'Spinach Garden',
  });

  @override
  State<RootWiseAssistantSheet> createState() => _RootWiseAssistantSheetState();
}

class _RootWiseAssistantSheetState extends State<RootWiseAssistantSheet> {
  bool _isListening = false;
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  void _sendChatMessage(TelemetryProvider provider) {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || provider.isAiTyping) return;
    _chatInputController.clear();
    provider.askAI(text).then((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _startSpeechToText(TelemetryProvider provider) async {
    if (!isSpeechSupported()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Speech not supported in this browser"), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
        );
      }
      return;
    }
    setState(() => _isListening = true);
    final transcript = await startSpeechRecognition();
    if (transcript.isNotEmpty) {
      _chatInputController.text = transcript;
    }
    if (mounted) setState(() => _isListening = false);
  }

  Widget _buildChatEmptyState(TelemetryProvider provider) {
    final suggestions = [
      'Is my ${widget.gardenName.split(' ').first} stressed?',
      'Should I irrigate now?',
      'What does ${provider.soil.toStringAsFixed(0)}% soil moisture mean?',
      'Why is my temp at ${provider.temp.toStringAsFixed(0)}°C?',
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Lottie.asset('assets/plant_loader.json'),
          ),
          const SizedBox(height: 4),
          const Text('Ask anything about your crop',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text('I have live access to your sensor data',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: suggestions.map((s) => GestureDetector(
              onTap: () {
                _chatInputController.text = s;
                _sendChatMessage(provider);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00979D).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00979D).withOpacity(0.2)),
                ),
                child: Text(s, style: const TextStyle(fontSize: 11, color: Color(0xFF00979D), fontWeight: FontWeight.w600)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF00979D), Color(0xFF02C39A)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: msg.isUser ? const Color(0xFF00979D) : Colors.grey[50],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: msg.isUser
                        ? const Color(0xFF00979D).withOpacity(0.15)
                        : Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 12,
                  color: msg.isUser ? Colors.white : const Color(0xFF1E293B),
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (msg.isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF00979D), Color(0xFF02C39A)]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => AnimatedContainer(
                duration: Duration(milliseconds: 400 + i * 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF00979D),
                  shape: BoxShape.circle,
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TelemetryProvider>();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00979D).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: Column(
          children: [
            // Premium Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D9488), Color(0xFF00979D)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RootWise Assistant',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Analyzes live sensor telemetry',
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: provider.clearChat,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.refresh, color: Colors.white.withOpacity(0.9), size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Chat body
            Expanded(
              child: provider.chatMessages.isEmpty
                  ? _buildChatEmptyState(provider)
                  : ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.chatMessages.length + (provider.isAiTyping ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (provider.isAiTyping && index == provider.chatMessages.length) {
                          return _buildTypingBubble();
                        }
                        final msg = provider.chatMessages[index];
                        return _buildChatBubble(msg);
                      },
                    ),
            ),

            // Pinned input
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatInputController,
                      enabled: !provider.isAiTyping,
                      decoration: InputDecoration(
                        hintText: 'Ask RootWise a custom question...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: Colors.grey.withOpacity(0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty) _sendChatMessage(provider);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: provider.isAiTyping ? null : () => _startSpeechToText(provider),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.red.withOpacity(0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.redAccent : Colors.grey[500],
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: provider.isAiTyping ? null : () => _sendChatMessage(provider),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF0D9488),
                      child: provider.isAiTyping
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }
}
