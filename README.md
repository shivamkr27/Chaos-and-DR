# Chaos Engineering + Multi-Region Disaster Recovery

A production-style resilience platform spanning two AWS regions.
The system **deliberately breaks itself** and proves it recovers automatically — no human intervention.

---

## Architecture

```
                     ┌──────────────────────────────┐
                     │    Cloudflare Worker          │
                     │  (https://chaos-dr-failove    │
                     │   .shivamkumarbxr8.workers.dev│
                     │                               │
                     │  Checks /health/live every    │
                     │  request; routes to DR if     │
                     │  primary is down              │
                     └──────┬────────────────┬───────┘
                            │                │ (failover)
               ┌────────────▼───┐     ┌──────▼──────────┐
               │  PRIMARY       │     │  DR              │
               │  us-east-1     │     │  us-west-2       │
               │                │     │                  │
               │  EC2 t3.micro  │     │  EC2 t3.micro   │
               │  K3s cluster   │     │  K3s cluster    │
               │  2 app pods    │     │  2 app pods     │
               │  Prometheus    │     │  Prometheus     │
               │  RDS Postgres  │     │  (standby)      │
               │  EIP: 100.56   │     │  EIP: 35.162    │
               │      .48.174   │     │      .14.199    │
               └────────────────┘     └─────────────────┘
```

**Active-passive setup:** Primary serves all traffic.
Cloudflare Worker checks primary health on every request.
If primary fails, Worker transparently forwards to DR — zero DNS propagation delay.

---

## Tech Stack

| Layer | Tool | Why |
|---|---|---|
| App | Node.js + Express | Simple REST API, containerised |
| IaC | Terraform | Reproducible modules per region |
| Kubernetes | K3s on EC2 t3.micro | Full K8s API, 1 GB RAM fits free tier |
| Chaos | kubectl (direct) | LitmusChaos removed — OOM on 1 GB |
| Failover | Cloudflare Worker | Free tier, no domain needed, zero TTL |
| DB | PostgreSQL RDS | Primary region only (free tier demo) |
| Monitoring | Prometheus | Standalone pod, no Grafana (RAM) |
| Dashboard | Streamlit | Python control panel with SSH buttons |

---

## SLOs (Proven)

| SLO | Target | Result |
|---|---|---|
| Pod recovery time | < 30 s | **17 s** consistently |
| Availability | ≥ 99.5% success rate | Pass |
| P99 latency | < 200 ms steady state | ~95 ms |
| CPU stress survival | error rate < 5% | Pass |
| Regional failover | Cloudflare Worker reroutes | Pass |

---

## Project Structure

```
.
├── app/                         # Node.js Express API
│   ├── src/
│   │   ├── index.js             # Entry + graceful shutdown
│   │   ├── db.js                # PostgreSQL pool (SSL on RDS)
│   │   ├── metrics.js           # Prometheus middleware
│   │   └── routes/
│   │       ├── health.js        # /health/live (always ok) + /health/ready (checks DB)
│   │       └── items.js         # /api/items CRUD
│   └── Dockerfile               # Multi-stage, non-root user
├── terraform/
│   ├── modules/
│   │   ├── vpc/                 # VPC, subnets, IGW, route tables
│   │   ├── k3s/                 # EC2 t3.micro, K3s bootstrap, IAM, EIP
│   │   ├── rds/                 # PostgreSQL 15 primary
│   │   ├── rds-replica/         # Cross-region read replica (disabled in DR demo)
│   │   └── s3-replication/      # S3 + CRR
│   ├── region-primary/          # us-east-1 (deployed and live)
│   └── region-dr/               # us-west-2 (deployed and live)
├── kubernetes/
│   ├── base/                    # Deployment, Service, HPA
│   └── overlays/
│       ├── primary/             # AWS_REGION=us-east-1
│       └── dr/                  # AWS_REGION=us-west-2, readiness=/health/live
├── chaos/
│   └── experiments/             # 4 experiment YAMLs (LitmusChaos format, manual run)
├── monitoring/
│   └── prometheus/              # Scrape config, alert rules, standalone deployment
├── workers/
│   ├── failover.js              # Cloudflare Worker source
│   └── wrangler.toml            # Worker config
├── dashboard/
│   └── app.py                   # Streamlit — real SSH chaos buttons + live terminal
└── scripts/
    └── failover.sh              # DR failover runbook (5 steps)
```

---

## Live Endpoints

| Endpoint | URL |
|---|---|
| Primary app | http://100.56.48.174:30080 |
| Primary Prometheus | http://100.56.48.174:32001 |
| DR app | http://35.162.14.199:30080 |
| DR Prometheus | http://35.162.14.199:32001 |
| Cloudflare Worker | https://chaos-dr-failove.shivamkumarbxr8.workers.dev |
| Streamlit dashboard | http://localhost:8501 |

---

## Quick Start

### Prerequisites
- AWS credentials with EC2/IAM/VPC permissions
- Terraform ≥ 1.5, kubectl, SSH key at `~/.ssh/chaos-dr`
- Python 3.10+ and `pip install streamlit requests`

### Deploy Infrastructure
```bash
# Primary (us-east-1)
cd terraform/region-primary
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init && terraform apply

# DR (us-west-2)
cd terraform/region-dr
terraform init && terraform apply
```

### Deploy App
```bash
# Primary
kubectl kustomize kubernetes/overlays/primary | \
  ssh -i ~/.ssh/chaos-dr ec2-user@100.56.48.174 \
  "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl apply -f -"

# DR
kubectl kustomize kubernetes/overlays/dr | \
  ssh -i ~/.ssh/chaos-dr ec2-user@35.162.14.199 \
  "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl apply -f -"
```

### Deploy Prometheus
```bash
ssh -i ~/.ssh/chaos-dr ec2-user@<ip> \
  "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl apply -f -" \
  < monitoring/prometheus/prometheus-standalone.yaml
```

### Run Dashboard
```bash
PRIMARY_IP=100.56.48.174 DR_IP=35.162.14.199 \
  python -m streamlit run dashboard/app.py
```

### Update Cloudflare Worker
```bash
cd workers
npx wrangler deploy --name chaos-dr-failove
# Requires: CLOUDFLARE_API_TOKEN env var
```

---

## Chaos Experiments

Run from the Streamlit dashboard (real SSH) or CLI:

```bash
# 1. Pod Delete — proves 17s recovery
kubectl delete pod -n chaos-dr \
  $(kubectl get pods -n chaos-dr -l app=chaos-dr-app -o jsonpath='{.items[0].metadata.name}') \
  --grace-period=0

# 2. Network Latency — 300ms injection via tc/netem
ssh ec2-user@100.56.48.174 "sudo tc qdisc add dev eth0 root netem delay 300ms 20ms"
# restore:
ssh ec2-user@100.56.48.174 "sudo tc qdisc del dev eth0 root"

# 3. CPU Stress — triggers HPA scale-out
POD=$(kubectl get pods -n chaos-dr -l app=chaos-dr-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n chaos-dr $POD -- sh -c 'dd if=/dev/zero of=/dev/null &'

# 4. Region Failure — stops primary, Cloudflare Worker reroutes
aws ec2 stop-instances --region us-east-1 --instance-ids i-0ba7fabda25f42a12
# Verify: curl -I https://chaos-dr-failove.shivamkumarbxr8.workers.dev/
# Expected: X-Served-By: us-west-2, X-Failover-Active: true
# Restore:
aws ec2 start-instances --region us-east-1 --instance-ids i-0ba7fabda25f42a12
```

---

## Teardown
```bash
cd terraform/region-dr      && terraform destroy -auto-approve
cd terraform/region-primary && terraform destroy -auto-approve
```

---

## Resume Bullets

```
• Designed multi-region active-passive DR architecture on AWS (us-east-1 / us-west-2)
  using K3s Kubernetes on t3.micro; Cloudflare Worker provides zero-TTL failover routing

• Implemented 4 chaos experiments (pod delete, network latency, CPU stress, region failure)
  via Streamlit dashboard with live SSH terminal; proven 17-second pod recovery against <30s SLO

• Built production observability stack (Prometheus + custom alert rules) tracking
  availability ≥99.5%, P99 latency, and RTO; entire infrastructure managed with Terraform modules
```
