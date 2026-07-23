#!/bin/bash
# Run a chaos experiment directly over SSH — no LitmusChaos, just the real
# commands (kubectl delete pod / tc netem / a busy-loop) against the K3s node.
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

# Experiment 04 stops the EC2 instance this script would be running commands against —
# applying it here would kill the SSH session mid-execution. Block it and require
# running the AWS CLI commands directly from your own machine.
if [ "$EXPERIMENT" = "04-region-failure" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  BLOCKED: 04-region-failure cannot run via run-chaos.sh     ║"
  echo "║                                                              ║"
  echo "║  This experiment stops the EC2 the SSH session runs on.     ║"
  echo "║                                                              ║"
  echo "║  Run it locally instead:                                     ║"
  echo "║    aws ec2 stop-instances --region us-east-1 \\              ║"
  echo "║      --instance-ids \$(aws ec2 describe-instances ...)       ║"
  echo "║    # verify Worker failover:                                 ║"
  echo "║    curl -sI https://chaos-dr-failove.shivamkumarbxr8\\      ║"
  echo "║                .workers.dev/health/live                     ║"
  echo "║    aws ec2 start-instances --region us-east-1 \\            ║"
  echo "║      --instance-ids <same-id>                               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  exit 1
fi

echo "=== Running chaos experiment: ${EXPERIMENT} on ${EC2_IP} ==="

case "$EXPERIMENT" in
  01-pod-delete)
    # Kill 1 app pod every 20s for 60s total (grace-period=0 = hard kill, tests SIGTERM handling)
    echo "[1/2] Killing pods (3 rounds, 20s apart)..."
    for i in 1 2 3; do
      $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      POD=\$(kubectl get pods -n chaos-dr -l app=chaos-dr-app -o jsonpath='{.items[0].metadata.name}')
      echo \"Round $i: deleting \$POD\"
      kubectl delete pod \"\$POD\" -n chaos-dr --grace-period=0 --force"
      [ "$i" -lt 3 ] && sleep 20
    done
    echo "[2/2] Watching recovery (90s)..."
    $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl get pods -n chaos-dr -w &
    WATCH_PID=\$!
    sleep 90
    kill \$WATCH_PID 2>/dev/null || true"
    ;;

  02-network-latency)
    # Inject 300ms±50ms latency on all outbound traffic for 60s, then remove it
    echo "[1/2] Injecting 300ms±50ms latency for 60s..."
    $SSH "sudo tc qdisc add dev eth0 root netem delay 300ms 50ms"
    sleep 60
    echo "[2/2] Removing latency..."
    $SSH "sudo tc qdisc del dev eth0 root netem" || echo "  (qdisc already clear)"
    ;;

  03-cpu-stress)
    # Saturate 1 core on an app pod for 120s — no extra tooling needed in the alpine image
    echo "[1/2] Saturating 1 core on one app pod for 120s..."
    $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    POD=\$(kubectl get pods -n chaos-dr -l app=chaos-dr-app -o jsonpath='{.items[0].metadata.name}')
    echo \"Stressing \$POD\"
    kubectl exec \"\$POD\" -n chaos-dr -- node -e 'const e=Date.now()+120000; while(Date.now()<e){}' &
    STRESS_PID=\$!
    kubectl get hpa chaos-dr-app -n chaos-dr -w &
    WATCH_PID=\$!
    sleep 120
    kill \$WATCH_PID 2>/dev/null || true
    wait \$STRESS_PID 2>/dev/null || true"
    echo "[2/2] Done — check HPA scale-up above (SLO: currentReplicas > 2 within 90s)."
    ;;

  *)
    echo "ERROR: unknown experiment '$EXPERIMENT'"
    echo "Available: 01-pod-delete | 02-network-latency | 03-cpu-stress | 04-region-failure"
    exit 1
    ;;
esac

echo ""
echo "=== Experiment ${EXPERIMENT} complete ==="
echo "  Check dashboard: open docs/index.html or https://shivamkr27.github.io/Chaos-and-DR"
