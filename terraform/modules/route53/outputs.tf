output "zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "NS records to add at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "primary_health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "dr_health_check_id" {
  value = aws_route53_health_check.dr.id
}
