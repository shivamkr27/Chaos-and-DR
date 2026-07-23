const express = require('express');
const { pool } = require('../db');
const router = express.Router();

// Mutating routes require a shared API key — same pattern as scripts/lambda-alert/index.js
function requireApiKey(req, res, next) {
  const expected = process.env.API_KEY;
  if (!expected) {
    console.error('API_KEY is not configured — refusing mutating request');
    return res.status(500).json({ error: 'Server misconfigured' });
  }
  if (req.get('x-api-key') !== expected) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// GET all items
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM items ORDER BY created_at DESC LIMIT 100'
    );
    res.json({ items: result.rows, count: result.rowCount });
  } catch (err) {
    console.error('Failed to fetch items:', err.message);
    res.status(500).json({ error: 'Failed to fetch items' });
  }
});

// GET single item
router.get('/:id', async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (isNaN(id)) return res.status(400).json({ error: 'Invalid id' });

  try {
    const result = await pool.query('SELECT * FROM items WHERE id = $1', [id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Item not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Failed to fetch item:', err.message);
    res.status(500).json({ error: 'Failed to fetch item' });
  }
});

// POST create item
router.post('/', requireApiKey, async (req, res) => {
  const { name, description } = req.body;
  if (!name || typeof name !== 'string' || name.trim() === '') {
    return res.status(400).json({ error: 'name is required and must be a non-empty string' });
  }
  if (name.length > 255) {
    return res.status(400).json({ error: 'name must be 255 characters or fewer' });
  }
  if (description !== undefined && description !== null && typeof description !== 'string') {
    return res.status(400).json({ error: 'description must be a string' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO items (name, description) VALUES ($1, $2) RETURNING *',
      [name.trim(), description?.trim() || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Failed to create item:', err.message);
    res.status(500).json({ error: 'Failed to create item' });
  }
});

// DELETE item
router.delete('/:id', requireApiKey, async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (isNaN(id)) return res.status(400).json({ error: 'Invalid id' });

  try {
    const result = await pool.query('DELETE FROM items WHERE id = $1 RETURNING id', [id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Item not found' });
    res.json({ deleted: true, id });
  } catch (err) {
    console.error('Failed to delete item:', err.message);
    res.status(500).json({ error: 'Failed to delete item' });
  }
});

module.exports = router;
