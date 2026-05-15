const express = require('express');
const fs = require('fs');
const client = require('prom-client');

const app = express();
app.use(express.json());

const PORT = Number(process.env.PORT || 3000);
const REGION = process.env.REGION || 'unknown';
const VERSION = process.env.GATEWAY_VERSION || 'v1';
const CREDENTIALS_FILE = process.env.CREDENTIALS_FILE || '/run/secrets/processor_credentials.env';

let credentials = {};
let ready = false;

function parseEnvFile(content) {
  const result = {};
  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx <= 0) continue;
    const key = line.slice(0, idx).trim();
    const value = line.slice(idx + 1).trim();
    result[key] = value;
  }
  return result;
}

function loadCredentials() {
  try {
    const data = fs.readFileSync(CREDENTIALS_FILE, 'utf8');
    credentials = parseEnvFile(data);
    ready = Boolean(credentials.PROCESSOR_API_KEY && credentials.PROCESSOR_NAME);
    console.log(`[${VERSION}-${REGION}] credentials loaded`);
  } catch (err) {
    ready = false;
    console.error(`[${VERSION}-${REGION}] failed to load credentials: ${err.message}`);
  }
}

function watchCredentials() {
  try {
    fs.watch(CREDENTIALS_FILE, { persistent: false }, () => {
      setTimeout(loadCredentials, 100);
    });
  } catch (err) {
    console.error(`[${VERSION}-${REGION}] credentials watcher unavailable: ${err.message}`);
  }
}

loadCredentials();
watchCredentials();

const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'gateway_' });

const requestCounter = new client.Counter({
  name: 'gateway_requests_total',
  help: 'Total requests handled by gateway version',
  labelNames: ['version', 'region', 'status', 'endpoint'],
  registers: [register]
});

const authCounter = new client.Counter({
  name: 'gateway_authorizations_total',
  help: 'Total authorization outcomes',
  labelNames: ['version', 'region', 'outcome'],
  registers: [register]
});

const latencyHistogram = new client.Histogram({
  name: 'gateway_request_duration_seconds',
  help: 'Gateway request duration in seconds',
  labelNames: ['version', 'region', 'endpoint'],
  buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5],
  registers: [register]
});

function statusCodeGroup(statusCode) {
  if (statusCode >= 500) return '5xx';
  if (statusCode >= 400) return '4xx';
  if (statusCode >= 300) return '3xx';
  if (statusCode >= 200) return '2xx';
  return '1xx';
}

app.use((req, res, next) => {
  const endTimer = latencyHistogram.startTimer({ version: VERSION, region: REGION, endpoint: req.path });
  res.on('finish', () => {
    endTimer();
    requestCounter.inc({
      version: VERSION,
      region: REGION,
      status: statusCodeGroup(res.statusCode),
      endpoint: req.path
    });
  });
  next();
});

app.get('/health', (_req, res) => {
  if (!credentials.PROCESSOR_API_KEY) {
    return res.status(503).json({ status: 'unhealthy', reason: 'missing processor credentials', version: VERSION, region: REGION });
  }
  return res.status(200).json({ status: 'ok', version: VERSION, region: REGION });
});

app.get('/ready', (_req, res) => {
  if (!ready) {
    return res.status(503).json({ status: 'not-ready', version: VERSION, region: REGION });
  }
  return res.status(200).json({ status: 'ready', version: VERSION, region: REGION });
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.post('/authorize', async (_req, res) => {
  if (!ready) {
    authCounter.inc({ version: VERSION, region: REGION, outcome: 'error_credentials' });
    return res.status(503).json({ approved: false, reason: 'credentials unavailable', version: VERSION, region: REGION });
  }

  const latencyMs = 120 + Math.floor(Math.random() * 260);
  const errorChance = Number(process.env.ERROR_CHANCE || 0.018);
  const approvalChance = Number(process.env.APPROVAL_CHANCE || 0.90);

  await new Promise((resolve) => setTimeout(resolve, latencyMs));

  if (Math.random() < errorChance) {
    authCounter.inc({ version: VERSION, region: REGION, outcome: 'error_upstream' });
    return res.status(502).json({ approved: false, reason: 'processor_error', version: VERSION, region: REGION });
  }

  const approved = Math.random() < approvalChance;
  authCounter.inc({ version: VERSION, region: REGION, outcome: approved ? 'approved' : 'declined' });
  return res.status(200).json({
    approved,
    processor: credentials.PROCESSOR_NAME,
    region: REGION,
    version: VERSION,
    latencyMs
  });
});

app.listen(PORT, () => {
  console.log(`[${VERSION}-${REGION}] listening on ${PORT}`);
});
