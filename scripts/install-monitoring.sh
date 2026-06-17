#!/bin/bash
# Install Prometheus on a K3s EC2 node via plain kubectl apply (no Helm).
# Helm causes K3s API HTTP/2 stream errors on t3.micro; kubectl apply is single-call.
#
# Usage:
#   ./scripts/install-monitoring.sh <ec2-ip>

set -euo pipefail

EC2_IP="${1:?EC2 IP required}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/chaos-dr}"
SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=20 ec2-user@${EC2_IP}"

echo "=== Installing Prometheus on ${EC2_IP} ==="

echo "[1/3] Copying standalone manifest..."
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/prometheus/prometheus-standalone.yaml \
  ec2-user@${EC2_IP}:/tmp/prometheus-standalone.yaml

echo "[2/3] Applying manifest (single kubectl apply — no Helm stream errors)..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
  kubectl apply -f /tmp/prometheus-standalone.yaml --validate=false"

echo "[3/3] Waiting for Prometheus pod (polls every 10s, up to 5 min)..."
for i in $(seq 1 30); do
  STATUS=$($SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && \
    kubectl get pods -n monitoring 2>/dev/null | grep prometheus | grep -v Terminating | awk '{print \$2}'" 2>/dev/null || echo "")
  if echo "$STATUS" | grep -q "1/1"; then
    echo "  Prometheus is Ready!"
    break
  fi
  echo "  attempt $i/30 — status: ${STATUS:-no pod yet}"
  sleep 10
done

$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -n monitoring"

echo ""
echo "=== Done! ==="
echo "  Prometheus: http://${EC2_IP}:32001"
