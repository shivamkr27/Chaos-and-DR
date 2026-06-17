#!/bin/bash
# Disaster Recovery Failover Script
# Promotes DR replica to primary when us-east-1 goes down.
#
# Usage:
#   ./scripts/failover.sh promote    — trigger failover to DR
#   ./scripts/failover.sh status     — check current region health
#   ./scripts/failover.sh rollback   — failback to primary (after it recovers)

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"
PROJECT="chaos-dr"
DR_REPLICA_ID="${PROJECT}-dr-postgres-replica"
KUBECONFIG_PRIMARY="/tmp/kubeconfig-primary"
KUBECONFIG_DR="/tmp/kubeconfig-dr"
LOG_FILE="/tmp/failover-$(date +%Y%m%d-%H%M%S).log"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%T)] $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date +%T)] WARNING: $1${NC}" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[$(date +%T)] ERROR: $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

# ── Health check ─────────────────────────────────────────────────────────────
check_status() {
  log "=== Checking region health ==="

  PRIMARY_HC=$(aws route53 get-health-check-status \
    --health-check-id "$(aws route53 list-health-checks \
      --query "HealthChecks[?Tags[?Key=='Name' && Value=='${PROJECT}-primary-health-check']].Id" \
      --output text --region us-east-1)" \
    --query "HealthCheckObservations[0].StatusReport.Status" \
    --output text 2>/dev/null || echo "UNKNOWN")

  echo "Primary (us-east-1) health: $PRIMARY_HC"

  aws rds describe-db-instances \
    --db-instance-identifier "$DR_REPLICA_ID" \
    --region "$DR_REGION" \
    --query "DBInstances[0].{Status:DBInstanceStatus,ReadReplicaSource:ReadReplicaSourceDBInstanceIdentifier}" \
    --output table 2>/dev/null || echo "DR RDS status: unknown"
}

# ── Promote DR replica to standalone primary ─────────────────────────────────
promote_replica() {
  log "=== Starting failover to DR (${DR_REGION}) ==="
  log "Log file: $LOG_FILE"

  # Step 1: Verify DR region is actually up
  log "[1/5] Verifying DR region is healthy..."
  DR_APP_IP=$(aws ec2 describe-addresses \
    --filters "Name=tag:Project,Values=${PROJECT}" "Name=tag:Name,Values=*dr*" \
    --query "Addresses[0].PublicIp" --output text --region "$DR_REGION")

  if ! curl -sf --max-time 5 "http://${DR_APP_IP}:30080/health/live" > /dev/null; then
    die "DR region app is also unhealthy — cannot failover. Fix DR first."
  fi
  log "DR region is healthy at $DR_APP_IP"

  # Step 2: Promote RDS replica → standalone writable instance
  log "[2/5] Promoting RDS replica to standalone primary..."
  aws rds promote-read-replica \
    --db-instance-identifier "$DR_REPLICA_ID" \
    --region "$DR_REGION"

  log "Waiting for replica promotion (this takes 2-5 minutes)..."
  aws rds wait db-instance-available \
    --db-instance-identifier "$DR_REPLICA_ID" \
    --region "$DR_REGION"
  log "RDS promotion complete"

  # Step 3: Get new primary endpoint
  NEW_DB_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$DR_REPLICA_ID" \
    --region "$DR_REGION" \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)
  log "New DB endpoint: $NEW_DB_ENDPOINT"

  # Step 4: Update K8s secret in DR cluster with new DB host
  log "[3/5] Updating DB endpoint in DR Kubernetes cluster via SSH..."
  DB_PASS="${DB_PASSWORD:-ChaosD3v#2024!}"
  SSH_KEY="${SSH_KEY:-${HOME}/.ssh/chaos-dr}"

  ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=15 \
      ec2-user@"$DR_APP_IP" \
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
       kubectl create secret generic db-credentials --namespace chaos-dr \
         --from-literal=DB_HOST='${NEW_DB_ENDPOINT}' \
         --from-literal=DB_PASSWORD='${DB_PASS}' \
         --dry-run=client -o yaml | kubectl apply -f - && \
       kubectl rollout restart deployment/chaos-dr-app -n chaos-dr && \
       kubectl rollout status deployment/chaos-dr-app -n chaos-dr --timeout=120s"
  log "App pods restarted and pointing to promoted DB"

  # Step 5: Route 53 — force immediate traffic shift
  # (Route 53 failover is automatic via health checks, but this forces it instantly)
  log "[4/5] Updating Route 53 to force DR as primary..."
  ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
    --output text | sed 's|/hostedzone/||')

  if [ -n "$ZONE_ID" ] && [ -n "${DOMAIN_NAME:-}" ]; then
    aws route53 change-resource-record-sets \
      --hosted-zone-id "$ZONE_ID" \
      --change-batch "{
        \"Changes\": [{
          \"Action\": \"UPSERT\",
          \"ResourceRecordSet\": {
            \"Name\": \"${DOMAIN_NAME}\",
            \"Type\": \"A\",
            \"TTL\": 30,
            \"ResourceRecords\": [{\"Value\": \"${DR_APP_IP}\"}]
          }
        }]
      }" > /dev/null
    log "Route 53 updated — traffic now pointing to DR"
  else
    warn "DOMAIN_NAME not set — Route 53 update skipped. Health checks will handle it."
  fi

  log "[5/5] Failover complete!"
  echo ""
  echo -e "${GREEN}=== FAILOVER SUMMARY ===${NC}"
  echo "  Active region   : $DR_REGION"
  echo "  App endpoint    : http://${DR_APP_IP}:30080"
  echo "  DB endpoint     : $NEW_DB_ENDPOINT"
  echo "  Grafana         : http://${DR_APP_IP}:32000"
  echo "  Log             : $LOG_FILE"
  echo ""
  warn "Primary region (${PRIMARY_REGION}) RDS is now stale. After it recovers, run './scripts/failover.sh rollback'"
}

# ── Rollback to primary after it recovers ────────────────────────────────────
rollback() {
  warn "=== Rollback: re-establishing primary region as active ==="
  warn "This assumes primary region (${PRIMARY_REGION}) is healthy again."
  warn "You will need to re-create a replica from the promoted DR DB."
  warn "Manual step: re-apply terraform/region-primary with updated primary_db_instance_arn."
  echo ""
  echo "Steps:"
  echo "  1. Verify primary region is healthy: curl http://<primary-ip>:30080/health/ready"
  echo "  2. Create new replica from DR (now writable): terraform apply in region-primary"
  echo "  3. Wait for replication to catch up (check lag in Grafana)"
  echo "  4. Run this script in promote mode targeting primary to re-promote"
  echo "  5. Update Route 53 back to primary IP"
}

# ── Entry point ──────────────────────────────────────────────────────────────
case "${1:-}" in
  promote)  promote_replica ;;
  status)   check_status ;;
  rollback) rollback ;;
  *)
    echo "Usage: $0 [promote|status|rollback]"
    echo ""
    echo "  promote   Failover to DR region (promotes RDS replica, shifts traffic)"
    echo "  status    Show current health of both regions"
    echo "  rollback  Instructions to failback after primary recovers"
    exit 1
    ;;
esac
