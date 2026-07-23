const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const rdsCaBundle = fs.readFileSync(path.join(__dirname, '..', 'rds-ca-bundle.pem'));

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'chaosdb',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  // AWS RDS requires SSL (rds.force_ssl=1 by default in PostgreSQL 15+).
  // Verify against Amazon's public RDS CA bundle instead of disabling verification.
  // Explicit opt-out via DB_SSL=false for local Postgres (docker-compose, plain localhost),
  // which doesn't have SSL enabled — inferring this from the hostname was unreliable
  // (e.g. the docker-compose service name "postgres" doesn't contain "localhost").
  ssl: process.env.DB_SSL === 'false'
    ? undefined
    : { rejectUnauthorized: true, ca: rdsCaBundle },
});

// An unhandled 'error' event on an idle client crashes the process (per node-postgres docs).
pool.on('error', (err) => {
  console.error('Unexpected DB pool error:', err.message);
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
