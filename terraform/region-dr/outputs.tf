output "k3s_public_ip" {
  value = module.k3s.public_ip
}

output "rds_replica_endpoint" {
  value = "disabled"
}

output "grafana_url" {
  value = "http://${module.k3s.public_ip}:32000"
}

output "app_url" {
  value = "http://${module.k3s.public_ip}:30080"
}
