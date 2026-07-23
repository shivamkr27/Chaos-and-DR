variable "project" {
  type    = string
  default = "chaos-dr"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "api_key" {
  description = "Shared API key the app requires for POST/DELETE on /api/items"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Contents of your ~/.ssh/id_rsa.pub"
  type        = string
}

variable "app_image" {
  description = "Docker image pushed to ECR or Docker Hub"
  type        = string
  default     = "your-dockerhub-username/chaos-dr-app:latest"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed SSH to the primary K3s node. Restrict to your IP (e.g. 1.2.3.4/32) — required, no insecure default."
  type        = string
}
