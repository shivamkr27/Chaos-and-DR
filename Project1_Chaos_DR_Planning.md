# Project 1: Chaos Engineering + Multi-Region Disaster Recovery
## Phase-Wise Planning Guide (Strategy, No Code)

---

## What You're Building (The Big Picture)

A generic web application deployed across two AWS regions that **tests its own resilience continuously**. The system intentionally breaks itself on a schedule (chaos engineering) and proves it can recover and failover automatically without human intervention.

This is exactly how Netflix, Amazon, and Google run their infrastructure. It's not a toy — it's the real deal at a learnable scale.

---

## Final Deliverable

By the end, you'll have:
- A sample microservices app running in 2 AWS regions (us-east-1 primary, another region as DR)
- A chaos controller that runs experiments every few hours
- Automatic failover when a region goes down
- Monitoring dashboards showing recovery metrics
- A GitHub repo with README, architecture diagram, and demo instructions
- A live demo you can run in interviews ("watch me kill a region")

**Cost: $0** — runs entirely on AWS free tier + open-source tools.

---

## Why This Project Wins

Most candidates show projects that work in the happy path. You'll show a project that **survives failure**. When an SRE interviewer asks "how do you know your system is reliable?", you answer: "I break it on purpose, every 6 hours, and measure recovery."

That's the difference between a junior and a senior mindset.

---

## Technology Choices (Decided)

**Application layer:** A simple sample app (a basic Node/Express service is fine — you don't need anything fancy, the app is just the thing being protected). Keep it generic, no specific project branding.

**Infrastructure as Code:** Terraform — industry standard, you already have it on your resume, lets you define both regions reproducibly.

**Orchestration:** Kubernetes (EKS on AWS, or K3s if you want lighter/cheaper). EKS has some cost; K3s on free-tier EC2 is truly free. We'll plan for K3s to stay at $0, with notes on EKS for "real" scale.

**Chaos tool:** LitmusChaos — Kubernetes-native, open-source, free. Alternative is Chaos Mesh (also good). Both let you inject pod/network/resource failures declaratively.

**Failover routing:** AWS Route 53 health checks — free tier covers this. Automatically routes traffic to the healthy region.

**Data replication:** PostgreSQL streaming replication (primary → replica across regions). For storage, S3 cross-region replication (free tier: 5GB).

**Monitoring:** Prometheus + Grafana — open-source, free, already on your resume.

**Alerting:** Slack webhook (free) or just Grafana alerts.

---

## Phase-by-Phase Breakdown

### Phase 0: Foundation & Setup (Days 1-2)

**Goal:** Get your environment ready and understand the moving parts before building.

What you do:
- Set up AWS account, configure free-tier limits and billing alerts (so you never get charged)
- Install tooling locally: Terraform, kubectl, AWS CLI, Docker
- Create a simple sample app — a basic API with a health endpoint and a couple of routes that read/write to a database. This is your "thing to protect." Keep it deliberately generic.
- Containerize the sample app (Dockerfile)
- Set up a GitHub repo with clean structure

**Deliverable for this phase:** Sample app running locally in Docker, repo initialized.

**Why this matters:** Don't skip the foundation. A clean, generic app makes the whole project reusable and avoids the "everything is tangled together" problem.

---

### Phase 1: Single-Region Deployment (Days 3-4)

**Goal:** Get the app running properly in ONE region first. Walk before you run.

What you do:
- Write Terraform to provision: a VPC, a Kubernetes cluster (K3s on EC2 for free, or EKS), and a managed PostgreSQL (RDS free tier)
- Deploy the sample app to Kubernetes with proper basics: multiple replicas, health checks (liveness/readiness probes), resource limits, and a horizontal pod autoscaler
- Confirm the app is reachable and the database works
- Add Prometheus + Grafana, get a basic dashboard showing the app's health, request rate, and latency

**Deliverable:** App live in one region, monitored, self-healing at the pod level (if a pod dies, Kubernetes restarts it).

**Key learning:** Pod-level resilience comes free with Kubernetes. Region-level resilience is what you build next.

---

### Phase 2: Going Multi-Region (Days 5-7)

**Goal:** Replicate everything to a second region and wire up automatic failover.

What you do:
- Extend your Terraform to provision the same stack in a second region (this is where Terraform modules pay off — write once, deploy twice)
- Set up database replication: primary database in region 1, read-replica in region 2, with the ability to promote the replica if region 1 dies
- Configure S3 cross-region replication for any file storage
- Set up Route 53 with health checks: a primary record pointing to region 1, a secondary (failover) record pointing to region 2. Route 53 monitors region 1's health and automatically shifts traffic to region 2 if it fails.
- Use a GitOps approach (ArgoCD) or Kustomize overlays so each region gets region-specific config without duplicating manifests

**Deliverable:** Same app running in both regions, with Route 53 ready to fail traffic over automatically.

**Key concept to understand deeply:** The difference between active-active (both regions serve traffic) and active-passive (one serves, one stands by). Plan for active-passive first (simpler), mention active-active as a "future enhancement." Understand the trade-offs — this is a guaranteed interview question.

---

### Phase 3: Chaos Engineering Layer (Days 8-10)

**Goal:** Build the system that intentionally breaks things and measures recovery.

What you do:
- Install LitmusChaos in your Kubernetes cluster
- Define a set of chaos experiments, starting simple and escalating:
  - **Pod deletion** — kill a percentage of pods, watch Kubernetes reschedule them
  - **Network latency** — inject delay between services, see if timeouts/retries handle it
  - **CPU/memory stress** — choke resources, verify autoscaling kicks in
  - **Region failure simulation** — the big one: take down region 1's entry point, watch Route 53 fail over to region 2
- Wrap these into a chaos workflow that runs them in sequence
- Schedule the workflow to run automatically (every 6 hours via a cron-style job)
- For each experiment, define what "success" means: e.g., "system recovers within 30 seconds," "error rate stays below 5% during chaos," "no data loss"

**Deliverable:** A chaos controller running on schedule, breaking things and logging outcomes.

**Critical principle:** Define your SLOs (Service Level Objectives) FIRST, before running chaos. "Recovery under 30 seconds" is an SLO. Chaos tests whether you meet it. This SLO-driven thinking is the core of SRE — make sure you can talk about it fluently.

**Safety note:** Always have a "blast radius" limit — chaos should never take down BOTH regions at once. Start experiments in a staging setup before touching anything that looks like production.

---

### Phase 4: Observability & Validation (Days 11-12)

**Goal:** Make the system's behavior visible and prove the chaos experiments are meaningful.

What you do:
- Build Grafana dashboards that specifically show chaos-related metrics: pod restart counts during experiments, recovery time after each chaos event, request error rate during chaos, database replication lag, and failover events (when did traffic switch regions?)
- Set up Prometheus alerting rules: alert if recovery takes too long, if error rate spikes beyond SLO, if replication lag grows too large, if a region goes down
- Wire alerts to Slack so you get notified (and can screenshot for your demo)
- Run through each chaos experiment manually once and verify the dashboards tell the right story

**Deliverable:** Dashboards that visually prove "chaos happened, system recovered, here's the data."

**Why this matters most for interviews:** The dashboards ARE your evidence. When you say "my system recovers in under 30 seconds," you point to the graph. Observability is half of SRE — don't treat it as an afterthought.

---

### Phase 5: Automated Failover & Polish (Days 13-14)

**Goal:** Tie it all together, test the full failure scenario, and document everything.

What you do:
- Test the complete disaster scenario end-to-end: manually take down region 1, watch Route 53 detect it, confirm traffic shifts to region 2, verify the database replica gets promoted, confirm users experience minimal disruption, then bring region 1 back and watch it rejoin
- Optionally add a small Lambda function that adds smarter failover logic (e.g., custom health checks, Slack notification when failover triggers)
- Write a clear README: what the project does, architecture diagram, how to deploy it, how to run a chaos experiment, what the demo looks like
- Create the architecture diagram (draw.io or Excalidraw — free)
- Record a short demo video or prepare a live-demo script for interviews

**Deliverable:** Complete, documented, demo-ready project on GitHub.

---

## SLOs to Define (Your North Star)

Before you start chaos, write these down. They make you sound like a real SRE:
- **Availability target:** e.g., 99.5% uptime
- **Recovery Time Objective (RTO):** how fast you recover from a failure — aim for under 30 seconds for pods, under 2 minutes for region failover
- **Recovery Point Objective (RPO):** how much data you can afford to lose — aim for under a few seconds (tight replication)
- **Error budget:** how much failure is acceptable before you stop and fix things

---

## Interview Talking Points This Project Gives You

- "I designed a multi-region system with automatic failover and tested it with continuous chaos engineering."
- "I define SLOs first, then use chaos to validate I'm meeting them."
- "When a region fails, my system recovers in under [X] seconds with no data loss."
- "I think in terms of blast radius and error budgets, not just 'does it work.'"
- "I can show you live — let me kill a region right now."

---

## Common Pitfalls to Avoid

- **Don't go active-active first.** It's harder (split-brain, conflict resolution). Master active-passive, mention active-active as the next step.
- **Don't skip SLOs.** Chaos without defined success criteria is just randomly breaking things. SLOs give it meaning.
- **Don't forget billing alerts.** Set them on day one so a misconfigured resource never surprises you with a bill.
- **Don't make chaos too aggressive too early.** Start with killing one pod. Build up to region failure. Aggressive chaos on a fragile setup just creates noise.
- **Don't neglect the demo.** A project nobody can see doesn't help in interviews. Make the dashboards and demo crisp.

---

## Cost Control Checklist (Stay at $0)

- Use K3s on a single free-tier EC2 instance per region instead of EKS (EKS has a control-plane fee)
- Use RDS free tier (db.t3.micro, single instance) — for the replica, understand it may incur small cost, so plan to spin it up only when demoing
- S3 stays under 5GB (free tier)
- Route 53 health checks have a small cost at scale — keep the number minimal
- Tear down expensive resources when not actively working (Terraform makes this one command)
- Set AWS billing alerts at $1, $5, $10 thresholds

---

## Realistic Timeline Within Your 8 Weeks

This project runs in parallel with your DSA prep. Budget roughly 1-1.5 hours per day on it:
- Weeks 1-2: Phases 0-1 (foundation + single region)
- Weeks 3-4: Phase 2 (multi-region)
- Weeks 5-6: Phases 3-4 (chaos + observability)
- Weeks 7-8: Phase 5 (failover testing + polish) — lighter, since you're also doing mock interviews

---

## What to Put on Your Resume

Two to three tight bullets, metrics-driven. Examples of the shape (fill in your real numbers after building):
- Designed a multi-region active-passive architecture on AWS with Route 53 health-check failover, achieving sub-2-minute regional recovery
- Built continuous chaos engineering pipeline (LitmusChaos) running pod, network, and resource failure experiments every 6 hours; validated sub-30-second pod recovery against defined SLOs
- Implemented full observability with Prometheus and Grafana tracking recovery time, error rates, and cross-region replication lag, with automated Slack alerting

---

Start with Phase 0. Get the boring foundation right, and the rest builds cleanly on top.
