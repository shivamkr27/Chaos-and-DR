const request = require('supertest');
const app = require('../index');

jest.mock('../db', () => ({
  pool: { query: jest.fn() },
  initDb: jest.fn().mockResolvedValue(),
}));

const { pool } = require('../db');

const mockItem = { id: 1, name: 'Test Item', description: 'A desc', created_at: new Date().toISOString() };

describe('GET /api/items', () => {
  it('returns list of items', async () => {
    pool.query.mockResolvedValueOnce({ rows: [mockItem], rowCount: 1 });
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(200);
    expect(res.body.items).toHaveLength(1);
    expect(res.body.count).toBe(1);
  });

  it('returns empty list when no items', async () => {
    pool.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(200);
    expect(res.body.items).toHaveLength(0);
  });

  it('returns 500 on DB error', async () => {
    pool.query.mockRejectedValueOnce(new Error('DB down'));
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(500);
  });
});

describe('GET /api/items/:id', () => {
  it('returns item by id', async () => {
    pool.query.mockResolvedValueOnce({ rows: [mockItem], rowCount: 1 });
    const res = await request(app).get('/api/items/1');
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(1);
  });

  it('returns 404 when item not found', async () => {
    pool.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const res = await request(app).get('/api/items/999');
    expect(res.status).toBe(404);
  });

  it('returns 400 for non-numeric id', async () => {
    const res = await request(app).get('/api/items/abc');
    expect(res.status).toBe(400);
  });
});

describe('POST /api/items', () => {
  it('creates an item successfully', async () => {
    pool.query.mockResolvedValueOnce({ rows: [mockItem], rowCount: 1 });
    const res = await request(app)
      .post('/api/items')
      .send({ name: 'Test Item', description: 'A desc' });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Test Item');
  });

  it('returns 400 when name is missing', async () => {
    const res = await request(app).post('/api/items').send({ description: 'no name' });
    expect(res.status).toBe(400);
  });

  it('returns 400 when name is empty string', async () => {
    const res = await request(app).post('/api/items').send({ name: '   ' });
    expect(res.status).toBe(400);
  });

  it('returns 400 when name exceeds 255 chars', async () => {
    const res = await request(app).post('/api/items').send({ name: 'a'.repeat(256) });
    expect(res.status).toBe(400);
  });

  it('returns 400 when name is not a string', async () => {
    const res = await request(app).post('/api/items').send({ name: 123 });
    expect(res.status).toBe(400);
  });

  it('trims whitespace from name', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ ...mockItem, name: 'Trimmed' }], rowCount: 1 });
    const res = await request(app).post('/api/items').send({ name: '  Trimmed  ' });
    expect(res.status).toBe(201);
    const [, args] = pool.query.mock.calls[pool.query.mock.calls.length - 1];
    expect(args[0]).toBe('Trimmed');
  });
});

describe('DELETE /api/items/:id', () => {
  it('deletes an item', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ id: 1 }], rowCount: 1 });
    const res = await request(app).delete('/api/items/1');
    expect(res.status).toBe(200);
    expect(res.body.deleted).toBe(true);
  });

  it('returns 404 when item does not exist', async () => {
    pool.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const res = await request(app).delete('/api/items/999');
    expect(res.status).toBe(404);
  });

  it('returns 400 for non-numeric id', async () => {
    const res = await request(app).delete('/api/items/xyz');
    expect(res.status).toBe(400);
  });
});

describe('404 fallback', () => {
  it('returns 404 for unknown routes', async () => {
    const res = await request(app).get('/nonexistent');
    expect(res.status).toBe(404);
  });
});
