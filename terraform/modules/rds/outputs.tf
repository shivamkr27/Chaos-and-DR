output "endpoint" {
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "db_instance_id" {
  value = aws_db_instance.postgres.id
}
