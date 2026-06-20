#!/bin/bash
# Run a chaos experiment on a K3s cluster and watch the result.
#
# Usage:
#   ./scripts/run-chaos.sh <ec2-ip> <experiment-name>
#
# Experiment names: 01-pod-delete | 02-network-latency | 03-cpu-stress | 04-region-failure
#
# Example:
#   ./scripts/run-chaos.sh 18.214.182.177 01-pod-delete

set -euo pipefail

EC2_IP="${1:?EC2 IP required}"
EXPERIMENT="${2:?Experiment name required (e.g. 01-pod-delete)}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/chaos-dr}"
SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=20 ec2-user@${EC2_IP}"

YAML_FILE="chaos/experiments/${EXPERIMENT}.yaml"
if [ ! -f "$YAML_FILE" ]; then
  echo "ERROR: $YAML_FILE not found"
  echo "Available experiments:"
  ls chaos/experiments/
  exit 1
fi

echo "=== Running chaos experiment: ${EXPERIMENT} on ${EC2_IP} ==="

echo "[1/3] Applying experiment YAML..."
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  "$YAML_FILE" \
  ec2-user@${EC2_IP}:/tmp/${EXPERIMENT}.yaml

$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl apply -f /tmp/${EXPERIMENT}.yaml --validate=false"

echo "[2/3] Watching pods in chaos-dr namespace (Ctrl+C to stop watching)..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -n chaos-dr -w &
WATCH_PID=\$!
sleep 90
kill \$WATCH_PID 2>/dev/null || true"

echo "[3/3] Chaos result:"
ENGINE_NAME=$(grep -m1 'name:' "$YAML_FILE" | awk '{print $2}')
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get chaosresult -n chaos-dr 2>/dev/null || echo 'No ChaosResult yet (experiment may still be running)'
kubectl get pods -n chaos-dr"

echo ""
echo "=== Experiment ${EXPERIMENT} complete ==="
echo "  Check dashboard: open docs/index.html or https://shivamkr27.github.io/Chaos-and-DR"
