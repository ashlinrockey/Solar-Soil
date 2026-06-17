import { InfluxDB, Point } from '@influxdata/influxdb-client';
import dotenv from 'dotenv';
import { execSync } from 'child_process';
import os from 'os';

dotenv.config();

/**
 * On Windows with WSL2, InfluxDB runs inside a WSL2 VM whose IP is not
 * reachable via localhost/127.0.0.1 due to rootless Podman port binding.
 * This function detects the actual WSL2 guest IP so the Node.js client
 * (running on Windows) can reach InfluxDB directly.
 */
function resolveInfluxUrl() {
  const configured = process.env.INFLUX_URL || 'http://localhost:8086';

  // If not on Windows or INFLUX_URL is not localhost, use as-is
  if (os.platform() !== 'win32') return configured;
  if (!configured.includes('localhost') && !configured.includes('127.0.0.1')) return configured;

  try {
    const wslIp = execSync('wsl -d Ubuntu -- bash -c "hostname -I"', { timeout: 3000 })
      .toString().trim().split(/\s+/)[0];
    if (wslIp && /^\d+\.\d+\.\d+\.\d+$/.test(wslIp)) {
      const resolved = configured.replace(/localhost|127\.0\.0\.1/, wslIp);
      console.log(`[InfluxDB] WSL2 detected — using ${resolved}`);
      return resolved;
    }
  } catch {
    // WSL not available or not running — fall through to configured URL
  }

  return configured;
}

const url = resolveInfluxUrl();
const token = process.env.INFLUX_TOKEN || 'solarsoil_secret_token_12345';
const org = process.env.INFLUX_ORG || 'college';
const bucket = process.env.INFLUX_BUCKET || 'solarsoil';

// Initialize InfluxDB Client
const client = new InfluxDB({ url, token });
const writeApi = client.getWriteApi(org, bucket, 'ns');
const queryApi = client.getQueryApi(org);

/**
 * Write a new telemetry log to InfluxDB
 * @param {Object} data - The telemetry reading { temp, soil, v, humidity, current }
 */
export const writeTelemetry = (data) => {
  try {
    const point = new Point('sensors')
      .tag('node', 'nodeA')
      .floatField('temp', parseFloat(data.temp || 0))
      .floatField('soil', parseFloat(data.soil || 0))
      .floatField('v', parseFloat(data.v || 0))
      .floatField('humidity', parseFloat(data.humidity || 0))
      .floatField('current', parseFloat(data.current || 0));

    writeApi.writePoint(point);
    // Flush asynchronously
    writeApi.flush();
    console.log('[InfluxDB] Successfully logged point:', data);
  } catch (error) {
    console.error('[InfluxDB] Error writing point:', error);
  }
};

/**
 * Query historical telemetry data from InfluxDB using Flux
 * @param {string} range - Time window (e.g., '1h', '6h', '24h', '7d')
 * @returns {Promise<Array>} - Telemetry history array
 */
export const getHistory = async (range = '24h') => {
  // Validate range pattern to avoid injection (e.g., must be digits followed by h, m, d)
  const validRange = /^[0-9]+[hmd]$/.test(range) ? range : '24h';

  const fluxQuery = `
    from(bucket: "${bucket}")
      |> range(start: -${validRange})
      |> filter(fn: (r) => r["_measurement"] == "sensors")
      |> filter(fn: (r) => r["node"] == "nodeA")
      |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> keep(columns: ["_time", "temp", "soil", "v", "humidity", "current"])
      |> sort(columns: ["_time"], desc: false)
      |> limit(n: 100)
  `;

  const results = [];
  return new Promise((resolve, reject) => {
    queryApi.queryRows(fluxQuery, {
      next(row, tableMeta) {
        const o = tableMeta.toObject(row);
        results.push({
          time: o._time,
          temp: o.temp !== undefined ? parseFloat(o.temp) : null,
          soil: o.soil !== undefined ? parseFloat(o.soil) : null,
          v: o.v !== undefined ? parseFloat(o.v) : null,
          humidity: o.humidity !== undefined ? parseFloat(o.humidity) : null,
          current: o.current !== undefined ? parseFloat(o.current) : null,
        });
      },
      error(err) {
        console.error('[InfluxDB] Query error:', err);
        reject(err);
      },
      complete() {
        resolve(results);
      },
    });
  });
};
