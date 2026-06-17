// Cloudflare Worker — multi-region failover
// Primary: us-east-1 (100.56.48.174)  DR: us-west-2 (35.162.14.199)
// nip.io converts IPs to valid hostnames so Cloudflare Workers can fetch them

const PRIMARY      = "http://100-56-48-174.nip.io:30080";
const DR           = "http://35-162-14-199.nip.io:30080";
const HEALTH_PATH  = "/health/live";
const TIMEOUT_MS   = 4000;

async function probe(base) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(base + HEALTH_PATH, { signal: ctrl.signal });
    clearTimeout(timer);
    return r.ok;
  } catch {
    clearTimeout(timer);
    return false;
  }
}

export default {
  async fetch(request) {
    const primaryUp = await probe(PRIMARY);
    const backend   = primaryUp ? PRIMARY : DR;
    const region    = primaryUp ? "us-east-1" : "us-west-2";

    // Forward the original request to the chosen backend
    const url     = new URL(request.url);
    const target  = backend + url.pathname + url.search;

    let resp;
    try {
      resp = await fetch(target, {
        method:  request.method,
        headers: request.headers,
        body:    request.method !== "GET" && request.method !== "HEAD"
                   ? request.body : undefined,
      });
    } catch (err) {
      return new Response(`Failover error: ${err.message}`, { status: 502 });
    }

    // Rebuild response so we can add custom headers
    const headers = new Headers(resp.headers);
    headers.set("X-Served-By",       region);
    headers.set("X-Failover-Active", primaryUp ? "false" : "true");
    headers.set("X-Primary-Up",      String(primaryUp));

    return new Response(resp.body, {
      status:  resp.status,
      headers,
    });
  },
};
