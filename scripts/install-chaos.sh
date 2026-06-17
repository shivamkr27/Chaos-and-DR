#!/bin/bash
# Install LitmusChaos 2.x operator + RBAC on a K3s cluster.
# Run AFTER deploy-app.sh so the chaos-dr namespace and app exist.
#
# Usage:
#   ./scripts/install-chaos.sh <ec2-ip>

set -euo pipefail

EC2_IP="${1:?EC2 IP required}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/chaos-dr}"
SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=20 ec2-user@${EC2_IP}"

echo "=== Installing LitmusChaos 2.x on ${EC2_IP} ==="

echo "[1/3] Installing LitmusChaos operator..."
$SSH 'bash -s' <<'HEREDOC'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v2.14.0.yaml --validate=false

echo "Waiting for litmus operator to be ready..."
kubectl rollout status deployment/chaos-operator-ce -n litmus --timeout=120s || true
kubectl get pods -n litmus
HEREDOC

echo "[2/3] Applying chaos RBAC..."
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  chaos/install/chaosengine-rbac.yaml \
  ec2-user@${EC2_IP}:/tmp/chaosengine-rbac.yaml

$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl apply -f /tmp/chaosengine-rbac.yaml"

echo "[3/4] Installing ChaosExperiment resources (pod-delete, cpu-hog)..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# Install experiment templates in the app namespace
kubectl apply -f https://raw.githubusercontent.com/litmuschaos/chaos-charts/2.14.0/charts/generic/pod-delete/experiment.yaml -n chaos-dr --validate=false 2>&1 || true
kubectl apply -f https://raw.githubusercontent.com/litmuschaos/chaos-charts/2.14.0/charts/generic/pod-cpu-hog/experiment.yaml -n chaos-dr --validate=false 2>&1 || true"

echo "[4/4] Verifying CRDs installed..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get crd | grep litmuschaos || echo 'CRDs not found yet — operator may still be starting'
kubectl get chaosexperiment -n chaos-dr 2>/dev/null"

echo ""
echo "=== LitmusChaos installed! ==="
echo ""
echo "Run chaos experiments:"
echo "  Pod delete (60s): ./scripts/run-chaos.sh ${EC2_IP} 01-pod-delete"
echo "  CPU stress (2m):  ./scripts/run-chaos.sh ${EC2_IP} 03-cpu-stress"
