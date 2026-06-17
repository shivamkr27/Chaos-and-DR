const client = require('prom-client');

const registry = new client.Registry();

// Default Node.js metrics (CPU, memory, event loop lag, GC)
client.collectDefaultMetrics({ register: registry });

// HTTP request counter — used to calculate error rate and throughput
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [registry],
});

// HTTP request duration histogram — used for latency percentiles (P50, P99)
const httpRequestDurationSeconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  // Buckets tuned for a low-latency API: 10ms → 2s
  buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1, 2],
  registers: [registry],
});

// DB connection pool metrics — shows stress during chaos
const dbPoolTotal = new client.Gauge({
  name: 'db_pool_total_connections',
  help: 'Total DB pool connections',
  registers: [registry],
});

const dbPoolIdle = new client.Gauge({
  name: 'db_pool_idle_connections',
  help: 'Idle DB pool connections',
  registers: [registry],
});

const dbPoolWaiting = new client.Gauge({
  name: 'db_pool_waiting_count',
  help: 'Requests waiting for a DB connection',
  registers: [registry],
});

// Express middleware that records every request automatically
function metricsMiddleware(req, res, next) {
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - start) / 1e9;
    // Normalise route so /api/items/123 and /api/items/456 share one label
    const route = req.route?.path || req.path || 'unknown';

    httpRequestsTotal.inc({
      method: req.method,
      route,
      status: res.statusCode,
    });

    httpRequestDurationSeconds.observe(
      { method: req.method, route, status: res.statusCode },
      durationMs
    );
  });

  next();
}

// Update pool gauges — called every 15s from index.js
function updatePoolMetrics(pool) {
  dbPoolTotal.set(pool.totalCount);
  dbPoolIdle.set(pool.idleCount);
  dbPoolWaiting.set(pool.waitingCount);
}

module.exports = { registry, metricsMiddleware, updatePoolMetrics };
