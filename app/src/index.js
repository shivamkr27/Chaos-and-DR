require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { initDb, pool } = require('./db');
const healthRoutes = require('./routes/health');
const itemsRoutes = require('./routes/items');
const { registry, metricsMiddleware, updatePoolMetrics } = require('./metrics');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

app.use(helmet());
app.use(rateLimit({ windowMs: 60 * 1000, limit: 120 }));
app.use(express.json());
app.use(metricsMiddleware);

app.use('/health', healthRoutes);
app.use('/api/items', itemsRoutes);

// Prometheus scrape endpoint — Prometheus polls this every 15s
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', registry.contentType);
    res.end(await registry.metrics());
  } catch (err) {
    res.status(500).end(err.message);
  }
});

app.get('/', (req, res) => {
  res.json({
    service: 'chaos-dr-app',
    version: '1.0.0',
    region: process.env.AWS_REGION || 'local',
    endpoints: [
      'GET  /health/live',
      'GET  /health/ready',
      'GET  /metrics',
      'GET  /api/items',
      'GET  /api/items/:id',
      'POST /api/items',
      'DELETE /api/items/:id',
    ],
  });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

async function start() {
  try {
    await initDb();
    console.log('Database initialized');
  } catch (err) {
    console.warn('DB not available at startup:', err.message);
  }

  // Refresh DB pool metrics every 15s
  const metricsInterval = setInterval(() => updatePoolMetrics(pool), 15000);

  const server = app.listen(PORT, () => {
    console.log(`chaos-dr-app running on port ${PORT} | region: ${process.env.AWS_REGION || 'local'}`);
  });

  const shutdown = (signal) => {
    console.log(`${signal} received, shutting down gracefully`);
    clearInterval(metricsInterval);
    server.close(() => {
      pool.end().finally(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

if (require.main === module) {
  start();
}

module.exports = app;
