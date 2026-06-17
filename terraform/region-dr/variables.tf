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

variable "ssh_public_key" {
  type = string
}

variable "app_image" {
  type    = string
  default = "your-dockerhub-username/chaos-dr-app:latest"
}

# RDS replica needs the primary DB instance ARN from region-primary outputs
variable "primary_db_instance_arn" {
  description = "ARN of primary RDS instance — get from region-primary output after apply"
  type        = string
}
