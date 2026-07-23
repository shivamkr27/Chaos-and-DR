const express = require('express');
const { pool } = require('../db');
const router = express.Router();

// Liveness probe — is the process alive?
router.get('/live', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Readiness probe — can we serve traffic? (checks DB too)
router.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      status: 'ok',
      db: 'connected',
      timestamp: new Date().toISOString(),
      region: process.env.AWS_REGION || 'local',
    });
  } catch (err) {
    console.error('Readiness check failed:', err.message);
    res.status(503).json({
      status: 'degraded',
      db: 'unreachable',
      timestamp: new Date().toISOString(),
    });
  }
});

module.exports = router;
