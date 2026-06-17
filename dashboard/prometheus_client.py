import requests
from config import PROMETHEUS_PRIMARY, PROMETHEUS_DR


def _query(base_url, promql):
    """Run an instant PromQL query. Returns float or None."""
    if not base_url:
        return None
    try:
        resp = requests.get(
            f"{base_url}/api/v1/query",
            params={"query": promql},
            timeout=5,
        )
        resp.raise_for_status()
        result = resp.json().get("data", {}).get("result", [])
        if result:
            return float(result[0]["value"][1])
        return None
    except Exception:
        return None


def _query_range(base_url, promql, start, end, step="30s"):
    """Run a range PromQL query. Returns list of (timestamp, value) tuples."""
    if not base_url:
        return []
    try:
        resp = requests.get(
            f"{base_url}/api/v1/query_range",
            params={"query": promql, "start": start, "end": end, "step": step},
            timeout=10,
        )
        resp.raise_for_status()
        result = resp.json().get("data", {}).get("result", [])
        if result:
            return [(float(t), float(v)) for t, v in result[0]["values"]]
        return []
    except Exception:
        return []


def get_metrics(region="primary"):
    """Fetch all key metrics from the Prometheus for a given region."""
    base = PROMETHEUS_PRIMARY if region == "primary" else PROMETHEUS_DR

    # Use actual metric names exported by the app (http_requests_total histogram)
    success_rate = _query(
        base,
        'sum(rate(http_requests_total{status!~"5.."}[5m])) / sum(rate(http_requests_total[5m]))',
    )
    p99_latency = _query(
        base,
        "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))",
    )
    # kube-state-metrics is included in prometheus-community/prometheus chart
    ready_pods = _query(
        base,
        'count(kube_pod_status_ready{namespace="chaos-dr", condition="true"})',
    )
    req_rate = _query(
        base,
        "sum(rate(http_requests_total[1m]))",
    )
    # pg_replication_lag requires pg_exporter — not installed, returns None gracefully
    replication_lag = None
    chaos_active = _query(
        base,
        'sum(kube_job_status_active{namespace="chaos-dr", job_name=~"chaos-.*"}) or vector(0)',
    )

    return {
        "success_rate":     success_rate,
        "p99_latency_s":    p99_latency,
        "ready_pods":       ready_pods,
        "req_rate":         req_rate,
        "replication_lag":  replication_lag,
        "chaos_active":     int(chaos_active) if chaos_active is not None else 0,
    }


def get_error_rate_history(region="primary", minutes=30):
    """Return error rate over the last N minutes for charting."""
    import time
    base  = PROMETHEUS_PRIMARY if region == "primary" else PROMETHEUS_DR
    end   = int(time.time())
    start = end - minutes * 60
    return _query_range(
        base,
        '1 - (sum(rate(http_requests_total{status!~"5.."}[5m])) / sum(rate(http_requests_total[5m])))',
        start, end, step="30s",
    )
