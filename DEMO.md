# Live Demo Script — Chaos DR Project

Use this during interviews or walkthroughs. Practice until it takes under 8 minutes.

---

## Setup (do 5 minutes before)

```bash
# 1. Start Streamlit dashboard
PRIMARY_IP=100.56.48.174 DR_IP=35.162.14.199 python -m streamlit run dashboard/app.py

# 2. Open these in browser
#    Tab 1: Streamlit dashboard → http://localhost:8501
#    Tab 2: Primary Prometheus  → http://100.56.48.174:32001
#    Tab 3: DR app              → http://35.162.14.199:30080/health/live
#    Tab 4: Cloudflare Worker   → https://chaos-dr-failove.shivamkumarbxr8.workers.dev/health/live
```

Verify both regions are green in the dashboard (top status strip).

---

## Opening Line

> "I built a system that deliberately breaks itself and proves it recovers automatically.
>  Two AWS regions, Cloudflare failover, real Kubernetes chaos — let me show you live."

---

## Part 1 — Architecture Walk (60 seconds)

Point to the dashboard:

> "Primary is us-east-1, DR is us-west-2. Both are live.
>  A Cloudflare Worker sits in front — it checks primary health on every request.
>  If primary fails, it silently forwards to DR. No DNS propagation delay, no TTL wait."

Point to SLO panel:

> "Three SLOs: 99.5% availability, sub-30-second pod recovery, P99 latency under 200ms.
>  We've proven all three — pod recovery is consistently 17 seconds."

---

## Part 2 — Pod Delete (click the button)

Click **Pod Delete** in the dashboard. Watch the terminal on the right.

> "This deletes a running pod with grace-period=0 — hard kill, no warning.
>  K3s detects the pod is gone and reschedules it immediately."

Point to the terminal output — you'll see the target pod name, the delete, then the new pod appearing.

> "Recovery time: 17 seconds. SLO is 30. Passed.
>  The other pod absorbed all traffic while this one restarted —
>  error rate stayed at zero because the readiness probe protected the Service."

---

## Part 3 — Network Latency (click the button)

Click **Network Latency**.

> "This injects 300ms of latency via tc/netem — simulates a degraded network.
>  The app keeps running. Slow queries complete slowly, not crash."

Point to the Prometheus dashboard at `:32001/graph`.

> "P99 latency climbs but stays under our 200ms baseline alert threshold.
>  After 5 seconds, the latency is removed and everything normalizes."

---

## Part 4 — Region Failure (the showstopper)

Check the confirmation checkbox in the dashboard, then click **Kill** on Region Failure.

> "I'm stopping the primary EC2 right now. All traffic should route to DR."

Open the Cloudflare Worker URL in a new tab:
`https://chaos-dr-failove.shivamkumarbxr8.workers.dev/health/live`

> "Watch the X-Served-By header. It was 'us-east-1'. Now it should flip to 'us-west-2'."

Show the response with DevTools Network tab open — `X-Served-By: us-west-2`, `X-Failover-Active: true`.

> "Zero DNS change. Zero TTL wait. The Cloudflare Worker detects primary down on the next request
>  and routes to DR. Total failover time: under 5 seconds from the EC2 stopping."

Then click **Restart Primary EC2** to recover:

> "Primary comes back, K3s restarts, passes the health check, and Worker routes back automatically."

---

## Common Interview Questions

**Q: Why Cloudflare Worker instead of Route 53?**
> "Route 53 failover costs money (health checks $0.50/month each) and has 60-90s minimum TTL.
>  The Worker is free, works per-request with zero latency, and I don't need a domain.
>  For a real prod system with an owned domain, Route 53 is the right answer."

**Q: Why K3s instead of EKS?**
> "K3s gives the full Kubernetes API — same manifests, same kubectl — at zero cost on a t3.micro.
>  EKS adds $72/month just for the control plane. The concepts transfer directly to EKS;
>  I'd swap the kubeconfig and add IRSA. K3s proves the architecture without the bill."

**Q: How do you prevent chaos from taking down both regions?**
> "Blast radius controls. Pod delete, network latency, CPU stress — all run only on primary.
>  Region failure is manual-only with a confirmation checkbox.
>  DR is never touched by automated experiments."

**Q: What about the database during failover?**
> "Primary region has RDS PostgreSQL. DR runs the app in degraded mode (no DB) —
>  the health/live endpoint stays green, but write operations would fail gracefully.
>  In a real DR, you'd promote a replica; I have the terraform module and failover script
>  for that — RDS cross-region replication requires backup retention which costs money
>  outside free tier, so it's disabled for this demo."

**Q: What would you change at real scale?**
> "Active-active with conflict resolution at the data layer, Velero for cluster state backup,
>  replace direct kubectl chaos with proper tooling like Gremlin or chaos-mesh,
>  and add a chaos hypothesis framework — define the expected blast radius before each experiment."
