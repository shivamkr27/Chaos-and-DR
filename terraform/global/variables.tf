variable "project" {
  type    = string
  default = "chaos-dr"
}

variable "domain_name" {
  description = "e.g. chaos-dr.yourdomain.com — register a free .tk domain or use nip.io for demo"
  type        = string
}

variable "primary_k3s_ip" {
  description = "Elastic IP from: cd terraform/region-primary && terraform output k3s_public_ip"
  type        = string
}

variable "dr_k3s_ip" {
  description = "Elastic IP from: cd terraform/region-dr && terraform output k3s_public_ip"
  type        = string
}

variable "alert_email" {
  description = "Email address to receive failover alerts"
  type        = string
}
