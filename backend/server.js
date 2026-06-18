import express from 'express';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import fs from 'fs';
import { WebSocketServer, WebSocket } from 'ws';
import mqtt from 'mqtt';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import ExcelJS from 'exceljs';
import { writeTelemetry, getHistory } from './influxService.js';
import { authenticateUser, changePassword } from './authService.js';
import { computeHealthScore, computeIrrigationAdvice, askGemini, scanLeafImage, getAIConfig, setAIConfig, testAIConnection, getAIMetrics } from './aiService.js';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 5000;

// ── Global error handlers to prevent crashes ──────────────────────────────────
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught exception:', err.message);
  console.error(err.stack);
});
process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled rejection:', reason);
});

// ── HTTPS / SSL Setup ─────────────────────────────────────────────────────────
// If SSL_KEY_PATH and SSL_CERT_PATH are set, create an HTTPS server.
// For Cloudflare, generate an Origin Certificate from your Cloudflare dashboard
// and point SSL_CERT_PATH / SSL_KEY_PATH to the downloaded files.
const sslKeyPath = process.env.SSL_KEY_PATH || '';
const sslCertPath = process.env.SSL_CERT_PATH || '';
const sslCaPath = process.env.SSL_CA_PATH || '';
let useHttps = false;
let httpsOptions = null;

if (sslKeyPath && sslCertPath && fs.existsSync(sslKeyPath) && fs.existsSync(sslCertPath)) {
  try {
    httpsOptions = {
      key: fs.readFileSync(sslKeyPath, 'utf-8'),
      cert: fs.readFileSync(sslCertPath, 'utf-8'),
    };
    if (sslCaPath && fs.existsSync(sslCaPath)) {
      httpsOptions.ca = fs.readFileSync(sslCaPath, 'utf-8');
    }
    useHttps = true;
    console.log(`[SSL]  Certificate loaded: ${sslCertPath}`);
  } catch (e) {
    console.warn(`[SSL]  Failed to load certificates, falling back to HTTP:`, e.message);
  }
} else {
  console.log(`[SSL]  No SSL certs configured — running HTTP only.`);
  console.log(`[SSL]  Set SSL_KEY_PATH and SSL_CERT_PATH in .env for HTTPS.`);
}

// Enable CORS so our Flutter app (running on a different port/web) can connect without issues
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

// Serve root-level static assets (tailwind-built.css, style.css, index.html)
app.use(express.static(path.join(__dirname, '..'), {
  index: false, // Don't serve index.html from static — handled by route below
}));

// Serve Flutter web build static assets under /dashboard
const frontendBuildPath = path.join(__dirname, '../frontend/build/web');
app.use('/dashboard', express.static(frontendBuildPath, {
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.html') || filePath.endsWith('.js') || filePath.endsWith('.css') || filePath.endsWith('.json')) {
      const contentType = res.getHeader('Content-Type');
      if (contentType && !contentType.includes('charset')) {
        res.setHeader('Content-Type', `${contentType}; charset=utf-8`);
      }
    }
  }
}));

// In-memory cache for the latest telemetry reading
let lastReading = {
  temp: 28.0,
  soil: 42.0,
  v: 5.2,
  humidity: 65.0,
  current: 410.0,
  timestamp: new Date().toISOString()
};

// Rolling window for anomaly detection and irrigation advisor context (last 20 readings)
let rollingHistory = [];

// Latest AI analysis (broadcast with each telemetry update)
let lastHealthScore = computeHealthScore(lastReading);
let lastIrrigationAdvice = computeIrrigationAdvice(lastReading, rollingHistory);

// ─────────────────────────────────────────────────────────────────────────────
// AUTH ENDPOINTS
// ─────────────────────────────────────────────────────────────────────────────

// Login endpoint — validates credentials against the JSON user database
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ success: false, message: 'Username and password are required.' });
  }

  const result = await authenticateUser(username, password);

  if (result.success) {
    res.json({ success: true, user: result.user, message: result.message });
  } else {
    res.status(401).json({ success: false, message: result.message });
  }
});

app.post('/api/auth/change-password', async (req, res) => {
  const { username, oldPassword, newPassword } = req.body;

  if (!username || !oldPassword || !newPassword) {
    return res.status(400).json({ success: false, message: 'Username, current password, and new password are required.' });
  }
  if (newPassword.length < 4) {
    return res.status(400).json({ success: false, message: 'New password must be at least 4 characters.' });
  }

  const result = await changePassword(username, oldPassword, newPassword);
  if (result.success) {
    res.json({ success: true, message: result.message });
  } else {
    res.status(400).json({ success: false, message: result.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// HTTP REST ENDPOINTS
// ─────────────────────────────────────────────────────────────────────────────

// Check backend status
app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date() });
});

// Fetch latest telemetry values (useful for initial load)
app.get('/api/telemetry/live', (req, res) => {
  res.json({
    ...lastReading,
    health: lastHealthScore,
    irrigation: lastIrrigationAdvice,
  });
});

// Fetch historical records from InfluxDB
app.get('/api/telemetry/history', async (req, res) => {
  const range = req.query.range || '24h';
  try {
    const history = await getHistory(range);
    res.json(history);
  } catch (error) {
    console.error('Error fetching telemetry history:', error);
    res.status(500).json({ error: 'Failed to retrieve telemetry records from InfluxDB' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// EXCEL EXPORT
// ─────────────────────────────────────────────────────────────────────────────

function computeVPD(temp, humidity) {
  const es = 0.61078 * Math.exp((17.27 * temp) / (temp + 237.3));
  return es * (1 - humidity / 100);
}

app.get('/api/telemetry/export-excel', async (req, res) => {
  const range = req.query.range || '24h';
  const includeAI = req.query.includeAI === 'true';
  const startDate = req.query.start || '';
  const endDate = req.query.end || '';

  let history;
  try {
    history = await getHistory(range);
  } catch (_) {
    history = [];
  }
  if (!history || history.length === 0) {
    const now = Date.now();
    history = Array.from({ length: 10 }, (_, i) => ({
      time: new Date(now - (9 - i) * 600000).toISOString(),
      temp: 24.5 + i * 0.8,
      soil: 42.0 + i * 1.5 - (i % 2 === 0 ? 3.0 : 0.0),
      v: 4.8 + i * 0.15,
      humidity: 60.0 + i * 1.2,
      current: 380.0 + i * 15.0,
    }));
  }

  try {
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Live Telemetry Log');
    worksheet.views = [{ showGridLines: true }];

    worksheet.columns = [
      { header: 'Timestamp', key: 'timestamp', width: 22 },
      { header: 'Status', key: 'status', width: 16 },
      { header: 'Temperature (°C)', key: 'temp', width: 18 },
      { header: 'Soil Moisture (%)', key: 'moisture', width: 18 },
      { header: 'Solar Voltage (V)', key: 'solar', width: 16 },
      { header: 'Air Humidity (%)', key: 'humidity', width: 16 },
      { header: 'Solar Current (mA)', key: 'current', width: 16 },
      { header: 'VPD (kPa)', key: 'vpd', width: 14 },
      { header: 'Soil Depletion', key: 'depletion', width: 16 },
    ];

    // Style header row
    const headerRow = worksheet.getRow(1);
    headerRow.font = { name: 'Segoe UI', size: 11, bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF00A896' } };
    headerRow.alignment = { horizontal: 'center', vertical: 'middle' };
    headerRow.eachCell((cell) => {
      cell.border = {
        top: { style: 'thin', color: { argb: 'FFE2E8F0' } },
        left: { style: 'thin', color: { argb: 'FFE2E8F0' } },
        bottom: { style: 'thin', color: { argb: 'FFE2E8F0' } },
        right: { style: 'thin', color: { argb: 'FFE2E8F0' } },
      };
    });

    // AI summary header rows (before data)
    if (includeAI) {
      const soilVals = history.map(r => r.soil).filter(v => v != null);
      const tempVals = history.map(r => r.temp).filter(v => v != null);
      const avgSoil = soilVals.reduce((a, b) => a + b, 0) / soilVals.length;
      const avgTemp = tempVals.reduce((a, b) => a + b, 0) / tempVals.length;
      const maxTemp = Math.max(...tempVals);
      const status = avgSoil >= 40 && avgSoil <= 70 ? 'stable' : 'variable';
      const obs = maxTemp > 28
        ? `Ambient temp peaked near ${maxTemp.toFixed(1)}°C. Monitor shading.`
        : 'Temperatures remained within optimal range.';

      worksheet.spliceRows(1, 0, [], [], [], []);
      worksheet.mergeCells(1, 1, 1, 9);
      const titleCell = worksheet.getCell(1, 1);
      titleCell.value = `SOLAR SOIL AI COMPANION REPORT - ${new Date().toISOString().slice(0, 10)}`;
      titleCell.font = { name: 'Segoe UI', size: 13, bold: true, color: { argb: 'FF1E293B' } };
      titleCell.alignment = { horizontal: 'left', vertical: 'middle' };

      worksheet.mergeCells(2, 1, 2, 9);
      const statusCell = worksheet.getCell(2, 1);
      statusCell.value = `STATUS SUMMARY: Soil moisture remained highly ${status} (Avg: ${avgSoil.toFixed(1)}%).`;
      statusCell.font = { name: 'Segoe UI', size: 10, italic: true, color: { argb: 'FF64748B' } };

      worksheet.mergeCells(3, 1, 3, 9);
      const obsCell = worksheet.getCell(3, 1);
      obsCell.value = `CRITICAL OBSERVATION: ${obs}`;
      obsCell.font = { name: 'Segoe UI', size: 10, italic: true, color: { argb: 'FF64748B' } };

      worksheet.mergeCells(4, 1, 4, 9);
      worksheet.getCell(4, 1).value = '';
      // Re-insert column headers at row 5
      worksheet.getRow(5).values = ['Timestamp', 'Status', 'Temperature (°C)', 'Soil Moisture (%)', 'Solar Voltage (V)', 'Air Humidity (%)', 'Solar Current (mA)', 'VPD (kPa)', 'Soil Depletion'];
      worksheet.getRow(5).font = { name: 'Segoe UI', size: 11, bold: true, color: { argb: 'FFFFFFFF' } };
      worksheet.getRow(5).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF00A896' } };
      worksheet.getRow(5).alignment = { horizontal: 'center', vertical: 'middle' };
      worksheet.getRow(5).eachCell((cell) => {
        cell.border = {
          top: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          left: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          bottom: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          right: { style: 'thin', color: { argb: 'FFE2E8F0' } },
        };
      });
    }

    let prevSoil = null;
    for (const data of history) {
      const ts = data.time;
      const isDry = data.soil != null && data.soil < 30;
      const isHot = data.temp != null && data.temp > 35;
      const hasAlert = isDry || isHot;
      const status = hasAlert ? (isDry ? 'LOW MOISTURE' : 'HIGH TEMP') : 'OPTIMAL';
      const vpd = (data.temp != null && data.humidity != null) ? computeVPD(data.temp, data.humidity) : null;
      const depletion = prevSoil != null && data.soil != null ? (data.soil - prevSoil).toFixed(1) : '';
      prevSoil = data.soil;

      const rowData = {
        timestamp: ts,
        status,
        temp: data.temp,
        moisture: data.soil,
        solar: data.v,
        humidity: data.humidity,
        current: data.current,
        vpd: vpd != null ? parseFloat(vpd.toFixed(3)) : null,
        depletion,
      };

      const row = worksheet.addRow(rowData);
      row.font = { name: 'Segoe UI', size: 10 };

      // Timestamp in monospace
      row.getCell('timestamp').font = { name: 'Consolas', size: 10 };
      row.getCell('timestamp').alignment = { horizontal: 'center' };

      // Number formatting
      if (data.temp != null) row.getCell('temp').numFmt = '0.0" °C"';
      if (data.soil != null) row.getCell('moisture').numFmt = '0" %"';
      if (data.v != null) row.getCell('solar').numFmt = '0.00" V"';
      if (data.humidity != null) row.getCell('humidity').numFmt = '0" %"';
      if (data.current != null) row.getCell('current').numFmt = '0" mA"';
      if (vpd != null) row.getCell('vpd').numFmt = '0.000';

      // Alignment
      ['status', 'temp', 'moisture', 'solar', 'humidity', 'current', 'vpd', 'depletion'].forEach((k) => {
        row.getCell(k).alignment = { horizontal: k === 'timestamp' ? 'center' : 'right' };
      });

      // Conditional status color
      if (status === 'OPTIMAL') {
        row.getCell('status').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFDCFCE7' } };
        row.getCell('status').font = { name: 'Segoe UI', bold: true, color: { argb: 'FF166534' } };
      } else {
        row.getCell('status').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFEF3C7' } };
        row.getCell('status').font = { name: 'Segoe UI', bold: true, color: { argb: 'FF92400E' } };
      }

      // Row borders
      row.eachCell({ includeEmpty: true }, (cell) => {
        cell.border = {
          top: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          left: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          bottom: { style: 'thin', color: { argb: 'FFE2E8F0' } },
          right: { style: 'thin', color: { argb: 'FFE2E8F0' } },
        };
      });
    }

    // Auto-filter
    const dataStartRow = includeAI ? 5 : 1;
    worksheet.autoFilter = {
      from: { row: dataStartRow, column: 1 },
      to: { row: dataStartRow + history.length, column: 9 },
    };

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename=SolarSoil_Report_${new Date().toISOString().slice(0, 10)}.xlsx`);

    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    console.error('Excel export error:', error.message, error.stack);
    res.status(500).json({ error: 'Error compiling spreadsheet.', detail: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// AI ENDPOINTS
// ─────────────────────────────────────────────────────────────────────────────

// Get latest AI health analysis snapshot
app.get('/api/ai/health', (req, res) => {
  res.json({
    health: lastHealthScore,
    irrigation: lastIrrigationAdvice,
    reading: lastReading,
  });
});

// LLM Chat — user asks a question, Gemini answers with live sensor context
app.post('/api/ai/ask', async (req, res) => {
  const { question } = req.body;

  if (!question || typeof question !== 'string' || question.trim().length === 0) {
    return res.status(400).json({ error: 'Question is required.' });
  }

  if (question.trim().length > 500) {
    return res.status(400).json({ error: 'Question too long (max 500 chars).' });
  }

  console.log(`[AI] Question received: "${question.trim()}"`);

  try {
    const answer = await askGemini(
      question.trim(),
      lastReading,
      rollingHistory,
      lastHealthScore,
      lastIrrigationAdvice
    );
    console.log(`[AI] Provider answered (${answer.length} chars)`);
    res.json({ answer, timestamp: new Date().toISOString() });
  } catch (err) {
    console.error('[AI] Ask endpoint error:', err);
    res.status(500).json({ error: 'AI service failed. Please try again.' });
  }
});

// Multimodal Leaf Image Diagnostic Scan endpoint
app.post('/api/ai/scan-image', async (req, res) => {
  const { image, mimeType, reading } = req.body;

  if (!image) {
    return res.status(400).json({ error: 'Image data is required.' });
  }

  console.log(`[AI Image Scanner] Diagnostic scan request received (MIME: ${mimeType || 'unknown'})`);

  try {
    const diagnosis = await scanLeafImage(image, mimeType, reading || lastReading);
    console.log('[AI Image Scanner] Diagnostic successful');
    res.json(diagnosis);
  } catch (err) {
    console.error('[AI Image Scanner] Diagnostic failed:', err.message);
    res.status(500).json({ error: err.message || 'AI visual scan failed. Please try again.' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// HTTP or HTTPS & WEBSOCKET SETUP
// ─────────────────────────────────────────────────────────────────────────────
const server = useHttps ? createHttpsServer(httpsOptions, app) : createServer(app);
const wss = new WebSocketServer({ server });

// AI Configuration endpoints
app.get('/api/ai/config', (req, res) => {
  try {
    const raw = getAIConfig();
    const safe = {
      provider: raw.provider || 'gemini',
      model: raw.model || '',
      baseUrl: raw.baseUrl || '',
      hasApiKey: !!(raw.apiKey && raw.apiKey.length > 0),
    };
    if (raw.apiKey) {
      safe.apiKeyMasked = raw.apiKey.substring(0, 4) + '••••' + raw.apiKey.slice(-4);
    }
    // Never send the actual apiKey over the wire
    res.json(safe);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/ai/config', (req, res) => {
  try {
    const { provider, apiKey, model, baseUrl } = req.body;
    const updated = setAIConfig({ provider, apiKey, model, baseUrl });
    if (updated) {
      res.json({ ok: true, message: 'AI configuration saved.' });
    } else {
      res.status(500).json({ error: 'Failed to save configuration.' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/ai/test', async (req, res) => {
  try {
    const result = await testAIConnection();
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/ai/metrics', (req, res) => {
  try {
    res.json(getAIMetrics());
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Garden zone config file
const GARDEN_CONFIG_PATH = path.join(__dirname, 'garden_config.json');

app.get('/api/garden/config', (req, res) => {
  try {
    if (fs.existsSync(GARDEN_CONFIG_PATH)) {
      const raw = fs.readFileSync(GARDEN_CONFIG_PATH, 'utf-8');
      return res.json(JSON.parse(raw));
    }
    res.json({ name: 'Spinach Garden', number: '08', zoneId: 'PL-02J', coverage: '200 m²' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/garden/config', (req, res) => {
  try {
    const { name, number, zoneId, coverage } = req.body;
    const config = {
      name: (name || 'Spinach Garden').trim(),
      number: (number || '08').trim(),
      zoneId: (zoneId || 'PL-02J').trim().toUpperCase(),
      coverage: (coverage || '200 m²').trim(),
    };
    fs.writeFileSync(GARDEN_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf-8');
    res.json({ ok: true, ...config });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Track connected WebSocket clients
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`[WebSocket] Client connected. Active clients: ${clients.size}`);
  
  // Immediately send the latest cached reading + AI analysis + MQTT status on connection
  ws.send(JSON.stringify({
    type: 'live',
    data: lastReading,
    health: lastHealthScore,
    irrigation: lastIrrigationAdvice,
    mqttConnected,
  }));

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`[WebSocket] Client disconnected. Active clients: ${clients.size}`);
  });

  ws.on('error', (err) => {
    console.error('[WebSocket] Client error:', err);
    clients.delete(ws);
  });
});

// Helper to broadcast JSON payloads to all connected Flutter clients
const broadcast = (data) => {
  const payload = JSON.stringify(data);
  clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  });
};

// ─────────────────────────────────────────────────────────────────────────────
// ANOMALY DETECTION — Z-score on rolling window
// ─────────────────────────────────────────────────────────────────────────────

function detectAnomalies(reading, history) {
  if (history.length < 5) return []; // not enough data yet

  const anomalies = [];
  const fields = ['temp', 'soil', 'humidity', 'v'];

  for (const field of fields) {
    const values = history.map(r => r[field]).filter(v => v != null && !isNaN(v));
    if (values.length < 5) continue;

    const mean = values.reduce((a, b) => a + b, 0) / values.length;
    const variance = values.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / values.length;
    const std = Math.sqrt(variance);

    if (std < 0.01) continue; // constant signal — skip

    const z = Math.abs((reading[field] - mean) / std);

    if (z > 2.8) {
      const direction = reading[field] > mean ? 'spike' : 'drop';
      anomalies.push({
        sensor: field,
        value: reading[field],
        mean: parseFloat(mean.toFixed(2)),
        z: parseFloat(z.toFixed(2)),
        direction,
        message: `Unusual ${direction} in ${field}: ${reading[field].toFixed(1)} (mean: ${mean.toFixed(1)}, z=${z.toFixed(1)})`
      });
    }
  }

  return anomalies;
}

// ─────────────────────────────────────────────────────────────────────────────
// MQTT CLIENT LISTENER
// ─────────────────────────────────────────────────────────────────────────────
const mqttBroker = process.env.MQTT_BROKER || 'mqtt://broker.emqx.io:1883';
// Subscribe to all solarsoil/nodes (A, B, C, …)
const mqttTopic = process.env.MQTT_TOPIC || 'solarsoil/#';

let mqttConnected = false;
const mqttStatusBroadcast = () => {
  broadcast({ type: 'mqtt_status', connected: mqttConnected });
};

console.log(`[MQTT] Connecting to broker: ${mqttBroker}`);
const mqttClient = mqtt.connect(mqttBroker, {
  reconnectPeriod: 5000,
  connectTimeout: 30000,
  keepalive: 60,
});

mqttClient.on('connect', () => {
  mqttConnected = true;
  mqttStatusBroadcast();
  console.log(`[MQTT] Connected. Subscribing to topic: ${mqttTopic}`);
  mqttClient.subscribe(mqttTopic, (err) => {
    if (err) {
      console.error(`[MQTT] Subscription error for topic ${mqttTopic}:`, err);
    }
  });
});

mqttClient.on('close', () => {
  mqttConnected = false;
  mqttStatusBroadcast();
  console.log('[MQTT] Disconnected from broker.');
});

mqttClient.on('offline', () => {
  mqttConnected = false;
  mqttStatusBroadcast();
  console.log('[MQTT] Broker offline.');
});

mqttClient.on('message', (topic, message) => {
  try {
    const rawPayload = message.toString();
    console.log(`[MQTT] Incoming message on ${topic}:`, rawPayload);

    const parsedData = JSON.parse(rawPayload);
    
    // Structure telemetry model
    const reading = {
      temp: parsedData.temp !== undefined ? parseFloat(parsedData.temp) : lastReading.temp,
      soil: parsedData.soil !== undefined ? parseFloat(parsedData.soil) : lastReading.soil,
      v: parsedData.v !== undefined ? parseFloat(parsedData.v) : lastReading.v,
      humidity: parsedData.humidity !== undefined ? parseFloat(parsedData.humidity) : lastReading.humidity,
      current: parsedData.current !== undefined ? parseFloat(parsedData.current) : lastReading.current,
      timestamp: new Date().toISOString()
    };

    // Update live cache
    lastReading = reading;

    // Maintain rolling window (last 20 readings)
    rollingHistory.push(reading);
    if (rollingHistory.length > 20) rollingHistory.shift();

    // ── AI Analysis ─────────────────────────────────────────────────────────
    lastHealthScore = computeHealthScore(reading);
    lastIrrigationAdvice = computeIrrigationAdvice(reading, rollingHistory);
    const anomalies = detectAnomalies(reading, rollingHistory);

    console.log(`[AI] Health: ${lastHealthScore.score}/100 (${lastHealthScore.label}) | Irrigation: ${lastIrrigationAdvice.action}`);

    // 1. Write telemetry to InfluxDB time-series DB
    writeTelemetry(reading);

    // 2. Broadcast telemetry + AI insights to all connected clients via WebSocket
    broadcast({
      type: 'telemetry',
      data: reading,
      health: lastHealthScore,
      irrigation: lastIrrigationAdvice,
    });

    // 3. Broadcast anomaly alerts separately if detected
    if (anomalies.length > 0) {
      anomalies.forEach(a => {
        console.warn(`[AI] Anomaly detected: ${a.message}`);
        broadcast({ type: 'alert', alert: a });
      });
    }

  } catch (error) {
    console.error('[MQTT] Message parsing error:', error.message);
    broadcast({ type: 'error', message: `Malformed packet: ${message.toString()}` });
  }
});

mqttClient.on('error', (err) => {
  console.error('[MQTT] Broker connection error:', err.message);
  mqttConnected = false;
  mqttStatusBroadcast();
});
mqttClient.on('close', () => {
  console.warn('[MQTT] Connection closed — will reconnect in 5s');
  mqttConnected = false;
  mqttStatusBroadcast();
});
mqttClient.on('offline', () => {
  console.warn('[MQTT] Client went offline — reconnecting...');
  mqttConnected = false;
  mqttStatusBroadcast();
});
mqttClient.on('reconnect', () => {
  console.log('[MQTT] Attempting reconnect...');
});

// Serve the vanilla HTML login page at /
const loginHtmlPath = path.join(__dirname, '../index.html');
app.get('/', (req, res, next) => {
  res.sendFile(loginHtmlPath, (err) => {
    if (err) {
      console.error('[Login] Error serving login page:', err.message);
      res.status(500).send('Login page unavailable');
    }
  });
});

// Fallback for Flutter SPA — serve index.html for any /dashboard/* path
app.get('/dashboard*', (req, res, next) => {
  res.sendFile(path.join(frontendBuildPath, 'index.html'), (err) => {
    if (err) {
      console.error('[SPA] Error serving Flutter app:', err.message);
      res.status(500).send('Dashboard unavailable');
    }
  });
});

// Start API & WebSocket server
server.listen(port, () => {
  const proto = useHttps ? 'HTTPS' : 'HTTP';
  console.log(`[Server] Solar Soil server online — ${proto} :${port}`);
  console.log(`[AI]     Health scoring, irrigation advisor & anomaly detection: ACTIVE`);
  console.log(`[AI]     Chat endpoint: POST /api/ai/ask`);
  if (!useHttps) {
    console.log(`[Server] For production, set SSL_KEY_PATH and SSL_CERT_PATH in .env`);
    console.log(`[Server] Cloudflare users: generate an Origin Certificate at`);
    console.log(`[Server]   Dashboard → SSL/TLS → Origin Server → Create Certificate`);
  }
});
