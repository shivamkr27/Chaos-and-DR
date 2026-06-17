output "primary_bucket_name" {
  value = aws_s3_bucket.primary.id
}

output "dr_bucket_name" {
  value = aws_s3_bucket.dr.id
}

output "primary_bucket_arn" {
  value = aws_s3_bucket.primary.arn
}
