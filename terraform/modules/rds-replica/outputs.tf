output "endpoint" {
  value = aws_db_instance.replica.address
}

output "port" {
  value = aws_db_instance.replica.port
}

output "db_instance_id" {
  value = aws_db_instance.replica.id
}

output "db_instance_arn" {
  value = aws_db_instance.replica.arn
}
