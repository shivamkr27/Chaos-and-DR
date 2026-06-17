import os

# Fill these after terraform apply outputs the IPs
PRIMARY_IP   = os.getenv("PRIMARY_IP", "")
DR_IP        = os.getenv("DR_IP", "")
APP_PORT     = int(os.getenv("APP_PORT", "30080"))
GRAFANA_PORT = int(os.getenv("GRAFANA_PORT", "32000"))

AWS_REGION_PRIMARY = "us-east-1"
AWS_REGION_DR      = "us-west-2"
PROJECT            = "chaos-dr"
NAMESPACE          = "chaos-dr"

# Prometheus base URLs (same node, different port)
PROMETHEUS_PRIMARY = f"http://{PRIMARY_IP}:32001" if PRIMARY_IP else ""
PROMETHEUS_DR      = f"http://{DR_IP}:32001"      if DR_IP      else ""

REFRESH_INTERVAL = 10   # seconds between auto-refresh
