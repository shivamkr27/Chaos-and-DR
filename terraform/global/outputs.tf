output "name_servers" {
  description = "Add these NS records at your domain registrar to activate Route 53"
  value       = module.route53.name_servers
}

output "app_domain" {
  value = "http://${var.domain_name}"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "primary_s3_bucket" {
  value = module.s3_replication.primary_bucket_name
}

output "dr_s3_bucket" {
  value = module.s3_replication.dr_bucket_name
}
