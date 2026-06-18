# 💥 Chaos Engineering + Multi-Region Disaster Recovery

A production-style resilience platform across two AWS regions that **deliberately breaks itself** and proves it recovers automatically.

> This is my (shivamkr27) personal project — infra is usually off to avoid AWS costs 😅
> The dashboard and Cloudflare Worker are always live though.
> If you fork this and run `terraform apply`, it spins up **your own** AWS infra, not mine.

🔗 **Dashboard:** https://shivamkr27.github.io/Chaos-and-DR  
🌐 **Worker:** https://chaos-dr-failove.shivamkumarbxr8.workers.dev

---

## 🏗️ Architecture

```
                     ┌──────────────────────────────────┐
                     │       Cloudflare Worker           │
                     │  Probes /health/live per request  │
                     │  Routes to DR if primary is down  │
                     └──────┬──────────────────┬─────────┘
                            │                  │ failover (<5s)
               ┌────────────▼────┐    ┌────────▼─────────┐
               │   PRIMARY        │    │   DR              │
               │   us-east-1      │    │   us-west-2       │
               │                  │    │                   │
               │  EC2 t3.micro    │    │  EC2 t3.micro     │
               │  K3s + 2 pods    │    │  K3s + 1 pod      │
               │  Prometheus      │    │  Prometheus       │
               │  Grafana         │    │  (standby)        │
               │  RDS Postgres    │    │  no DB (degraded) │
               └──────────────────┘    └───────────────────┘
                        │
               ┌────────▼────────┐
               │  GitHub Actions  │
               │  CI/CD Pipeline  │
               │  test→build→push │
               │  →deploy (SSH)   │
               └─────────────────┘
```

**Active-passive:** Primary serves all traffic. Worker health-probes per request.
On failure → Worker routes to DR instantly. No DNS change, no TTL wait.

---

## 🛠️ Tech Stack

| Layer | Tool | Why |
|---|---|---|
| App | Node.js + Express | REST API, prom-client metrics |
| IaC | Terraform | Reproducible modules per region |
| Kubernetes | K3s on EC2 t3.micro | Full K8s API, fits 1GB RAM free tier |
| Container | Docker multi-stage | Non-root, minimal image |
| Failover | Cloudflare Worker | Free tier, zero TTL, no domain needed |
| Monitoring | Prometheus + Grafana | Standalone pods, dashboard 1860 imported |
| Alerting | AWS Lambda + SNS | Email alert on failover event |
| Autoscaling | HPA autoscaling/v2 | CPU 70% + memory 80% dual metric |
| CI/CD | GitHub Actions | test → build → push → kubectl rollout |
| Dashboard | HTML/JS (static) | Chaos Lab, SLO panels, Chart.js — no backend needed |
| DB | RDS PostgreSQL | Primary only (DR runs degraded) |

---

## 📊 SLOs (Proven Live)

| SLO | Target | Actual |
|---|---|---|
| Pod recovery time | < 30 s | **17 s** |
| Availability | ≥ 99.5% | Pass |
| P99 latency | < 200 ms | ~95 ms |
| Regional failover RTO | < 30 s | **< 5 s** |

---

## 📁 Project Structure

```
.
├── app/                          # Node.js Express API
│   ├── src/
│   │   ├── index.js              # Entry + graceful shutdown
│   │   ├── routes/health.js      # /health/live (no DB) + /health/ready (checks DB)
│   │   └── routes/items.js       # /api/items CRUD
│   └── Dockerfile                # Multi-stage, non-root user
├── terraform/
│   ├── modules/
│   │   ├── vpc/                  # VPC, subnets, IGW, route tables
│   │   ├── k3s/                  # EC2, K3s bootstrap, IAM, EIP, swap user-data
│   │   ├── rds/                  # PostgreSQL 15 primary
│   │   └── rds-replica/          # Cross-region replica (disabled — free tier)
│   ├── region-primary/           # us-east-1
│   └── region-dr/                # us-west-2
├── kubernetes/
│   ├── base/                     # Deployment, Service, HPA (autoscaling/v2)
│   └── overlays/
│       ├── primary/              # 2 replicas, us-east-1
│       └── dr/                   # 1 replica, /health/live probe, us-west-2
├── monitoring/
│   ├── prometheus/               # Standalone deployment, alert rules, scrape config
│   └── grafana.yaml              # Grafana 10.2.0, datasource auto-provisioned
├── workers/
│   ├── failover.js               # Cloudflare Worker — health probe + routing + alert
│   └── wrangler.toml
├── docs/
│   └── index.html                # Static HTML/JS dashboard — served via GitHub Pages
├── scripts/
│   ├── lambda-alert/index.js     # Lambda: receives Worker call → publishes SNS email
│   └── failover.sh               # Manual DR runbook (5 steps)
└── .github/workflows/
    └── deploy.yml                # CI/CD: test → build → push → deploy (manual trigger)
```

---

## 🚀 Deploy Your Own

### Prerequisites
- AWS account + credentials (`aws configure`)
- Terraform ≥ 1.5
- SSH key pair at `~/.ssh/chaos-dr` (or update `ssh_public_key` in tfvars)
- Docker Hub account (for CI/CD)

### 1 — Terraform tfvars

```bash
cp terraform/region-primary/terraform.tfvars.example terraform/region-primary/terraform.tfvars
# fill in: ssh_public_key, db_password, app_image, aws_region
```

### 2 — Deploy Infrastructure

```bash
cd terraform/region-primary && terraform init && terraform apply
cd terraform/region-dr      && terraform init && terraform apply
```

Note the output IPs. Update `workers/failover.js` — PRIMARY and DR constants with new nip.io URLs.

### 3 — Deploy App to Both Clusters

```bash
PRIMARY_IP=<your-primary-ip>
DR_IP=<your-dr-ip>

kubectl kustomize kubernetes/overlays/primary | \
  ssh -i ~/.ssh/chaos-dr ec2-user@$PRIMARY_IP \
  "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -"

kubectl kustomize kubernetes/overlays/dr | \
  ssh -i ~/.ssh/chaos-dr ec2-user@$DR_IP \
  "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -"
```

### 4 — Deploy Monitoring

```bash
for IP in $PRIMARY_IP $DR_IP; do
  scp -i ~/.ssh/chaos-dr monitoring/prometheus/prometheus-standalone.yaml ec2-user@$IP:/tmp/
  scp -i ~/.ssh/chaos-dr monitoring/grafana.yaml ec2-user@$IP:/tmp/
  ssh -i ~/.ssh/chaos-dr ec2-user@$IP \
    "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f /tmp/prometheus-standalone.yaml -f /tmp/grafana.yaml"
done
```

### 5 — Deploy Cloudflare Worker

```bash
cd workers && CLOUDFLARE_API_TOKEN=<token> npx wrangler deploy
```

### 6 — GitHub Actions Secrets

Repo Settings → Secrets → Actions:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | your DockerHub username |
| `DOCKERHUB_TOKEN` | DockerHub access token (Read+Write) |
| `EC2_SSH_KEY` | content of `~/.ssh/chaos-dr` private key |
| `EC2_HOST` | your primary EC2 IP |

Then trigger deploy manually: Actions → CI/CD → Run workflow.

---

## 🔬 Chaos Experiments

Open `docs/index.html` (or the GitHub Pages link above) → Chaos Lab tab for the interactive version, or run directly:

```bash
PRIMARY_IP=<your-primary-ip>

# Pod Delete — proves 17s recovery
ssh -i ~/.ssh/chaos-dr ec2-user@$PRIMARY_IP \
  "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl delete pod -n chaos-dr \
  \$(kubectl get pods -n chaos-dr -l app=chaos-dr-app -o jsonpath='{.items[0].metadata.name}') \
  --grace-period=0"

# Network Latency — 300ms via tc/netem
ssh -i ~/.ssh/chaos-dr ec2-user@$PRIMARY_IP "sudo tc qdisc add dev eth0 root netem delay 300ms"
ssh -i ~/.ssh/chaos-dr ec2-user@$PRIMARY_IP "sudo tc qdisc del dev eth0 root"  # restore

# Region Failure — Worker auto-routes to DR in <5s
aws ec2 stop-instances --region us-east-1 --instance-ids <your-instance-id>
curl -sI https://chaos-dr-failove.shivamkumarbxr8.workers.dev/health/live
# expect: X-Served-By: us-west-2, X-Failover-Active: true
aws ec2 start-instances --region us-east-1 --instance-ids <your-instance-id>  # restore
```

---

## ♻️ Teardown (Zero Cost)

```bash
cd terraform/region-dr      && terraform destroy -auto-approve
cd terraform/region-primary && terraform destroy -auto-approve
```

Terminates EC2, releases EIPs, deletes RDS. Cloudflare Worker + GitHub Pages stay live (both free).

---

## 🔁 Restart Guide (for when I bring it back up)

> New `terraform apply` gives **new IPs** every time since EIPs are released on destroy.

```
1. terraform apply (primary) → note PRIMARY_IP
2. terraform apply (dr)      → note DR_IP
3. Update workers/failover.js  PRIMARY = "http://<PRIMARY_IP>.nip.io:30080"
                               DR      = "http://<DR_IP>.nip.io:30080"
4. cd workers && npx wrangler deploy
5. GitHub → Settings → Secrets → EC2_HOST = <new PRIMARY_IP>
6. kubectl apply (steps 3+4 above) on both clusters
7. GitHub Actions → Run workflow  (manual deploy trigger)
```

Dashboard and Cloudflare Worker URL never change — always live regardless.
