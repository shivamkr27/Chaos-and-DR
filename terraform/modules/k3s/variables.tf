variable "project" {
  type = string
}

variable "region_alias" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Public subnet to place the K3s node in"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content for EC2 access"
  type        = string
}

variable "db_host" {
  description = "RDS endpoint passed to K3s bootstrap"
  type        = string
}

variable "db_password" {
  description = "RDS password passed to K3s bootstrap"
  type        = string
  sensitive   = true
}

variable "app_image" {
  description = "Docker image for the app (ECR or Docker Hub)"
  type        = string
}
