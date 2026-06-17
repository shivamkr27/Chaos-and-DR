const request = require('supertest');
const app = require('../index');

jest.mock('../db', () => ({
  pool: {
    query: jest.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
    totalCount: 2,
    idleCount: 2,
    waitingCount: 0,
  },
  initDb: jest.fn().mockResolvedValue(),
}));

const { pool } = require('../db');

describe('GET /health/live', () => {
  it('returns 200 with status ok', async () => {
    const res = await request(app).get('/health/live');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.timestamp).toBeDefined();
  });
});

describe('GET /health/ready', () => {
  it('returns 200 when DB is reachable', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
    const res = await request(app).get('/health/ready');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.db).toBe('connected');
  });

  it('returns 503 when DB is unreachable', async () => {
    pool.query.mockRejectedValueOnce(new Error('connection refused'));
    const res = await request(app).get('/health/ready');
    expect(res.status).toBe(503);
    expect(res.body.status).toBe('degraded');
    expect(res.body.db).toBe('unreachable');
  });
});

describe('GET /metrics', () => {
  it('returns 200 with prometheus text format', async () => {
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
    expect(res.text).toMatch(/http_requests_total/);
    expect(res.text).toMatch(/http_request_duration_seconds/);
  });
});
