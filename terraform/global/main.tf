# Wire up Route 53 and S3 replication using outputs from both regions.
# Apply this AFTER both region-primary and region-dr are applied.

# SNS topic for failover alerts — Slack + email subscribe to this
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
  tags = {
    Project = var.project
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

module "route53" {
  source        = "../modules/route53"
  project       = var.project
  domain_name   = var.domain_name
  primary_ip    = var.primary_k3s_ip
  dr_ip         = var.dr_k3s_ip
  sns_topic_arn = aws_sns_topic.alerts.arn
}

module "s3_replication" {
  source         = "../modules/s3-replication"
  project        = var.project
  account_id     = data.aws_caller_identity.current.account_id
  primary_region = "us-east-1"
  dr_region      = "us-west-2"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}

data "aws_caller_identity" "current" {}
