#!/bin/bash
# Deploy the chaos-dr app to a K3s cluster over SSH.
# Run this AFTER `terraform apply` finishes and the EC2 is up.
#
# Usage:
#   DB_PASSWORD=... API_KEY=... ./scripts/deploy-app.sh primary <ec2-ip> <db-host>
#   DB_PASSWORD=... API_KEY=... ./scripts/deploy-app.sh dr      <ec2-ip> <db-host>
#
# Example — get IPs from terraform output first:
#   PRIMARY_IP=$(cd terraform/region-primary && terraform output -raw k3s_public_ip)
#   PRIMARY_DB=$(cd terraform/region-primary && terraform output -raw rds_endpoint)
#   DB_PASSWORD=... API_KEY=... ./scripts/deploy-app.sh primary "$PRIMARY_IP" "$PRIMARY_DB"
#
#   DR_IP=$(cd terraform/region-dr && terraform output -raw k3s_public_ip)
#   DR_DB=$(cd terraform/region-dr && terraform output -raw rds_replica_endpoint)
#   DB_PASSWORD=... API_KEY=... ./scripts/deploy-app.sh dr "$DR_IP" "$DR_DB"

set -euo pipefail

ROLE="${1:?Usage: $0 <primary|dr> <ec2-ip> <db-host>}"
EC2_IP="${2:?EC2 IP required}"
DB_HOST="${3:?DB host (RDS endpoint) required}"

DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var required}"
API_KEY="${API_KEY:?API_KEY env var required (shared secret for POST/DELETE on /api/items)}"
APP_IMAGE="${APP_IMAGE:-shivam272727/chaos-dr-app:latest}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/chaos-dr}"

case "$ROLE" in
  primary) AWS_REGION="us-east-1" ;;
  dr)      AWS_REGION="us-west-2" ;;
  *) echo "ERROR: role must be 'primary' or 'dr'"; exit 1 ;;
esac

SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=20 ec2-user@${EC2_IP}"

echo "=== Deploying chaos-dr app ==="
echo "  Role:    $ROLE  |  Region: $AWS_REGION"
echo "  EC2:     $EC2_IP"
echo "  DB Host: $DB_HOST"
echo "  Image:   $APP_IMAGE"
echo ""

# Verify SSH works before proceeding
$SSH "echo 'SSH OK'" || { echo "ERROR: Cannot SSH to $EC2_IP. Check IP and key."; exit 1; }

echo "[1/3] Creating namespace and DB secret..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create namespace chaos-dr --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic db-credentials --namespace chaos-dr \
  --from-literal=DB_HOST='${DB_HOST}' \
  --from-literal=DB_PASSWORD='${DB_PASSWORD}' \
  --from-literal=API_KEY='${API_KEY}' \
  --dry-run=client -o yaml | kubectl apply -f -"

echo "[2/3] Applying Deployment, Service, HPA..."
# Generate YAML locally and pipe to kubectl on the remote — avoids nested heredoc issues
cat <<YAML | $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl apply -f -"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chaos-dr-app
  namespace: chaos-dr
  labels:
    app: chaos-dr-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: chaos-dr-app
  template:
    metadata:
      labels:
        app: chaos-dr-app
    spec:
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
      containers:
        - name: app
          image: ${APP_IMAGE}
          ports:
            - containerPort: 3000
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          env:
            - name: PORT
              value: "3000"
            - name: DB_PORT
              value: "5432"
            - name: DB_NAME
              value: "chaosdb"
            - name: DB_USER
              value: "postgres"
            - name: AWS_REGION
              value: "${AWS_REGION}"
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: DB_HOST
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: DB_PASSWORD
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: API_KEY
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          livenessProbe:
            httpGet:
              path: /health/live
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
      volumes:
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: chaos-dr-app
  namespace: chaos-dr
  labels:
    app: chaos-dr-app
spec:
  type: NodePort
  selector:
    app: chaos-dr-app
  ports:
    - name: http
      port: 80
      targetPort: 3000
      nodePort: 30080
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: chaos-dr-app
  namespace: chaos-dr
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: chaos-dr-app
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
YAML

echo "[3/3] Waiting for rollout (up to 2 min)..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl rollout status deployment/chaos-dr-app -n chaos-dr --timeout=120s
echo ''
kubectl get pods -n chaos-dr -o wide
echo ''
echo 'Health check:'
curl -sf http://localhost:30080/health/live && echo ' LIVE OK' || echo ' not ready yet'
curl -sf http://localhost:30080/health/ready && echo ' READY OK' || echo ' db not reachable yet'"

echo ""
echo "=== App deployed to $ROLE region ==="
echo "  App:     http://${EC2_IP}:30080"
echo "  Metrics: http://${EC2_IP}:30080/metrics"
echo "  Health:  http://${EC2_IP}:30080/health/ready"
