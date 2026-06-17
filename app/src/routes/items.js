const express = require('express');
const { pool } = require('../db');
const router = express.Router();

// GET all items
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM items ORDER BY created_at DESC LIMIT 100'
    );
    res.json({ items: result.rows, count: result.rowCount });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch items', detail: err.message });
  }
});

// GET single item
router.get('/:id', async (req, res) => {
  const id = parseInt(req.params.id);
  if (isNaN(id)) return res.status(400).json({ error: 'Invalid id' });

  try {
    const result = await pool.query('SELECT * FROM items WHERE id = $1', [id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Item not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch item', detail: err.message });
  }
});

// POST create item
router.post('/', async (req, res) => {
  const { name, description } = req.body;
  if (!name || typeof name !== 'string' || name.trim() === '') {
    return res.status(400).json({ error: 'name is required and must be a non-empty string' });
  }
  if (name.length > 255) {
    return res.status(400).json({ error: 'name must be 255 characters or fewer' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO items (name, description) VALUES ($1, $2) RETURNING *',
      [name.trim(), description?.trim() || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to create item', detail: err.message });
  }
});

// DELETE item
router.delete('/:id', async (req, res) => {
  const id = parseInt(req.params.id);
  if (isNaN(id)) return res.status(400).json({ error: 'Invalid id' });

  try {
    const result = await pool.query('DELETE FROM items WHERE id = $1 RETURNING id', [id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Item not found' });
    res.json({ deleted: true, id });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete item', detail: err.message });
  }
});

module.exports = router;
