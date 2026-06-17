/**
 * aiService.js — Solar Soil AI Brain
 *
 * Provides three AI features:
 *   1. computeHealthScore(reading)     — Rule-based plant health score (0–100)
 *   2. computeIrrigationAdvice(reading, history) — Smart pump recommendation
 *   3. askGemini(question, reading, history)     — LLM chat via configurable provider
 */

import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AI_CONFIG_PATH = path.join(__dirname, 'ai_config.json');

// ── AI Provider Configuration ────────────────────────────────────────────────

function loadAIConfig() {
  try {
    if (fs.existsSync(AI_CONFIG_PATH)) {
      const raw = fs.readFileSync(AI_CONFIG_PATH, 'utf-8');
      return JSON.parse(raw);
    }
  } catch (e) {
    console.warn('[AI Config] Failed to load config file:', e.message);
  }
  return {
    provider: 'gemini',
    apiKey: process.env.GEMINI_API_KEY || '',
    model: 'gemini-2.5-flash',
    baseUrl: ''
  };
}

function saveAIConfig(config) {
  try {
    fs.writeFileSync(AI_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf-8');
    return true;
  } catch (e) {
    console.error('[AI Config] Failed to save config:', e.message);
    return false;
  }
}

export function getAIConfig() {
  return loadAIConfig();
}

export function setAIConfig(config) {
  const current = loadAIConfig();
  const merged = { ...current, ...config };
  // Strip sensitive fields from logs
  if (merged.apiKey) merged.apiKey = merged.apiKey.trim();
  return saveAIConfig(merged);
}

// ── AI Performance Metrics ──────────────────────────────────────────────────

const metrics = {
  serviceStart: Date.now(),
  totalCalls: 0,
  successfulCalls: 0,
  lastLatencyMs: 0,
  lastModel: '',
  lastProvider: '',
  lastResponseTokens: 0,
  avgLatencyMs: 0,
};

function estimateTokens(text) {
  return Math.ceil((text?.length || 0) / 4);
}

export function getAIMetrics() {
  return { ...metrics, uptimeSeconds: Math.floor((Date.now() - metrics.serviceStart) / 1000) };
}

function trackCall(provider, model, latencyMs, success, responseText) {
  metrics.totalCalls++;
  metrics.lastProvider = provider;
  metrics.lastModel = model || '';
  metrics.lastLatencyMs = latencyMs;
  if (success) {
    metrics.successfulCalls++;
    metrics.lastResponseTokens = estimateTokens(responseText);
    metrics.avgLatencyMs = metrics.avgLatencyMs === 0
      ? latencyMs
      : Math.round((metrics.avgLatencyMs * (metrics.successfulCalls - 1) + latencyMs) / metrics.successfulCalls);
  }
}

// ── Multi-Provider AI Call ───────────────────────────────────────────────────

async function callAIProvider(prompt, systemPrompt = null) {
  const config = loadAIConfig();
  const { provider, apiKey, model, baseUrl } = config;

  if (!apiKey && provider !== 'ollama') {
    return { error: `⚠️ ${capitalize(provider)} API key not configured. Add it in Settings.` };
  }

  console.log(`[AI] Calling ${provider} with model: ${model}`);

  try {
    switch (provider) {
      case 'gemini':
        return await callGemini(prompt, apiKey, model);
      case 'openrouter':
        return await callOpenRouter(prompt, apiKey, model, systemPrompt);
      case 'ollama':
        return await callOllama(prompt, model, baseUrl);
      case 'nvidia':
        return await callNVIDIA(prompt, apiKey, model, systemPrompt);
      default:
        return { error: `⚠️ Unknown provider: ${provider}` };
    }
  } catch (err) {
    console.error(`[AI] ${provider} call failed:`, err.message);
    return { error: `⚠️ AI service error: ${err.message}` };
  }
}

function capitalize(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// ── Gemini ──────────────────────────────────────────────────────────────────

async function callGemini(prompt, apiKey, model) {
  const models = [
    model || 'gemini-2.5-flash',
    'gemini-2.5-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash'
  ];
  if (!models[0].startsWith('gemini')) {
    models.unshift('gemini-2.5-flash');
  }

  for (const m of [...new Set(models)]) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=${apiKey}`;
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.4, maxOutputTokens: 1024, topP: 0.9 }
        })
      });
      if (res.ok) {
        const data = await res.json();
        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) return { text: text.trim() };
      }
      if (res.status === 403) return { error: '⚠️ Invalid Gemini API key.' };
      console.warn(`[Gemini] Model ${m} returned ${res.status}`);
    } catch (e) {
      console.warn(`[Gemini] Model ${m} failed:`, e.message);
    }
  }
  return { error: '⚠️ All Gemini models failed. Check your API key or try again.' };
}

// ── OpenRouter ──────────────────────────────────────────────────────────────

async function callOpenRouter(prompt, apiKey, model, systemPrompt) {
  const messages = [];
  if (systemPrompt) messages.push({ role: 'system', content: systemPrompt });
  messages.push({ role: 'user', content: prompt });

  const url = 'https://openrouter.ai/api/v1/chat/completions';
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://solarsoil.local',
      'X-Title': 'Solar Soil AI'
    },
    body: JSON.stringify({
      model: model || 'google/gemini-2.5-flash-exp:free',
      messages,
      max_tokens: 1024,
      temperature: 0.4
    })
  });
  if (!res.ok) {
    const err = await res.text();
    return { error: `⚠️ OpenRouter error (${res.status}): ${err.substring(0, 200)}` };
  }
  const data = await res.json();
  return { text: data?.choices?.[0]?.message?.content?.trim() || 'No response.' };
}

// ── Ollama ──────────────────────────────────────────────────────────────────

async function callOllama(prompt, model, baseUrl) {
  const url = (baseUrl || 'http://localhost:11434') + '/api/generate';
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: model || 'llama3.2',
      prompt,
      stream: false,
      options: { temperature: 0.4, num_predict: 1024 }
    })
  });
  if (!res.ok) {
    const err = await res.text();
    return { error: `⚠️ Ollama error (${res.status}): ${err.substring(0, 200)}` };
  }
  const data = await res.json();
  return { text: data?.response?.trim() || 'No response.' };
}

// ── NVIDIA ──────────────────────────────────────────────────────────────────

async function callNVIDIA(prompt, apiKey, model, systemPrompt) {
  const messages = [];
  if (systemPrompt) messages.push({ role: 'system', content: systemPrompt });
  messages.push({ role: 'user', content: prompt });

  const url = 'https://integrate.api.nvidia.com/v1/chat/completions';
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: model || 'meta/llama-3.2-3b-instruct',
      messages,
      max_tokens: 1024,
      temperature: 0.4
    })
  });
  if (!res.ok) {
    const err = await res.text();
    return { error: `⚠️ NVIDIA error (${res.status}): ${err.substring(0, 200)}` };
  }
  const data = await res.json();
  return { text: data?.choices?.[0]?.message?.content?.trim() || 'No response.' };
}

// ── Test Connection ─────────────────────────────────────────────────────────

export async function testAIConnection() {
  const result = await callAIProvider('Say exactly: CONNECTION_OK', null);
  if (result.text && result.text.includes('CONNECTION_OK')) {
    return { ok: true, message: 'Connection successful!' };
  }
  return { ok: false, message: result.error || 'Unexpected response from AI provider.' };
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURE 1 — PLANT HEALTH SCORING ENGINE
// Thresholds tuned for Spinacia oleracea (spinach)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compute a 0–100 plant health score for spinach from current sensor reading.
 * Returns { score, status, label, color, issues, tips }
 */
export function computeHealthScore(reading) {
  const { temp, soil, humidity, v } = reading;
  let score = 100;
  const issues = [];
  const tips = [];

  // ── Soil Moisture ─────────────────────────────────────────────────────────
  if (soil < 20) {
    score -= 35;
    issues.push('Severe drought stress');
    tips.push('Irrigate immediately — soil critically dry');
  } else if (soil < 30) {
    score -= 20;
    issues.push('Low soil moisture');
    tips.push('Consider irrigating within the next hour');
  } else if (soil > 85) {
    score -= 20;
    issues.push('Waterlogging risk');
    tips.push('Pause irrigation — soil is saturated');
  } else if (soil > 70) {
    score -= 8;
    issues.push('Soil slightly over-watered');
    tips.push('Allow soil to drain before next irrigation');
  }

  // ── Temperature ───────────────────────────────────────────────────────────
  if (temp > 38) {
    score -= 30;
    issues.push('Severe heat stress — bolting risk');
    tips.push('Deploy shade netting immediately, increase irrigation frequency');
  } else if (temp > 32) {
    score -= 18;
    issues.push('High temperature stress');
    tips.push('Ensure shade netting is deployed during peak hours');
  } else if (temp < 5) {
    score -= 25;
    issues.push('Frost risk — cold damage possible');
    tips.push('Cover crops with frost cloth overnight');
  } else if (temp < 10) {
    score -= 10;
    issues.push('Cool temperature — growth slowdown');
    tips.push('Monitor for frost if temp drops further');
  }

  // ── Humidity ──────────────────────────────────────────────────────────────
  if (humidity > 90) {
    score -= 12;
    issues.push('High humidity — fungal disease risk');
    tips.push('Improve air circulation, check for downy mildew');
  } else if (humidity < 35) {
    score -= 12;
    issues.push('Low humidity — transpiration stress');
    tips.push('Consider misting or humidity control in greenhouse');
  }

  // ── Solar / Power ─────────────────────────────────────────────────────────
  const hour = new Date().getHours();
  const isDaytime = hour >= 7 && hour <= 19;
  if (isDaytime && v < 1.0) {
    score -= 8;
    issues.push('Low solar output during daylight');
    tips.push('Check solar panel for shading or dust buildup');
  }

  // Clamp score
  score = Math.max(0, Math.min(100, Math.round(score)));

  // Determine status tier
  let status, label, color;
  if (score >= 80) {
    status = 'excellent'; label = 'Excellent'; color = '#10B981';
  } else if (score >= 65) {
    status = 'good'; label = 'Good'; color = '#34D399';
  } else if (score >= 45) {
    status = 'stressed'; label = 'Stressed'; color = '#F59E0B';
  } else if (score >= 25) {
    status = 'poor'; label = 'Poor'; color = '#F97316';
  } else {
    status = 'critical'; label = 'Critical'; color = '#EF4444';
  }

  return { score, status, label, color, issues, tips };
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURE 2 — IRRIGATION AI ADVISOR
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compute a smart irrigation recommendation.
 * @param {Object} reading   - Latest telemetry reading
 * @param {Array}  history   - Recent readings array (newest last)
 * Returns { action, reason, urgency }
 */
export function computeIrrigationAdvice(reading, history = []) {
  const { soil, temp, v, humidity } = reading;
  const hour = new Date().getHours();

  // Compute soil trend from last 3 readings (if available)
  let soilTrend = 0; // negative = drying out
  if (history.length >= 3) {
    const recent = history.slice(-3).map(r => r.soil);
    soilTrend = recent[2] - recent[0]; // positive = wetter, negative = drier
  }

  const isDaytime = hour >= 7 && hour <= 19;
  const isPeakSun = hour >= 11 && hour <= 15;
  const hasSolarPower = v > 2.0;
  const isSunrise = hour >= 5 && hour <= 8;
  const isSunset = hour >= 17 && hour <= 20;

  // ── Decision tree ────────────────────────────────────────────────────────

  // Critical — irrigate regardless of time
  if (soil < 20) {
    return {
      action: 'irrigate_now',
      urgency: 'critical',
      reason: `Soil critically dry at ${soil}%. Spinach may wilt — irrigate immediately.`
    };
  }

  // Low soil + drying trend
  if (soil < 35 && soilTrend < -5) {
    if (isPeakSun) {
      return {
        action: 'schedule_for_dusk',
        urgency: 'moderate',
        reason: `Soil at ${soil}% and falling. Delaying to dusk reduces evaporation by ~40%.`
      };
    }
    return {
      action: 'irrigate_now',
      urgency: 'moderate',
      reason: `Soil at ${soil}% and declining. Good time to irrigate before heat peaks.`
    };
  }

  // Optimal range — hold
  if (soil >= 40 && soil <= 70) {
    const trendMsg = soilTrend < -3 ? `, slowly drying (${soilTrend.toFixed(1)}% change)` : '';
    return {
      action: 'hold',
      urgency: 'none',
      reason: `Soil moisture optimal at ${soil}%${trendMsg}. No irrigation needed now.`
    };
  }

  // Over-watered — definitely hold
  if (soil > 70) {
    return {
      action: 'hold',
      urgency: 'caution',
      reason: `Soil at ${soil}% — already well-watered. Allow to drain before irrigating.`
    };
  }

  // Borderline dry — schedule for best time
  if (soil < 40) {
    if (isSunrise || isSunset) {
      return {
        action: 'irrigate_now',
        urgency: 'low',
        reason: `Soil at ${soil}%. ${isSunrise ? 'Morning' : 'Evening'} is the optimal irrigation window.`
      };
    }
    if (isPeakSun) {
      return {
        action: 'schedule_for_dusk',
        urgency: 'low',
        reason: `Soil at ${soil}% during peak sun. Schedule irrigation for after 17:00 to minimise evaporation.`
      };
    }
    return {
      action: 'hold',
      urgency: 'low',
      reason: `Soil at ${soil}% — monitor closely. Consider irrigating this evening.`
    };
  }

  return {
    action: 'hold',
    urgency: 'none',
    reason: 'Conditions nominal. No irrigation action required.'
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURE 3 — LLM CHAT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Build the system context prompt with live sensor data.
 */
function buildPrompt(question, reading, history = [], healthScore = null, irrigation = null) {
  const { temp, soil, v, humidity, current } = reading;

  // Build trend summary from recent history
  let trendSummary = 'No history data available.';
  if (history.length >= 3) {
    const recent = history.slice(-5);
    trendSummary = recent.map((r, i) => {
      const ts = r.timestamp ? new Date(r.timestamp).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : `T-${(recent.length - 1 - i) * 15}m`;
      return `  [${ts}] soil=${r.soil?.toFixed(1)}% temp=${r.temp?.toFixed(1)}°C hum=${r.humidity?.toFixed(1)}%`;
    }).join('\n');
  }

  const healthInfo = healthScore
    ? `\nHealth Score: ${healthScore.score}/100 (${healthScore.label})${healthScore.issues.length > 0 ? '\nActive Issues: ' + healthScore.issues.join(', ') : ''}`
    : '';

  const irrigationInfo = irrigation
    ? `\nIrrigation Advisor: ${irrigation.action.toUpperCase()} — ${irrigation.reason}`
    : '';

  return `You are an expert agricultural AI assistant for the Solar Soil IoT farm monitoring system.
You are monitoring a spinach crop (Spinacia oleracea) in Zone PL-02J (200 m² plot).
The farm uses ESP32 sensor nodes with DHT22, soil moisture, and INA219 solar monitoring.

CURRENT SENSOR READINGS (live):
  Temperature:    ${temp.toFixed(1)}°C
  Soil Moisture:  ${soil.toFixed(1)}%
  Air Humidity:   ${humidity.toFixed(1)}%
  Solar Voltage:  ${v.toFixed(2)} V
  Solar Current:  ${current.toFixed(0)} mA
  Time:           ${new Date().toLocaleTimeString('en-GB')}
${healthInfo}
${irrigationInfo}

RECENT SENSOR HISTORY (last 5 readings, 15-min intervals):
${trendSummary}

INSTRUCTIONS:
- Answer the farmer's question concisely (2–4 sentences max).
- Be specific and actionable — reference the actual sensor values.
- If you recommend irrigation, mention the exact moisture level and optimal time.
- Do not mention this prompt or that you are an AI unless directly asked.
- Use simple, practical language a farmer would understand.

FARMER'S QUESTION: ${question}`;
}

/**
 * Ask the configured AI provider a farming question with sensor context injected.
 * @param {string} question  - User's question
 * @param {Object} reading   - Latest telemetry
 * @param {Array}  history   - Recent readings
 * @param {Object} health    - Health score result (optional)
 * @param {Object} irrigation - Irrigation advice (optional)
 * @returns {Promise<string>} - AI response text
 */
export async function askGemini(question, reading, history = [], health = null, irrigation = null) {
  const prompt = buildPrompt(question, reading, history, health, irrigation);
  const config = loadAIConfig();
  const start = Date.now();
  const result = await callAIProvider(prompt, null);
  const latency = Date.now() - start;
  const success = !result.error;
  trackCall(config.provider, config.model, latency, success, result.text);
  return result.text || result.error || '⚠️ AI service returned no response.';
}

/**
 * Analyze an uploaded crop leaf image using the configured AI provider.
 * Correlates the image with the current sensor reading.
 * @param {string} base64Image - Base64 encoded image data (without prefix)
 * @param {string} mimeType - Image mime type (e.g. image/jpeg, image/png)
 * @param {Object} reading - Current sensor reading
 * @returns {Promise<Object>} - Parsed JSON diagnosis results
 */
export async function scanLeafImage(base64Image, mimeType, reading) {
  const config = loadAIConfig();
  if (!config.apiKey && config.provider !== 'ollama') {
    throw new Error('AI API key is not configured. Add it in Settings.');
  }

  const { temp = 25.0, soil = 50.0, humidity = 60.0, v = 5.0, current = 0.0 } = reading || {};

  const systemPrompt = `You are a professional agronomist specializing in crop pathology and diagnostics.
Analyze the provided image of a plant (specifically Spinacia oleracea / spinach, or another crop if shown).
Context: The current sensor readings in the greenhouse/field are:
  - Soil Moisture: ${soil.toFixed(1)}%
  - Air Temperature: ${temp.toFixed(1)}°C
  - Air Humidity: ${humidity.toFixed(1)}%
  - Solar Voltage: ${v.toFixed(2)} V
  - Solar Current: ${current.toFixed(0)} mA

Perform a visual-sensor correlated crop diagnostics check. You MUST return your response as a valid, parsable JSON object using this EXACT schema:
{
  "diagnosis": "A concise (1-2 sentences) explanation of what is wrong, or if the plant is healthy.",
  "severity": "LOW" | "MEDIUM" | "HIGH",
  "confidence": "e.g. 90%",
  "issues": ["Issue 1", "Issue 2"],
  "remedies": ["Actionable treatment remedy 1", "Actionable treatment remedy 2"]
}
Do not return any markdown formatting outside of the JSON block (no backticks, no wrap, just the raw JSON object itself).`;

  // Clean base64 string if it contains data URI prefix
  let cleanBase64 = base64Image;
  if (base64Image.includes('base64,')) {
    cleanBase64 = base64Image.split('base64,')[1];
  }

  // For providers that support vision (Gemini, OpenRouter with vision models)
  if (config.provider === 'gemini') {
    const models = [
      config.model || 'gemini-2.5-flash',
      'gemini-2.5-flash',
      'gemini-2.0-flash-lite',
      'gemini-2.0-flash'
    ];
    for (const m of [...new Set(models)]) {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=${config.apiKey}`;
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{
              parts: [
                { text: systemPrompt },
                { inlineData: { mimeType: mimeType || 'image/jpeg', data: cleanBase64 } }
              ]
            }],
            generationConfig: { temperature: 0.2, maxOutputTokens: 1024, topP: 0.9, responseMimeType: 'application/json' }
          })
        });
        if (res.ok) {
          const data = await res.json();
          const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
          if (text) {
            try { return JSON.parse(text.trim()); } catch (_) {
              return { diagnosis: text.trim().substring(0, 200), severity: 'MEDIUM', confidence: '70%', issues: ['Could not parse structured diagnostics'], remedies: ['Verify leaf symptoms manually'] };
            }
          }
        }
        if (res.status === 403) throw new Error('Invalid AI API key.');
      } catch (e) { console.warn(`[AI Scanner] Model ${m} failed:`, e.message); }
    }
    throw new Error('All models failed for image scan.');
  }

  // For text-only providers (Ollama, OpenRouter, NVIDIA), fall back to text description
  const textResult = await callAIProvider(`[IMAGE ANALYSIS REQUEST]\n${systemPrompt}\n\nThe user uploaded a leaf image. Describe what you see and provide a diagnosis in the JSON schema specified above.`, systemPrompt);
  if (textResult.text) {
    try { return JSON.parse(textResult.text); } catch (_) {
      return { diagnosis: textResult.text.substring(0, 200), severity: 'MEDIUM', confidence: '70%', issues: ['Text-based analysis only'], remedies: ['Upload to a vision-capable provider for full diagnosis'] };
    }
  }
  throw new Error(textResult.error || 'AI scanner service failed.');
}

