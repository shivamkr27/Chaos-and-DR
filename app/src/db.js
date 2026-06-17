const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'chaosdb',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  // AWS RDS requires SSL (rds.force_ssl=1 by default in PostgreSQL 15+)
  ssl: process.env.DB_HOST && !process.env.DB_HOST.includes('localhost')
    ? { rejectUnauthorized: false }
    : undefined,
});

async function initDb() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS items (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
  } finally {
    client.release();
  }
}

module.exports = { pool, initDb };
