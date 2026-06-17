# Route 53 hosted zone — one per domain, not per region
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name    = "${var.project}-zone"
    Project = var.project
  }
}

# Health check for PRIMARY region — pings /health/live every 10s
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_ip   # Route 53 can check by IP too
  ip_address        = var.primary_ip
  port              = 30080
  type              = "HTTP"
  resource_path     = "/health/live"
  failure_threshold = 3   # 3 consecutive failures = unhealthy
  request_interval  = 10  # check every 10 seconds

  tags = {
    Name    = "${var.project}-primary-health-check"
    Project = var.project
    Region  = "us-east-1"
  }
}

# Health check for DR region
resource "aws_route53_health_check" "dr" {
  ip_address        = var.dr_ip
  port              = 30080
  type              = "HTTP"
  resource_path     = "/health/live"
  failure_threshold = 3
  request_interval  = 10

  tags = {
    Name    = "${var.project}-dr-health-check"
    Project = var.project
    Region  = "us-west-2"
  }
}

# PRIMARY DNS record — serves traffic normally
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  # Failover routing: PRIMARY record is active when healthy
  failover_routing_policy {
    type = "PRIMARY"
  }

  # Route 53 watches this health check — if it fails, traffic auto-shifts to DR
  health_check_id = aws_route53_health_check.primary.id
  set_identifier  = "primary"
  ttl             = 30   # short TTL so DNS failover propagates fast

  records = [var.primary_ip]
}

# SECONDARY (DR) DNS record — takes over when primary is unhealthy
resource "aws_route53_record" "dr" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  # No health_check_id on secondary — it's always available as fallback
  set_identifier = "dr"
  ttl            = 30

  records = [var.dr_ip]
}

# CloudWatch alarm that fires when primary health check fails
# Used by Grafana + Slack alerting in Phase 4
resource "aws_cloudwatch_metric_alarm" "primary_down" {
  alarm_name          = "${var.project}-primary-region-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 10
  statistic           = "Minimum"
  threshold           = 1   # 0 = unhealthy, 1 = healthy

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  alarm_description = "Primary region (us-east-1) health check is failing — DR failover active"
  alarm_actions     = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions        = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Project = var.project
  }
}
