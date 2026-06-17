import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class TelemetryReading {
  final double temp;
  final double soil;
  final double v;
  final double humidity;
  final double current;
  final DateTime time;

  TelemetryReading({
    required this.temp,
    required this.soil,
    required this.v,
    required this.humidity,
    required this.current,
    required this.time,
  });

  factory TelemetryReading.fromJson(Map<String, dynamic> json) {
    return TelemetryReading(
      temp: (json['temp'] ?? 0.0).toDouble(),
      soil: (json['soil'] ?? 0.0).toDouble(),
      v: (json['v'] ?? 0.0).toDouble(),
      humidity: (json['humidity'] ?? 0.0).toDouble(),
      current: (json['current'] ?? 0.0).toDouble(),
      time: json['time'] != null
          ? DateTime.parse(json['time'])
          : (json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now()),
    );
  }
}

// ── AI Health Score ──────────────────────────────────────────────────────────
class HealthScore {
  final int score;
  final String status;
  final String label;
  final String color;
  final List<String> issues;
  final List<String> tips;

  const HealthScore({
    required this.score,
    required this.status,
    required this.label,
    required this.color,
    required this.issues,
    required this.tips,
  });

  factory HealthScore.fromJson(Map<String, dynamic> json) {
    return HealthScore(
      score: (json['score'] ?? 0).toInt(),
      status: json['status'] ?? 'unknown',
      label: json['label'] ?? 'Unknown',
      color: json['color'] ?? '#94A3B8',
      issues: List<String>.from(json['issues'] ?? []),
      tips: List<String>.from(json['tips'] ?? []),
    );
  }

  Color get dartColor {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  static HealthScore get loading => const HealthScore(
    score: 0, status: 'loading', label: 'Calculating…',
    color: '#94A3B8', issues: [], tips: [],
  );
}

// ── Irrigation Advice ────────────────────────────────────────────────────────
class IrrigationAdvice {
  final String action;   // 'irrigate_now' | 'hold' | 'schedule_for_dusk'
  final String urgency;  // 'critical' | 'moderate' | 'low' | 'none' | 'caution'
  final String reason;

  const IrrigationAdvice({
    required this.action,
    required this.urgency,
    required this.reason,
  });

  factory IrrigationAdvice.fromJson(Map<String, dynamic> json) {
    return IrrigationAdvice(
      action: json['action'] ?? 'hold',
      urgency: json['urgency'] ?? 'none',
      reason: json['reason'] ?? '',
    );
  }

  String get actionLabel {
    switch (action) {
      case 'irrigate_now':    return 'Irrigate Now';
      case 'schedule_for_dusk': return 'Schedule for Dusk';
      case 'hold':
      default:                return 'Hold';
    }
  }

  IconData get actionIcon {
    switch (action) {
      case 'irrigate_now':      return Icons.water_drop;
      case 'schedule_for_dusk': return Icons.schedule;
      case 'hold':
      default:                  return Icons.pause_circle_outline;
    }
  }

  Color get urgencyColor {
    switch (urgency) {
      case 'critical': return const Color(0xFFEF4444);
      case 'moderate': return const Color(0xFFF97316);
      case 'low':      return const Color(0xFFF59E0B);
      case 'caution':  return const Color(0xFF8B5CF6);
      case 'none':
      default:         return const Color(0xFF10B981);
    }
  }

  static IrrigationAdvice get loading => const IrrigationAdvice(
    action: 'hold', urgency: 'none', reason: 'Analysing sensor data…',
  );
}

// ── Anomaly Alert ────────────────────────────────────────────────────────────
class SensorAlert {
  final String sensor;
  final double value;
  final double mean;
  final double z;
  final String direction;
  final String message;
  final DateTime time;

  SensorAlert({
    required this.sensor,
    required this.value,
    required this.mean,
    required this.z,
    required this.direction,
    required this.message,
  }) : time = DateTime.now();

  factory SensorAlert.fromJson(Map<String, dynamic> json) {
    return SensorAlert(
      sensor: json['sensor'] ?? '',
      value: (json['value'] ?? 0.0).toDouble(),
      mean: (json['mean'] ?? 0.0).toDouble(),
      z: (json['z'] ?? 0.0).toDouble(),
      direction: json['direction'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

// ── Chat Message ─────────────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  ChatMessage({required this.text, required this.isUser}) : time = DateTime.now();
}

// ── Leaf Diagnostic ─────────────────────────────────────────────────────────
class LeafDiagnostic {
  final String diagnosis;
  final String severity;
  final String confidence;
  final List<String> issues;
  final List<String> remedies;

  LeafDiagnostic({
    required this.diagnosis,
    required this.severity,
    required this.confidence,
    required this.issues,
    required this.remedies,
  });

  factory LeafDiagnostic.fromJson(Map<String, dynamic> json) {
    return LeafDiagnostic(
      diagnosis: json['diagnosis'] ?? 'No analysis available.',
      severity: json['severity'] ?? 'LOW',
      confidence: json['confidence'] ?? 'Unknown',
      issues: List<String>.from(json['issues'] ?? []),
      remedies: List<String>.from(json['remedies'] ?? []),
    );
  }

  Color get severityColor {
    switch (severity.toUpperCase()) {
      case 'HIGH': return const Color(0xFFEF4444);
      case 'MEDIUM': return const Color(0xFFF59E0B);
      case 'LOW':
      default: return const Color(0xFF10B981);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TELEMETRY PROVIDER
// ─────────────────────────────────────────────────────────────────────────────
class TelemetryProvider extends ChangeNotifier {
  // Config URLs — dynamic for web based on browser location, absolute for native
  String get _baseHttpUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      final port = Uri.base.port;
      final scheme = Uri.base.scheme;
      return port != 80 && port != 443
          ? '$scheme://$host:$port'
          : '$scheme://$host';
    }
    return 'https://solarsoil.ashlin.rocks';
  }

  String get _baseWsUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      final port = Uri.base.port;
      final protocol = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      return port != 80 && port != 443
          ? '$protocol://$host:$port'
          : '$protocol://$host';
    }
    return 'wss://solarsoil.ashlin.rocks';
  }

  // ── Telemetry State ────────────────────────────────────────────────────────
  double _temp = 28.0;
  double _soil = 42.0;
  double _v = 5.2;
  double _humidity = 65.0;
  double _current = 410.0;
  bool _isConnected = false;
  bool _isMqttConnected = false;
  int _mqttPacketCount = 0;
  DateTime? _lastMqttTime;
  bool _isPumpOn = false;

  // History & Logs
  List<TelemetryReading> _history = [];
  final List<String> _terminalLogs = [];

  // ── AI State ───────────────────────────────────────────────────────────────
  HealthScore _healthScore = HealthScore.loading;
  IrrigationAdvice _irrigationAdvice = IrrigationAdvice.loading;
  final List<SensorAlert> _alerts = [];
  final List<ChatMessage> _chatMessages = [];
  bool _isAiTyping = false;

  WebSocketChannel? _wsChannel;
  Timer? _reconnectTimer;

  // Getters — Telemetry
  double get temp => _temp;
  double get soil => _soil;
  double get v => _v;
  double get humidity => _humidity;
  double get current => _current;
  bool get isConnected => _isConnected;
  bool get isMqttConnected => _isMqttConnected;
  int get mqttPacketCount => _mqttPacketCount;
  DateTime? get lastMqttTime => _lastMqttTime;
  bool get isPumpOn => _isPumpOn;
  List<TelemetryReading> get history => _history;
  List<String> get terminalLogs => _terminalLogs;

  // Getters — AI
  HealthScore get healthScore => _healthScore;
  IrrigationAdvice get irrigationAdvice => _irrigationAdvice;
  List<SensorAlert> get alerts => List.unmodifiable(_alerts);
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  bool get isAiTyping => _isAiTyping;
  bool get hasAlerts => _alerts.isNotEmpty;

  TelemetryProvider() {
    init();
  }

  void init() {
    addTerminalLog("Connecting to Web Application Gateway...");
    fetchHistory();
    _connectWebSocket();
  }

  // ── API CALLS ──────────────────────────────────────────────────────────────

  void _seedMockHistory() {
    final now = DateTime.now();
    _history = List.generate(7, (i) {
      final timeOffset = now.subtract(Duration(minutes: (7 - i) * 10));
      return TelemetryReading(
        temp: 24.5 + (i * 0.8),
        soil: 42.0 + (i * 1.5) - (i % 2 == 0 ? 3.0 : 0.0),
        v: 4.8 + (i * 0.15),
        humidity: 60.0 + (i * 1.2),
        current: 380.0 + (i * 15.0),
        time: timeOffset,
      );
    });
    addTerminalLog("Seeded dashboard spline chart with initial series logs.");
    notifyListeners();
  }

  Future<void> fetchHistory({String range = '24h'}) async {
    try {
      final response = await http.get(Uri.parse('$_baseHttpUrl/api/telemetry/history?range=$range'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _history = data.map((jsonItem) => TelemetryReading.fromJson(jsonItem)).toList();
        if (_history.isEmpty) {
          _seedMockHistory();
        } else {
          addTerminalLog("Loaded ${_history.length} historical logs from database (range: $range).");
          notifyListeners();
        }
      } else {
        addTerminalLog("ERR: Failed to fetch history. Seeding mock logs...");
        _seedMockHistory();
      }
    } catch (e) {
      addTerminalLog("ERR: Database history fetch failed. Seeding mock logs...");
      _seedMockHistory();
    }
  }

  // ── WEBSOCKET ──────────────────────────────────────────────────────────────

  void _connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(_baseWsUrl));

      _wsChannel!.stream.listen(
        (message) {
          _isConnected = true;
          _handleWsMessage(message);
        },
        onError: (error) {
          _handleDisconnect("Socket Error: $error");
        },
        onDone: () {
          _handleDisconnect("Server connection closed.");
        },
      );
    } catch (e) {
      _handleDisconnect("Socket Initialization failed: $e");
    }
  }

  void _handleWsMessage(String message) {
    try {
      final Map<String, dynamic> payload = json.decode(message);
      final String type = payload['type'] ?? '';

      if (type == 'mqtt_status') {
        _isMqttConnected = payload['connected'] == true;
        addTerminalLog(_isMqttConnected ? '[MQTT] Broker connected.' : '[MQTT] Broker disconnected.');
        notifyListeners();
        return;
      }

      if (type == 'live' || type == 'telemetry') {
        final data = payload['data'];
        _temp = (data['temp'] ?? _temp).toDouble();
        _soil = (data['soil'] ?? _soil).toDouble();
        _v = (data['v'] ?? _v).toDouble();
        _humidity = (data['humidity'] ?? _humidity).toDouble();
        _current = (data['current'] ?? _current).toDouble();

        // MQTT connection state and live activity tracking
        if (payload['mqttConnected'] != null) {
          _isMqttConnected = payload['mqttConnected'] == true;
        }
        _mqttPacketCount++;
        _lastMqttTime = DateTime.now();

        // Parse AI payloads if present
        if (payload['health'] != null) {
          _healthScore = HealthScore.fromJson(payload['health']);
        }
        if (payload['irrigation'] != null) {
          _irrigationAdvice = IrrigationAdvice.fromJson(payload['irrigation']);
        }

        // Add dynamic reading to chart history
        final reading = TelemetryReading(
          temp: _temp, soil: _soil, v: _v,
          humidity: _humidity, current: _current,
          time: DateTime.now(),
        );
        _history.add(reading);
        if (_history.length > 50) _history.removeAt(0);

        if (type == 'telemetry') {
          addTerminalLog("Received: {temp: $_temp°C, soil: $_soil%, v: ${_v}V, hum: $_humidity%, cur: ${_current}mA}");
          addTerminalLog("[AI] Health: ${_healthScore.score}/100 (${_healthScore.label}) | Pump: ${_irrigationAdvice.actionLabel}");
        } else {
          addTerminalLog("Synced live state with gateway.");
        }
        notifyListeners();

      } else if (type == 'alert') {
        final alertData = payload['alert'];
        if (alertData != null) {
          final alert = SensorAlert.fromJson(alertData);
          _alerts.insert(0, alert);
          if (_alerts.length > 10) _alerts.removeLast();
          addTerminalLog("⚠️ ANOMALY: ${alert.message}");
          notifyListeners();
        }

      } else if (type == 'error') {
        addTerminalLog("ERR: ${payload['message']}");
      }
    } catch (e) {
      addTerminalLog("ERR: Message decoding failed: $e");
    }
  }

  void _handleDisconnect(String reason) {
    if (_isConnected) {
      _isConnected = false;
      addTerminalLog("DISCONNECTED: $reason");
      notifyListeners();
    }

    _wsChannel = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      addTerminalLog("Attempting connection to Node.js backend...");
      _connectWebSocket();
    });
  }

  // ── AI ACTIONS ─────────────────────────────────────────────────────────────

  /// Send a question to the Gemini AI chat endpoint
  Future<void> askAI(String question) async {
    if (question.trim().isEmpty) return;

    // Add user message
    _chatMessages.add(ChatMessage(text: question.trim(), isUser: true));
    _isAiTyping = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseHttpUrl/api/ai/ask'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'question': question.trim()}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final answer = data['answer'] ?? 'No response received.';
        _chatMessages.add(ChatMessage(text: answer, isUser: false));
      } else {
        _chatMessages.add(ChatMessage(
          text: '⚠️ AI service error. Please try again.',
          isUser: false,
        ));
      }
    } catch (e) {
      _chatMessages.add(ChatMessage(
        text: '⚠️ Could not reach AI service. Check your connection.',
        isUser: false,
      ));
    }

    _isAiTyping = false;
    notifyListeners();
  }

  void clearAlerts() {
    _alerts.clear();
    notifyListeners();
  }

  void clearChat() {
    _chatMessages.clear();
    notifyListeners();
  }

  // ── ACTIONS ────────────────────────────────────────────────────────────────

  void addTerminalLog(String message) {
    final timeStr = DateTime.now().toLocal().toString().substring(11, 19);
    _terminalLogs.add("[$timeStr] $message");
    if (_terminalLogs.length > 30) _terminalLogs.removeAt(0);
    notifyListeners();
  }

  void togglePump() {
    _isPumpOn = !_isPumpOn;
    addTerminalLog("COMMAND: GPIO 23 Water Pump is now ${_isPumpOn ? 'ON' : 'OFF'}");
    notifyListeners();
  }

  // ── Leaf Scanning State ──────────────────────────────────────────────────────
  bool _isScanningImage = false;
  bool get isScanningImage => _isScanningImage;

  LeafDiagnostic? _lastDiagnostic;
  LeafDiagnostic? get lastDiagnostic => _lastDiagnostic;

  Future<LeafDiagnostic?> uploadAndScanLeafImage(List<int> bytes, String mimeType) async {
    _isScanningImage = true;
    _lastDiagnostic = null;
    notifyListeners();

    try {
      final base64String = base64Encode(bytes);
      
      final readingPayload = {
        'temp': temp,
        'soil': soil,
        'humidity': humidity,
        'v': v,
        'current': current,
      };

      final response = await http.post(
        Uri.parse('$_baseHttpUrl/api/ai/scan-image'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'image': base64String,
          'mimeType': mimeType,
          'reading': readingPayload,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _lastDiagnostic = LeafDiagnostic.fromJson(data);
        addTerminalLog("AI SCANNER: Leaf diagnosis scan complete. Severity: ${_lastDiagnostic!.severity}");
      } else {
        addTerminalLog("AI SCANNER ERROR: Server returned status code ${response.statusCode}");
      }
    } catch (e) {
      addTerminalLog("AI SCANNER ERROR: $e");
    } finally {
      _isScanningImage = false;
      notifyListeners();
    }
    return _lastDiagnostic;
  }
  
  void clearDiagnostic() {
    _lastDiagnostic = null;
    notifyListeners();
  }

  // ── AI Configuration ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAIConfig() async {
    try {
      final res = await http.get(Uri.parse('$_baseHttpUrl/api/ai/config'));
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (_) {}
    return {'provider': 'gemini', 'model': '', 'hasApiKey': false, 'apiKeyMasked': '', 'baseUrl': ''};
  }

  Future<bool> saveAIConfig(Map<String, dynamic> config) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseHttpUrl/api/ai/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testAIConnection() async {
    try {
      final res = await http.post(Uri.parse('$_baseHttpUrl/api/ai/test'));
      if (res.statusCode == 200) return json.decode(res.body);
      return {'ok': false, 'message': 'Connection failed'};
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }

  // ── Garden Zone Config ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGardenConfig() async {
    try {
      final res = await http.get(Uri.parse('$_baseHttpUrl/api/garden/config'));
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (_) {}
    return {'name': 'Spinach Garden', 'number': '08', 'zoneId': 'PL-02J', 'coverage': '200 m²'};
  }

  Future<bool> saveGardenConfig(Map<String, dynamic> config) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseHttpUrl/api/garden/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getAIMetrics() async {
    try {
      final res = await http.get(Uri.parse('$_baseHttpUrl/api/ai/metrics'));
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (_) {}
    return {};
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
