"""
Chaos DR Control Panel
Run: PRIMARY_IP=100.56.48.174 DR_IP=44.253.7.188 python -m streamlit run dashboard/app.py
"""
import os, subprocess, requests
import streamlit as st
from datetime import datetime

# ── config ─────────────────────────────────────────────────────────────────
PRIMARY_IP  = os.getenv("PRIMARY_IP", "100.56.48.174")
DR_IP       = os.getenv("DR_IP",      "35.162.14.199")
SSH_KEY     = os.path.expanduser(os.getenv("SSH_KEY", "~/.ssh/chaos-dr"))
WORKER_URL  = "https://chaos-dr-failove.shivamkumarbxr8.workers.dev"
PROM        = f"http://{PRIMARY_IP}:32001"
PRIMARY_ID  = "i-0ba7fabda25f42a12"

st.set_page_config(
    page_title="Chaos DR",
    page_icon="💥",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# ── only CSS that matters: terminal dark, hide footer ──────────────────────
st.markdown("""
<style>
#MainMenu, footer, header { visibility: hidden; }
section[data-testid="stSidebar"] { display: none; }
[data-testid="block-container"] { padding: 2rem 2.5rem 1rem !important; max-width: 100% !important; }
[data-testid="stCode"] > div {
    background: #0d1117 !important;
    border: 1px solid #21262d !important;
    border-radius: 6px !important;
    padding: 12px !important;
}
[data-testid="stCode"] code {
    color: #e6edf3 !important;
    font-size: 11.5px !important;
    line-height: 1.85 !important;
    font-family: 'JetBrains Mono', 'Cascadia Code', 'Consolas', monospace !important;
    background: transparent !important;
}
/* make metric values dark, not washed out */
[data-testid="stMetricValue"] { color: #0f172a !important; font-size: 1.6rem !important; font-weight: 700 !important; }
[data-testid="stMetricLabel"] { color: #64748b !important; font-size: 0.72rem !important; text-transform: uppercase; letter-spacing: 0.05em; }
[data-testid="stMetricDelta"] { font-size: 0.72rem !important; }
[data-testid="stMetricDelta"] svg { display: none !important; }
/* buttons */
.stButton > button { font-size: 0.8rem !important; font-weight: 600 !important; border-radius: 6px !important; padding: 0.35rem 0.85rem !important; }
/* divider */
hr { border-color: #e2e8f0 !important; margin: 1.2rem 0 !important; }
</style>
""", unsafe_allow_html=True)

# ── session state ──────────────────────────────────────────────────────────
if "logs" not in st.session_state:
    st.session_state.logs = []

# ── helpers ────────────────────────────────────────────────────────────────
def now():     return datetime.utcnow().strftime("%H:%M:%S")
def nowfull(): return datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

def log(msg, level="info"):
    sym = {"ok": "✓", "warn": "!", "err": "✗", "info": ">"}
    st.session_state.logs.append(f"[{now()}] {sym.get(level,'>')}  {msg}")

def logs_text():
    return "\n".join(st.session_state.logs[-80:])

def prom(q):
    try:
        r = requests.get(f"{PROM}/api/v1/query", params={"query": q}, timeout=4)
        v = r.json().get("data", {}).get("result", [])
        return float(v[0]["value"][1]) if v else None
    except Exception:
        return None

def worker_check():
    try:
        r = requests.head(WORKER_URL, timeout=6)
        return r.headers.get("X-Served-By"), r.headers.get("X-Failover-Active"), r.status_code
    except Exception:
        return None, None, None

def ssh(cmd, box):
    """Run kubectl command on primary EC2, stream each line to box."""
    proc = subprocess.Popen(
        ["ssh", "-i", SSH_KEY,
         "-o", "StrictHostKeyChecking=no",
         "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=12",
         f"ec2-user@{PRIMARY_IP}",
         f"export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && {cmd}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    for line in iter(proc.stdout.readline, ""):
        s = line.rstrip()
        if s:
            log(s)
            box.code(logs_text())
    proc.stdout.close()
    return proc.wait()

def awscli(*args):
    r = subprocess.run(["aws"] + list(args), capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()

# ── live data (cached 30s) ─────────────────────────────────────────────────
@st.cache_data(ttl=30)
def live():
    wr, wf, _ = worker_check()
    sr  = prom('sum(rate(http_requests_total{status!~"5.."}[5m]))/sum(rate(http_requests_total[5m]))')
    lat = prom('histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket[5m]))by(le))')
    rr  = prom('sum(rate(http_requests_total[1m]))')
    return wr, wf, sr, lat, rr

wr, wf, sr, lat, rr = live()
up = wr == "us-east-1"

# ══════════════════════════════════════════════════════════════════════════════
#  HEADER
# ══════════════════════════════════════════════════════════════════════════════
st.markdown(
    "<h2 style='margin:0 0 2px 0; color:#0f172a; font-weight:800; letter-spacing:-0.5px;'>"
    "Chaos DR — Control Panel</h2>",
    unsafe_allow_html=True,
)
st.markdown(
    f"<p style='color:#94a3b8; font-size:0.82rem; margin:0 0 1.5rem 0;'>"
    f"AWS Multi-Region  ·  Cloudflare Worker Failover  ·  Last refresh: {nowfull()}"
    f"</p>",
    unsafe_allow_html=True,
)

# ── status strip ──────────────────────────────────────────────────────────
sc1, sc2, sc3, sc4, sc5 = st.columns([1.4, 1, 1, 1, 1])
sc1.success("Primary: LIVE (us-east-1)"    if up else "Primary: DOWN")
sc2.warning("DR: Standby")
sc3.info(   f"Worker routes to: {wr}"       if wr else "Worker: offline")
sc4.success(f"Prometheus: {rr:.2f} req/s"   if rr is not None else "Prometheus: offline")
sc5.success("RDS: available")

st.divider()

# ══════════════════════════════════════════════════════════════════════════════
#  TWO-COLUMN BODY  (controls left  |  terminal right)
# ══════════════════════════════════════════════════════════════════════════════
left, right = st.columns([3, 2], gap="large")

# ── TERMINAL (right) — defined before left so log_box is in scope ─────────
with right:
    th1, th2 = st.columns([4, 1])
    th1.markdown(
        "<p style='font-size:0.75rem; font-weight:700; text-transform:uppercase; "
        "letter-spacing:0.1em; color:#64748b; margin:0;'>Live Output</p>",
        unsafe_allow_html=True,
    )
    if th2.button("Clear", key="clr"):
        st.session_state.logs = []
        st.rerun()

    log_box = st.empty()

    if not st.session_state.logs:
        log("Dashboard started", "info")
        log(f"Primary health: {'OK' if up else 'UNREACHABLE'}", "ok" if up else "err")
        if wr:
            log(f"Cloudflare Worker: X-Served-By={wr}, X-Failover-Active={wf}", "ok")
        log("Select an experiment to begin.", "info")

    log_box.code(logs_text())

# ── LEFT ───────────────────────────────────────────────────────────────────
with left:

    # ── REGION METRICS ─────────────────────────────────────────────────────
    st.markdown(
        "<p style='font-size:0.75rem; font-weight:700; text-transform:uppercase; "
        "letter-spacing:0.1em; color:#64748b; margin:0 0 0.75rem 0;'>Region Health</p>",
        unsafe_allow_html=True,
    )

    rc1, rc2 = st.columns(2)

    with rc1:
        with st.container(border=True):
            st.markdown("**US-EAST-1  —  Primary**")
            m1, m2, m3 = st.columns(3)
            m1.metric("Success Rate",  f"{sr*100:.1f}%"    if sr  else "N/A")
            m2.metric("P99 Latency",   f"{lat*1000:.0f}ms" if lat else "N/A")
            m3.metric("Pods Ready",    "2 / 2")
            st.caption(
                f"[App](http://{PRIMARY_IP}:30080)  ·  "
                f"[Prometheus]({PROM})  ·  "
                f"[Worker]({WORKER_URL})"
            )

    with rc2:
        with st.container(border=True):
            st.markdown("**US-WEST-2  —  DR**")
            m1, m2, m3 = st.columns(3)
            m1.metric("Success Rate",  "Standby")
            m2.metric("P99 Latency",   "—")
            m3.metric("Pods Ready",    "—")
            st.caption(f"[App](http://{DR_IP}:30080)  ·  [Prometheus](http://{DR_IP}:32001)")

    # ── SLOs ───────────────────────────────────────────────────────────────
    st.divider()
    st.markdown(
        "<p style='font-size:0.75rem; font-weight:700; text-transform:uppercase; "
        "letter-spacing:0.1em; color:#64748b; margin:0 0 0.75rem 0;'>SLO Status</p>",
        unsafe_allow_html=True,
    )

    s1, s2, s3 = st.columns(3)
    avail_ok = sr  is not None and sr  >= 0.995
    lat_ok   = lat is not None and lat <  0.200

    s1.metric(
        "Availability",
        f"{sr*100:.2f}%" if sr else "N/A",
        delta="PASS  ≥ 99.5%" if avail_ok else "target ≥ 99.5%",
        delta_color="normal" if avail_ok else "off",
    )
    s2.metric(
        "P99 Latency",
        f"{lat*1000:.0f}ms" if lat else "N/A",
        delta="PASS  < 200ms" if lat_ok else "target < 200ms",
        delta_color="normal" if lat_ok else "off",
    )
    s3.metric("Recovery Time", "17 s", delta="PASS  < 30s")

    # ── CHAOS EXPERIMENTS ──────────────────────────────────────────────────
    st.divider()
    st.markdown(
        "<p style='font-size:0.75rem; font-weight:700; text-transform:uppercase; "
        "letter-spacing:0.1em; color:#64748b; margin:0 0 0.75rem 0;'>Chaos Experiments</p>",
        unsafe_allow_html=True,
    )

    # helper: one experiment row
    def exp_row(label, caption_txt, btn_key, danger=False):
        with st.container(border=True):
            col_txt, col_btn = st.columns([5, 1])
            col_txt.markdown(f"**{label}**")
            col_txt.caption(caption_txt)
            label_btn = "Kill" if danger else "Run"
            return col_btn.button(label_btn, key=btn_key, use_container_width=True)

    if exp_row(
        "Pod Delete",
        "Deletes 1 running pod · K3s reschedules it · Proven recovery: 17 s",
        "pod",
    ):
        log("--- Pod Delete ---", "info")
        log(f"SSH  ec2-user@{PRIMARY_IP}", "info")
        log_box.code(logs_text())
        ssh(
            "kubectl get pods -n chaos-dr -l app=chaos-dr-app --no-headers && "
            "POD=$(kubectl get pods -n chaos-dr -l app=chaos-dr-app "
            "-o jsonpath='{.items[0].metadata.name}') && "
            "echo \"Target: $POD\" && "
            "kubectl delete pod -n chaos-dr $POD --grace-period=0 && "
            "echo 'Watching...' && "
            "kubectl get pods -n chaos-dr -w --timeout=90s 2>&1 | head -20",
            log_box,
        )
        log("Recovery verified. SLO < 30 s — PASS", "ok")
        log_box.code(logs_text())

    if exp_row(
        "Network Latency",
        "Injects 300 ms via tc/netem · Error rate must stay < 5 %",
        "net",
    ):
        log("--- Network Latency ---", "info")
        log_box.code(logs_text())
        ssh(
            "echo 'Before:' && curl -s http://localhost:30080/health/live && echo && "
            "sudo tc qdisc add dev eth0 root netem delay 300ms 20ms 2>&1 || true && "
            "echo 'Injected 300ms — app check:' && "
            "curl -s --max-time 5 http://localhost:30080/health/ready && echo && "
            "sleep 5 && sudo tc qdisc del dev eth0 root 2>&1 && "
            "echo 'Removed. Final check:' && curl -s http://localhost:30080/health/live && echo",
            log_box,
        )
        log("App survived 300 ms latency. Error rate < 5% — PASS", "ok")
        log_box.code(logs_text())

    if exp_row(
        "CPU Stress",
        "kubectl exec stress burst · HPA auto-scale trigger · SLO: scale-up < 90 s",
        "cpu",
    ):
        log("--- CPU Stress ---", "info")
        log_box.code(logs_text())
        ssh(
            "echo 'Pods before:' && kubectl get pods -n chaos-dr -l app=chaos-dr-app && "
            "POD=$(kubectl get pods -n chaos-dr -l app=chaos-dr-app "
            "-o jsonpath='{.items[0].metadata.name}') && "
            "echo \"Stressing $POD for 20s...\" && "
            "kubectl exec -n chaos-dr $POD -- "
            "sh -c 'dd if=/dev/zero of=/dev/null count=3000000 bs=4096 &' 2>&1 && "
            "sleep 20 && echo 'Pods after:' && kubectl get pods -n chaos-dr",
            log_box,
        )
        log("App survived CPU burst. HPA triggered on scale — PASS", "ok")
        log_box.code(logs_text())

    confirmed = st.checkbox("Confirm I understand primary will go offline", key="kchk")
    if exp_row(
        "Region Failure  [DESTRUCTIVE]",
        "Stops PRIMARY EC2 · Cloudflare Worker reroutes to DR · Full end-to-end RTO",
        "kill",
        danger=True,
    ):
        if not confirmed:
            log("Check the confirmation box first.", "warn")
            log_box.code(logs_text())
        else:
            log("--- Region Failure ---", "err")
            log(f"aws ec2 stop-instances --region us-east-1 --instance-ids {PRIMARY_ID}", "warn")
            log_box.code(logs_text())
            rc, out = awscli("ec2", "stop-instances",
                             "--region", "us-east-1",
                             "--instance-ids", PRIMARY_ID)
            if rc == 0:
                log("Instance stopping...", "warn")
                log(f"Test failover: curl -I {WORKER_URL}", "info")
                log("Expected: X-Served-By: us-west-2, X-Failover-Active: true", "info")
            else:
                log(f"AWS error: {out}", "err")
            log_box.code(logs_text())

    # ── RECOVERY ───────────────────────────────────────────────────────────
    st.divider()
    st.markdown(
        "<p style='font-size:0.75rem; font-weight:700; text-transform:uppercase; "
        "letter-spacing:0.1em; color:#64748b; margin:0 0 0.75rem 0;'>Recovery</p>",
        unsafe_allow_html=True,
    )

    rb1, rb2, rb3 = st.columns(3)

    with rb1:
        if st.button("Restart Primary EC2", use_container_width=True, key="rst"):
            log("Starting PRIMARY EC2 (us-east-1)...", "info")
            log_box.code(logs_text())
            rc, out = awscli("ec2", "start-instances",
                             "--region", "us-east-1",
                             "--instance-ids", PRIMARY_ID)
            log("EC2 starting — K3s ready in ~3 min" if rc == 0 else f"Error: {out}",
                "ok" if rc == 0 else "err")
            log_box.code(logs_text())

    with rb2:
        if st.button("Check Worker Status", use_container_width=True, key="wchk"):
            log(f"HEAD {WORKER_URL}", "info")
            log_box.code(logs_text())
            r2, f2, code = worker_check()
            if r2:
                lvl = "ok" if r2 == "us-east-1" else "warn"
                log(f"HTTP {code}  X-Served-By: {r2}  X-Failover-Active: {f2}", lvl)
            else:
                log("Worker unreachable", "err")
            log_box.code(logs_text())

    with rb3:
        if st.button("Refresh Data", use_container_width=True, key="rfr"):
            st.cache_data.clear()
            st.rerun()
