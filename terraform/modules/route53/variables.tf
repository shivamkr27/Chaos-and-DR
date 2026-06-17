variable "project" {
  type = string
}

variable "domain_name" {
  description = "Domain name for the app e.g. chaos-dr.example.com — can be a Route53-only subdomain for demo"
  type        = string
}

variable "primary_ip" {
  description = "Elastic IP of the primary region K3s node"
  type        = string
}

variable "dr_ip" {
  description = "Elastic IP of the DR region K3s node"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for failover alerts (Slack/email). Leave empty to skip."
  type        = string
  default     = ""
}
