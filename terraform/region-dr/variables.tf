variable "project" {
  type    = string
  default = "chaos-dr"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "api_key" {
  description = "Shared API key the app requires for POST/DELETE on /api/items (same value as primary)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  type = string
}

variable "app_image" {
  type    = string
  default = "your-dockerhub-username/chaos-dr-app:latest"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed SSH to the DR K3s node. Restrict to your IP (e.g. 1.2.3.4/32) — required, no insecure default."
  type        = string
}
