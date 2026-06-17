output "k3s_public_ip" {
  description = "SSH to this IP and access the cluster"
  value       = module.k3s.public_ip
}

output "rds_endpoint" {
  description = "PostgreSQL endpoint (internal)"
  value       = module.rds.endpoint
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${module.k3s.public_ip}:32000"
}

output "app_url" {
  description = "App API URL"
  value       = "http://${module.k3s.public_ip}:30080"
}
