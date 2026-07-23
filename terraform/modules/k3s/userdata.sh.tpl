#!/bin/bash
# Bootstrap: K3s + Helm only.
# App and monitoring are deployed separately via scripts/deploy-app.sh and scripts/install-monitoring.sh
# This keeps bootstrap fast (~5 min) and avoids OOM on 1 GB t3.micro.
exec > /var/log/k3s-bootstrap.log 2>&1
set -x

echo "=== Starting K3s bootstrap at $(date) ==="

# Wait for network + DNS
sleep 30
until curl -sf https://get.k3s.io > /dev/null 2>&1; do
  echo "Waiting for internet..."
  sleep 10
done
echo "Network ready at $(date)"

# dnf install — skip update to avoid curl/curl-minimal conflict on AL2023
for i in 1 2 3; do
  dnf install -y git wget unzip --allowerasing && break || { echo "dnf attempt $i failed"; sleep 30; }
done

# Install K3s (no traefik — we use NodePort directly)
for i in 1 2 3; do
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh - && break || {
    echo "K3s attempt $i failed"
    sleep 60
  }
done

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p /root/.kube && cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc

echo "Waiting for K3s node Ready..."
timeout 300 bash -c 'until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done'
echo "K3s ready at $(date)"

# Install Helm
for i in 1 2 3; do
  curl -sf https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && break || { sleep 30; }
done

# Label node
kubectl label node "$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')" \
  topology.kubernetes.io/region=${region} \
  app.kubernetes.io/managed-by=terraform \
  --overwrite

# Create app namespace and DB secret — app pods need these when deployed later.
# set +x here: DB_PASSWORD/API_KEY must not be written to /var/log/k3s-bootstrap.log by the trace.
set +x
kubectl create namespace chaos-dr --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic db-credentials \
  --namespace chaos-dr \
  --from-literal=DB_HOST="${db_host}" \
  --from-literal=DB_PASSWORD="${db_password}" \
  --from-literal=API_KEY="${api_key}" \
  --dry-run=client -o yaml | kubectl apply -f -
set -x

echo "=== Bootstrap COMPLETE at $(date) ==="
echo "Next: run scripts/deploy-app.sh and scripts/install-monitoring.sh from your local machine"
echo "K3s API: https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):6443"
