const PRIMARY      = "http://100-56-48-174.nip.io:30080";
const DR           = "http://35-162-14-199.nip.io:30080";
const HEALTH_PATH  = "/health/live";
// Every request re-probes PRIMARY (no cross-request caching in a stateless Worker),
// so during an actual outage every request pays this timeout before falling back to
// DR. Kept short — a healthy same-region probe responds in well under 1s normally.
// A proper fix would cache health status in Workers KV; not done to avoid needing a
// new binding for this demo.
const PROBE_TIMEOUT_MS  = 1500;
const FETCH_TIMEOUT_MS  = 4000;
// So the GitHub Pages dashboard can read the real status via a cross-origin fetch
// (its own EC2 backends are usually torn down to save cost, but this Worker isn't).
const DASHBOARD_ORIGIN  = "https://shivamkr27.github.io";

function withCors(headers) {
  headers.set("Access-Control-Allow-Origin", DASHBOARD_ORIGIN);
  headers.set("Access-Control-Expose-Headers", "X-Served-By, X-Failover-Active, X-Primary-Up");
  return headers;
}

async function probe(base) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), PROBE_TIMEOUT_MS);
  try {
    const r = await fetch(base + HEALTH_PATH, { signal: ctrl.signal });
    clearTimeout(timer);
    return r.ok;
  } catch {
    clearTimeout(timer);
    return false;
  }
}

async function sendFailoverAlert(env, path) {
  if (!env.LAMBDA_URL || !env.ALERT_SECRET) return;
  try {
    await fetch(env.LAMBDA_URL, {
      method:  "POST",
      headers: {
        "Content-Type":   "application/json",
        "x-alert-secret": env.ALERT_SECRET,
      },
      body: JSON.stringify({ 
        path, 
        timestamp: Date.now(),
        region: "us-west-2",
        primaryUp: false
      }),
    });
  } catch (_) {
    // alert failure must never block traffic routing
  }
}

export default {
  async fetch(request, env, ctx) {
    const primaryUp = await probe(PRIMARY);
    const backend   = primaryUp ? PRIMARY : DR;
    const region    = primaryUp ? "us-east-1" : "us-west-2";

    if (!primaryUp) {
      const url = new URL(request.url);
      ctx.waitUntil(sendFailoverAlert(env, url.pathname));
    }

    const url    = new URL(request.url);
    const target = backend + url.pathname + url.search;

    const fetchCtrl  = new AbortController();
    const fetchTimer = setTimeout(() => fetchCtrl.abort(), FETCH_TIMEOUT_MS);

    let resp;
    try {
      resp = await fetch(target, {
        method:  request.method,
        headers: request.headers,
        body:    request.method !== "GET" && request.method !== "HEAD"
                   ? request.body : undefined,
        signal:  fetchCtrl.signal,
      });
    } catch (err) {
      return new Response(`Failover error: ${err.message}`, {
        status:  502,
        headers: withCors(new Headers()),
      });
    } finally {
      clearTimeout(fetchTimer);
    }

    const headers = withCors(new Headers(resp.headers));
    headers.set("X-Served-By",       region);
    headers.set("X-Failover-Active", primaryUp ? "false" : "true");
    headers.set("X-Primary-Up",      String(primaryUp));

    return new Response(resp.body, {
      status:  resp.status,
      headers,
    });
  },
};